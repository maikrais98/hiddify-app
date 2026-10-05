import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/dialog/widgets/confirmation_dialog.dart';
import 'package:hiddify/core/widget/adaptive_menu.dart';
import 'package:hiddify/features/common/qr_code_dialog.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_modal.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart';
import 'package:toastification/toastification.dart';

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
    await tester.tap(find.byIcon(Icons.update_rounded));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.update_rounded));
    expect(spy.calls, ['update:remote-id']);
    await f.close(tester);
  });
  testWidgets('real remote actions menu preserves update/share/edit/delete and JSON binding', (tester) async {
    final profile = ProfileEntity.remote(
      id: 'remote-menu',
      active: true,
      name: 'Remote',
      url: 'https://example.invalid/sub',
      lastUpdate: DateTime.utc(2026),
    );
    final spy = TileProfilesSpy();
    final f = await mountHomeFixture(
      tester,
      child: ProfileTile(profile: profile),
      extraOverrides: [profilesNotifierProvider.overrideWith(() => spy)],
    );
    final menu = tester.widget<AdaptiveMenu>(find.byType(AdaptiveMenu));
    final items = menu.items.toList();
    expect(items.length, 4);
    expect(items[0].icon, Icons.update_rounded);
    expect(items[2].icon, Icons.edit_rounded);
    expect(items[3].icon, Icons.delete_outline_rounded);
    expect(items[1].subItems!.length, 3, reason: 'URL clipboard, URL QR and JSON remain available');
    await items[1].subItems!.last.onTap!();
    expect(spy.calls, ['export:remote-menu']);
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
  testWidgets('remote QR action shows exact synthetic link in real dialog', (tester) async {
    final profile = ProfileEntity.remote(
      id: 'qr-id',
      active: false,
      name: 'Remote',
      url: 'https://example.invalid/sub',
      lastUpdate: DateTime.utc(2026),
    );
    final f = await mountHomeFixture(tester, child: ProfileTile(profile: profile));
    final menu = tester.widget<AdaptiveMenu>(find.byType(AdaptiveMenu));
    final result = menu.items.toList()[1].subItems![1].onTap!();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final qr = tester.widget<QrCodeDialog>(find.byType(QrCodeDialog));
    expect(qr.data, 'https://example.invalid/sub#Remote');
    expect(qr.message, 'Remote');
    f.router.pop();
    await tester.pump();
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
        inAppNotificationControllerProvider.overrideWith((ref) => notifications),
      ],
    );
    final items = tester.widget<AdaptiveMenu>(find.byType(AdaptiveMenu)).items.toList();
    await items[1].subItems!.first.onTap!();
    expect(clipboard, [
      {'text': 'https://example.invalid/sub#Remote'},
    ]);
    expect(notifications.successCount, 1);
    items.first.onTap!();
    items.first.onTap!();
    expect(update.calls, ['update:menu-id']);
    items[2].onTap!();
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
  ToastificationItem? showSuccessToast(String message) {
    successCount++;
    return null;
  }
}
