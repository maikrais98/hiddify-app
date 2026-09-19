import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/analytics/analytics_logger.dart';
import 'package:hiddify/core/observability/observability.dart';
import 'package:loggy/loggy.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  test('closed INFO duration terminals are events while arbitrary INFO stays breadcrumb-only', () async {
    final captured = <SentryEvent>[];
    final options = SentryOptions()
      ..dsn = 'https://public@example.invalid/1'
      ..beforeSend = (event, hint) {
        captured.add(event);
        return null;
      };
    final hub = Hub(options);
    addTearDown(hub.close);
    final integration = SentryLoggyIntegration()..call(hub, options);
    final payloads = <Map<String, Object>>[];
    final client = ObservabilityClient(sink: (payload, _) => payloads.add(payload));
    client.startOperation(module: ObservabilityModule.vpn, operation: ObservabilityOperation.connect).success();
    await integration.onLog(LogRecord(LogLevel.info, 'ordinary info', 'app'));
    await integration.onLog(LogRecord(LogLevel.info, jsonEncode(payloads.first), 'observability'));
    expect(captured, isEmpty);
    await integration.onLog(LogRecord(LogLevel.info, jsonEncode(payloads.last), 'observability'));
    expect(captured.length, 1);
    expect((jsonDecode(captured.single.message!.formatted) as Map<String, dynamic>)['duration_ms'], isNonNegative);
    await integration.onLog(LogRecord(LogLevel.error, 'follow-up', 'app'));
    expect(captured.last.breadcrumbs!.any((b) => b.message == jsonEncode(payloads.last)), isTrue);
  });
}
