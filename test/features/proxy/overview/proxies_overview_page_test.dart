import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/adaptive_layout/my_adaptive_layout.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/proxy/model/auto_mode_selection.dart';
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_page.dart';
import 'package:hiddify/features/proxy/overview/proxy_picker_state.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _ProxiesState extends ProxiesOverviewNotifier {
  _ProxiesState(this.selection, {this.source});

  final AutoModeSelection selection;
  final Stream<OutboundGroup?>? source;
  final requestedGroups = <String>[];
  final requestedSelections = <(String, String)>[];
  int buildCount = 0;

  @override
  Stream<OutboundGroup?> build() {
    buildCount++;
    return source ??
        Stream.value(
          OutboundGroup(
            tag: 'select',
            items: [OutboundInfo(tag: 'server')],
          ),
        );
  }

  @override
  Future<AutoModeSelection?> urlTest(String groupTag) async {
    requestedGroups.add(groupTag);
    return selection;
  }

  @override
  Future<void> changeProxy(String groupTag, String outboundTag) async {
    requestedSelections.add((groupTag, outboundTag));
    final group = state.valueOrNull;
    if (group == null) return;
    group.selected = outboundTag;
    state = AsyncData(group);
  }
}

class _SortState extends ProxiesSortNotifier {
  @override
  ProxiesSort build() => ProxiesSort.unsorted;

  @override
  Future<void> update(ProxiesSort value) async => state = value;
}

class _ActiveProfileState extends ActiveProfile {
  _ActiveProfileState(this.source);

  final Stream<ProfileEntity?> source;

  @override
  Stream<ProfileEntity?> build() => source;
}

class _UpdateProfileState extends UpdateProfileNotifier {
  ProfileEntity? updatedProfile;

  @override
  AsyncValue<Unit?> build(String id) => const AsyncData(null);

  @override
  Future<void> updateProfile(RemoteProfileEntity profile) async => updatedProfile = profile;
}

class _ConnectionState extends ConnectionNotifier {
  ProfileEntity? reconnectedProfile;

  @override
  Stream<ConnectionStatus> build() => Stream.value(const ConnectionStatus.connected());

  @override
  Future<void> reconnect(ProfileEntity? profile) async => reconnectedProfile = profile;
}

class _BottomSheetsState extends BottomSheetsNotifier {
  int addProfileCount = 0;
  int profilesOverviewCount = 0;

  @override
  void build() {}

  @override
  Future<void> showAddProfile({String? url, bool triggeredByDeepLink = false}) async => addProfileCount++;

  @override
  Future<void> showProfilesOverview() async => profilesOverviewCount++;
}

void main() {
  String feedback(AutoModeSelection selection) =>
      autoModeSelectionFeedback(selection, autoLabel: 'Auto', timeoutLabel: 'Timeout', emptyLabel: 'No servers');

  test('presents the selected server and measured latency', () {
    expect(
      feedback(
        const AutoModeSelection(
          outboundTag: 'Stockholm',
          reason: AutoModeSelectionReason.lowestLatency,
          latency: Duration(milliseconds: 42),
        ),
      ),
      'Auto: Stockholm · 42 ms',
    );
  });

  test('presents deterministic, timeout, and empty outcomes truthfully', () {
    expect(
      feedback(
        const AutoModeSelection(outboundTag: 'Amsterdam', reason: AutoModeSelectionReason.deterministicFallback),
      ),
      'Auto: Amsterdam',
    );
    expect(
      feedback(const AutoModeSelection(outboundTag: 'Berlin', reason: AutoModeSelectionReason.latencyUnavailable)),
      'Auto: Berlin · Timeout',
    );
    expect(
      feedback(const AutoModeSelection(outboundTag: null, reason: AutoModeSelectionReason.noAuthorizedServers)),
      'No servers',
    );
  });

  test('distinguishes missing group, empty group, loading, service-stopped, and proxy-error states', () {
    expect(proxiesRecoveryStateFor(const AsyncLoading<OutboundGroup?>()), ProxiesRecoveryState.loading);
    expect(proxiesRecoveryStateFor(const AsyncData<OutboundGroup?>(null)), ProxiesRecoveryState.noGroup);
    expect(
      proxiesRecoveryStateFor(AsyncData<OutboundGroup?>(OutboundGroup(tag: 'select'))),
      ProxiesRecoveryState.emptyGroup,
    );
    expect(
      proxiesRecoveryStateFor(const AsyncError<OutboundGroup?>(ServiceNotRunning(), StackTrace.empty)),
      ProxiesRecoveryState.serviceStopped,
    );
    expect(
      proxiesRecoveryStateFor(AsyncError<OutboundGroup?>(StateError('proxy failed'), StackTrace.empty)),
      ProxiesRecoveryState.proxyError,
    );
    expect(
      proxiesRecoveryStateFor(
        AsyncData<OutboundGroup?>(
          OutboundGroup(
            tag: 'select',
            items: [OutboundInfo(tag: 'server')],
          ),
        ),
      ),
      isNull,
    );
  });

  testWidgets('Servers recovery panel exposes the action for the failure reason', (tester) async {
    var actions = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [NovaThemeData.dark]),
        home: Scaffold(
          body: ProxiesRecoveryPanel(
            title: 'Connect to load servers',
            message: 'The VPN service is stopped',
            actionLabel: 'Connect',
            actionIcon: Icons.power_settings_new_rounded,
            onAction: () => actions++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Connect'));
    expect(actions, 1);
  });

  testWidgets('Servers recovery action supports keyboard and descriptive semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    var actions = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [NovaThemeData.dark]),
        home: Scaffold(
          body: ProxiesRecoveryPanel(
            title: 'No servers found',
            message: 'Refresh the selected access.',
            actionLabel: 'Refresh access',
            onAction: () => actions++,
          ),
        ),
      ),
    );

    expect(find.text('No servers found'), findsOneWidget);
    expect(find.text('Refresh the selected access.'), findsOneWidget);
    expect(find.bySemanticsLabel('Refresh access'), findsOneWidget);
    expect(
      tester.getCenter(find.byType(SingleChildScrollView)).dy,
      closeTo(tester.getCenter(find.byType(Scaffold)).dy, 1),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    final focused = find.byElementPredicate(
      (element) => identical(element, FocusManager.instance.primaryFocus?.context),
    );
    expect(
      find.ancestor(of: focused, matching: find.byKey(const ValueKey('proxies_recovery_primary_action'))),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(actions, 1);
    semantics.dispose();
  });

  testWidgets('Servers recovery panel fits narrow screens at 200% text scale', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [NovaThemeData.dark]),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: ProxiesRecoveryPanel(
            title: 'No servers found',
            message: 'Refresh the selected VPN access or select another one.',
            actionLabel: 'Refresh access',
            onAction: () {},
            secondaryActionLabel: 'Select access',
            onSecondaryAction: () {},
          ),
        ),
      ),
    );

    expect(find.text('Refresh access'), findsOneWidget);
    expect(find.text('Select access'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Servers loading panel has no recovery action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [NovaThemeData.dark]),
        home: const Scaffold(
          body: ProxiesRecoveryPanel(title: 'Loading servers', message: 'Please wait', loading: true),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('production Servers retries proxy errors and disables Auto Mode', (tester) async {
    final notifier = _ProxiesState(
      const AutoModeSelection(outboundTag: null, reason: AutoModeSelectionReason.noAuthorizedServers),
      source: Stream.error(StateError('proxy failed')),
    );
    final translations = await AppLocale.en.build();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWith((ref) => translations),
          proxiesOverviewNotifierProvider.overrideWith(() => notifier),
          proxiesSortNotifierProvider.overrideWith(_SortState.new),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [NovaThemeData.dark]),
          home: const ProxiesOverviewPage(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Could not load servers'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.widget<FloatingActionButton>(find.byType(FloatingActionButton)).onPressed, isNull);

    final initialBuildCount = notifier.buildCount;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(notifier.buildCount, greaterThan(initialBuildCount));
  });

  testWidgets('production Servers sends a stopped service to Home to connect', (tester) async {
    final notifier = _ProxiesState(
      const AutoModeSelection(outboundTag: null, reason: AutoModeSelectionReason.noAuthorizedServers),
      source: Stream.error(const ServiceNotRunning()),
    );
    final translations = await AppLocale.en.build();
    final router = GoRouter(
      initialLocation: '/proxies',
      routes: [
        GoRoute(name: 'home', path: '/home', builder: (_, _) => const Text('Home destination')),
        GoRoute(path: '/proxies', builder: (_, _) => const ProxiesOverviewPage()),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWith((ref) => translations),
          proxiesOverviewNotifierProvider.overrideWith(() => notifier),
          proxiesSortNotifierProvider.overrideWith(_SortState.new),
        ],
        child: MaterialApp.router(
          theme: ThemeData(extensions: const [NovaThemeData.dark]),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connect to get the server list'), findsOneWidget);
    expect(find.text('Go to connection'), findsOneWidget);
    expect(tester.widget<FloatingActionButton>(find.byType(FloatingActionButton)).onPressed, isNull);

    await tester.tap(find.text('Go to connection'));
    await tester.pumpAndSettle();
    expect(find.text('Home destination'), findsOneWidget);
  });

  testWidgets('production Servers offers access selection when no group is available', (tester) async {
    final translations = await AppLocale.en.build();

    for (final hasProfiles in [false, true]) {
      final notifier = _ProxiesState(
        const AutoModeSelection(outboundTag: null, reason: AutoModeSelectionReason.noAuthorizedServers),
        source: Stream.value(null),
      );
      final bottomSheets = _BottomSheetsState();
      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey(hasProfiles),
          overrides: [
            translationsProvider.overrideWith((ref) => translations),
            proxiesOverviewNotifierProvider.overrideWith(() => notifier),
            proxiesSortNotifierProvider.overrideWith(_SortState.new),
            hasAnyProfileProvider.overrideWith((ref) => Stream.value(hasProfiles)),
            bottomSheetsNotifierProvider.overrideWith(() => bottomSheets),
          ],
          child: MaterialApp(
            theme: ThemeData(extensions: const [NovaThemeData.dark]),
            home: const ProxiesOverviewPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Select VPN access'), findsOneWidget);
      expect(find.text('Select access'), findsOneWidget);
      expect(find.text('Refresh access'), findsNothing);
      expect(tester.widget<FloatingActionButton>(find.byType(FloatingActionButton)).onPressed, isNull);

      await tester.tap(find.text('Select access'));
      await tester.pump();
      expect(bottomSheets.addProfileCount, hasProfiles ? 0 : 1);
      expect(bottomSheets.profilesOverviewCount, hasProfiles ? 1 : 0);
    }
  });

  Future<void> pumpEmptyGroup(
    WidgetTester tester, {
    required Stream<ProfileEntity?> activeProfile,
    required _UpdateProfileState profileUpdate,
    required _ConnectionState connection,
    required _BottomSheetsState bottomSheets,
    bool hasProfiles = true,
  }) async {
    final translations = await AppLocale.en.build();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWith((ref) => translations),
          proxiesOverviewNotifierProvider.overrideWith(
            () => _ProxiesState(
              const AutoModeSelection(outboundTag: null, reason: AutoModeSelectionReason.noAuthorizedServers),
              source: Stream.value(OutboundGroup(tag: 'select')),
            ),
          ),
          proxiesSortNotifierProvider.overrideWith(_SortState.new),
          activeProfileProvider.overrideWith(() => _ActiveProfileState(activeProfile)),
          updateProfileNotifierProvider('remote').overrideWith(() => profileUpdate),
          connectionNotifierProvider.overrideWith(() => connection),
          hasAnyProfileProvider.overrideWith((ref) => Stream.value(hasProfiles)),
          bottomSheetsNotifierProvider.overrideWith(() => bottomSheets),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [NovaThemeData.dark]),
          home: const ProxiesOverviewPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty-group refresh updates and reconnects the active remote profile', (tester) async {
    final active = ProfileEntity.remote(
      id: 'remote',
      active: true,
      name: 'Remote',
      url: 'https://example.com/sub',
      lastUpdate: DateTime(2026),
    );
    final profileUpdate = _UpdateProfileState();
    final connection = _ConnectionState();
    final bottomSheets = _BottomSheetsState();
    await pumpEmptyGroup(
      tester,
      activeProfile: Stream.value(active),
      profileUpdate: profileUpdate,
      connection: connection,
      bottomSheets: bottomSheets,
    );

    expect(find.text('No proxies available'), findsOneWidget);
    expect(find.text('Refresh access'), findsOneWidget);
    expect(find.text('Select access'), findsOneWidget);
    expect(tester.widget<FloatingActionButton>(find.byType(FloatingActionButton)).onPressed, isNull);

    await tester.tap(find.text('Refresh access'));
    await tester.pump();
    expect(profileUpdate.updatedProfile, active);
    expect(connection.reconnectedProfile, isNull);
    expect(bottomSheets.profilesOverviewCount, 0);
  });

  testWidgets('empty-group refresh reconnects the active local profile', (tester) async {
    final active = ProfileEntity.local(id: 'local', active: true, name: 'Local', lastUpdate: DateTime(2026));
    final profileUpdate = _UpdateProfileState();
    final connection = _ConnectionState();
    final bottomSheets = _BottomSheetsState();
    await pumpEmptyGroup(
      tester,
      activeProfile: Stream.value(active),
      profileUpdate: profileUpdate,
      connection: connection,
      bottomSheets: bottomSheets,
    );

    await tester.tap(find.text('Refresh access'));
    await tester.pump();
    expect(connection.reconnectedProfile, active);
    expect(profileUpdate.updatedProfile, isNull);
    expect(bottomSheets.profilesOverviewCount, 0);
  });

  testWidgets('empty-group refresh falls back to selecting access for null and active-profile errors', (tester) async {
    for (final activeProfile in <Stream<ProfileEntity?>>[
      Stream.value(null),
      Stream.error(StateError('active profile failed')),
    ]) {
      final profileUpdate = _UpdateProfileState();
      final connection = _ConnectionState();
      final bottomSheets = _BottomSheetsState();
      await pumpEmptyGroup(
        tester,
        activeProfile: activeProfile,
        profileUpdate: profileUpdate,
        connection: connection,
        bottomSheets: bottomSheets,
      );

      await tester.tap(find.text('Refresh access'));
      await tester.pumpAndSettle();
      expect(bottomSheets.profilesOverviewCount, 1);
      expect(profileUpdate.updatedProfile, isNull);
      expect(connection.reconnectedProfile, isNull);
    }
  });

  testWidgets('cold recovery providers keep actions visible and disabled until values arrive', (tester) async {
    final activeProfiles = StreamController<ProfileEntity?>();
    final hasProfiles = StreamController<bool>();
    addTearDown(activeProfiles.close);
    addTearDown(hasProfiles.close);
    final profileUpdate = _UpdateProfileState();
    final connection = _ConnectionState();
    final bottomSheets = _BottomSheetsState();
    final translations = await AppLocale.en.build();
    final active = ProfileEntity.remote(
      id: 'remote',
      active: true,
      name: 'Remote',
      url: 'https://example.com/sub',
      lastUpdate: DateTime(2026),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWith((ref) => translations),
          proxiesOverviewNotifierProvider.overrideWith(
            () => _ProxiesState(
              const AutoModeSelection(outboundTag: null, reason: AutoModeSelectionReason.noAuthorizedServers),
              source: Stream.value(OutboundGroup(tag: 'select')),
            ),
          ),
          proxiesSortNotifierProvider.overrideWith(_SortState.new),
          activeProfileProvider.overrideWith(() => _ActiveProfileState(activeProfiles.stream)),
          updateProfileNotifierProvider('remote').overrideWith(() => profileUpdate),
          connectionNotifierProvider.overrideWith(() => connection),
          hasAnyProfileProvider.overrideWith((ref) => hasProfiles.stream),
          bottomSheetsNotifierProvider.overrideWith(() => bottomSheets),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [NovaThemeData.dark]),
          home: const ProxiesOverviewPage(),
        ),
      ),
    );
    await tester.pump();

    final primary = find.byKey(const ValueKey('proxies_recovery_primary_action'));
    final secondary = find.byKey(const ValueKey('proxies_recovery_secondary_action'));
    expect(primary, findsOneWidget);
    expect(secondary, findsOneWidget);
    expect(tester.widget<FilledButton>(primary).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(secondary).onPressed, isNull);

    activeProfiles.add(active);
    hasProfiles.add(true);
    await tester.pump();
    expect(tester.widget<FilledButton>(primary).onPressed, isNotNull);
    expect(tester.widget<OutlinedButton>(secondary).onPressed, isNotNull);

    await tester.tap(primary);
    await tester.pump();
    expect(profileUpdate.updatedProfile, active);

    await tester.tap(secondary);
    await tester.pump();
    expect(bottomSheets.profilesOverviewCount, 1);
  });

  testWidgets('the production Auto Mode action tests select and shows the chosen server', (tester) async {
    const selection = AutoModeSelection(
      outboundTag: 'Stockholm',
      reason: AutoModeSelectionReason.lowestLatency,
      latency: Duration(milliseconds: 42),
    );
    final notifier = _ProxiesState(selection);
    final translations = await AppLocale.en.build();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWith((ref) => translations),
          proxiesOverviewNotifierProvider.overrideWith(() => notifier),
          proxiesSortNotifierProvider.overrideWith(_SortState.new),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [NovaThemeData.dark]),
          home: const ProxiesOverviewPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(notifier.requestedGroups, ['select']);
    expect(find.text('Auto: Stockholm · 42 ms'), findsOneWidget);
  });

  testWidgets('production picker searches and exposes the previous node for one-tap repeat selection', (tester) async {
    final notifier = _ProxiesState(
      const AutoModeSelection(outboundTag: null, reason: AutoModeSelectionReason.noAuthorizedServers),
      source: Stream.value(
        OutboundGroup(
          tag: 'select',
          selected: 'vienna',
          items: [
            OutboundInfo(tag: 'stockholm', tagDisplay: 'Stockholm'),
            OutboundInfo(tag: 'tokyo', tagDisplay: 'Tokyo edge'),
            OutboundInfo(tag: 'vienna', tagDisplay: 'Vienna'),
          ],
        ),
      ),
    );
    final translations = await AppLocale.en.build();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWith((ref) => translations),
          proxiesOverviewNotifierProvider.overrideWith(() => notifier),
          proxiesSortNotifierProvider.overrideWith(_SortState.new),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [NovaThemeData.dark]),
          home: const ProxiesOverviewPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('proxy_picker_search')), 'stock');
    await tester.pump();
    expect(find.text('Stockholm'), findsOneWidget);
    expect(find.text('Tokyo edge'), findsNothing);
    expect(find.text('Vienna'), findsOneWidget);

    await tester.tap(find.text('Stockholm'));
    await tester.pump();

    expect(notifier.requestedSelections, [('select', 'stockholm')]);
    expect(find.byKey(const ValueKey('proxy_picker_recent_vienna')), findsOneWidget);
    expect(find.text('Stockholm'), findsNWidgets(2));
  });

  testWidgets('production shell resets search after Servers to Settings to Servers while preserving shortcuts', (
    tester,
  ) async {
    final translations = await AppLocale.en.build();
    final notifier = _ProxiesState(
      const AutoModeSelection(outboundTag: null, reason: AutoModeSelectionReason.noAuthorizedServers),
      source: Stream.value(
        OutboundGroup(
          tag: 'select',
          selected: 'tokyo',
          items: [
            OutboundInfo(tag: 'stockholm', tagDisplay: 'Stockholm'),
            OutboundInfo(tag: 'tokyo', tagDisplay: 'Tokyo edge'),
            OutboundInfo(tag: 'vienna', tagDisplay: 'Vienna'),
          ],
        ),
      ),
    );
    final recent = ProxyRecentTagsNotifier()..record('vienna');
    final router = GoRouter(
      initialLocation: '/home/proxies',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              MyAdaptiveLayout(navigationShell: navigationShell, isMobileBreakpoint: true, showProfilesAction: false),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/home',
                  name: 'home',
                  builder: (context, state) => const Text('Home destination'),
                  routes: [
                    GoRoute(path: 'proxies', name: 'proxies', builder: (context, state) => const ProxiesOverviewPage()),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/settings',
                  name: 'settings',
                  builder: (context, state) => const Text('Settings destination'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWith((ref) => translations),
          proxiesOverviewNotifierProvider.overrideWith(() => notifier),
          proxiesSortNotifierProvider.overrideWith(_SortState.new),
          proxyRecentTagsProvider.overrideWith((ref) => recent),
        ],
        child: MaterialApp.router(
          theme: ThemeData.dark().copyWith(extensions: const [NovaThemeData.dark]),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('proxy_picker_search')), 'stock');
    await tester.pump();
    expect(find.text('Tokyo edge'), findsOneWidget);
    expect(find.text('Vienna'), findsOneWidget);
    expect(find.byKey(const ValueKey('proxy_picker_recent_vienna')), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/settings');

    await tester.tap(find.bySemanticsLabel('Proxies'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/home/proxies');

    expect(tester.widget<TextField>(find.byKey(const ValueKey('proxy_picker_search'))).controller!.text, isEmpty);
    expect(find.text('Stockholm'), findsOneWidget);
    expect(find.text('Tokyo edge'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('proxy_picker_recent_vienna')), findsOneWidget);
  });

  testWidgets('the production Auto Mode action reports an empty authorized set', (tester) async {
    final notifier = _ProxiesState(
      const AutoModeSelection(outboundTag: null, reason: AutoModeSelectionReason.noAuthorizedServers),
    );
    final translations = await AppLocale.en.build();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWith((ref) => translations),
          proxiesOverviewNotifierProvider.overrideWith(() => notifier),
          proxiesSortNotifierProvider.overrideWith(_SortState.new),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [NovaThemeData.dark]),
          home: const ProxiesOverviewPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(notifier.requestedGroups, ['select']);
    expect(find.text(translations.pages.proxies.empty), findsOneWidget);
  });
}
