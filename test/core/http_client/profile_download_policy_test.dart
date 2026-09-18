import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/http_client/profile_download_policy.dart';
import 'package:loggy/loggy.dart';

void main() {
  for (final ip in [
    '0.0.0.0',
    '127.0.0.1',
    '10.1.2.3',
    '172.16.0.1',
    '192.168.1.1',
    '192.0.0.1',
    '192.0.2.1',
    '198.51.100.1',
    '169.254.169.254',
    '100.64.0.1',
    '224.0.0.1',
    '::1',
    '::',
    'fc00::1',
    'fe80::1',
    '::ffff:127.0.0.1',
    '2002:7f00:1::',
    '2001:db8::1',
  ]) {
    test(
      'blocks non-public destination $ip',
      () => expect(ProfileDownloadPolicy.isPublic(InternetAddress(ip)), isFalse),
    );
  }
  for (final ip in [
    '8.8.8.8',
    '1.1.1.1',
    '192.0.1.1',
    '192.2.0.1',
    '198.51.99.1',
    '198.51.101.1',
    '2606:4700:4700::1111',
  ]) {
    test('allows public destination $ip', () => expect(ProfileDownloadPolicy.isPublic(InternetAddress(ip)), isTrue));
  }

  late Directory temp;
  late String path;
  late _Adapter adapter;
  late List<String> lookups;
  late List<String> pins;
  late ProfileDownloadPolicy policy;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('profile-policy-');
    path = '${temp.path}/profile';
    adapter = _Adapter();
    lookups = [];
    pins = [];
    policy = ProfileDownloadPolicy(
      lookup: (host) async {
        lookups.add(host);
        return [InternetAddress(host == 'private.test' ? '127.0.0.1' : '8.8.8.8')];
      },
      adapterFactory: (ip) {
        pins.add(ip.address);
        return adapter;
      },
      byteLimit: 16,
    );
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<Response> download([String url = 'https://public.test/config']) =>
      policy.download(url, path, userAgent: 'test');

  test('bounded profile transport emits its explicit endpoint class without URLs', () async {
    final printer = _ApiEvents();
    Loggy.initLoggy(logPrinter: printer);
    addTearDown(() => Loggy.initLoggy());
    await download('https://PRIVATE_CANARY.test/config?token=PRIVATE_CANARY');
    expect(printer.events.length, 2);
    expect(printer.events.last['endpoint_class'], 'profile_download');
    expect(printer.events.last['retry_count'], 0);
    expect(printer.events.last['status_class'], 'http_2xx');
    expect(jsonEncode(printer.events), isNot(contains('PRIVATE_CANARY')));
  });

  test('passes validated IP to transport, keeps original TLS hostname', () async {
    await download();
    expect(lookups, ['public.test']);
    expect(pins, ['8.8.8.8']);
    expect(adapter.requests.single.uri.host, 'public.test');
    expect(File(path).readAsStringSync(), 'config');
  });
  test('rejects private literal without DNS or request', () async {
    await expectLater(download('https://127.0.0.1/config'), throwsFormatException);
    expect(lookups, isEmpty);
    expect(adapter.requests, isEmpty);
  });
  test('rejects mixed DNS answer before connecting', () async {
    policy = ProfileDownloadPolicy(
      lookup: (_) async => [InternetAddress('8.8.8.8'), InternetAddress('10.0.0.1')],
      adapterFactory: (_) => adapter,
    );
    await expectLater(download(), throwsFormatException);
    expect(adapter.requests, isEmpty);
  });
  test('revalidates redirect DNS and blocks private result', () async {
    adapter.respond = (_) => ResponseBody.fromString(
      '',
      302,
      headers: {
        'location': ['https://private.test/config'],
      },
    );
    await expectLater(download(), throwsFormatException);
    expect(lookups, ['public.test', 'private.test']);
    expect(adapter.requests, hasLength(1));
  });
  test('rejects rebinding on same-host redirect before second request', () async {
    var count = 0;
    policy = ProfileDownloadPolicy(
      lookup: (_) async => [InternetAddress(count++ == 0 ? '8.8.8.8' : '127.0.0.1')],
      adapterFactory: (_) => adapter,
    );
    adapter.respond = (_) => ResponseBody.fromString(
      '',
      302,
      headers: {
        'location': ['/next'],
      },
    );
    await expectLater(download(), throwsFormatException);
    expect(adapter.requests, hasLength(1));
  });
  test('rejects redirect downgrade', () async {
    adapter.respond = (_) => ResponseBody.fromString(
      '',
      302,
      headers: {
        'location': ['http://public.test/config'],
      },
    );
    await expectLater(download(), throwsFormatException);
    expect(adapter.requests, hasLength(1));
  });
  test('bounds redirect loops', () async {
    adapter.respond = (_) => ResponseBody.fromString(
      '',
      302,
      headers: {
        'location': ['/again'],
      },
    );
    await expectLater(download(), throwsFormatException);
    expect(adapter.requests, hasLength(ProfileDownloadPolicy.maxRedirects + 1));
  });
  test('bounds chunked body without trusting content length and removes partial file', () async {
    adapter.respond = (_) => ResponseBody(Stream.fromIterable([Uint8List(10), Uint8List(10)]), 200);
    await expectLater(download(), throwsFormatException);
    expect(File(path).existsSync(), isFalse);
  });
  test('rejects declared oversized body before writing', () async {
    adapter.respond = (_) => ResponseBody.fromString(
      'small',
      200,
      headers: {
        'content-length': ['100'],
      },
    );
    await expectLater(download(), throwsFormatException);
    expect(File(path).existsSync(), isFalse);
  });
  test('deadline cancels a stalled response stream and removes partial file', () async {
    final body = StreamController<Uint8List>();
    adapter.respond = (_) => ResponseBody(body.stream, 200);
    policy = ProfileDownloadPolicy(
      lookup: (_) async => [InternetAddress('8.8.8.8')],
      adapterFactory: (_) => adapter,
      timeLimit: const Duration(milliseconds: 30),
    );
    await expectLater(
      download(),
      throwsA(
        isA<ProfileDownloadException>().having((error) => error.kind, 'kind', ProfileDownloadFailureKind.deadline),
      ),
    );
    expect(File(path).existsSync(), isFalse);
    await body.close();
  });

  test('bounds DNS time', () async {
    final lookup = Completer<List<InternetAddress>>();
    var adapterCalls = 0;
    policy = ProfileDownloadPolicy(
      lookup: (_) => lookup.future,
      adapterFactory: (_) {
        adapterCalls++;
        return adapter;
      },
      timeLimit: const Duration(milliseconds: 20),
    );
    await expectLater(
      download(),
      throwsA(
        isA<ProfileDownloadException>().having((error) => error.kind, 'kind', ProfileDownloadFailureKind.deadline),
      ),
    );
    lookup.complete([InternetAddress('8.8.8.8')]);
    await Future<void>.delayed(Duration.zero);

    expect(adapterCalls, 0);
    expect(adapter.requests, isEmpty);
    expect(File(path).existsSync(), isFalse);
  });
}

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  ResponseBody Function(RequestOptions)? respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond?.call(options) ?? ResponseBody.fromString('config', 200);
  }

  @override
  void close({bool force = false}) {}
}

class _ApiEvents extends LoggyPrinter {
  final events = <Map<String, dynamic>>[];
  @override
  void onLog(LogRecord record) {
    if (record.loggerName == 'observability') events.add(jsonDecode(record.message) as Map<String, dynamic>);
  }
}
