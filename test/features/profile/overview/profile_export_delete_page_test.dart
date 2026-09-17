import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/overview/profile_export_delete_page.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  late Translations translations;

  setUpAll(() async {
    translations = await AppLocale.en.build();
  });

  testWidgets('presents only explicit export and confirmed delete without secret previews', (tester) async {
    final dialogs = _RecordingDialogs(false);
    final profiles = _RecordingProfilesNotifier();
    final profile = _profile(active: false);

    await _pumpPage(tester, profile, translations, dialogs, profiles);

    expect(find.text('Export and delete'), findsOneWidget);
    expect(find.text('Copy configuration snapshot'), findsOneWidget);
    expect(find.text('Delete access'), findsOneWidget);
    expect(find.text('vpn-profile-secret-name'), findsOneWidget);
    expect(find.textContaining('example.test'), findsNothing);
    expect(find.textContaining('token='), findsNothing);
    expect(find.textContaining('raw configuration'), findsNothing);
    expect(find.textContaining('logs'), findsNothing);
    expect(profiles.exported, isEmpty);
    expect(profiles.deleted, isEmpty);

    expect(find.text('Inactive access saved on this device'), findsOneWidget);
    expect(find.textContaining('source link and automatic updates are not included'), findsOneWidget);

    await tester.tap(find.text('Copy configuration snapshot'));
    await tester.pumpAndSettle();
    expect(profiles.exported, [profile]);
    expect(profiles.deleted, isEmpty);

    await tester.tap(find.text('Delete access'));
    await tester.pumpAndSettle();
    expect(dialogs.message, contains('removes this VPN access from this device'));
    expect(profiles.deleted, isEmpty);
  });

  testWidgets('confirmed active deletion preserves disconnect warning and invokes existing delete API', (tester) async {
    final dialogs = _RecordingDialogs(true);
    final profiles = _RecordingProfilesNotifier();
    final profile = _profile(active: true);

    await _pumpPage(tester, profile, translations, dialogs, profiles);
    expect(find.text('Active access saved on this device'), findsOneWidget);
    await tester.tap(find.text('Delete access'));
    await tester.pumpAndSettle();

    expect(dialogs.message, contains('will stop the current connection'));
    expect(dialogs.message, contains('Export it first'));
    expect(profiles.deleted, [profile]);
  });
}

ProfileEntity _profile({required bool active}) => ProfileEntity.remote(
  id: active ? 'active-profile' : 'inactive-profile',
  active: active,
  name: 'vpn-profile-secret-name',
  url: 'https://example.test/subscription?token=vpn-profile-secret-token',
  lastUpdate: DateTime.utc(2026, 9, 17),
);

Future<void> _pumpPage(
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
      child: MaterialApp(home: ProfileExportDeletePage(profile: profile)),
    ),
  );
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
