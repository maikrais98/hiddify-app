import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/details/profile_details_notifier.dart';
import 'package:hiddify/features/profile/details/profile_details_page.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:toastification/toastification.dart';

void main() {
  testWidgets('shows one success and closes only after a successful save', (tester) async {
    final harness = await _SaveHarness.pump(tester, _SaveOutcome.success);

    await harness.editAndSave(tester);

    expect(harness.notifications.successCount, 1);
    expect(harness.notifications.errorCount, 0);
    expect(harness.dialogs.errorCount, 0);
    expect(find.byType(ProfileDetailsPage), findsNothing);
  });

  testWidgets('keeps the dirty edit and page open when save returns failure', (tester) async {
    final pendingSave = Completer<Either<ProfileFailure, Unit>>();
    final harness = await _SaveHarness.pump(tester, _SaveOutcome.failure, pendingSave: pendingSave);

    await harness.editAndStartSave(tester);
    harness.container
        .read(profileDetailsNotifierProvider(_SaveHarness.profileId).notifier)
        .setContent(_SaveHarness.editedConfig);
    pendingSave.complete(left(const ProfileFailure.invalidConfig('invalid config')));
    await tester.pumpAndSettle();

    final details = harness.container.read(profileDetailsNotifierProvider(_SaveHarness.profileId)).requireValue;
    expect(harness.notifications.successCount, 0);
    expect(harness.notifications.errorCount, 0);
    expect(harness.dialogs.errorCount, 1);
    expect(find.byType(ProfileDetailsPage), findsOneWidget);
    expect(tester.widget<TextFormField>(find.byType(TextFormField).first).controller!.text, _SaveHarness.editedName);
    expect(details.configContent, _SaveHarness.editedConfig);
    expect(details.isDetailsChanged, isTrue);
    expect(details.isLoading, isFalse);
  });

  testWidgets('keeps the dirty edit and reports an unexpected save exception', (tester) async {
    final harness = await _SaveHarness.pump(tester, _SaveOutcome.exception);

    await harness.editAndSave(tester);

    final details = harness.container.read(profileDetailsNotifierProvider(_SaveHarness.profileId)).requireValue;
    expect(harness.notifications.successCount, 0);
    expect(harness.notifications.errorCount, 1);
    expect(harness.dialogs.errorCount, 0);
    expect(find.byType(ProfileDetailsPage), findsOneWidget);
    expect(tester.widget<TextFormField>(find.byType(TextFormField).first).controller!.text, _SaveHarness.editedName);
    expect(details.isDetailsChanged, isTrue);
    expect(details.isLoading, isFalse);
  });

  final updateIntervalCases = <({String name, Duration? interval, UserOverride? override, int expectedHours})>[
    (name: 'invalid', interval: null, override: null, expectedHours: 0),
    (name: 'negative', interval: const Duration(hours: -1), override: null, expectedHours: 0),
    (name: '97', interval: const Duration(hours: 97), override: null, expectedHours: 96),
    (name: 'huge', interval: const Duration(hours: 999999999), override: null, expectedHours: 96),
    (
      name: 'out-of-range override',
      interval: const Duration(hours: 24),
      override: const UserOverride(updateInterval: 97),
      expectedHours: 96,
    ),
  ];
  for (final testCase in updateIntervalCases) {
    testWidgets('keeps the update interval Slider in range for ${testCase.name}', (tester) async {
      final profile = ProfileEntity.remote(
        id: _SaveHarness.profileId,
        active: true,
        name: 'Remote profile',
        url: 'https://example.com/profile',
        lastUpdate: DateTime.utc(2026),
        options: testCase.interval == null ? null : ProfileOptions(updateInterval: testCase.interval!),
        userOverride: testCase.override,
      );
      final harness = await _SaveHarness.pump(tester, _SaveOutcome.success, profile: profile);

      expect(tester.takeException(), isNull);
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.min, minProfileUpdateIntervalHours.toDouble());
      expect(slider.max, maxProfileUpdateIntervalHours.toDouble());
      expect(slider.divisions, maxProfileUpdateIntervalHours - minProfileUpdateIntervalHours);
      expect(slider.value, testCase.expectedHours.toDouble());
      expect(slider.label, testCase.expectedHours.toString());

      slider.onChanged!(48);
      await tester.pump();

      final details = harness.container.read(profileDetailsNotifierProvider(_SaveHarness.profileId)).requireValue;
      expect(details.profile.userOverride?.updateInterval, 48);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 48);
    });
  }
}

enum _SaveOutcome { success, failure, exception }

class _SaveHarness {
  _SaveHarness(this.container, this.notifications, this.dialogs);

  static const profileId = 'profile-id';
  static const editedName = 'Edited profile';
  static const editedConfig = 'edited config';

  final ProviderContainer container;
  final _RecordingNotifications notifications;
  final _RecordingDialogs dialogs;

  static Future<_SaveHarness> pump(
    WidgetTester tester,
    _SaveOutcome outcome, {
    Completer<Either<ProfileFailure, Unit>>? pendingSave,
    ProfileEntity? profile,
  }) async {
    final notifications = _RecordingNotifications();
    final dialogs = _RecordingDialogs();
    final translations = await AppLocale.en.build();
    final container = ProviderContainer(
      overrides: [
        translationsProvider.overrideWith((ref) => translations),
        profileRepositoryProvider.overrideWith((ref) => _SaveRepository(outcome, pendingSave, profile)),
        inAppNotificationControllerProvider.overrideWithValue(notifications),
        dialogNotifierProvider.overrideWith(() => dialogs),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      navigatorKey: rootNavKey,
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: TextButton(onPressed: () => context.push('/details'), child: const Text('Open profile')),
          ),
        ),
        GoRoute(
          path: '/details',
          builder: (context, state) => const ProfileDetailsPage(id: profileId),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('Open profile'));
    await tester.pumpAndSettle();
    return _SaveHarness(container, notifications, dialogs);
  }

  Future<void> editAndSave(WidgetTester tester) async {
    await editAndStartSave(tester);
    await tester.pumpAndSettle();
  }

  Future<void> editAndStartSave(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).first, editedName);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.check));
    await tester.pump();
  }
}

class _SaveRepository implements ProfileRepository {
  _SaveRepository(this.outcome, this.pendingSave, this.profile);

  final _SaveOutcome outcome;
  final Completer<Either<ProfileFailure, Unit>>? pendingSave;
  final ProfileEntity? profile;

  @override
  TaskEither<ProfileFailure, ProfileEntity?> getById(String id) => TaskEither.of(
    profile ?? ProfileEntity.local(id: id, active: true, name: 'Original profile', lastUpdate: DateTime.utc(2026)),
  );

  @override
  TaskEither<ProfileFailure, String> generateConfig(String id) => TaskEither.of('config');

  @override
  TaskEither<ProfileFailure, String> getRawConfig(String id) => TaskEither.of('config');

  @override
  TaskEither<ProfileFailure, Unit> offlineUpdate(ProfileEntity nProfile, String nContent) => TaskEither(() async {
    if (pendingSave case final pending?) return pending.future;
    return switch (outcome) {
      _SaveOutcome.success => right(unit),
      _SaveOutcome.failure => left(const ProfileFailure.invalidConfig('invalid config')),
      _SaveOutcome.exception => throw StateError('save crashed'),
    };
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingNotifications extends InAppNotificationController {
  int successCount = 0;
  int errorCount = 0;

  @override
  ToastificationItem? showSuccessToast(String message) {
    successCount++;
    return null;
  }

  @override
  ToastificationItem? showErrorToast(String message) {
    errorCount++;
    return null;
  }
}

class _RecordingDialogs extends DialogNotifier {
  int errorCount = 0;

  @override
  void build() {}

  @override
  Future<void> showCustomAlertFromErr(PresentableError err) async {
    errorCount++;
  }
}
