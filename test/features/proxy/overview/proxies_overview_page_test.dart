import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
import 'package:hiddify/features/proxy/model/auto_mode_selection.dart';
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_page.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _ProxiesState extends ProxiesOverviewNotifier {
  _ProxiesState(this.selection, {this.source});

  final AutoModeSelection selection;
  final Stream<OutboundGroup?>? source;
  final requestedGroups = <String>[];
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
}

class _SortState extends ProxiesSortNotifier {
  @override
  ProxiesSort build() => ProxiesSort.unsorted;

  @override
  Future<void> update(ProxiesSort value) async => state = value;
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

  test('distinguishes Servers empty, loading, service-stopped, and proxy-error states', () {
    expect(proxiesRecoveryStateFor(const AsyncLoading<OutboundGroup?>()), ProxiesRecoveryState.loading);
    expect(proxiesRecoveryStateFor(const AsyncData<OutboundGroup?>(null)), ProxiesRecoveryState.empty);
    expect(
      proxiesRecoveryStateFor(AsyncData<OutboundGroup?>(OutboundGroup(tag: 'select'))),
      ProxiesRecoveryState.empty,
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
    expect(find.text('Connect'), findsOneWidget);
    expect(tester.widget<FloatingActionButton>(find.byType(FloatingActionButton)).onPressed, isNull);

    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Home destination'), findsOneWidget);
  });

  testWidgets('production Servers keeps access available for an empty group', (tester) async {
    final notifier = _ProxiesState(
      const AutoModeSelection(outboundTag: null, reason: AutoModeSelectionReason.noAuthorizedServers),
      source: Stream.value(OutboundGroup(tag: 'select')),
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

    expect(find.text('No proxies available'), findsOneWidget);
    expect(find.text('Profiles'), findsOneWidget);
    expect(tester.widget<FloatingActionButton>(find.byType(FloatingActionButton)).onPressed, isNull);
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
