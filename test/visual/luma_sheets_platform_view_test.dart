import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/bottom_sheets/widgets/quick_settings_modal.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_glass.dart';
import 'package:hiddify/features/profile/add/add_profile_modal.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/overview/profiles_modal.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';

import '../support/home_fixture.dart';

// Regression for build 48: on iPhone the Profiles and Quick Settings sheets drew
// their header, but everything below it was cut off 60pt from the left edge.
// Layout in Flutter was always correct (see the width assertions); the cause is a
// UiKitView (native Liquid Glass header button) inside a sheet that Flutter
// composites above the Home screen's own platform views. Sheets must contain none.

Widget _applied(Widget child) => Builder(
  builder: (context) => Theme(data: BlizzardTheme.from(Theme.of(context)), child: child),
);

final _profiles = [
  ProfileEntity.remote(
    id: 'a',
    active: true,
    name: 'First subscription',
    url: 'https://example.invalid/first',
    lastUpdate: DateTime.utc(2026),
  ),
  ProfileEntity.remote(
    id: 'b',
    active: false,
    name: 'Second subscription',
    url: 'https://example.invalid/second',
    lastUpdate: DateTime.utc(2026),
  ),
];

enum _Sheet { profiles, quickSettings, addProfile }

Widget _modal(_Sheet sheet) => switch (sheet) {
  _Sheet.profiles => const ProfilesModal(),
  _Sheet.quickSettings => const QuickSettingsModal(),
  _Sheet.addProfile => const AddProfileModal(),
};

Future<HomeFixture> _open(WidgetTester tester, double width, _Sheet sheet) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  tester.view.physicalSize = Size(width, 956);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fixture = await mountHomeFixture(
    tester,
    width: width,
    height: 956,
    nativeViewport: true,
    extraOverrides: [profilesNotifierProvider.overrideWith(() => TileProfilesSpy()..profiles = _profiles)],
    child: Builder(
      builder: (context) => TextButton(
        key: const ValueKey('open'),
        onPressed: () => Navigator.of(context, rootNavigator: true).push<void>(
          ModalBottomSheetRoute(
            constraints: BottomSheetConst.boxConstraints,
            isScrollControlled: true,
            builder: (context) => Material(child: _applied(_modal(sheet))),
          ),
        ),
        child: const Text('open'),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  expect(tester.takeException(), isNull);
  return fixture;
}

void main() {
  for (final width in [440.0, 393.0]) {
    for (final sheet in _Sheet.values) {
      testWidgets('${sheet.name} sheet at ${width}pt has no platform view and full-width content', (tester) async {
        final fixture = await _open(tester, width, sheet);

        expect(
          find.descendant(of: find.byType(BottomSheet), matching: find.byType(UiKitView)),
          findsNothing,
          reason: 'a UiKitView inside a sheet makes iOS clip the sheet content',
        );
        // Glass is still there, drawn by Flutter.
        expect(find.descendant(of: find.byType(BottomSheet), matching: find.byType(BlizzardGlass)), findsWidgets);

        const margin = 20.0;
        switch (sheet) {
          case _Sheet.profiles:
            for (final tile in tester.widgetList(find.byType(ProfileTile)).toList().asMap().keys) {
              expect(tester.getSize(find.byType(ProfileTile).at(tile)).width, width - 2 * margin);
            }
          case _Sheet.quickSettings:
            expect(tester.getSize(find.byType(SegmentedButton<ServiceMode>)).width, width - 2 * margin);
          case _Sheet.addProfile:
            expect(tester.getSize(find.byType(ListView).first).width, width);
        }
        await fixture.close(tester);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }

  testWidgets('every sheet opened through BottomSheetsNotifier is free of platform views', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final fixture = await mountHomeFixture(
      tester,
      width: 440,
      height: 956,
      extraOverrides: [profilesNotifierProvider.overrideWith(() => TileProfilesSpy()..profiles = _profiles)],
    );
    final notifier = fixture.container.read(bottomSheetsNotifierProvider.notifier);
    final opens = <String, Future<void> Function()>{
      'profiles': notifier.showProfilesOverview,
      'quick settings': notifier.showQuickSettings,
      'add profile': notifier.showAddProfile,
      'logs share': notifier.showLogsShare,
      'logs recent': notifier.showLogsRecent,
    };
    for (final MapEntry(:key, :value) in opens.entries) {
      final shown = value();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(BottomSheet), findsOneWidget, reason: key);
      final probe = find.descendant(of: find.byType(BottomSheet), matching: find.byType(UiKitView));
      expect(probe, findsNothing, reason: '$key sheet must not host platform views');
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await shown;
    }
    await fixture.close(tester);
    debugDefaultTargetPlatformOverride = null;
  });
}
