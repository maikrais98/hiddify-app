import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
import 'package:hiddify/features/common/general_pref_tiles.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/navigation_fixtures.dart';

void main() {
  testWidgets('real theme tile persists all four modes, cancels, resets and reloads', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = navigationContainer(prefs);
    await container.read(sharedPreferencesProvider.future);
    final router = singlePageRouter(const ThemeModePrefTile());
    addTearDown(() {
      router.dispose();
      container.dispose();
    });
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: ContractApp(router)));
    await tester.pumpAndSettle();
    expect(container.read(themePreferencesProvider), AppThemeMode.system);
    expect(prefs.containsKey('theme_mode'), false);
    for (final mode in [AppThemeMode.light, AppThemeMode.dark, AppThemeMode.system, AppThemeMode.black]) {
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      final options = tester.widgetList<RadioListTile<AppThemeMode>>(find.byType(RadioListTile<AppThemeMode>)).toList();
      expect(options.map((e) => e.value), AppThemeMode.values);
      // Characterize the shipped RadioListTile API without migrating its production widget.
      // ignore: deprecated_member_use
      expect(options.every((e) => e.groupValue == container.read(themePreferencesProvider)), true);
      await tester.tap(find.widgetWithText(RadioListTile<AppThemeMode>, mode.present(fixtureTranslations)));
      await tester.pumpAndSettle();
      expect(container.read(themePreferencesProvider), mode);
      expect(prefs.getString('theme_mode'), mode.name);
      final fresh = navigationContainer(prefs);
      await fresh.read(sharedPreferencesProvider.future);
      expect(fresh.read(themePreferencesProvider), mode);
      fresh.dispose();
    }
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text(fixtureTranslations.common.cancel));
    await tester.pumpAndSettle();
    expect(prefs.getString('theme_mode'), 'black');
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text(fixtureTranslations.common.reset));
    await tester.pumpAndSettle();
    expect(container.read(themePreferencesProvider), AppThemeMode.system);
    expect(prefs.getString('theme_mode'), 'system');
  });

  testWidgets('System tracks brightness; explicit modes and true black retain legacy meaning', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = navigationContainer(await SharedPreferences.getInstance());
    await container.read(sharedPreferencesProvider.future);
    final router = singlePageRouter(const Text('theme probe'));
    addTearDown(() {
      router.dispose();
      container.dispose();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
    });
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: ContractApp(router)));
    for (final mode in AppThemeMode.values) {
      await container.read(themePreferencesProvider.notifier).changeThemeMode(mode);
      for (final brightness in Brightness.values) {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        await tester.pumpAndSettle();
        final actual = Theme.of(tester.element(find.text('theme probe')));
        expect(
          actual.brightness,
          mode == AppThemeMode.system
              ? brightness
              : mode == AppThemeMode.light
              ? Brightness.light
              : Brightness.dark,
        );
        if (mode == AppThemeMode.black) expect(actual.scaffoldBackgroundColor, Colors.black);
      }
    }
    expect(AppTheme(AppThemeMode.dark, 'Roboto').darkTheme(null).scaffoldBackgroundColor, isNot(Colors.black));
  });
}
