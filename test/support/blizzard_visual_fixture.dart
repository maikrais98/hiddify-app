import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/analytics/analytics_controller.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/adaptive_layout/my_adaptive_layout.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'blizzard_capture.dart';
import 'connection_fixtures.dart';

const visualSwitch = blizzardVisuals;
bool expectsBlizzard(AppThemeMode mode, Brightness brightness, double width) =>
    visualSwitch &&
    Platform.isIOS &&
    width < 600 &&
    (mode == AppThemeMode.dark || (mode == AppThemeMode.system && brightness == Brightness.dark));

class VisualAutoStart extends AutoStartNotifier {
  @override
  Future<bool> build() async => false;
}

class VisualAnalytics extends AnalyticsController {
  @override
  Future<bool> build() async => false;
}

class VisualFixture {
  VisualFixture(this.container, this.router, this.events, this.captureLabel);
  final ProviderContainer container;
  final GoRouter router;
  final List<String> events;
  final String captureLabel;
  ThemeData? innerTheme;
  Future<void> close(WidgetTester tester) async {
    await captureBlizzardFixture(tester, captureLabel);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    container.dispose();
  }
}

/// Real adaptive shell and real content. Overrides isolate only app dependencies.
Future<VisualFixture> mountVisualFixture(
  WidgetTester tester, {
  Widget child = const Center(child: ConnectionButton()),
  AppThemeMode mode = AppThemeMode.dark,
  Brightness systemBrightness = Brightness.dark,
  double width = 393,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
  AppLocale locale = AppLocale.en,
  bool highContrast = false,
  bool disableAnimations = false,
}) async {
  // The renderer must use the requested viewport, including wide iPad cases.
  await tester.binding.setSurfaceSize(Size(width, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // Widget/renderer fixture only; native persistence has a separate integration host.
  SharedPreferences.setMockInitialValues({'haptic_feedback': false, 'theme_mode': mode.name});
  final prefs = await SharedPreferences.getInstance();
  final translations = (await tester.runAsync(() => locale.build()))!;
  final events = <String>[];
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) => prefs),
      translationsProvider.overrideWith((ref) => translations),
      environmentProvider.overrideWithValue(Environment.prod),
      connectionNotifierProvider.overrideWith(() => ButtonConnectionSpy(const AsyncData(Connected()), events)),
      activeProfileProvider.overrideWith(() => FixtureProfile(connectionProfile)),
      activeProxyNotifierProvider.overrideWith(() => FixtureProxy(84)),
      configOptionNotifierProvider.overrideWith(() => FixtureConfig(false)),
      autoStartNotifierProvider.overrideWith(VisualAutoStart.new),
      analyticsControllerProvider.overrideWith(VisualAnalytics.new),
    ],
  );
  await container.read(sharedPreferencesProvider.future);
  await container.read(autoStartNotifierProvider.future);
  await container.read(analyticsControllerProvider.future);
  container.read(activeProfileProvider);
  final font = FontLoader('BlizzardFixture')..addFont(rootBundle.load('assets/fonts/Shabnam.ttf'));
  await font.load();
  await (FontLoader('Shabnam')..addFont(rootBundle.load('assets/fonts/Shabnam.ttf'))).load();
  late VisualFixture fixture;
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MyAdaptiveLayout(
          navigationShell: shell,
          isMobileBreakpoint: Breakpoint(context).isMobile(),
          showProfilesAction: false,
        ),
        branches: ['home', 'settings', 'logs', 'about']
            .map(
              (name) => StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/$name',
                    builder: (context, state) => Builder(
                      builder: (context) {
                        fixture.innerTheme = Theme.of(context);
                        return Scaffold(body: name == 'home' ? child : Text(name));
                      },
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    ],
  );
  fixture = VisualFixture(
    container,
    router,
    events,
    '${child.runtimeType}-${mode.name}-${locale.name}-$width-$scale-${direction.name}-$highContrast',
  );
  final base = AppTheme(
    mode,
    locale == AppLocale.fa ? 'Shabnam' : (Platform.isIOS ? '.SF Pro Text' : 'BlizzardFixture'),
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        theme: base.lightTheme(null),
        darkTheme: base.darkTheme(null),
        themeMode: mode == AppThemeMode.system
            ? (systemBrightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light)
            : mode.flutterThemeMode,
        builder: (context, child) => Center(
          child: SizedBox(
            width: width,
            height: 852,
            child: RepaintBoundary(
              key: blizzardFixtureCanvas,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: Size(width, 852),
                  textScaler: TextScaler.linear(scale),
                  platformBrightness: systemBrightness,
                  highContrast: highContrast,
                  disableAnimations: disableAnimations,
                ),
                child: Directionality(textDirection: direction, child: child!),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  expect(tester.getSize(find.byKey(blizzardFixtureCanvas)), Size(width, 852));
  return fixture;
}
