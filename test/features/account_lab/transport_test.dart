import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/account_lab/account_io.dart';
import 'package:hiddify/features/account_lab/account_protocol.dart';
import 'protocol_test.dart' show tokenJson;

void main() {
  test('real TLS trusts only the supplied certificate and checks the IP SAN', () async {
    final directory = await Directory.systemTemp.createTemp('luma-tls-');
    addTearDown(() => directory.delete(recursive: true));
    final openssl = Platform.isWindows ? 'C:/Program Files/Git/usr/bin/openssl.exe' : 'openssl';
    Future<(SecurityContext, List<int>)> material(String name, String host) async {
      final key = '${directory.path}/$name.key';
      final cert = '${directory.path}/$name.pem';
      final result = await Process.run(openssl, [
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-sha256',
        '-nodes',
        '-days',
        '1',
        '-keyout',
        key,
        '-out',
        cert,
        '-subj',
        '/CN=Luma test',
        '-addext',
        'subjectAltName=IP:$host',
      ]);
      expect(result.exitCode, 0, reason: 'Local TLS fixture generation');
      final pem = await File(cert).readAsString();
      final bytes = base64Decode(pem.replaceAll(RegExp(r'-----[^-]+-----|\s'), ''));
      final context = SecurityContext()
        ..useCertificateChain(cert)
        ..usePrivateKey(key);
      return (context, bytes);
    }

    final good = await material('good', '127.0.0.1');
    final other = await material('other', '127.0.0.2');
    Future<HttpServer> server(SecurityContext context) async {
      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'ok': true, 'request_id': '11111111-1111-4111-8111-111111111111', 'data': <String, dynamic>{}}),
        );
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));
      return server;
    }

    final goodServer = await server(good.$1);
    final wrongHostServer = await server(other.$1);
    final accepted = DioLabApi(
      'https://127.0.0.1:${goodServer.port}/api/luma/v1/',
      certificateDer: Uint8List.fromList(good.$2),
      enabled: true,
    );
    final untrusted = DioLabApi(
      'https://127.0.0.1:${goodServer.port}/api/luma/v1/',
      certificateDer: Uint8List.fromList(other.$2),
      enabled: true,
    );
    final wrongHost = DioLabApi(
      'https://127.0.0.1:${wrongHostServer.port}/api/luma/v1/',
      certificateDer: Uint8List.fromList(other.$2),
      enabled: true,
    );
    addTearDown(accepted.close);
    addTearDown(untrusted.close);
    addTearDown(wrongHost.close);
    expect(await accepted.call('GET', 'me'), isEmpty);
    await expectLater(untrusted.call('GET', 'me'), throwsA(isA<LabFailure>()));
    await expectLater(wrongHost.call('GET', 'me'), throwsA(isA<LabFailure>()));
  });
  test('HTTP request, envelope validation, redirects and errors never retry', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requests = 0;
    var mode = 'ok';
    server.listen((request) async {
      requests++;
      expect(request.uri.path, '/api/luma/v1/auth/refresh');
      expect(request.uri.query, isEmpty);
      expect(jsonDecode(await utf8.decoder.bind(request).join()), {'refresh_token': tokenJson()['refresh_token']});
      request.response.headers.contentType = ContentType.json;
      if (mode == 'redirect') {
        request.response.statusCode = 307;
        request.response.headers.set('location', '/public');
      } else if (mode == 'error') {
        request.response.statusCode = 503;
        request.response.write(
          jsonEncode({
            'ok': false,
            'request_id': '11111111-1111-4111-8111-111111111111',
            'error': 'auth_unavailable',
            'message': 'SECRET_DO_NOT_EXPOSE',
          }),
        );
      } else {
        request.response.write(
          jsonEncode({
            'ok': true,
            'request_id': mode == 'bad' ? 'bad' : '11111111-1111-4111-8111-111111111111',
            'data': tokenJson(),
          }),
        );
      }
      await request.response.close();
    });
    final api = DioLabApi('http://127.0.0.1:${server.port}/api/luma/v1/', enabled: true);
    addTearDown(api.close);
    Future<Map<String, dynamic>> request() =>
        api.call('POST', 'auth/refresh', body: {'refresh_token': tokenJson()['refresh_token']});
    expect((await request())['session_id'], tokenJson()['session_id']);
    mode = 'error';
    await expectLater(request(), throwsA(isA<LabFailure>().having((e) => e.toString(), 'safe', 'auth_unavailable')));
    mode = 'redirect';
    await expectLater(request(), throwsA(isA<LabFailure>()));
    mode = 'bad';
    await expectLater(request(), throwsA(isA<LabFailure>()));
    expect(requests, 4);
    await expectLater(api.call('GET', '../other'), throwsA(isA<LabFailure>()));
    expect(requests, 4);
  });
}
