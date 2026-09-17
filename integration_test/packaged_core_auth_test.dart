import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/hiddifycore/core_interface/local_control_credentials.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/hiddifycore/generated/v2/hello/hello.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hello/hello_service.pbgrpc.dart';
import 'package:integration_test/integration_test.dart';

const _methodChannel = MethodChannel('com.hiddify.app/method');
const _controlPort = 17078;
const _firstSecret = '0101010101010101010101010101010101010101010101010101010101010101';
const _secondSecret = '0202020202020202020202020202020202020202020202020202020202020202';
const _wrongSecret = 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('packaged core enforces bearer auth and pinned TLS lifecycle', (tester) async {
    final directories = await Directory.systemTemp.createTemp('packaged-core-auth.');
    final originalWorkingDirectory = Directory.current;
    final baseDir = Directory('${directories.path}/base')..createSync(recursive: true);
    final workingDir = Directory('${directories.path}/work')..createSync(recursive: true);
    final tempDir = Directory('${directories.path}/tmp')..createSync(recursive: true);
    final channels = <ClientChannel>[];

    Future<Uint8List> setup(String secret) async {
      await _methodChannel.invokeMethod<void>('_test_setup_packaged_core', {
        'baseDir': baseDir.path,
        'workingDir': workingDir.path,
        'tempDir': tempDir.path,
        'grpcPort': _controlPort,
        'mode': SetupMode.GRPC_BACKGROUND_INSECURE.value,
        'controlSecret': secret,
        'debug': false,
      });
      final certificate = await _methodChannel.invokeMethod<Uint8List>('get_grpc_server_public_key');
      expect(certificate, isNotNull);
      expect(utf8.decode(certificate!), contains('BEGIN CERTIFICATE'));
      return certificate;
    }

    ClientChannel channel(Uint8List certificate) {
      final clientChannel = ClientChannel(
        '127.0.0.1',
        port: _controlPort,
        options: ChannelOptions(credentials: pinnedControlCredentials(certificate)),
      );
      channels.add(clientChannel);
      return clientChannel;
    }

    Future<void> expectUnauthenticated(CallOptions? options, Uint8List certificate) async {
      await expectLater(
        HelloClient(channel(certificate), options: options).sayHello(
          HelloRequest(name: 'packaged-probe'),
          options: CallOptions(timeout: const Duration(seconds: 5)),
        ),
        throwsA(isA<GrpcError>().having((error) => error.code, 'code', StatusCode.unauthenticated)),
      );
    }

    Future<void> closeCore(ClientChannel clientChannel, String secret) async {
      try {
        await CoreClient(clientChannel, options: controlCallOptions(secret)).close(
          CloseRequest(mode: SetupMode.GRPC_BACKGROUND_INSECURE),
          options: CallOptions(timeout: const Duration(seconds: 5)),
        );
      } on GrpcError catch (error) {
        // The server stops itself before the Close response is flushed.
        if (error.code != StatusCode.unknown && error.code != StatusCode.unavailable) rethrow;
      }

      for (var attempt = 0; attempt < 20; attempt++) {
        try {
          final socket = await Socket.connect(
            InternetAddress.loopbackIPv4,
            _controlPort,
            timeout: const Duration(milliseconds: 100),
          );
          socket.destroy();
        } on SocketException {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      fail('packaged core did not release its control port');
    }

    try {
      final firstCertificate = await setup(_firstSecret);
      final firstChannel = channel(firstCertificate);

      await HelloClient(firstChannel, options: controlCallOptions(_firstSecret)).sayHello(
        HelloRequest(name: 'packaged-probe'),
        options: CallOptions(timeout: const Duration(seconds: 5)),
      );
      await expectUnauthenticated(null, firstCertificate);
      await expectUnauthenticated(controlCallOptions(_wrongSecret), firstCertificate);

      final repeatedCertificate = await setup(_firstSecret);
      expect(repeatedCertificate, orderedEquals(firstCertificate));
      await expectLater(
        setup(_secondSecret),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.message,
            'message',
            contains('control API session changed; restart native core'),
          ),
        ),
      );

      await closeCore(firstChannel, _firstSecret);

      final secondCertificate = await setup(_secondSecret);
      expect(secondCertificate, isNot(orderedEquals(firstCertificate)));
      final secondChannel = channel(secondCertificate);
      await HelloClient(secondChannel, options: controlCallOptions(_secondSecret)).sayHello(
        HelloRequest(name: 'packaged-probe-after-restart'),
        options: CallOptions(timeout: const Duration(seconds: 5)),
      );
      await expectUnauthenticated(controlCallOptions(_firstSecret), secondCertificate);
      await expectLater(
        HelloClient(channel(firstCertificate), options: controlCallOptions(_secondSecret)).sayHello(
          HelloRequest(name: 'packaged-probe-stale-pin'),
          options: CallOptions(timeout: const Duration(seconds: 5)),
        ),
        throwsA(
          isA<GrpcError>()
              .having((error) => error.code, 'code', StatusCode.unavailable)
              .having((error) => error.message, 'message', contains('CERTIFICATE_VERIFY_FAILED')),
        ),
      );
      await closeCore(secondChannel, _secondSecret);
    } finally {
      await Future.wait(
        channels.map((clientChannel) => clientChannel.terminate()),
      ).timeout(const Duration(seconds: 5), onTimeout: () => throw TestFailure('client channels did not terminate'));
      Directory.current = originalWorkingDirectory;
      await directories.delete(recursive: true);
    }
  });
}
