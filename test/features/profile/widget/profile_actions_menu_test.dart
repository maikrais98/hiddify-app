import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  late Translations translations;

  setUpAll(() async {
    translations = await AppLocale.en.build();
  });

  testWidgets('active deletion explains disconnect and cancel keeps the profile', (tester) async {
    final dialogs = _RecordingDialogs(false);
    final profiles = _RecordingProfilesNotifier();

    await _pumpMenu(tester, _profile(active: true), translations, dialogs, profiles);
    await _openExportDelete(tester);
    await _choose(tester, 'Delete access');

    expect(dialogs.message, contains('will stop the current connection'));
    expect(dialogs.message, contains('Export it first'));
    expect(profiles.deleted, isEmpty);
  });

  testWidgets('inactive deletion explains local removal and confirm deletes it', (tester) async {
    final dialogs = _RecordingDialogs(true);
    final profiles = _RecordingProfilesNotifier();
    final profile = _profile(active: false);

    await _pumpMenu(tester, profile, translations, dialogs, profiles);
    await _openExportDelete(tester);
    await _choose(tester, 'Delete access');

    expect(dialogs.message, contains('removes this VPN access from this device'));
    expect(dialogs.message, isNot(contains('stop the current connection')));
    expect(profiles.deleted, [profile]);
  });

  testWidgets('active deletion only runs after explicit confirmation', (tester) async {
    final dialogs = _RecordingDialogs(true);
    final profiles = _RecordingProfilesNotifier();
    final profile = _profile(active: true);

    await _pumpMenu(tester, profile, translations, dialogs, profiles);
    await _openExportDelete(tester);
    await _choose(tester, 'Delete access');

    expect(profiles.deleted, [profile]);
  });

  testWidgets('secret export is behind the dedicated export and delete presentation', (tester) async {
    final dialogs = _RecordingDialogs(false);
    final profiles = _RecordingProfilesNotifier();
    final profile = _profile(active: false);

    await _pumpMenu(tester, profile, translations, dialogs, profiles);
    expect(profiles.exported, isEmpty);

    await tester.tap(find.text('Export and delete'));
    await tester.pumpAndSettle();
    expect(profiles.exported, isEmpty);

    expect(find.text('Copy configuration'), findsOneWidget);
    expect(find.textContaining('example.test'), findsNothing);
    expect(find.textContaining('token='), findsNothing);

    await tester.tap(find.text('Copy configuration'));
    await tester.pumpAndSettle();
    expect(profiles.exported, [profile]);
    expect(profiles.deleted, isEmpty);
  });
}

ProfileEntity _profile({required bool active}) => ProfileEntity.remote(
  id: active ? 'active-profile' : 'inactive-profile',
  active: active,
  name: 'secret-bearing-profile-name',
  url: 'https://example.test/subscription?token=secret',
  lastUpdate: DateTime.utc(2026, 9, 16),
);

Future<void> _pumpMenu(
  WidgetTester tester,
  ProfileEntity profile,
  Translations translations,
  _RecordingDialogs dialogs,
  _RecordingProfilesNotifier profiles,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        translationsProvider.overrideWith((ref) => translations),
        dialogNotifierProvider.overrideWith(() => dialogs),
        profilesNotifierProvider.overrideWith(() => profiles),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ProfileActionsMenu(
            profile,
            (context, toggleVisibility, child) =>
                TextButton(onPressed: toggleVisibility, child: const Text('Open actions')),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open actions'));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String action) async {
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

Future<void> _openExportDelete(WidgetTester tester) async {
  await _choose(tester, 'Export and delete');
  expect(find.text('Export and delete'), findsOneWidget);
}

class _RecordingDialogs extends DialogNotifier {
  _RecordingDialogs(this.result);

  final bool result;
  String? message;

  @override
  void build() {}

  @override
  Future<bool> showConfirmation({
    required String title,
    required String message,
    IconData? icon,
    String? positiveBtnTxt,
  }) async {
    this.message = message;
    return result;
  }
}

class _RecordingProfilesNotifier extends ProfilesNotifier {
  final deleted = <ProfileEntity>[];
  final exported = <ProfileEntity>[];

  @override
  Stream<List<ProfileEntity>> build() => const Stream.empty();

  @override
  Future<void> deleteProfile(ProfileEntity profile) async {
    deleted.add(profile);
  }

  @override
  Future<void> exportConfigToClipboard(ProfileEntity profile) async {
    exported.add(profile);
  }
}
