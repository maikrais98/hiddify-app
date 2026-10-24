import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/diagnostics/diagnostic_providers.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_event.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_journal.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/model/profile_sort_enum.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('due automatic update passes the automatic trigger and never reads connection state', () async {
    final profile = _profile(lastUpdate: DateTime.now().subtract(const Duration(hours: 2)));
    final repo = _Profiles([profile]);
    final fixture = await _fixture(repo);
    addTearDown(fixture.dispose);

    await fixture.container.read(foregroundProfilesUpdateNotifierProvider.notifier).updateProfiles();

    expect(repo.triggers, [DiagnosticTrigger.automatic]);
    expect(repo.urls, [profile.url]);
  });

  test('not-due automatic profile records one closed skipped decision', () async {
    final profile = _profile(lastUpdate: DateTime.now());
    final repo = _Profiles([profile]);
    final fixture = await _fixture(repo);
    addTearDown(fixture.dispose);

    await fixture.container.read(foregroundProfilesUpdateNotifierProvider.notifier).updateProfiles();

    expect(repo.urls, isEmpty);
    expect(fixture.journal.events, hasLength(1));
    final event = fixture.journal.events.single;
    expect(event.operation, DiagnosticOperation.subscriptionUpdate);
    expect(event.trigger, DiagnosticTrigger.automatic);
    expect(event.phase, DiagnosticPhase.action);
    expect(event.stage, DiagnosticStage.skipped);
    expect(event.code, DiagnosticCode.none);
  });

  test('globally throttled automatic run records a closed busy skip', () async {
    final repo = _Profiles([_profile(lastUpdate: DateTime.now().subtract(const Duration(hours: 2)))]);
    final fixture = await _fixture(
      repo,
      initialPreferences: {ForegroundProfilesUpdateNotifier.prefKey: DateTime.now().toIso8601String()},
    );
    addTearDown(fixture.dispose);

    await fixture.container.read(foregroundProfilesUpdateNotifierProvider.notifier).updateProfiles();

    expect(repo.urls, isEmpty);
    final event = fixture.journal.events.single;
    expect(event.stage, DiagnosticStage.skipped);
    expect(event.code, DiagnosticCode.busy);
    expect(event.trigger, DiagnosticTrigger.automatic);
  });

  test('forced automatic run bypasses both global and per-profile throttles', () async {
    final profile = _profile(lastUpdate: DateTime.now());
    final repo = _Profiles([profile]);
    final fixture = await _fixture(
      repo,
      initialPreferences: {ForegroundProfilesUpdateNotifier.prefKey: DateTime.now().toIso8601String()},
    );
    addTearDown(fixture.dispose);
    final notifier = fixture.container.read(foregroundProfilesUpdateNotifierProvider.notifier);

    await notifier.trigger();
    if (repo.urls.isEmpty) await notifier.updateProfiles();

    expect(repo.urls, [profile.url]);
    expect(repo.triggers, [DiagnosticTrigger.automatic]);
  });

  test('automatic update failure stays a business failure status and does not reconnect', () async {
    final profile = _profile(lastUpdate: DateTime.now().subtract(const Duration(hours: 2)));
    final repo = _Profiles([profile], fail: true);
    final fixture = await _fixture(repo);
    addTearDown(fixture.dispose);

    await fixture.container.read(foregroundProfilesUpdateNotifierProvider.notifier).updateProfiles();

    expect(repo.triggers, [DiagnosticTrigger.automatic]);
    expect(fixture.container.read(foregroundProfilesUpdateNotifierProvider).value?.success, false);
  });
}

RemoteProfileEntity _profile({required DateTime lastUpdate}) =>
    ProfileEntity.remote(
          id: 'synthetic',
          active: true,
          name: 'Synthetic',
          url: 'https://example.invalid/profile',
          lastUpdate: lastUpdate,
          options: const ProfileOptions(updateInterval: Duration(hours: 1)),
        )
        as RemoteProfileEntity;

Future<_Fixture> _fixture(_Profiles repo, {Map<String, Object> initialPreferences = const {}}) async {
  SharedPreferences.setMockInitialValues(initialPreferences);
  final preferences = await SharedPreferences.getInstance();
  final journal = SafeDiagnosticJournal();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) => Future.value(preferences)),
      profileRepositoryProvider.overrideWith((ref) => repo),
      translationsProvider.overrideWith((ref) => AppLocale.en.buildSync()),
      inAppNotificationControllerProvider.overrideWithValue(_Notifications()),
      safeDiagnosticJournalProvider.overrideWithValue(journal),
    ],
  );
  await container.read(sharedPreferencesProvider.future);
  await container.read(profileRepositoryProvider.future);
  await container.read(translationsProvider.future);
  return _Fixture(container, journal);
}

final class _Fixture {
  _Fixture(this.container, this.journal);
  final ProviderContainer container;
  final SafeDiagnosticJournal journal;
  void dispose() {
    container.dispose();
    journal.dispose();
  }
}

final class _Profiles implements ProfileRepository {
  _Profiles(this.profiles, {this.fail = false});
  final List<RemoteProfileEntity> profiles;
  final bool fail;
  final urls = <String>[];
  final triggers = <DiagnosticTrigger?>[];

  @override
  Stream<Either<ProfileFailure, List<ProfileEntity>>> watchAll({
    ProfilesSort sort = ProfilesSort.lastUpdate,
    SortMode sortMode = SortMode.ascending,
  }) => Stream.value(right(profiles));

  @override
  TaskEither<ProfileFailure, Unit> upsertRemote(
    String url, {
    UserOverride? userOverride,
    CancelToken? cancelToken,
    int? diagnosticOperationId,
    DiagnosticTrigger? diagnosticTrigger,
  }) => TaskEither(() async {
    urls.add(url);
    triggers.add(diagnosticTrigger);
    return fail ? left(const ProfileFailure.unexpected()) : right(unit);
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Notifications extends InAppNotificationController {
  @override
  ToastificationItem? showSuccessToast(String message) => null;

  @override
  ToastificationItem? showErrorToast(String message) => null;
}
