import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/data/connection_data_providers.dart';
import 'package:hiddify/features/connection/data/connection_repository.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _failureA = ConnectionFailure.backgroundCoreNotAvailable('attempt A failed');
const _waitTimeout = Duration(seconds: 2);
final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('start Left followed by its late disconnected error presents one alert', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);
    harness.repository.enqueue(left(_failureA));

    await harness.notifier.toggleConnection();
    await harness.settle();
    expect(harness.dialogs.errors, hasLength(1));
    final handledFailureState = harness.container.read(connectionNotifierProvider);
    expect(handledFailureState, isA<AsyncError<ConnectionStatus>>());

    harness.repository.emitStopped(operationId: harness.repository.operationIds.single);
    await harness.settle();

    expect(harness.dialogs.errors, hasLength(1));
    expect(harness.container.read(connectionNotifierProvider), handledFailureState);
  });

  test('late error from attempt A cannot replace retry B connecting state', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);
    harness.repository.enqueue(left(_failureA));

    await harness.notifier.toggleConnection();
    await harness.settle();
    expect(harness.container.read(connectionNotifierProvider), isA<AsyncError<ConnectionStatus>>());
    final operationA = harness.repository.operationIds.single;

    final retryResult = Completer<Either<ConnectionFailure, Unit>>();
    harness.repository.enqueueFuture(retryResult.future);
    final retry = harness.notifier.toggleConnection();
    await harness.waitForConnectCalls(2);
    await harness.settle();
    expect(harness.container.read(connectionNotifierProvider).valueOrNull, const Connecting());

    harness.repository.emitStopped(operationId: operationA);
    await harness.settle();
    final stateAfterLateA = harness.container.read(connectionNotifierProvider).valueOrNull;

    retryResult.complete(right(unit));
    await retry;
    expect(stateAfterLateA, const Connecting());
  });

  test('late error from attempt A cannot replace retry B handled failure', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);
    harness.repository.enqueue(left(_failureA));
    harness.repository.enqueue(left(_failureA));

    await harness.notifier.toggleConnection();
    final operationA = harness.repository.operationIds.single;
    await harness.notifier.toggleConnection();
    await harness.settle();
    final handledFailureB = harness.container.read(connectionNotifierProvider);

    harness.repository.emitStopped(operationId: operationA);
    await harness.settle();

    expect(harness.dialogs.errors, hasLength(2));
    expect(handledFailureB, isA<AsyncError<ConnectionStatus>>());
    expect(harness.container.read(connectionNotifierProvider), handledFailureB);
  });

  test('current retry failure remains visible when its operation ID matches', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);
    final result = Completer<Either<ConnectionFailure, Unit>>();
    harness.repository.enqueueFuture(result.future);

    final attempt = harness.notifier.toggleConnection();
    await harness.waitForConnectCalls(1);
    harness.repository.emitStopped(operationId: harness.repository.operationIds.single);
    await harness.settle();
    final status = harness.container.read(connectionNotifierProvider).valueOrNull;

    result.complete(right(unit));
    await attempt;
    expect(status, isA<Disconnected>());
    expect((status! as Disconnected).connectionFailure, isNotNull);
  });

  test('uncorrelated terminal failure remains visible for compatibility', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);
    final result = Completer<Either<ConnectionFailure, Unit>>();
    harness.repository.enqueueFuture(result.future);

    final attempt = harness.notifier.toggleConnection();
    await harness.waitForConnectCalls(1);
    harness.repository.emitStopped();
    await harness.settle();
    final status = harness.container.read(connectionNotifierProvider).valueOrNull;

    result.complete(right(unit));
    await attempt;
    expect(status, isA<Disconnected>());
    expect((status! as Disconnected).connectionFailure, isNotNull);
  });

  test('uncorrelated terminal does not retire a later tagged current failure', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);
    final result = Completer<Either<ConnectionFailure, Unit>>();
    harness.repository.enqueueFuture(result.future);

    final attempt = harness.notifier.toggleConnection();
    await harness.waitForConnectCalls(1);
    final operationId = harness.repository.operationIds.single;
    harness.repository.emitStopped();
    harness.repository.emitStarted(operationId: operationId);
    result.complete(right(unit));
    await attempt;
    await harness.settle();
    expect(harness.container.read(connectionNotifierProvider).valueOrNull, const Connected());

    harness.repository.emitStopped(operationId: operationId);
    await harness.settle();
    final status = harness.container.read(connectionNotifierProvider).valueOrNull;

    expect(status, isA<Disconnected>());
    final disconnected = status! as Disconnected;
    expect(disconnected.operationId, operationId);
    expect(disconnected.connectionFailure, isNotNull);
  });

  test('uncorrelated terminal does not revive an explicitly handled attempt', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);
    harness.repository.enqueue(left(_failureA));

    await harness.notifier.toggleConnection();
    final operationA = harness.repository.operationIds.single;
    harness.repository.emitStopped();
    await harness.settle();
    final uncorrelatedState = harness.container.read(connectionNotifierProvider);

    harness.repository.emitStopped(operationId: operationA);
    await harness.settle();

    expect(uncorrelatedState.valueOrNull, isA<Disconnected>());
    expect((uncorrelatedState.valueOrNull! as Disconnected).operationId, isNull);
    expect(harness.container.read(connectionNotifierProvider), uncorrelatedState);
  });

  test('current operation failure remains visible after the tunnel connected', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);
    final result = Completer<Either<ConnectionFailure, Unit>>();
    harness.repository.enqueueFuture(result.future);

    final attempt = harness.notifier.toggleConnection();
    await harness.waitForConnectCalls(1);
    final operationId = harness.repository.operationIds.single;
    harness.repository.emitStarted(operationId: operationId);
    result.complete(right(unit));
    await attempt;
    await harness.settle();
    expect(harness.container.read(connectionNotifierProvider).valueOrNull, const Connected());

    harness.repository.emitStopped(operationId: operationId);
    await harness.settle();
    final status = harness.container.read(connectionNotifierProvider).valueOrNull;

    expect(status, isA<Disconnected>());
    expect((status! as Disconnected).connectionFailure, isNotNull);
  });

  test('double tap while start is pending submits one connection attempt', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);
    final result = Completer<Either<ConnectionFailure, Unit>>();
    harness.repository.enqueueFuture(result.future);

    final first = harness.notifier.toggleConnection();
    await harness.waitForConnectCalls(1);
    final second = harness.notifier.toggleConnection();
    await harness.settle();

    expect(harness.repository.connectCalls, 1);
    result.complete(right(unit));
    await Future.wait([first, second]);
  });

  test('failed start owns its error lifecycle before allowing the next attempt', () async {
    final dialogsReleased = Completer<void>();
    final harness = await _Harness.create(dialogBlocker: dialogsReleased.future);
    addTearDown(harness.dispose);
    harness.repository.enqueue(left(_failureA));

    var firstCompleted = false;
    final first = harness.notifier.toggleConnection()..then((_) => firstCompleted = true);
    await harness.dialogs.entered.future.timeout(_waitTimeout);
    await harness.settle();
    final stateWhileDialogIsOpen = harness.container.read(connectionNotifierProvider);
    final completedWhileDialogIsOpen = firstCompleted;

    await harness.notifier.toggleConnection();
    final callsWhileDialogIsOpen = harness.repository.connectCalls;

    dialogsReleased.complete();
    await first.timeout(_waitTimeout);
    await harness.settle();
    harness.repository.enqueue(right(unit));
    await harness.notifier.toggleConnection();

    expect(stateWhileDialogIsOpen, isA<AsyncError<ConnectionStatus>>());
    expect(completedWhileDialogIsOpen, isFalse);
    expect(callsWhileDialogIsOpen, 1);
    expect(harness.repository.connectCalls, 2);
  });
}

final class _Harness {
  _Harness({
    required this.container,
    required this.repository,
    required this.dialogs,
    required this.subscription,
    required this.dependencies,
    required this.tempDir,
  });

  final ProviderContainer container;
  final _ConnectionRepository repository;
  final _RecordingDialogs dialogs;
  final ProviderSubscription<AsyncValue<ConnectionStatus>> subscription;
  final ProviderContainer dependencies;
  final Directory tempDir;

  ConnectionNotifier get notifier => container.read(connectionNotifierProvider.notifier);

  static Future<_Harness> create({Future<void>? dialogBlocker}) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final translations = await AppLocale.en.build();
    final tempDir = await Directory.systemTemp.createTemp('connection-attempt-lifecycle-');
    final dependencies = ProviderContainer();
    final ref = dependencies.read(_refProvider);
    final core = _CoreService(ref);
    final repository = _ConnectionRepository(ref: ref, core: core, tempDir: tempDir);
    final dialogs = _RecordingDialogs(dialogBlocker);
    final profile = ProfileEntity.local(
      id: 'connection-attempt-profile',
      active: true,
      name: 'Connection attempt profile',
      lastUpdate: DateTime.utc(2026, 10, 2),
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => preferences),
        translationsProvider.overrideWith((ref) => translations),
        connectionRepositoryProvider.overrideWith((ref) => repository),
        connectionNotifierProvider.overrideWith(() => ConnectionNotifier(initializeOnBuild: false)),
        activeProfileProvider.overrideWith(() => _ActiveProfile(profile)),
        hapticServiceProvider.overrideWith(_NoHaptic.new),
        dialogNotifierProvider.overrideWith(() => dialogs),
      ],
    );
    final subscription = container.listen(connectionNotifierProvider, (_, _) {}, fireImmediately: true);
    await container.read(connectionNotifierProvider.future);
    return _Harness(
      container: container,
      repository: repository,
      dialogs: dialogs,
      subscription: subscription,
      dependencies: dependencies,
      tempDir: tempDir,
    );
  }

  Future<void> waitForConnectCalls(int count) async {
    for (var i = 0; i < 1000 && repository.connectCalls < count; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(repository.connectCalls, count);
  }

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> dispose() async {
    subscription.close();
    container.dispose();
    await repository.close();
    dependencies.dispose();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  }
}

final class _ConnectionRepository extends ConnectionRepositoryImpl {
  _ConnectionRepository({required super.ref, required _CoreService core, required Directory tempDir})
    : _core = core,
      super(
        directories: (baseDir: tempDir, workingDir: tempDir, tempDir: tempDir),
        singbox: core,
        configOptionRepository: _UnusedConfigOptions(),
        profilePathResolver: ProfilePathResolver(tempDir),
      );

  final _CoreService _core;
  final _results = <Future<Either<ConnectionFailure, Unit>>>[];
  final operationIds = <String>[];
  int connectCalls = 0;

  void enqueue(Either<ConnectionFailure, Unit> result) => enqueueFuture(Future.value(result));

  void enqueueFuture(Future<Either<ConnectionFailure, Unit>> result) => _results.add(result);

  void emitStarted({required String operationId}) {
    _core.emitNative({'status': 'Started', 'operation_id': operationId});
  }

  void emitStopped({String? operationId}) {
    _core.emitNative({
      'status': 'Stopped',
      'alert': 'startFailed',
      'message': 'same failure for every attempt',
      if (operationId != null) 'operation_id': operationId,
    });
  }

  Future<void> close() => _core.close();

  @override
  TaskEither<ConnectionFailure, Unit> connect(
    ProfileEntity activeProfile,
    bool disableMemoryLimit, {
    String? operationId,
  }) => TaskEither(() {
    connectCalls++;
    operationIds.add(operationId!);
    _core.emit(const CoreStarting());
    return _results.removeAt(0);
  });
}

final class _CoreService implements HiddifyCoreService {
  _CoreService(this.ref);

  @override
  final Ref ref;
  final _statuses = BehaviorSubject<CoreStatus>.seeded(const CoreStopped());

  void emit(CoreStatus status) => _statuses.add(status);

  void emitNative(Map<String, Object> event) => _statuses.add(CoreStatus.fromEvent(event));

  Future<void> close() => _statuses.close();

  @override
  Stream<CoreStatus> watchStatus() => _statuses.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _UnusedConfigOptions implements ConfigOptionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ActiveProfile extends ActiveProfile {
  _ActiveProfile(this.profile);

  final ProfileEntity profile;

  @override
  Stream<ProfileEntity?> build() => Stream.value(profile);
}

final class _NoHaptic extends HapticService {
  @override
  bool build() => false;
}

final class _RecordingDialogs extends DialogNotifier {
  _RecordingDialogs(this.blocker);

  final Future<void>? blocker;
  final errors = <({String type, String? message})>[];
  final entered = Completer<void>();

  @override
  void build() {}

  @override
  Future<void> showCustomAlertFromErr(({String type, String? message}) err) async {
    errors.add(err);
    if (!entered.isCompleted) entered.complete();
    await blocker;
  }
}
