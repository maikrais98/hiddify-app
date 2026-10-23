import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/router/adaptive_layout/blizzard_dock.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_native_tab_bar.dart';
import '../support/blizzard_visual_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerBlizzardVisualContracts();
}

void registerBlizzardVisualContracts() {
  for (final mode in AppThemeMode.values) {
    for (final brightness in Brightness.values) {
      for (final width in [393.0, 599.0, 600.0, 840.0]) {
        testWidgets('visual scope ${mode.name}/${brightness.name}/$width', (tester) async {
          final fixture = await mountVisualFixture(tester, mode: mode, systemBrightness: brightness, width: width);
          final enabled = expectsBlizzard(mode, brightness, width);
          final theme = fixture.innerTheme!;
          if (enabled) {
            expect(theme.scaffoldBackgroundColor, BlizzardPalette.background);
            expect(theme.colorScheme.primary, BlizzardPalette.accent);
            expect(theme.colorScheme.onSurface, BlizzardPalette.primary);
            expect(theme.colorScheme.surface, BlizzardPalette.surface);
            expect(theme.textTheme.bodyLarge!.fontSize, 17);
          } else {
            final legacy = AppTheme(mode, 'BlizzardFixture');
            final expected = theme.brightness == Brightness.dark ? legacy.darkTheme(null) : legacy.lightTheme(null);
            expect(theme.colorScheme, expected.colorScheme);
            expect(theme.scaffoldBackgroundColor, expected.scaffoldBackgroundColor);
          }
          // Global factory stays legacy; presentation scopes only the eligible child.
          expect(
            AppTheme(mode, 'BlizzardFixture').darkTheme(null).colorScheme.primary,
            isNot(BlizzardPalette.accent),
          );
          expect(fixture.events, isEmpty, reason: 'Appearance rebuild must not issue a VPN command');
          expect(tester.takeException(), isNull);
          await fixture.close(tester);
        });
      }
    }
  }
  for (final mode in [AppThemeMode.dark, AppThemeMode.light, AppThemeMode.black]) {
    testWidgets('dock preserves Scaffold safe-area removal for ${mode.name}', (tester) async {
      tester.view.padding = FakeViewPadding(
        top: 62 * tester.view.devicePixelRatio,
        bottom: 34 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetPadding);
      final fixture = await mountVisualFixture(tester, mode: mode);
      final eligible = expectsBlizzard(mode, Brightness.dark, 393);
      final navFinder = find.byType(NavigationBar);
      if (eligible) {
        final dock = find.byKey(const ValueKey('blizzard_bottom_dock'));
        final nativeDock = find.descendant(of: dock, matching: find.byType(BlizzardNativeTabBar));
        expect(tester.getSize(dock), const Size(320, 88));
        expect(tester.getSize(find.byType(BlizzardDock)).height, 100);
        expect(nativeDock, findsOneWidget);
        expect(find.descendant(of: nativeDock, matching: find.byType(UiKitView)), findsOneWidget);
        expect(find.byKey(const ValueKey('blizzard_bottom_dock_tab_0')), findsNothing);
        expect(find.byKey(const ValueKey('blizzard_bottom_dock_tab_1')), findsNothing);
        expect(MediaQuery.paddingOf(tester.element(dock)).top, 0);
      } else {
        expect(tester.getSize(navFinder).height, 114);
        final navContext = tester.element(navFinder);
        expect(MediaQuery.paddingOf(navContext).top, 0);
        expect(MediaQuery.paddingOf(navContext).bottom, 34);
      }
      expect(fixture.events, isEmpty);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    });
  }
  testWidgets('Blizzard connection geometry and floating dock retain actual actions', (tester) async {
    final fixture = await mountVisualFixture(tester);
    final material = tester.widget<Material>(find.byKey(const ValueKey('home_connection_button')));
    if (expectsBlizzard(AppThemeMode.dark, Brightness.dark, 393)) {
      expect(material.shape, isA<RoundedRectangleBorder>());
      expect((material.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(44));
      final dock = find.byKey(const ValueKey('blizzard_bottom_dock'));
      final nativeDock = find.descendant(of: dock, matching: find.byType(BlizzardNativeTabBar));
      expect(tester.getSize(dock), const Size(320, 88));
      expect(nativeDock, findsOneWidget);
      expect(find.descendant(of: nativeDock, matching: find.byType(UiKitView)), findsOneWidget);
      expect(fixture.innerTheme!.colorScheme.primary, BlizzardPalette.accent);
    } else {
      expect(material.shape, isA<CircleBorder>());
      expect(tester.getSize(find.byKey(const ValueKey('home_connection_button'))), const Size(148, 148));
    }
    await tester.tap(find.byKey(const ValueKey('home_connection_button')));
    await tester.pump();
    expect(fixture.events, ['toggle']);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });
}
