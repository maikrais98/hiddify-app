import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/features/connection/data/connection_repository.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/model/config_option_failure.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  late Directory tempDir;
  late ProviderContainer container;
  late SingboxConfigOption options;
  late ProfileEntity profile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('connection-repository-test-');
    container = ProviderContainer();
    options = _TestConfigOptions();
    profile = ProfileEntity.local(id: 'profile-id', active: true, name: 'Test', lastUpdate: DateTime.utc(2026));
  });

  tearDown(() {
    container.dispose();
    tempDir.deleteSync(recursive: true);
  });

  test('changeOptions Left reaches the caller and blocks start', () async {
    final core = _FakeCoreService(container.read(_refProvider), changeOptionsResult: left('options rejected'));
    final repository = _repository(container, tempDir, core, options);

    final result = await repository.connect(profile, false).run();

    result.match((failure) {
      expect(failure, isA<InvalidConfigOption>());
      expect((failure as InvalidConfigOption).message, 'options rejected');
    }, (_) => fail('connect must return the changeOptions failure'));
    expect(core.startCalls, 0);
    expect(repository.configOptionsSnapshot, isNull);
  });

  test('changeOptions Right preserves start and publishes the snapshot', () async {
    final core = _FakeCoreService(container.read(_refProvider), changeOptionsResult: right(unit));
    final repository = _repository(container, tempDir, core, options);

    final result = await repository.connect(profile, false).run();

    expect(result, isA<Right<ConnectionFailure, Unit>>());
    expect(core.startCalls, 1);
    expect(identical(repository.configOptionsSnapshot, options), isTrue);
  });

  test('changeOptions exception reaches the caller as unexpected and blocks start', () async {
    final error = StateError('changeOptions crashed');
    final core = _FakeCoreService(container.read(_refProvider), changeOptionsError: error);
    final repository = _repository(container, tempDir, core, options);

    final result = await repository.connect(profile, false).run();

    result.match((failure) {
      expect(failure, isA<UnexpectedConnectionFailure>());
      expect((failure as UnexpectedConnectionFailure).error, same(error));
    }, (_) => fail('connect must return the thrown changeOptions error'));
    expect(core.startCalls, 0);
    expect(repository.configOptionsSnapshot, isNull);
  });

  test('reconnect Left keeps the last successfully applied snapshot and blocks restart', () async {
    final originalOptions = _TestConfigOptions();
    final rejectedOptions = _TestConfigOptions();
    final configOptions = _FakeConfigOptionRepository(originalOptions);
    final core = _FakeCoreService(container.read(_refProvider), changeOptionsResult: right(unit));
    final repository = _repository(container, tempDir, core, originalOptions, configOptionRepository: configOptions);
    expect(await repository.connect(profile, false).run(), isA<Right<ConnectionFailure, Unit>>());

    configOptions.options = rejectedOptions;
    core.changeOptionsResult = left('updated options rejected');
    final result = await repository.reconnect(profile, false).run();

    expect(result, isA<Left<ConnectionFailure, Unit>>());
    expect(core.restartCalls, 0);
    expect(identical(repository.configOptionsSnapshot, originalOptions), isTrue);
  });
}

ConnectionRepositoryImpl _repository(
  ProviderContainer container,
  Directory tempDir,
  HiddifyCoreService core,
  SingboxConfigOption options, {
  ConfigOptionRepository? configOptionRepository,
}) {
  final directories = (baseDir: tempDir, workingDir: tempDir, tempDir: tempDir);
  return ConnectionRepositoryImpl(
    ref: container.read(_refProvider),
    directories: directories,
    singbox: core,
    configOptionRepository: configOptionRepository ?? _FakeConfigOptionRepository(options),
    profilePathResolver: ProfilePathResolver(tempDir),
  );
}

class _FakeConfigOptionRepository implements ConfigOptionRepository {
  _FakeConfigOptionRepository(this.options);

  SingboxConfigOption options;

  @override
  Either<ConfigOptionFailure, SingboxConfigOption> fullOptionsOverrided(String? profileOverride) => right(options);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCoreService implements HiddifyCoreService {
  _FakeCoreService(this.ref, {Either<String, Unit>? changeOptionsResult, this.changeOptionsError})
    : changeOptionsResult = changeOptionsResult ?? right(unit);

  @override
  final Ref ref;
  Either<String, Unit> changeOptionsResult;
  final Object? changeOptionsError;
  int startCalls = 0;
  int restartCalls = 0;

  @override
  TaskEither<String, Unit> setup() => TaskEither.of(unit);

  @override
  TaskEither<String, Unit> changeOptions(SingboxConfigOption options) {
    if (changeOptionsError case final error?) {
      return TaskEither(() async => throw error);
    }
    return TaskEither.fromEither(changeOptionsResult);
  }

  @override
  TaskEither<ConnectionFailure, Unit> start(String path, String name, bool disableMemoryLimit) {
    startCalls++;
    return TaskEither.of(unit);
  }

  @override
  TaskEither<String, Unit> restart(String path, String name, bool disableMemoryLimit) {
    restartCalls++;
    return TaskEither.of(unit);
  }

  @override
  Stream<CoreStatus> watchStatus() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestConfigOptions implements SingboxConfigOption {
  @override
  ChainStatus get chainStatus => ChainStatus.off;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
