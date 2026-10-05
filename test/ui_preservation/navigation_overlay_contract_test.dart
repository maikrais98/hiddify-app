import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/bottom_sheets/widgets/quick_settings_modal.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/router/go_router/routing_config_notifier.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/navigation_fixtures.dart';

void main() {
  for (final width in [599.0, 600.0, 840.0]) {
    testWidgets('real adaptive shell navigation and branch lifetime at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final container = navigationContainer(await SharedPreferences.getInstance());
      await container.read(sharedPreferencesProvider.future);
      final router = shellRouter();
      addTearDown(() {
        router.dispose();
        container.dispose();
      });
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: ContractApp(router)));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), width < 600 ? findsOneWidget : findsNothing);
      expect(find.byType(NavigationRail), width < 600 ? findsNothing : findsOneWidget);
      if (width >= 600) expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).extended, width >= 840);
      final state = tester.state<BranchProbeState>(find.byKey(const ValueKey('home')));
      await tester.enterText(find.byKey(const ValueKey('home-draft')), 'preserved draft');
      state.scroll.jumpTo(350);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/settings');
      expect(find.text('settings child'), findsNothing);
      await tester.tap(find.text('settings open child'));
      await tester.pumpAndSettle();
      expect(find.text('settings child'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.power_settings_new_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pumpAndSettle();
      expect(find.text('settings child'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/settings');
      expect(find.text('settings child'), findsNothing);
      await tester.tap(find.text('settings open child'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/settings');
      await container.read(themePreferencesProvider.notifier).changeThemeMode(AppThemeMode.dark);
      tester.view.physicalSize = Size(
        width == 599
            ? 590
            : width == 600
            ? 700
            : 900,
        1000,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.power_settings_new_rounded));
      await tester.pumpAndSettle();
      expect(tester.state(find.byKey(const ValueKey('home'))), same(state));
      expect(state.draft.text, 'preserved draft');
      expect(state.scroll.offset, 350);
      expect(tester.takeException(), isNull);
    });
  }

  test('actual routing config preserves mobile and wide branch/child maps', () async {
    for (final mobile in [true, false]) {
      for (final profiles in [true, false]) {
        final container = ProviderContainer(
          overrides: [
            isMobileBreakpointProvider.overrideWith((ref) => mobile),
            hasAnyProfileProvider.overrideWith((ref) => Stream.value(profiles)),
          ],
        );
        await container.read(hasAnyProfileProvider.future);
        final config = container.read(routingConfigNotifierProvider);
        final shell = config.routes.first as StatefulShellRoute;
        expect(
          shell.branches.map((b) => (b.routes.first as GoRoute).name),
          mobile ? ['home', 'settings'] : ['home', if (profiles) 'profiles', 'settings', 'logs', 'about'],
        );
        final settings = shell.branches.map((b) => b.routes.first as GoRoute).singleWhere((r) => r.name == 'settings');
        final home = shell.branches.first.routes.first as GoRoute;
        expect(home.routes.cast<GoRoute>().map((r) => r.name), mobile ? ['proxies', 'profileDetails'] : ['proxies']);
        expect(config.routes.last is GoRoute && (config.routes.last as GoRoute).name == 'intro', true);
        expect(
          settings.routes.cast<GoRoute>().map((r) => r.name),
          containsAll([
            'general',
            'routeOptions',
            'dnsOptions',
            'inboundOptions',
            'tlsTricks',
            'warpOptions',
            if (mobile) ...['logs', 'about'],
          ]),
        );
        container.dispose();
      }
    }
  });

  testWidgets('real dialogs preserve results, cancellation, validation, reset, draft and focus', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = navigationContainer(await SharedPreferences.getInstance());
    await container.read(sharedPreferencesProvider.future);
    final router = singlePageRouter(const Text('underlying page'));
    addTearDown(() {
      router.dispose();
      container.dispose();
      tester.view.resetViewInsets();
    });
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: ContractApp(router)));
    await tester.pumpAndSettle();
    final dialogs = container.read(dialogNotifierProvider.notifier);
    for (final action in ['confirm', 'cancel', 'back']) {
      final result = dialogs.showConfirmation(
        title: 'Delete fixture?',
        message: 'Synthetic item',
        positiveBtnTxt: 'Proceed',
      );
      await tester.pumpAndSettle();
      if (action == 'back') {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.text(action == 'confirm' ? 'Proceed' : fixtureTranslations.common.cancel));
      }
      await tester.pumpAndSettle();
      expect(await result, action == 'confirm');
    }
    final result = dialogs.showSettingInput<int>(
      title: 'Fixture number',
      initialValue: 7,
      mapTo: int.tryParse,
      validator: (value) => int.tryParse(value) != null,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '42');
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, true);
    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    await container.read(themePreferencesProvider.notifier).changeThemeMode(AppThemeMode.dark);
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, '42');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(await result, 42);
    final invalid = dialogs.showSettingInput<int>(
      title: 'Fixture number',
      initialValue: 7,
      mapTo: int.tryParse,
      validator: (value) => int.tryParse(value) != null,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'invalid');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(await invalid, isNull);
    var resets = 0;
    final reset = dialogs.showSettingInput<String>(
      title: 'Fixture draft',
      initialValue: 'original',
      onReset: () => resets++,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(fixtureTranslations.common.reset));
    await tester.pumpAndSettle();
    expect(await reset, isNull);
    expect(resets, 1);
    final cancel = dialogs.showSettingInput<String>(title: 'Fixture draft', initialValue: 'original');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'unsaved');
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(await cancel, isNull);
    expect(find.text('underlying page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('real quick settings sheet applies toggle, handles insets and dismisses on back', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = navigationContainer(prefs);
    await container.read(sharedPreferencesProvider.future);
    final router = singlePageRouter(const Text('sheet underlying page'));
    addTearDown(() {
      router.dispose();
      container.dispose();
      tester.view.resetViewInsets();
    });
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: ContractApp(router)));
    await tester.pumpAndSettle();
    final sheets = container.read(bottomSheetsNotifierProvider.notifier);
    final shown = sheets.showQuickSettings();
    await tester.pumpAndSettle();
    expect(find.byType(QuickSettingsModal), findsOneWidget);
    expect(container.read(ConfigOptions.enableWarp), false);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(container.read(ConfigOptions.enableWarp), true);
    expect(prefs.getBool('enable-warp'), true);
    tester.view.viewInsets = const FakeViewPadding(bottom: 100);
    await tester.pumpAndSettle();
    final sheetContext = tester.element(find.byType(QuickSettingsModal));
    expect(MediaQuery.viewInsetsOf(sheetContext).bottom, 100);
    expect(
      find.ancestor(
        of: find.byType(QuickSettingsModal),
        matching: find.byWidgetPredicate(
          (widget) => widget is Padding && widget.padding == const EdgeInsets.only(bottom: 100),
        ),
      ),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await shown;
    expect(find.byType(QuickSettingsModal), findsNothing);
    expect(find.text('sheet underlying page'), findsOneWidget);
    expect(container.read(ConfigOptions.enableWarp), true);
    expect(tester.takeException(), isNull);
  });
}
