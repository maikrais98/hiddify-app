import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/model/optional_range.dart';
import 'package:hiddify/features/connection/data/connection_repository.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/diagnostics/observed_connection_repository.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_event.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_journal.dart';
import 'package:hiddify/features/log/model/log_level.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/model/config_option_failure.dart';
import 'package:hiddify/features/settings/notifier/warp_option/warp_option_notifier.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  late Directory tempDir;
  late ProviderContainer container;
  late ProfileEntity profile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('connection-repository-test-');
    container = ProviderContainer(overrides: [warpLicenseNotifierProvider.overrideWith(_GrantedWarpLicense.new)]);
    profile = ProfileEntity.local(id: 'profile-id', active: true, name: 'Test profile', lastUpdate: DateTime.utc(2026));
  });

  tearDown(() {
    container.dispose();
    tempDir.deleteSync(recursive: true);
  });

  test('iOS connection phases share the lazy command attempt without changing core call order', () async {
    final journal = SafeDiagnosticJournal();
    addTearDown(journal.dispose);
    final core = _FakeCoreService(
      container.read(_refProvider),
      ios: true,
      readinessResults: [Future.value(true)],
      changeOptionsResults: [right(unit)],
    );
    final repository = ObservedConnectionRepository(
      _repository(container, tempDir, core, _FakeConfigOptionRepository(right(_options('observed')))),
      journal,
    );
    final task = repository.connect(profile, false);
    expect(journal.events, isEmpty);
    expect(core.readinessCalls, 0);

    final result = await task.run();

    expect(result, isA<Right<ConnectionFailure, Unit>>());
    final phases = journal.events.where((event) => event.phase != null).toList();
    expect(phases.map((event) => '${event.phase!.name}:${event.stage.name}'), [
      'foregroundReady:requested',
      'foregroundReady:accepted',
      'optionsReady:accepted',
      'changeOptions:requested',
      'changeOptions:accepted',
      'backgroundStart:requested',
      'backgroundStart:accepted',
    ]);
    expect(phases.map((event) => event.operationId).toSet(), {journal.events.first.operationId});
    expect(core.readinessCalls, 1);
    expect(core.changeOptionsCalls, hasLength(1));
    expect(core.startCalls, hasLength(1));
  });

  test('concurrent connection attempts keep distinct phase IDs through shared readiness', () async {
    final journal = SafeDiagnosticJournal();
    addTearDown(journal.dispose);
    final firstReady = Completer<bool>();
    final core = _FakeCoreService(
      container.read(_refProvider),
      ios: true,
      readinessResults: [firstReady.future],
      changeOptionsResults: [right(unit), right(unit)],
    );
    final repository = ObservedConnectionRepository(
      _repository(container, tempDir, core, _FakeConfigOptionRepository(right(_options('concurrent')))),
      journal,
    );
    final first = repository.connect(profile, false).run();
    final second = repository.reconnect(profile, true).run();
    await Future<void>.delayed(Duration.zero);
    firstReady.complete(true);
    await Future.wait([first, second]);

    final requested = journal.events.where(
      (event) => event.phase?.name == 'foregroundReady' && event.stage == DiagnosticStage.requested,
    );
    expect(requested, hasLength(2));
    final ids = {for (final event in requested) event.operation: event.operationId};
    expect(ids.values.toSet(), hasLength(2));
    for (final event in journal.events.where((event) => event.phase != null)) {
      expect(event.operationId, ids[event.operation]);
    }
  });

  test('connect returns changeOptions Left without starting or publishing the rejected snapshot', () async {
    final options = _options('rejected-connect');
    final core = _FakeCoreService(container.read(_refProvider), changeOptionsResults: [left('options rejected')]);
    final repository = _repository(container, tempDir, core, _FakeConfigOptionRepository(right(options)));

    final result = await repository.connect(profile, false).run();

    _expectRejectedOptions(result, 'options rejected');
    expect(core.startCalls, isEmpty);
    expect(repository.configOptionsSnapshot, isNull);
  });

  test('reconnect returns changeOptions Left without restarting', () async {
    final options = _options('rejected-reconnect');
    final core = _FakeCoreService(container.read(_refProvider), changeOptionsResults: [left('options rejected')]);
    final repository = _repository(container, tempDir, core, _FakeConfigOptionRepository(right(options)));

    final result = await repository.reconnect(profile, true).run();

    _expectRejectedOptions(result, 'options rejected');
    expect(core.restartCalls, isEmpty);
    expect(repository.configOptionsSnapshot, isNull);
  });

  test('failed update preserves the last successfully applied snapshot', () async {
    final originalOptions = _options('original');
    final rejectedOptions = _options('rejected');
    final config = _FakeConfigOptionRepository(right(originalOptions));
    final core = _FakeCoreService(
      container.read(_refProvider),
      changeOptionsResults: [right(unit), left('updated options rejected')],
    );
    final repository = _repository(container, tempDir, core, config);
    expect(await repository.connect(profile, false).run(), isA<Right<ConnectionFailure, Unit>>());

    config.result = right(rejectedOptions);
    final result = await repository.reconnect(profile, false).run();

    _expectRejectedOptions(result, 'updated options rejected');
    expect(core.restartCalls, isEmpty);
    expect(repository.configOptionsSnapshot, same(originalOptions));
  });

  test('successful connect publishes snapshot after changeOptions and starts the exact profile once', () async {
    final options = _options('connect-success');
    final core = _FakeCoreService(container.read(_refProvider), changeOptionsResults: [right(unit)]);
    final repository = _repository(container, tempDir, core, _FakeConfigOptionRepository(right(options)));
    SingboxConfigOption? snapshotDuringChange;
    core.beforeChangeOptionsResult = () => snapshotDuringChange = repository.configOptionsSnapshot;

    final result = await repository.connect(profile, true).run();

    expect(result, isA<Right<ConnectionFailure, Unit>>());
    expect(snapshotDuringChange, isNull);
    expect(repository.configOptionsSnapshot, same(options));
    expect(core.startCalls, [
      (path: ProfilePathResolver(tempDir).file(profile.id).path, name: profile.name, disableMemoryLimit: true),
    ]);
  });

  test('successful reconnect replaces snapshot after changeOptions and restarts the exact profile once', () async {
    final originalOptions = _options('original');
    final updatedOptions = _options('updated');
    final config = _FakeConfigOptionRepository(right(originalOptions));
    final core = _FakeCoreService(container.read(_refProvider), changeOptionsResults: [right(unit), right(unit)]);
    final repository = _repository(container, tempDir, core, config);
    expect(await repository.connect(profile, false).run(), isA<Right<ConnectionFailure, Unit>>());
    config.result = right(updatedOptions);
    SingboxConfigOption? snapshotDuringChange;
    core.beforeChangeOptionsResult = () => snapshotDuringChange = repository.configOptionsSnapshot;

    final result = await repository.reconnect(profile, true).run();

    expect(result, isA<Right<ConnectionFailure, Unit>>());
    expect(snapshotDuringChange, same(originalOptions));
    expect(repository.configOptionsSnapshot, same(updatedOptions));
    expect(core.restartCalls, [
      (path: ProfilePathResolver(tempDir).file(profile.id).path, name: profile.name, disableMemoryLimit: true),
    ]);
  });

  test('connect can retry changeOptions after a rejection', () async {
    final options = _options('retry');
    final core = _FakeCoreService(
      container.read(_refProvider),
      changeOptionsResults: [left('transient rejection'), right(unit)],
    );
    final repository = _repository(container, tempDir, core, _FakeConfigOptionRepository(right(options)));

    final first = await repository.connect(profile, false).run();
    final second = await repository.connect(profile, false).run();

    _expectRejectedOptions(first, 'transient rejection');
    expect(second, isA<Right<ConnectionFailure, Unit>>());
    expect(core.changeOptionsCalls, [options, options]);
    expect(core.startCalls, hasLength(1));
    expect(repository.configOptionsSnapshot, same(options));
  });

  test('invalid profile override still blocks changeOptions and start', () async {
    const configFailure = ConfigOptionFailure.unexpected('invalid override');
    final core = _FakeCoreService(container.read(_refProvider));
    final repository = _repository(container, tempDir, core, _FakeConfigOptionRepository(left(configFailure)));

    final result = await repository.connect(profile, false).run();

    result.match((failure) {
      expect(failure, isA<InvalidConfigOption>());
      expect((failure as InvalidConfigOption).configOptionFailure, same(configFailure));
    }, (_) => fail('connect must return the invalid override failure'));
    expect(core.changeOptionsCalls, isEmpty);
    expect(core.startCalls, isEmpty);
  });

  test('iOS connect joins pending resume readiness after repository setup was already initialized', () async {
    final readiness = Completer<bool>();
    final options = _options('resume-connect');
    final core = _FakeCoreService(
      container.read(_refProvider),
      ios: true,
      readinessResults: [readiness.future],
      changeOptionsResults: [right(unit)],
    );
    final repository = _repository(container, tempDir, core, _FakeConfigOptionRepository(right(options)));
    expect(await repository.setup().run(), isA<Right<ConnectionFailure, Unit>>());

    final resume = core.resume();
    final connect = repository.connect(profile, true).run();
    await Future<void>.delayed(Duration.zero);

    expect(core.setupCalls, 1, reason: 'Repository startup setup remains initialized');
    expect(core.readinessCalls, 2, reason: 'Resume and connect both use the shared readiness operation');
    expect(core.changeOptionsCalls, isEmpty);
    expect(core.startCalls, isEmpty);

    readiness.complete(true);
    await resume;
    expect(await connect, isA<Right<ConnectionFailure, Unit>>());
    expect(core.changeOptionsCalls, [options]);
    expect(core.startCalls, hasLength(1));
  });

  test('iOS reconnect waits for foreground readiness before changing options or restarting', () async {
    final readiness = Completer<bool>();
    final options = _options('resume-reconnect');
    final core = _FakeCoreService(
      container.read(_refProvider),
      ios: true,
      readinessResults: [readiness.future],
      changeOptionsResults: [right(unit)],
    );
    final repository = _repository(container, tempDir, core, _FakeConfigOptionRepository(right(options)));

    final reconnect = repository.reconnect(profile, false).run();
    await Future<void>.delayed(Duration.zero);

    expect(core.readinessCalls, 1);
    expect(core.changeOptionsCalls, isEmpty);
    expect(core.restartCalls, isEmpty);

    readiness.complete(true);
    expect(await reconnect, isA<Right<ConnectionFailure, Unit>>());
    expect(core.changeOptionsCalls, [options]);
    expect(core.restartCalls, hasLength(1));
  });

  test('iOS connect does not trust initialized repository state after a failed resume', () async {
    final options = _options('initialized-after-failed-resume');
    final core = _FakeCoreService(
      container.read(_refProvider),
      ios: true,
      readinessResults: [Future.value(false), Future.value(true)],
      changeOptionsResults: [right(unit)],
    );
    final repository = _repository(container, tempDir, core, _FakeConfigOptionRepository(right(options)));
    expect(await repository.setup().run(), isA<Right<ConnectionFailure, Unit>>());

    await core.resume();
    final result = await repository.connect(profile, false).run();

    expect(result, isA<Right<ConnectionFailure, Unit>>());
    expect(core.setupCalls, 1);
    expect(core.readinessCalls, 2, reason: 'The tap must start recovery again after failed resume');
    expect(core.changeOptionsCalls, [options]);
    expect(core.startCalls, hasLength(1));
  });

  test('failed iOS readiness blocks start and the next connect retries readiness', () async {
    final options = _options('readiness-retry');
    final core = _FakeCoreService(
      container.read(_refProvider),
      ios: true,
      readinessResults: [Future.value(false), Future.value(true)],
      changeOptionsResults: [right(unit)],
    );
    final repository = _repository(container, tempDir, core, _FakeConfigOptionRepository(right(options)));
    expect(await repository.setup().run(), isA<Right<ConnectionFailure, Unit>>());

    final first = await repository.connect(profile, false).run();
    final second = await repository.connect(profile, false).run();

    expect(first, isA<Left<ConnectionFailure, Unit>>());
    first.match(
      (failure) => expect(failure, isA<BackgroundCoreNotAvailable>()),
      (_) => fail('failed foreground readiness must return a core failure'),
    );
    expect(second, isA<Right<ConnectionFailure, Unit>>());
    expect(core.readinessCalls, 2, reason: 'A failed readiness result must not latch across explicit taps');
    expect(core.changeOptionsCalls, [options]);
    expect(core.startCalls, hasLength(1));
  });

  test('iOS exact foreground unavailable marker maps to core failure and preserves the previous snapshot', () async {
    final originalOptions = _options('original-before-foreground-loss');
    final rejectedOptions = _options('rejected-foreground-settings');
    final config = _FakeConfigOptionRepository(right(originalOptions));
    final core = _FakeCoreService(
      container.read(_refProvider),
      ios: true,
      readinessResults: [Future.value(true), Future.value(true)],
      changeOptionsResults: [right(unit), left('foreground_settings_unavailable')],
    );
    final repository = _repository(container, tempDir, core, config);
    expect(await repository.connect(profile, false).run(), isA<Right<ConnectionFailure, Unit>>());
    config.result = right(rejectedOptions);

    final result = await repository.reconnect(profile, false).run();

    result.match((failure) {
      expect(failure, isA<BackgroundCoreNotAvailable>());
      expect((failure as BackgroundCoreNotAvailable).message, 'foreground_settings_unavailable');
    }, (_) => fail('foreground settings unavailability must return a core failure'));
    expect(repository.configOptionsSnapshot, same(originalOptions));
    expect(core.restartCalls, isEmpty);
  });

  test('iOS genuine settings failure remains invalidConfigOption and preserves the previous snapshot', () async {
    final originalOptions = _options('original-before-settings-error');
    final rejectedOptions = _options('rejected-real-settings-error');
    final config = _FakeConfigOptionRepository(right(originalOptions));
    final core = _FakeCoreService(
      container.read(_refProvider),
      ios: true,
      readinessResults: [Future.value(true), Future.value(true)],
      changeOptionsResults: [right(unit), left('real settings error')],
    );
    final repository = _repository(container, tempDir, core, config);
    expect(await repository.connect(profile, false).run(), isA<Right<ConnectionFailure, Unit>>());
    config.result = right(rejectedOptions);

    final result = await repository.reconnect(profile, false).run();

    _expectRejectedOptions(result, 'real settings error');
    expect(repository.configOptionsSnapshot, same(originalOptions));
    expect(core.restartCalls, isEmpty);
  });

  test('non-iOS connect keeps setup flow and does not request foreground readiness', () async {
    final options = _options('non-ios');
    final core = _FakeCoreService(
      container.read(_refProvider),
      readinessResults: [Future.value(false)],
      changeOptionsResults: [right(unit), right(unit)],
    );
    final repository = _repository(container, tempDir, core, _FakeConfigOptionRepository(right(options)));

    expect(await repository.connect(profile, false).run(), isA<Right<ConnectionFailure, Unit>>());
    expect(await repository.reconnect(profile, false).run(), isA<Right<ConnectionFailure, Unit>>());

    expect(core.setupCalls, 1);
    expect(core.readinessCalls, 0);
    expect(core.changeOptionsCalls, [options, options]);
    expect(core.startCalls, hasLength(1));
    expect(core.restartCalls, hasLength(1));
  });
}

void _expectRejectedOptions(Either<ConnectionFailure, Unit> result, String message) {
  result.match((failure) {
    expect(failure, isA<InvalidConfigOption>());
    expect((failure as InvalidConfigOption).message, message);
  }, (_) => fail('operation must return the changeOptions failure'));
}

ConnectionRepositoryImpl _repository(
  ProviderContainer container,
  Directory tempDir,
  HiddifyCoreService core,
  ConfigOptionRepository config,
) {
  final directories = (baseDir: tempDir, workingDir: tempDir, tempDir: tempDir);
  return ConnectionRepositoryImpl(
    ref: container.read(_refProvider),
    directories: directories,
    singbox: core,
    configOptionRepository: config,
    profilePathResolver: ProfilePathResolver(tempDir),
  );
}

class _GrantedWarpLicense extends WarpLicenseNotifier {
  @override
  bool build() => true;
}

class _FakeConfigOptionRepository implements ConfigOptionRepository {
  _FakeConfigOptionRepository(this.result);

  Either<ConfigOptionFailure, SingboxConfigOption> result;

  @override
  Either<ConfigOptionFailure, SingboxConfigOption> fullOptionsOverrided(String? profileOverride) => result;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCoreService implements HiddifyCoreService {
  _FakeCoreService(
    this.ref, {
    bool ios = false,
    List<Future<bool>>? readinessResults,
    List<Either<String, Unit>>? changeOptionsResults,
  }) : core = _FakeCoreInterface(ios),
       readinessResults = readinessResults ?? <Future<bool>>[],
       changeOptionsResults = changeOptionsResults ?? <Either<String, Unit>>[];

  @override
  final Ref ref;
  @override
  final CoreInterface core;
  final List<Future<bool>> readinessResults;
  final List<Either<String, Unit>> changeOptionsResults;
  final List<SingboxConfigOption> changeOptionsCalls = [];
  final List<({String path, String name, bool disableMemoryLimit})> startCalls = [];
  final List<({String path, String name, bool disableMemoryLimit})> restartCalls = [];
  int setupCalls = 0;
  int readinessCalls = 0;
  Future<bool>? _foregroundReadiness;
  void Function()? beforeChangeOptionsResult;

  @override
  TaskEither<String, Unit> setup() => TaskEither(() async {
    setupCalls++;
    return right(unit);
  });

  @override
  Future<bool> ensureForegroundReady() {
    readinessCalls++;
    final pending = _foregroundReadiness;
    if (pending != null) return pending;
    late final Future<bool> readiness;
    readiness = readinessResults.removeAt(0).whenComplete(() {
      if (identical(_foregroundReadiness, readiness)) _foregroundReadiness = null;
    });
    return _foregroundReadiness = readiness;
  }

  @override
  Future<void> resume() async {
    await ensureForegroundReady();
  }

  @override
  TaskEither<String, Unit> changeOptions(SingboxConfigOption options) => TaskEither(() async {
    changeOptionsCalls.add(options);
    beforeChangeOptionsResult?.call();
    return changeOptionsResults.removeAt(0);
  });

  @override
  TaskEither<ConnectionFailure, Unit> start(String path, String name, bool disableMemoryLimit) {
    startCalls.add((path: path, name: name, disableMemoryLimit: disableMemoryLimit));
    return TaskEither.right(unit);
  }

  @override
  TaskEither<String, Unit> restart(String path, String name, bool disableMemoryLimit) {
    restartCalls.add((path: path, name: name, disableMemoryLimit: disableMemoryLimit));
    return TaskEither.right(unit);
  }

  @override
  Stream<CoreStatus> watchStatus() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCoreInterface extends CoreInterface {
  _FakeCoreInterface(this.ios);

  final bool ios;

  @override
  bool get supportsSystemStatus => ios;
}

SingboxConfigOption _options(String region) {
  const range = OptionalRange();
  const warp = SingboxWarpOption(
    enable: false,
    mode: WarpDetourMode.proxyOverWarp,
    wireguardConfig: '',
    licenseKey: '',
    accountId: '',
    accessToken: '',
    cleanIp: '',
    cleanPort: 0,
    noise: range,
    noiseSize: range,
    noiseDelay: range,
    noiseMode: '',
  );
  const tls = SingboxTlsTricks(
    enableFragment: false,
    fragmentSize: range,
    fragmentSleep: range,
    mixedSniCase: false,
    enablePadding: false,
    paddingSize: range,
  );
  return SingboxConfigOption(
    region: region,
    balancerStrategy: BalancerStrategy.roundRobin,
    blockAds: false,
    useXrayCoreWhenPossible: false,
    executeConfigAsIs: false,
    logLevel: LogLevel.warn,
    resolveDestination: false,
    ipv6Mode: IPv6Mode.disable,
    remoteDnsAddress: 'https://dns.example.invalid/dns-query',
    remoteDnsDomainStrategy: DomainStrategy.auto,
    directDnsAddress: 'https://direct-dns.example.invalid/dns-query',
    directDnsDomainStrategy: DomainStrategy.auto,
    mixedPort: 1234,
    tproxyPort: 1235,
    directPort: 1236,
    redirectPort: 1237,
    tunImplementation: TunImplementation.mixed,
    mtu: 1500,
    strictRoute: false,
    connectionTestUrl: 'https://probe.example.invalid/',
    urlTestInterval: const Duration(minutes: 1),
    enableClashApi: false,
    clashApiPort: 9090,
    enableTun: true,
    setSystemProxy: false,
    bypassLan: false,
    allowConnectionFromLan: false,
    enableFakeDns: false,
    independentDnsCache: false,
    rules: const [],
    tlsTricks: tls,
    warp: warp,
    warp2: warp,
  );
}
