import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:loggy/loggy.dart';

const _secretUrl = 'https://private.example/access?token=profile-secret-73e129';
const _secretName = 'private-profile-name-73e129';
const _secretError = 'raw-profile-error-73e129';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ObservabilityPrinter printer;

  setUp(() {
    printer = _ObservabilityPrinter();
    Loggy.initLoggy(logPrinter: printer);
  });

  tearDown(() => Loggy.initLoggy());

  Future<ProviderContainer> importContainer(_ProfileRepository repo) async {
    final container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWith((ref) => Future.value(repo))],
    );
    addTearDown(container.dispose);
    container.listen(addProfileNotifierProvider, (_, _) {});
    container.listen(importPhaseProvider, (_, _) {});
    await container.read(profileRepositoryProvider.future);
    return container;
  }

  test('remote import emits one correlated safe lifecycle and no private values', () async {
    final container = await importContainer(_ProfileRepository());

    await container
        .read(addProfileNotifierProvider.notifier)
        .addManual(
          url: _secretUrl,
          userOverride: const UserOverride(name: _secretName),
        );

    final events = printer.accessEvents;
    expect(events.map((event) => event['event']), [
      'operation_started',
      'access_validating',
      'access_fetching',
      'access_parsing',
      'access_validating',
      'access_persisting',
      'operation_succeeded',
    ]);
    expect(events.map((event) => event['operation_id']).toSet(), hasLength(1));
    expect(events.last['duration_ms'], isNonNegative);
    expect(jsonEncode(events), isNot(contains(_secretUrl)));
    expect(jsonEncode(events), isNot(contains(_secretName)));
  });

  test('duplicate submission emits no second operation and retry gets a new id', () async {
    final repo = _ProfileRepository()
      ..pending = Completer<void>()
      ..remoteFailure = const ProfileFailure.unexpected(_secretError);
    final container = await importContainer(repo);
    final notifier = container.read(addProfileNotifierProvider.notifier);

    final first = notifier.addClipboard(_secretUrl);
    await Future<void>.delayed(Duration.zero);
    await notifier.addClipboard(_secretUrl);
    expect(printer.accessEvents.where((event) => event['event'] == 'operation_started'), hasLength(1));

    repo.pending!.complete();
    await first;
    final firstId = printer.accessEvents.first['operation_id'];
    expect(printer.accessEvents.last, containsPair('error_code', 'access_unexpected'));

    repo.remoteFailure = null;
    await notifier.retry();
    final starts = printer.accessEvents.where((event) => event['event'] == 'operation_started').toList();
    expect(starts, hasLength(2));
    expect(starts.last['operation_id'], isNot(firstId));
    expect(printer.accessEvents.last['status'], 'succeeded');
    expect(jsonEncode(printer.accessEvents), isNot(contains(_secretError)));
  });

  test('cancel is a single non-error terminal event and late completion cannot succeed', () async {
    final repo = _ProfileRepository()..pending = Completer<void>();
    final container = await importContainer(repo);
    final notifier = container.read(addProfileNotifierProvider.notifier);

    final operation = notifier.addClipboard(_secretUrl);
    await Future<void>.delayed(Duration.zero);
    notifier.cancel();
    repo.pending!.complete();
    await operation;

    final events = printer.accessEvents;
    expect(events.where((event) => event['event'] == 'operation_cancelled'), hasLength(1));
    expect(events.where((event) => event['event'] == 'operation_succeeded'), isEmpty);
    expect(events.last['status'], 'cancelled');
    expect(printer.accessLevels.last, LogLevel.info);
  });

  test('local import separates known invalid configuration from an unknown failure', () async {
    final repo = _ProfileRepository()..localFailure = const ProfileFailure.invalidConfig(_secretError);
    final container = await importContainer(repo);
    final notifier = container.read(addProfileNotifierProvider.notifier);

    await notifier.addClipboard(base64Encode(utf8.encode('xhttp://$_secretError')));
    expect(printer.accessEvents.last, containsPair('error_code', 'invalid_configuration'));
    expect(printer.accessEvents.map((event) => event['event']), contains('access_parsing'));
    expect(printer.accessEvents.map((event) => event['event']), isNot(contains('access_persisting')));
    expect(jsonEncode(printer.accessEvents), isNot(contains(_secretError)));

    printer.clear();
    repo.localFailure = const ProfileFailure.unexpected(_secretError);
    await notifier.addClipboard(base64Encode(utf8.encode('unknown://$_secretError')));
    expect(printer.accessEvents.last, containsPair('error_code', 'access_unexpected'));
    expect(printer.accessEvents.map((event) => event['event']), contains('access_persisting'));
    expect(jsonEncode(printer.accessEvents), isNot(contains(_secretError)));
  });

  test('manual update emits one correlated terminal result without profile data', () async {
    final translations = await AppLocale.en.build();
    final repo = _ProfileRepository();
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith((ref) => Future.value(repo)),
        translationsProvider.overrideWith((ref) => translations),
        hapticServiceProvider.overrideWith(_NoHaptic.new),
        activeProfileProvider.overrideWith(_NoActiveProfile.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(profileRepositoryProvider.future);
    container.listen(updateProfileNotifierProvider('profile-secret-id'), (_, _) {});
    final profile =
        ProfileEntity.remote(
              id: 'profile-secret-id',
              active: false,
              name: _secretName,
              url: _secretUrl,
              lastUpdate: DateTime.utc(2026, 9, 18),
            )
            as RemoteProfileEntity;

    await container.read(updateProfileNotifierProvider(profile.id).notifier).updateProfile(profile);

    final events = printer.accessEvents;
    expect(events.map((event) => event['event']), [
      'operation_started',
      'access_fetching',
      'access_parsing',
      'access_validating',
      'access_persisting',
      'operation_succeeded',
    ]);
    expect(events.map((event) => event['operation_id']).toSet(), hasLength(1));
    expect(jsonEncode(events), isNot(contains(_secretUrl)));
    expect(jsonEncode(events), isNot(contains(_secretName)));
    expect(jsonEncode(events), isNot(contains(profile.id)));
  });

  test('manual update preserves one reconnect after a successful active-profile update', () async {
    final translations = await AppLocale.en.build();
    final repo = _ProfileRepository();
    final profile =
        ProfileEntity.remote(
              id: 'active-profile-id',
              active: true,
              name: _secretName,
              url: _secretUrl,
              lastUpdate: DateTime.utc(2026, 9, 18),
            )
            as RemoteProfileEntity;
    final connection = _RecordingConnection();
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith((ref) => Future.value(repo)),
        translationsProvider.overrideWith((ref) => translations),
        hapticServiceProvider.overrideWith(_NoHaptic.new),
        activeProfileProvider.overrideWith(() => _ActiveProfile(profile)),
        connectionNotifierProvider.overrideWith(() => connection),
      ],
    );
    addTearDown(container.dispose);
    await container.read(profileRepositoryProvider.future);
    container.listen(updateProfileNotifierProvider(profile.id), (_, _) {});

    await container.read(updateProfileNotifierProvider(profile.id).notifier).updateProfile(profile);

    expect(repo.remoteCalls, 1);
    expect(connection.reconnectCalls, 1);
    expect(connection.reconnectedProfile, same(profile));
    expect(printer.accessEvents.last['status'], 'succeeded');
  });

  test('manual update failure emits a closed code without raw error', () async {
    final translations = await AppLocale.en.build();
    final repo = _ProfileRepository()..remoteFailure = const ProfileFailure.invalidConfig(_secretError);
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith((ref) => Future.value(repo)),
        translationsProvider.overrideWith((ref) => translations),
        hapticServiceProvider.overrideWith(_NoHaptic.new),
        activeProfileProvider.overrideWith(_NoActiveProfile.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(profileRepositoryProvider.future);
    container.listen(updateProfileNotifierProvider('profile-secret-id'), (_, _) {});
    final profile =
        ProfileEntity.remote(
              id: 'profile-secret-id',
              active: false,
              name: _secretName,
              url: _secretUrl,
              lastUpdate: DateTime.utc(2026, 9, 18),
            )
            as RemoteProfileEntity;

    await container.read(updateProfileNotifierProvider(profile.id).notifier).updateProfile(profile);

    expect(printer.accessEvents.last, containsPair('error_code', 'invalid_configuration'));
    expect(printer.accessEvents.last['status'], 'failed');
    expect(jsonEncode(printer.accessEvents), isNot(contains(_secretError)));
  });
}

final class _ObservabilityPrinter extends LoggyPrinter {
  final records = <({Map<String, Object> payload, LogLevel level})>[];

  List<Map<String, Object>> get accessEvents =>
      records.where((record) => record.payload['module'] == 'access').map((record) => record.payload).toList();

  List<LogLevel> get accessLevels =>
      records.where((record) => record.payload['module'] == 'access').map((record) => record.level).toList();

  void clear() => records.clear();

  @override
  void onLog(LogRecord record) {
    try {
      final decoded = jsonDecode(record.message);
      if (decoded is Map<String, dynamic>) {
        records.add((payload: decoded.cast<String, Object>(), level: record.level));
      }
    } catch (_) {
      // Non-observability application logs are outside this test.
    }
  }
}

final class _ProfileRepository implements ProfileRepository {
  ProfileFailure? remoteFailure;
  ProfileFailure? localFailure;
  Completer<void>? pending;
  int remoteCalls = 0;

  @override
  TaskEither<ProfileFailure, Unit> upsertRemote(
    String url, {
    UserOverride? userOverride,
    CancelToken? cancelToken,
    void Function()? onParsing,
    void Function()? onValidating,
    void Function()? onPersisting,
  }) => TaskEither(() async {
    remoteCalls++;
    await pending?.future;
    if (cancelToken?.isCancelled ?? false) return left(const ProfileFailure.cancelByUser());
    onParsing?.call();
    onValidating?.call();
    if (remoteFailure is ProfileInvalidConfigFailure) return left(remoteFailure!);
    onPersisting?.call();
    return remoteFailure == null ? right(unit) : left(remoteFailure!);
  });

  @override
  TaskEither<ProfileFailure, Unit> addLocal(
    String content, {
    UserOverride? userOverride,
    CancelToken? cancelToken,
    void Function()? onValidating,
    void Function()? onPersisting,
  }) => TaskEither(() async {
    onValidating?.call();
    if (localFailure is ProfileInvalidConfigFailure) return left(localFailure!);
    onPersisting?.call();
    return localFailure == null ? right(unit) : left(localFailure!);
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NoHaptic extends HapticService {
  @override
  bool build() => false;
}

final class _NoActiveProfile extends ActiveProfile {
  @override
  Stream<ProfileEntity?> build() => Stream.value(null);
}

final class _ActiveProfile extends ActiveProfile {
  _ActiveProfile(this.profile);

  final ProfileEntity profile;

  @override
  Stream<ProfileEntity?> build() => Stream.value(profile);
}

final class _RecordingConnection extends ConnectionNotifier {
  int reconnectCalls = 0;
  ProfileEntity? reconnectedProfile;

  @override
  Stream<ConnectionStatus> build() => Stream.value(const ConnectionStatus.disconnected());

  @override
  Future<void> reconnect(ProfileEntity? profile) async {
    reconnectCalls++;
    reconnectedProfile = profile;
  }
}
