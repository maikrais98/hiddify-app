import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/dialog/widgets/confirmation_dialog.dart';
import 'package:hiddify/core/widget/adaptive_menu.dart';
import 'package:hiddify/features/common/qr_code_dialog.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_modal.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../support/home_fixture.dart';

void main() => registerProfileTileContracts();

void registerProfileTileContracts() {
  for (final active in [false, true]) {
    testWidgets('real tile selects exact ID once while pending; active=$active', (tester) async {
      final profile = ProfileEntity.local(
        id: 'tile-id',
        active: active,
        name: 'Selection target',
        lastUpdate: DateTime.utc(2026),
      );
      final spy = TileProfilesSpy()..selection = Completer<Unit>();
      final f = await mountHomeFixture(
        tester,
        child: ProfileTile(profile: profile),
        extraOverrides: [profilesNotifierProvider.overrideWith(() => spy)],
      );
      await tester.tap(find.text('Selection target'));
      await tester.pump();
      await tester.tap(find.text('Selection target'));
      expect(spy.calls, ['select:tile-id']);
      expect(f.router.routeInformationProvider.value.uri.path, '/home');
      if (active) await f.close(tester);
      spy.selection!.complete(unit);
      await tester.pump();
      if (!active) {
        expect(f.router.routeInformationProvider.value.uri.path, "/home");
        await f.close(tester);
      }
      expect(tester.takeException(), isNull, reason: 'late completion must respect mounted');
    });
  }
  testWidgets('remote main update is bound to ID and ignores repeat while loading', (tester) async {
    final profile = ProfileEntity.remote(
      id: 'remote-id',
      active: true,
      name: 'Remote',
      url: 'https://example.invalid/sub',
      lastUpdate: DateTime.utc(2026),
    );
    final spy = TileUpdateSpy();
    final f = await mountHomeFixture(
      tester,
      child: ProfileTile(profile: profile, isMain: true),
      extraOverrides: [updateProfileNotifierProvider('remote-id').overrideWith(() => spy)],
    );
    final updateAt = tester.getCenter(find.byKey(const ValueKey('update')));
    await tester.tapAt(updateAt);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const ValueKey('updating')), findsOneWidget);
    await tester.tapAt(updateAt);
    expect(spy.calls, ['update:remote-id']);
    await f.close(tester);
  });
  testWidgets('real remote menu preserves pin/update/share/edit/delete and JSON copying', (tester) async {
    final profile = ProfileEntity.remote(
      id: 'remote-menu',
      active: true,
      name: 'Remote',
      url: 'https://example.invalid/sub',
      lastUpdate: DateTime.utc(2026),
    );
    final clipboard = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard.add(call.arguments);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final spy = _TileShareSpy();
    final f = await mountHomeFixture(
      tester,
      child: ProfileTile(profile: profile),
      extraOverrides: [profilesNotifierProvider.overrideWith(() => spy)],
    );
    final t = f.container.read(translationsProvider).requireValue;
    final items = tester.widget<AdaptiveMenu>(find.byType(AdaptiveMenu)).items.toList();
    expect(items.map((item) => item.title), [
      t.common.pin,
      t.common.update,
      t.common.share,
      t.common.edit,
      t.common.delete,
    ]);
    expect((items[1].leadingIcon! as Icon).icon, Icons.sync_rounded);
    expect((items[3].leadingIcon! as Icon).icon, Icons.edit_rounded);
    expect((items[4].leadingIcon! as Icon).icon, Icons.delete_outline_rounded);
    final sharing = items[2].onTap!();
    await tester.pumpAndSettle();
    expect(find.byType(ShareProfileDialog), findsOneWidget);
    expect(spy.calls, ['generate:remote-menu']);
    await tester.tap(find.text(t.pages.profiles.share.copy));
    await tester.pump();
    expect(clipboard, [
      {'text': _TileShareSpy.config},
    ]);
    f.router.pop();
    await tester.pumpAndSettle();
    await sharing;
    await f.close(tester);
  });
  testWidgets('real Home opens overview; selection closes immediately before late completion', (tester) async {
    final profile = ProfileEntity.local(
      id: 'modal-id',
      active: true,
      name: 'Modal profile',
      lastUpdate: DateTime.utc(2026),
    );
    final spy = TileProfilesSpy()
      ..profiles = [profile]
      ..selection = Completer<Unit>();
    final f = await mountHomeFixture(
      tester,
      profile: profile,
      extraOverrides: [profilesNotifierProvider.overrideWith(() => spy)],
    );
    await tester.tap(find.text('Modal profile'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ProfilesModal), findsOneWidget);
    expect(spy.calls, isEmpty);
    await tester.tap(find.descendant(of: find.byType(ProfilesModal), matching: find.text('Modal profile')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ProfilesModal), findsNothing);
    expect(spy.calls, ['select:modal-id']);
    spy.selection!.complete(unit);
    await tester.pump();
    expect(f.router.routeInformationProvider.value.uri.path, '/home');
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });
  for (final confirm in [false, true]) {
    testWidgets('delete actual confirmation $confirm uses exact profile', (tester) async {
      final profile = ProfileEntity.local(
        id: 'delete-id',
        active: true,
        name: 'Delete candidate',
        lastUpdate: DateTime.utc(2026),
      );
      final spy = TileProfilesSpy();
      final f = await mountHomeFixture(
        tester,
        child: ProfileTile(profile: profile),
        extraOverrides: [profilesNotifierProvider.overrideWith(() => spy)],
      );
      final menu = tester.widget<AdaptiveMenu>(find.byType(AdaptiveMenu));
      final result = menu.items.last.onTap!();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ConfirmationDialog), findsOneWidget);
      expect(spy.calls, isEmpty);
      final buttons = find.descendant(of: find.byType(ConfirmationDialog), matching: find.byType(TextButton));
      await tester.tap(confirm ? buttons.last : buttons.first);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await result;
      expect(spy.calls, confirm ? ['delete:delete-id'] : isEmpty);
      await f.close(tester);
    });
  }
  testWidgets('remote share action shows exact synthetic QR link and profile name', (tester) async {
    final profile = ProfileEntity.remote(
      id: 'qr-id',
      active: false,
      name: 'Remote',
      url: 'https://example.invalid/sub',
      lastUpdate: DateTime.utc(2026),
    );
    final f = await mountHomeFixture(
      tester,
      child: ProfileTile(profile: profile),
      extraOverrides: [profilesNotifierProvider.overrideWith(_TileShareSpy.new)],
    );
    final menu = tester.widget<AdaptiveMenu>(find.byType(AdaptiveMenu));
    final result = menu.items.toList()[2].onTap!();
    await tester.pumpAndSettle();
    final dialog = tester.widget<ShareProfileDialog>(find.byType(ShareProfileDialog));
    expect(dialog.link, 'https://example.invalid/sub#Remote');
    expect(dialog.name, 'Remote');
    expect(find.byType(QrImageView), findsOneWidget);
    f.router.pop();
    await tester.pumpAndSettle();
    await result;
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });
  testWidgets('remote clipboard, menu update and wide edit preserve exact payloads', (tester) async {
    final profile = ProfileEntity.remote(
      id: 'menu-id',
      active: false,
      name: 'Remote',
      url: 'https://example.invalid/sub',
      lastUpdate: DateTime.utc(2026),
    );
    final update = TileUpdateSpy();
    final notifications = _TileNotifications();
    final clipboard = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard.add(call.arguments);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final f = await mountHomeFixture(
      tester,
      width: 900,
      child: ProfileTile(profile: profile),
      extraOverrides: [
        updateProfileNotifierProvider('menu-id').overrideWith(() => update),
        profilesNotifierProvider.overrideWith(_TileShareSpy.new),
        inAppNotificationControllerProvider.overrideWith((ref) => notifications),
      ],
    );
    final items = tester.widget<AdaptiveMenu>(find.byType(AdaptiveMenu)).items.toList();
    final sharing = items[2].onTap!();
    await tester.pumpAndSettle();
    await tester.tap(find.text('https://example.invalid/sub#Remote'));
    await tester.pump();
    expect(clipboard, [
      {'text': 'https://example.invalid/sub#Remote'},
    ]);
    final t = f.container.read(translationsProvider).requireValue;
    expect(find.text(t.dialogs.qrCode.copied).hitTestable(), findsOneWidget);
    expect(notifications.successCount, 0, reason: 'official share feedback is shown in the copy tile');
    f.router.pop();
    await tester.pumpAndSettle();
    await sharing;
    items[1].onTap!();
    items[1].onTap!();
    expect(update.calls, ['update:menu-id']);
    items[3].onTap!();
    await tester.pump();
    expect(f.router.routeInformationProvider.value.uri.path, '/profile/menu-id');
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });
  testWidgets('main wide tile routes to profiles without selecting', (tester) async {
    final profile = ProfileEntity.local(
      id: 'wide-id',
      active: true,
      name: 'Wide profile',
      lastUpdate: DateTime.utc(2026),
    );
    final spy = TileProfilesSpy();
    final f = await mountHomeFixture(
      tester,
      width: 900,
      child: ProfileTile(profile: profile, isMain: true),
      extraOverrides: [profilesNotifierProvider.overrideWith(() => spy)],
    );
    await tester.tap(find.text('Wide profile'));
    await tester.pump();
    expect(f.router.routeInformationProvider.value.uri.path, '/profiles');
    expect(spy.calls, isEmpty);
    await f.close(tester);
  });
}

class _TileNotifications extends InAppNotificationController {
  int successCount = 0;
  @override
  void showSuccessToast(String message, {ToastAction? action}) {
    successCount++;
  }
}

class _TileShareSpy extends TileProfilesSpy {
  static const config = '{"outbounds":[{"tag":"synthetic-profile","type":"direct"}]}';

  @override
  Future<String> generateConfig(ProfileEntity profile) async {
    calls.add('generate:${profile.id}');
    return config;
  }
}
