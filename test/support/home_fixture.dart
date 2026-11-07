import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/analytics/analytics_controller.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/app_info_entity.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/adaptive_layout/my_adaptive_layout.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:hiddify/features/chain/model/chain_enum.dart';
import 'package:hiddify/features/chain/notifier/chain_profile_notifier.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/home/widget/home_page.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service_provider.dart';
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

class HomeFixture {
  HomeFixture(this.container, this.router, this.events, this.captureLabel);
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
Future<HomeFixture> mountHomeFixture(
  WidgetTester tester, {
  Widget child = const HomePage(),
  Widget? settingsChild,
  Widget? proxiesChild,
  ProfileEntity? profile,
  List<Override> extraOverrides = const [],
  AppThemeMode mode = AppThemeMode.dark,
  Brightness systemBrightness = Brightness.dark,
  double width = 393,
  double height = 852,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
  AppLocale locale = AppLocale.en,
  bool highContrast = false,
  bool disableAnimations = false,
  bool nativeViewport = false,
}) async {
  if (!nativeViewport) {
    await tester.binding.setSurfaceSize(Size(width, height + 148));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }
  // Widget/renderer fixture only; native persistence has a separate integration host.
  SharedPreferences.setMockInitialValues({'haptic_feedback': false, 'theme_mode': mode.name});
  final prefs = await SharedPreferences.getInstance();
  final translations = (await tester.runAsync(() => locale.build()))!;
  final events = <String>[];
  final directory = Directory.systemTemp.createTempSync('luma-home-fixture-');
  addTearDown(() => directory.deleteSync(recursive: true));
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) => prefs),
      appInfoProvider.overrideWith(HomeAppInfo.new),
      appDirectoriesProvider.overrideWith(() => HomeFixtureDirectories(directory)),
      profilesNotifierProvider.overrideWith(() => TileProfilesSpy()..profiles = [profile ?? connectionProfile]),
      for (final type in ChainType.values) chainProfileNotifierProvider(type).overrideWith(HomeFixtureChainProfile.new),
      translationsProvider.overrideWith((ref) => translations),
      environmentProvider.overrideWithValue(Environment.prod),
      connectionNotifierProvider.overrideWith(() => ButtonConnectionSpy(const AsyncData(Connected()), events)),
      activeProfileProvider.overrideWith(() => FixtureProfile(profile ?? connectionProfile)),
      mainOutboundsNotifierProvider.overrideWith(() => FixtureMainOutbounds()),
      statsNotifierProvider.overrideWith(ConnectionFixtureStats.new),
      hasAnyProfileProvider.overrideWith((ref) => Stream.value(true)),
      hiddifyCoreServiceProvider.overrideWith((ref) => HomeFixtureCoreService()),
      autoStartNotifierProvider.overrideWith(VisualAutoStart.new),
      analyticsControllerProvider.overrideWith(VisualAnalytics.new),
      ...extraOverrides,
    ],
  );
  await container.read(sharedPreferencesProvider.future);
  await container.read(appInfoProvider.future);
  await container.read(appDirectoriesProvider.future);
  await container.read(autoStartNotifierProvider.future);
  await container.read(analyticsControllerProvider.future);
  container.read(activeProfileProvider);
  final font = FontLoader('BlizzardFixture')..addFont(rootBundle.load('assets/fonts/Shabnam.ttf'));
  await font.load();
  late HomeFixture fixture;
  final router = GoRouter(
    navigatorKey: rootNavKey,
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/profile/:id',
        name: 'profileDetails',
        builder: (context, state) => Scaffold(body: Text('details:${state.pathParameters["id"]}')),
      ),
      for (final name in [
        "profiles",
        "general",
        "routeOptions",
        "routingOptions",
        "chainOptions",
        "dnsOptions",
        "inboundOptions",
        "tlsTricks",
        "warpOptions",
      ])
        GoRoute(
          path: "/$name",
          name: name,
          builder: (context, state) => Scaffold(body: Text(name)),
        ),
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
                    name: name,
                    builder: (context, state) => Builder(
                      builder: (context) {
                        fixture.innerTheme = Theme.of(context);
                        return Scaffold(
                          backgroundColor: name == 'home' ? Colors.transparent : null,
                          body: name == 'home'
                              ? child
                              : name == 'settings' && settingsChild != null
                              ? settingsChild
                              : Text(name),
                        );
                      },
                    ),
                    routes: name == 'home'
                        ? [
                            GoRoute(
                              path: '/proxies',
                              name: 'proxies',
                              builder: (context, state) => Scaffold(body: proxiesChild ?? const Text('proxies')),
                            ),
                          ]
                        : const [],
                  ),
                ],
              ),
            )
            .toList(),
      ),
    ],
  );
  fixture = HomeFixture(
    container,
    router,
    events,
    '${child.runtimeType}-${mode.name}-${locale.name}-$width-$scale-${direction.name}-$highContrast',
  );
  final base = AppTheme(mode, Platform.isIOS ? '.SF Pro Text' : 'BlizzardFixture');
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
            height: height,
            child: RepaintBoundary(
              key: blizzardFixtureCanvas,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: Size(width, height),
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
  expect(tester.getSize(find.byKey(blizzardFixtureCanvas)), Size(width, height));
  return fixture;
}

// Spies stop only at the external action boundary. ProfileTile and its hooks are real.
class TileProfilesSpy extends ProfilesNotifier {
  final calls = <String>[];
  List<ProfileEntity> profiles = [];
  Completer<Unit>? selection;
  @override
  Stream<List<ProfileEntity>> build() => Stream.value(profiles);
  @override
  Future<Unit> selectActiveProfile(String id) async {
    calls.add('select:$id');
    return selection == null ? unit : await selection!.future;
  }

  Future<void> exportConfigToClipboard(ProfileEntity profile) async {
    calls.add('export:${profile.id}');
  }

  @override
  Future<void> deleteProfile(ProfileEntity profile) async {
    calls.add('delete:${profile.id}');
  }
}

class TileUpdateSpy extends UpdateProfileNotifier {
  final calls = <String>[];
  @override
  AsyncValue<Unit?> build(String id) => const AsyncData(null);
  @override
  Future<void> updateProfile(RemoteProfileEntity profile, {bool isBulk = false}) async {
    calls.add('update:${profile.id}');
    state = const AsyncLoading();
  }
}

class HomeAppInfo extends AppInfo {
  @override
  Future<AppInfoEntity> build() async => const AppInfoEntity(
    name: "Hiddify",
    version: "4.1.1",
    buildNumber: "1",
    release: Release.general,
    operatingSystem: "fixture",
    operatingSystemVersion: "1",
    environment: Environment.prod,
  );
}

class HomeProxy extends ActiveProxyNotifier {
  @override
  AsyncValue<OutboundInfo> build() =>
      AsyncData(OutboundInfo(tagDisplay: 'Synthetic Finland', type: 'VLESS', urlTestDelay: 84));
}

// Capability-only external boundary used by the settings surface in the real shell.
class HomeFixtureCoreService implements HiddifyCoreService {
  @override
  final CoreInterface core = _HomeFixtureCoreInterface();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HomeFixtureCoreInterface extends CoreInterface {
  @override
  bool get hasVpnProfile => true;
}

class HomeFixtureDirectories extends AppDirectories {
  HomeFixtureDirectories(this.directory);
  final Directory directory;

  @override
  Future<Directories> build() async => (baseDir: directory, workingDir: directory, tempDir: directory);
}

class HomeFixtureChainProfile extends ChainProfileNotifier {
  @override
  Future<ProfileEntity?> build(ChainType type) => ref.watch(activeProfileProvider.future);
}
