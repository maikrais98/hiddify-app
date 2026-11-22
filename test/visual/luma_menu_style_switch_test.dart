import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_presentation.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';

import '../support/home_fixture.dart';

// The menu style is a user setting (Settings > General > Appearance): solid (the sheet's material)
// by default, glass on request, applied at once. Structural checks only, no pixel goldens.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 700));
}

Widget _aurora(Widget child) => Builder(
  builder: (context) => Theme(data: BlizzardTheme.from(Theme.of(context)), child: child),
);

Future<HomeFixture> _mount(WidgetTester tester, {Widget? child}) {
  tester.view.physicalSize = const Size(440 * 3, 956 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return mountHomeFixture(
    tester,
    width: 440,
    height: 956,
    nativeViewport: true,
    locale: AppLocale.ru,
    child: child ?? const SizedBox.shrink(),
  );
}

Finder _blurIn(Finder scope) => find.descendant(of: scope, matching: find.byType(BackdropFilter));

void main() {
  setUp(() {
    BlizzardPresentation.debugAssumeIOS = true;
    BlizzardMenuStyleSwitch.value = BlizzardMenuStyle.neutral;
  });
  tearDown(() {
    BlizzardPresentation.debugAssumeIOS = false;
    BlizzardMenuStyleSwitch.value = BlizzardMenuStyle.neutral;
  });

  testWidgets('the setting defaults to the solid style, never the old one', (tester) async {
    final fixture = await _mount(tester);
    expect(fixture.container.read(Preferences.menuStyle), BlizzardMenuStyle.neutral);
    await fixture.close(tester);
  });

  testWidgets('a dialog changes its material as soon as the setting changes', (tester) async {
    final fixture = await _mount(tester, child: _aurora(SettingsPage()));
    await _settle(tester);
    final dialogs = fixture.container.read(dialogNotifierProvider.notifier);
    final shown = dialogs.showConfirmation(title: 'Заголовок', message: 'Сообщение');
    await _settle(tester);
    expect(_blurIn(find.byType(Dialog)), findsNothing);

    await fixture.container.read(Preferences.menuStyle.notifier).update(BlizzardMenuStyle.glass);
    await _settle(tester);
    expect(_blurIn(find.byType(Dialog)), findsOneWidget);

    await fixture.container.read(Preferences.menuStyle.notifier).update(BlizzardMenuStyle.neutral);
    await _settle(tester);
    expect(_blurIn(find.byType(Dialog)), findsNothing);
    expect(tester.takeException(), isNull);

    Navigator.of(tester.element(find.byType(Dialog).first)).pop(false);
    await tester.pump(const Duration(milliseconds: 500));
    await shown;
    await fixture.close(tester);
  });

  testWidgets('the quick settings sheet changes its material with the setting', (tester) async {
    final fixture = await _mount(tester);
    final shown = fixture.container.read(bottomSheetsNotifierProvider.notifier).showQuickSettings();
    await _settle(tester);
    // the sheet has a backdrop filter of its own in both styles; glass adds exactly one
    final solid = _blurIn(find.byType(BottomSheet)).evaluate().length;

    await fixture.container.read(Preferences.menuStyle.notifier).update(BlizzardMenuStyle.glass);
    await _settle(tester);
    expect(_blurIn(find.byType(BottomSheet)), findsNWidgets(solid + 1));
    expect(tester.takeException(), isNull);

    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
    await tester.pump(const Duration(milliseconds: 700));
    await shown;
    await fixture.close(tester);
  });

  for (final style in [BlizzardMenuStyle.neutral, BlizzardMenuStyle.glass]) {
    testWidgets('the overflow menu keeps clear of the right screen edge [${style.name}]', (tester) async {
      final fixture = await _mount(tester, child: _aurora(SettingsPage()));
      await fixture.container.read(Preferences.menuStyle.notifier).update(style);
      await _settle(tester);
      await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.byType(IconButton)).last);
      await _settle(tester);
      final menu = find.byKey(const ValueKey('settings-overflow-menu-glass'));
      expect(menu, findsOneWidget);
      // the visible material, not the transparent gap around it
      final material = find.descendant(of: menu, matching: find.byType(ClipRRect)).first;
      final right = tester.getRect(material).right;
      expect(right, lessThanOrEqualTo(440 - 12));
      expect(_blurIn(menu), style == BlizzardMenuStyle.glass ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    });
  }
}
