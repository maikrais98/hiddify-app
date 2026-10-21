import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/observability/better_stack_log_printer.dart';
import 'package:hiddify/core/observability/observability.dart';
import 'package:hiddify/core/observability/telemetry_budget.dart';
import 'package:loggy/loggy.dart';

void main() {
  late String? stored;
  late DateTime now;
  late List<String> sent;
  late BetterStackLogPrinter printer;
  late int response;

  Map<String, Object> event({ObservabilityEvent name = ObservabilityEvent.vpnConnected}) {
    late Map<String, Object> result;
    ObservabilityClient(sink: (payload, _) => result = payload).event(
      module: ObservabilityModule.vpn,
      operation: ObservabilityOperation.connect,
      name: name,
      status: ObservabilityStatus.succeeded,
    );
    return result;
  }

  LogRecord record({LogLevel level = LogLevel.info, Map<String, Object>? payload}) =>
      LogRecord(level, jsonEncode(payload ?? event()), 'observability');

  TelemetryBudget budget({int bytes = 256 * 1024}) => TelemetryBudget(
    read: () => stored,
    write: (value) async {
      stored = value;
      return true;
    },
    now: () => now,
    maxLogBytes: bytes,
  );

  setUp(() {
    stored = null;
    now = DateTime.utc(2026, 10, 21);
    sent = [];
    response = 202;
    printer = BetterStackLogPrinter(
      endpoint: Uri.parse('https://s1.us-west-2a.betterstackdata.com'),
      token: 'write-only-test-token',
      budget: budget(),
      autoFlush: false,
      now: () => now,
      post: (endpoint, token, body) async {
        sent.add(body);
        return response;
      },
    );
  });

  tearDown(() async => printer.dispose());

  test('only typed diagnostics leave the app; arbitrary fields and raw logs are discarded', () async {
    printer.onLog(LogRecord(LogLevel.error, 'PRIVATE_CANARY', 'vpn-core'));
    printer.onLog(LogRecord(LogLevel.error, '{"password":"PRIVATE_CANARY"}', 'observability'));
    printer.onLog(record(level: LogLevel.debug));
    printer.onLog(record(payload: {...event(), 'url': 'PRIVATE_CANARY', 'headers': 'PRIVATE_CANARY'}));
    await printer.flush();
    expect(sent.length, 1);
    expect(sent.single, isNot(contains('PRIVATE_CANARY')));
    final decoded = (jsonDecode(sent.single) as List).single as Map;
    expect(decoded['module'], 'vpn');
    expect(decoded['event'], 'vpn_connected');
    expect(decoded['dt'], isA<String>());
    expect(decoded['schema_version'], 1);
    expect(printer.queuedCount, 0);
  });

  test('quota and credential responses disable sending and clear pending data', () async {
    response = 402;
    printer.onLog(record());
    await printer.flush();
    printer.onLog(record());
    await printer.flush();
    expect(sent.length, 1);
    expect(printer.active, isFalse);
    expect(printer.queuedCount, 0);
  });

  test('retryable responses have a bounded retry count and consume byte budget', () async {
    response = 503;
    printer.onLog(record());
    await printer.flush();
    await printer.flush();
    await printer.flush();
    await printer.flush();
    expect(sent.length, 3);
    expect(printer.queuedCount, 0);
    expect(jsonDecode(stored!)['log_bytes'], utf8.encode(sent.join()).length);
  });

  test('transport exceptions stay isolated and eventually discard the failed batch', () async {
    await printer.dispose();
    var attempts = 0;
    printer = BetterStackLogPrinter(
      endpoint: Uri.parse('https://s1.us-west-2a.betterstackdata.com'),
      token: 'test',
      budget: budget(),
      autoFlush: false,
      post: (_, _, _) async {
        attempts++;
        throw StateError('network unavailable');
      },
    );
    printer.onLog(record());
    for (var i = 0; i < 4; i++) {
      await printer.flush();
    }
    expect(attempts, 3);
    expect(printer.queuedCount, 0);
  });

  test('repeated errors are throttled without using operation IDs as deduplication keys', () async {
    printer.onLog(record(level: LogLevel.error));
    printer.onLog(record(level: LogLevel.error));
    await printer.flush();
    expect((jsonDecode(sent.single) as List).length, 1);
    now = now.add(const Duration(minutes: 1));
    printer.onLog(record(level: LogLevel.error));
    await printer.flush();
    expect(sent.length, 2);
  });

  test('offline queue and outgoing batches are bounded', () async {
    for (var i = 0; i < 150; i++) {
      printer.onLog(record());
    }
    expect(printer.queuedCount, BetterStackLogPrinter.maxQueueLength);
    await printer.flush();
    expect((jsonDecode(sent.single) as List).length, BetterStackLogPrinter.maxBatchLength);
    expect(printer.queuedCount, 80);
  });

  test('persisted daily cap prevents the network request', () async {
    await printer.dispose();
    printer = BetterStackLogPrinter(
      endpoint: Uri.parse('https://s1.us-west-2a.betterstackdata.com'),
      token: 'test',
      budget: budget(bytes: 1),
      autoFlush: false,
      post: (_, _, body) async {
        sent.add(body);
        return 202;
      },
    );
    printer.onLog(record());
    await printer.flush();
    expect(sent, isEmpty);
    expect(printer.queuedCount, 0);
  });

  test('overlapping flushes send once and disposal stops future requests', () async {
    await printer.dispose();
    final completion = Completer<int>();
    printer = BetterStackLogPrinter(
      endpoint: Uri.parse('https://s1.us-west-2a.betterstackdata.com'),
      token: 'test',
      budget: budget(),
      autoFlush: false,
      post: (_, _, body) {
        sent.add(body);
        return completion.future;
      },
    );
    printer.onLog(record());
    final first = printer.flush();
    final second = printer.flush();
    completion.complete(202);
    await Future.wait([first, second]);
    expect(sent.length, 1);
    await printer.dispose();
    printer.onLog(record());
    await printer.flush();
    expect(sent.length, 1);
  });

  test('only HTTPS Better Stack ingestion hosts are accepted', () {
    for (final url in [
      'http://s1.betterstackdata.com',
      'https://betterstackdata.com.attacker.invalid',
      'https://s1.betterstackdata.com?token=test',
      'https://test@s1.betterstackdata.com',
      'https://s1.betterstackdata.com:444',
      'https://s1.betterstackdata.com/path',
    ]) {
      expect(isBetterStackLogsEndpoint(Uri.parse(url)), isFalse, reason: url);
    }
  });
}
