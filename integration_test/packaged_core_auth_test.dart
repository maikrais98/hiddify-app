import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart' hide Response;
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/db/provider/db_providers.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/core/http_client/http_client_provider.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_data_source.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface.dart';
import 'package:hiddify/hiddifycore/core_interface/local_control_credentials.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/hiddifycore/generated/v2/hello/hello.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hello/hello_service.pbgrpc.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets('repository imports and generates a profile through the actual packaged validator', (tester) async {
    final root = await Directory.systemTemp.createTemp('packaged-profile-validator.');
    final originalWorkingDirectory = Directory.current;
    final directories = (
      baseDir: Directory('${root.path}/base')..createSync(recursive: true),
      workingDir: Directory('${root.path}/work')..createSync(recursive: true),
      tempDir: Directory('${root.path}/tmp')..createSync(recursive: true),
    );
    final database = Db(NativeDatabase.memory());
    final download = _FixtureSubscription();
    ProviderContainer? container;
    ClientChannel? channel;
    HiddifyCoreService? service;
    CoreClient? client;
    var completed = false;

    try {
      await _methodChannel.invokeMethod<void>('_test_setup_packaged_core', {
        'baseDir': directories.baseDir.path,
        'workingDir': directories.workingDir.path,
        'tempDir': directories.tempDir.path,
        'grpcPort': _controlPort,
        'mode': SetupMode.GRPC_BACKGROUND_INSECURE.value,
        'controlSecret': _firstSecret,
        'debug': false,
      });
      final certificate = await _methodChannel.invokeMethod<Uint8List>('get_grpc_server_public_key');
      expect(certificate, isNotNull);
      channel = ClientChannel(
        '127.0.0.1',
        port: _controlPort,
        options: ChannelOptions(credentials: pinnedControlCredentials(certificate!)),
      );
      client = CoreClient(
        channel,
        options: controlCallOptions(_firstSecret).mergedWith(CallOptions(timeout: const Duration(seconds: 15))),
      );
      final interface = CoreInterface()
        ..fgClient = client
        ..bgClient = client;
      SharedPreferences.setMockInitialValues({'enable-clash-api': false});
      final preferences = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [
          dbProvider.overrideWithValue(database),
          sharedPreferencesProvider.overrideWith((ref) => preferences),
          appDirectoriesProvider.overrideWith(() => _FixtureDirectories(directories)),
          httpClientProvider.overrideWith((ref) => download),
          hiddifyCoreServiceFactoryProvider.overrideWithValue((ref) => HiddifyCoreService(ref, core: interface)),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      await container.read(appDirectoriesProvider.future);
      service = container.read(hiddifyCoreServiceProvider);
      final repository = await container.read(profileRepositoryProvider.future);
      final dao = ProfileDao(database);

      final imported = await repository.upsertRemote(_FixtureSubscription.url).run();
      expect(imported.isRight(), isTrue, reason: 'real packaged validator must accept the synthetic subscription');
      final profile = await dao.getByUrl(_FixtureSubscription.url);
      expect(profile, isNotNull);
      expect(profile!.name, 'Packaged validator fixture');
      expect(await dao.watchProfilesCount().first, 1);
      final file = container.read(profilePathResolverProvider).file(profile.id);
      final before = await file.readAsString();
      final normalized = jsonDecode(before) as Map<String, dynamic>;
      expect(normalized['outbounds'], isNotEmpty);
      expect(before, contains('192.0.2.1'));
      final generated = await repository.generateConfig(profile.id).run();
      expect(generated.isRight(), isTrue);
      generated.fold((failure) => fail('generation failed'), (content) => expect(jsonDecode(content), isA<Map>()));

      // Core validation must reject a syntactically plausible but unsupported outbound.
      download.content = '{"outbounds":[{"type":"audit-invalid-outbound","tag":"invalid"}]}';
      final rejected = await repository.upsertRemote(_FixtureSubscription.url).run();
      expect(rejected.isLeft(), isTrue, reason: 'the real validator must reject the invalid update');
      expect(await dao.watchProfilesCount().first, 1);
      expect((await dao.getById(profile.id))?.name, profile.name);
      expect(await file.readAsString(), before);
      final remaining = file.parent.listSync().whereType<File>().map((file) => file.path).toList();
      expect(remaining, [file.path]);
      completed = true;
    } finally {
      final cleanupFailures = <String>[];
      if (service != null) await _attemptCleanup('service', service.dispose, cleanupFailures);
      await _attemptCleanup('container', () => container?.dispose(), cleanupFailures);
      if (client != null) {
        await _attemptCleanup('core', () async {
          try {
            await client!.close(
              CloseRequest(mode: SetupMode.GRPC_BACKGROUND_INSECURE),
              options: CallOptions(timeout: const Duration(seconds: 5)),
            );
          } on GrpcError catch (error) {
            if (error.code != StatusCode.unknown && error.code != StatusCode.unavailable) rethrow;
          }
        }, cleanupFailures);
      }
      if (channel != null) await _attemptCleanup('channel', channel.terminate, cleanupFailures);
      await _attemptCleanup('database', database.close, cleanupFailures);
      Directory.current = originalWorkingDirectory;
      await _attemptCleanup('directory', () async => await root.delete(recursive: true), cleanupFailures);
      if (cleanupFailures.isNotEmpty) {
        final message = 'packaged validator cleanup failed: ${cleanupFailures.join(', ')}';
        if (completed) fail(message);
        // Keep the original assertion/RPC failure when cleanup also fails.
        debugPrint(message);
      }
    }
  });
}

Future<void> _attemptCleanup(String stage, FutureOr<void> Function() action, List<String> failures) async {
  try {
    await Future<void>.sync(action).timeout(const Duration(seconds: 5));
  } catch (error) {
    failures.add('$stage (${error.runtimeType})');
  }
}

final class _FixtureDirectories extends AppDirectories {
  _FixtureDirectories(this.directories);
  final Directories directories;
  @override
  Future<Directories> build() async => directories;
}

// HTTP input is fixed and provider state is isolated. Parser, repository, Drift,
// option serialization, service, authenticated RPC and packaged core are real;
// core bootstrap uses the simulator bridge rather than the shipping OS setup.
final class _FixtureSubscription extends DioHttpClient {
  _FixtureSubscription()
    : super(timeout: const Duration(seconds: 5), userAgent: 'packaged-validator-test', debug: false);
  static const url = 'https://example.invalid/packaged-validator-fixture';
  String content =
      '{"outbounds":[{"type":"shadowsocks","tag":"audit-ss","server":"192.0.2.1",'
      '"server_port":443,"method":"aes-128-gcm","password":"public-test-fixture"}]}';

  @override
  Future<Response> downloadProfile(
    String url,
    String path, {
    CancelToken? cancelToken,
    String? userAgent,
    Duration timeLimit = const Duration(seconds: 30),
  }) async {
    expect(url, _FixtureSubscription.url);
    await File(path).writeAsString(content);
    return Response(
      requestOptions: RequestOptions(path: url),
      statusCode: 200,
      headers: Headers.fromMap({
        'profile-title': ['Packaged validator fixture'],
      }),
    );
  }
}
