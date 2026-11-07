import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/bottom_sheets/widgets/quick_settings_modal.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
import 'package:hiddify/features/common/general_pref_tiles.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/blizzard_dock_fixture_action.dart';
import '../test/support/connection_fixtures.dart';
import '../test/support/navigation_fixtures.dart';
import '../test/visual/blizzard_accessibility_contract_test.dart';
import '../test/visual/blizzard_home_visual_test.dart';
import '../test/visual/blizzard_material_contract_test.dart';
import '../test/visual/blizzard_surface_coverage_test.dart';
import '../test/visual/blizzard_theme_transition_test.dart';
import '../test/visual/blizzard_visual_contract_test.dart';
import 'blizzard_home_particles_test.dart' as particles;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment('BLIZZARD_SNOWFALL_CHECKS')) {
    // Keep the existing native entry flag while exercising the current cached
    // Aurora, UIKit control, visibility gates and actual transition frames.
    particles.main();
    return;
  }
  setUpAll(() async {
    final framePolicy = binding.framePolicy;
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    runApp(const MaterialApp(home: SizedBox.shrink()));
    await binding.endOfFrame;
    await Future<void>.delayed(const Duration(seconds: 1));
    binding.framePolicy = framePolicy;
  });
  const phase = String.fromEnvironment('BLIZZARD_STORAGE_PHASE', defaultValue: 'write');
  testWidgets('B-IOS native preference persistence and real UI smoke', (tester) async {
    expect(Platform.isIOS, true, reason: 'Requires actual iOS process, no host override');
    expect(['write', 'read'], contains(phase));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (phase == 'read') {
      expect(prefs.getString('blizzard_harness_receipt'), 'native-write-v1');
      expect(prefs.getString('theme_mode'), 'dark');
    }
    final container = navigationContainer(prefs);
    await container.read(sharedPreferencesProvider.future);
    final router = singlePageRouter(const SafeArea(child: ThemeModePrefTile()));
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: ContractApp(router)));
    await tester.pumpAndSettle();
    if (phase == 'read') {
      expect(container.read(themePreferencesProvider), AppThemeMode.dark);
      debugPrint('BLIZZARD_STORAGE backend=ios_shared_preferences phase=read level=process_restart result=PASS');
    } else {
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      final picker = tester.widget<RadioGroup<AppThemeMode>>(find.byType(RadioGroup<AppThemeMode>));
      expect(picker.groupValue, container.read(themePreferencesProvider));
      expect(
        tester
            .widgetList<RadioListTile<AppThemeMode>>(find.byType(RadioListTile<AppThemeMode>))
            .map((row) => row.value),
        AppThemeMode.values,
      );
      await tester.tap(
        find.widgetWithText(RadioListTile<AppThemeMode>, AppThemeMode.dark.present(fixtureTranslations)),
      );
      await tester.pumpAndSettle();
      expect(prefs.getString('theme_mode'), 'dark');
      expect(await prefs.setString('blizzard_harness_receipt', 'native-write-v1'), true);
      await prefs.reload();
      expect(prefs.getString('blizzard_harness_receipt'), 'native-write-v1');
      final shown = container.read(bottomSheetsNotifierProvider.notifier).showQuickSettings();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byType(QuickSettingsModal), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await shown;
      expect(find.byType(QuickSettingsModal), findsNothing);
      debugPrint('BLIZZARD_STORAGE backend=ios_shared_preferences phase=write level=native_reopen result=PASS');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    container.dispose();
    final events = <String>[];
    final spy = ButtonConnectionSpy(const AsyncData(Connected()), events);
    final smoke = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => prefs),
        translationsProvider.overrideWith((ref) => fixtureTranslations),
        connectionNotifierProvider.overrideWith(() => spy),
        activeProfileProvider.overrideWith(() => FixtureProfile(connectionProfile)),
        activeProxyNotifierProvider.overrideWith(() => FixtureProxy(10)),
        mainOutboundsNotifierProvider.overrideWith(FixtureMainOutbounds.new),
        statsNotifierProvider.overrideWith(ConnectionFixtureStats.new),
        configOptionNotifierProvider.overrideWith(() => FixtureConfig(false)),
      ],
    );
    await smoke.read(sharedPreferencesProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: smoke,
        child: const MaterialApp(
          home: Scaffold(body: Center(child: ConnectionButton())),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('home_connection_button')));
    await tester.pump();
    expect(events, ['toggle']);
    await tester.pumpWidget(const SizedBox.shrink());
    smoke.dispose();
    final nav = navigationContainer(prefs);
    await nav.read(sharedPreferencesProvider.future);
    final shell = shellRouter();
    await tester.pumpWidget(UncontrolledProviderScope(container: nav, child: ContractApp(shell)));
    await tester.pumpAndSettle();
    expect(
      find.byType(NavigationBar).evaluate().isNotEmpty ||
          find.byKey(const ValueKey('blizzard_bottom_dock')).evaluate().isNotEmpty,
      isTrue,
    );
    await activateFixtureDockDestination(tester, 1);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-draft')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    shell.dispose();
    nav.dispose();
    debugPrint('BLIZZARD_IOS_UI phase=$phase platform=ios fixtures=synthetic connection_boundary=spy result=PASS');
  });
  if (const bool.fromEnvironment('BLIZZARD_VISUAL_CHECKS')) {
    registerBlizzardVisualContracts();
    registerBlizzardAccessibilityContracts();
    registerHomeVisualContracts();
    registerBlizzardSurfaceCoverage();
    registerBlizzardMaterialContracts();
    registerBlizzardThemeTransitions();
  }
}
