import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';

void main() {
  group('HTTPS policy', () {
    late _RecordingAdapter adapter;
    late _NoProbeDioHttpClient client;
    late Directory tempDir;
    late String downloadPath;

    setUp(() {
      adapter = _RecordingAdapter();
      client = _NoProbeDioHttpClient(adapter);
      tempDir = Directory.systemTemp.createTempSync('dio-https-policy-test-');
      downloadPath = '${tempDir.path}/profile';
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('allows HTTPS before issuing the request', () async {
      final response = await client.download('https://example.test/profile', downloadPath);

      expect(response.statusCode, 200);
      expect(adapter.requests, [Uri.parse('https://example.test/profile')]);
      expect(client.proxyProbeCount, 1);
    });

    test('accepts a mixed-case HTTPS scheme', () async {
      await client.download('HtTpS://example.test/profile', downloadPath);

      expect(adapter.requests, [Uri.parse('https://example.test/profile')]);
    });

    for (final invalidUrl in ['http://example.test/profile', 'ftp://example.test/profile', 'not a URL', 'https://']) {
      test('rejects $invalidUrl without any network activity', () async {
        await expectLater(client.download(invalidUrl, downloadPath), throwsA(isA<DioException>()));

        expect(client.proxyProbeCount, 0);
        expect(adapter.requests, isEmpty);
      });
    }

    test('does not follow an HTTPS redirect to HTTP', () async {
      adapter.responseFor = (uri) => ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': ['http://example.test/insecure-profile'],
        },
      );

      await expectLater(client.download('https://example.test/profile', downloadPath), throwsA(isA<DioException>()));

      expect(adapter.requests, [Uri.parse('https://example.test/profile')]);
    });

    test('follows a relative redirect that remains on HTTPS', () async {
      adapter.responseFor = (uri) => uri.path == '/profile'
          ? ResponseBody.fromString(
              '',
              302,
              headers: {
                'location': ['/secure-profile'],
              },
            )
          : ResponseBody.fromString('profile', 200);

      final response = await client.download('https://example.test/profile', downloadPath);

      expect(response.statusCode, 200);
      expect(adapter.requests, [
        Uri.parse('https://example.test/profile'),
        Uri.parse('https://example.test/secure-profile'),
      ]);
    });

    test('does not forward explicit credentials across HTTPS origins', () async {
      adapter.responseFor = (uri) => uri.host == 'trusted.test'
          ? ResponseBody.fromString(
              '',
              302,
              headers: {
                'location': ['https://attacker.test/profile'],
              },
            )
          : ResponseBody.fromString('profile', 200);

      await client.get<String>(
        'https://trusted.test/profile',
        credentials: (username: 'synthetic-user', password: 'synthetic-password'),
      );

      expect(adapter.requests, [Uri.parse('https://trusted.test/profile'), Uri.parse('https://attacker.test/profile')]);
      expect(adapter.requestHeaders.first, contains('authorization'));
      expect(adapter.requestHeaders.last, isNot(contains('authorization')));
    });

    test('does not forward URL user info across HTTPS origins', () async {
      adapter.responseFor = (uri) => uri.host == 'trusted.test'
          ? ResponseBody.fromString(
              '',
              302,
              headers: {
                'location': ['https://attacker.test/profile'],
              },
            )
          : ResponseBody.fromString('profile', 200);

      await client.get<String>('https://synthetic-user:synthetic-password@trusted.test/profile');

      expect(adapter.requestHeaders.first, contains('authorization'));
      expect(adapter.requestHeaders.last, isNot(contains('authorization')));
    });

    test('get rejects HTTP before the proxy probe and adapter', () async {
      await expectLater(client.get<String>('http://example.test/profile'), throwsA(isA<DioException>()));

      expect(client.proxyProbeCount, 0);
      expect(adapter.requests, isEmpty);
    });

    test('get does not follow an HTTPS redirect to HTTP', () async {
      adapter.responseFor = (uri) => ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': ['http://example.test/insecure-profile'],
        },
      );

      await expectLater(client.get<String>('https://example.test/profile'), throwsA(isA<DioException>()));

      expect(adapter.requests, [Uri.parse('https://example.test/profile')]);
    });
  });
}

class _NoProbeDioHttpClient extends DioHttpClient {
  _NoProbeDioHttpClient(HttpClientAdapter adapter)
    : super(
        timeout: const Duration(seconds: 1),
        userAgent: 'https-policy-test',
        debug: false,
        httpClientAdapterFactory: () => adapter,
      );

  int proxyProbeCount = 0;

  @override
  Future<bool> isPortOpen(String host, int port, {Duration timeout = const Duration(seconds: 5)}) async {
    proxyProbeCount++;
    return false;
  }
}

class _RecordingAdapter implements HttpClientAdapter {
  final requests = <Uri>[];
  final requestHeaders = <Map<String, dynamic>>[];
  ResponseBody Function(Uri uri)? responseFor;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri);
    requestHeaders.add(Map<String, dynamic>.from(options.headers));
    return responseFor?.call(options.uri) ?? ResponseBody.fromString('profile', 200);
  }

  @override
  void close({bool force = false}) {}
}
