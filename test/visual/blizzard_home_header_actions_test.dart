import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/bottom_sheets/widgets/quick_settings_modal.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_glass.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_system_symbol.dart';
import 'package:hiddify/features/home/widget/home_page.dart';
import 'package:hiddify/features/profile/add/add_profile_modal.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../support/home_fixture.dart';

void _testIosWidgets(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, (_) async => null);
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, null),
    );
    try {
      await callback(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  _testIosWidgets('Home keeps existing glass, symbols, labels and 48 point Flutter header targets', (tester) async {
    final fixture = await mountHomeFixture(tester, child: _appliedHome());
    addTearDown(() => fixture.close(tester));
    final translations = fixture.container.read(translationsProvider).requireValue;
    final labels = [translations.pages.home.quickSettings, translations.pages.profiles.add];
    final keys = ['profile_quick_settings', 'profile_add_button'];
    for (var index = 0; index < keys.length; index++) {
      final target = find.byKey(ValueKey(keys[index]));
      expect(tester.widget<Semantics>(target).properties.label, labels[index]);
      expect(find.descendant(of: target, matching: find.byType(BlizzardGlass)), findsOneWidget);
      expect(find.descendant(of: target, matching: find.byType(BlizzardSystemSymbol)), findsOneWidget);
      final button = find.descendant(of: target, matching: find.byType(IconButton));
      expect(button, findsOneWidget);
      expect(tester.getSize(button), const Size(48, 48));
    }
  });

  _testIosWidgets('real Flutter taps open the matching Quick Settings and Add Profile routes', (tester) async {
    final fixture = await mountHomeFixture(tester, child: _appliedHome());
    addTearDown(() => fixture.close(tester));
    await tester.tap(find.byKey(const ValueKey('profile_quick_settings')));
    await tester.pump();
    expect(find.byType(QuickSettingsModal), findsOneWidget);
    Navigator.of(tester.element(find.byType(QuickSettingsModal))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('profile_add_button')));
    await tester.pump();
    expect(find.byType(AddProfileModal), findsOneWidget);
    Navigator.of(tester.element(find.byType(AddProfileModal))).pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 61));
  });

  _testIosWidgets('RTL mirrors existing Flutter header action ordering', (tester) async {
    final fixture = await mountHomeFixture(tester, child: _appliedHome(), direction: TextDirection.rtl);
    addTearDown(() => fixture.close(tester));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('profile_quick_settings'))).dx,
      greaterThan(tester.getTopLeft(find.byKey(const ValueKey('profile_add_button'))).dx),
    );
  });

  _testIosWidgets('root sheet barrier prevents a tap from activating the underlying header', (tester) async {
    final fixture = await mountHomeFixture(tester, child: _appliedHome());
    addTearDown(() => fixture.close(tester));
    final target = tester.getCenter(find.byKey(const ValueKey('profile_quick_settings')));
    final shown = showModalBottomSheet<void>(
      context: rootNavKey.currentContext!,
      builder: (_) => const SizedBox(height: 120, child: Text('root sheet')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tapAt(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await shown;
    expect(find.byType(QuickSettingsModal), findsNothing);
  });
}

Widget _appliedHome() => Builder(
  builder: (context) => Theme(
    data: BlizzardTheme.from(Theme.of(context)).copyWith(platform: TargetPlatform.iOS),
    child: const HomePage(),
  ),
);
