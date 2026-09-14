import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/adaptive_layout/my_adaptive_layout.dart';
import 'package:hiddify/core/router/adaptive_layout/nova_tab_route.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_page.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _ProxiesOverview extends ProxiesOverviewNotifier {
  @override
  Stream<OutboundGroup?> build() => Stream.value(OutboundGroup(tag: 'select'));
}

class _ProxiesSort extends ProxiesSortNotifier {
  @override
  ProxiesSort build() => ProxiesSort.unsorted;
}

Future<void> _pumpProductionProxyShell(WidgetTester tester, {double textScale = 1}) async {
  final translations = await AppLocale.en.build();
  final router = GoRouter(
    initialLocation: '/home/proxies',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MyAdaptiveLayout(navigationShell: navigationShell, isMobileBreakpoint: true, showProfilesAction: false),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/home/proxies', builder: (context, state) => const ProxiesOverviewPage())],
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
        proxiesOverviewNotifierProvider.overrideWith(_ProxiesOverview.new),
        proxiesSortNotifierProvider.overrideWith(_ProxiesSort.new),
      ],
      child: MaterialApp.router(
        theme: AppTheme(AppThemeMode.dark, 'Shabnam').darkTheme(null),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('maps production routes to the four Nova destinations', () {
    expect(novaTabForLocation('/home'), NovaTab.home);
    expect(novaTabForLocation('/home/proxies'), NovaTab.servers);
    expect(novaTabForLocation('/home/proxies/detail'), NovaTab.servers);
    expect(novaTabForLocation('/settings/routing-options'), NovaTab.rules);
    expect(novaTabForLocation('/settings/routing-options/rule/0'), NovaTab.rules);
    expect(novaTabForLocation('/settings'), NovaTab.settings);
    expect(novaTabForLocation('/settings/general'), NovaTab.settings);
  });

  test('resets the current shell branch only when the selected Nova tab is reselected', () {
    expect(shouldResetNovaBranch(current: NovaTab.home, requested: NovaTab.home), isTrue);
    expect(shouldResetNovaBranch(current: NovaTab.home, requested: NovaTab.servers), isFalse);
  });

  test('chooses a destination-aware action when each selected tab is reselected', () {
    expect(novaTabReselectionAction(NovaTab.home), NovaTabReselectionAction.resetShellBranch);
    expect(novaTabReselectionAction(NovaTab.servers), NovaTabReselectionAction.goToProxiesRoot);
    expect(novaTabReselectionAction(NovaTab.rules), NovaTabReselectionAction.goToRoutingOptionsRoot);
    expect(novaTabReselectionAction(NovaTab.settings), NovaTabReselectionAction.resetShellBranch);
  });

  testWidgets('production-style shell opens a destination and resets a reselected nested tab', (tester) async {
    final translations = await AppLocale.en.build();
    final router = GoRouter(
      initialLocation: '/home',
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
                  builder: (context, state) => const Text('home-root'),
                  routes: [
                    GoRoute(
                      path: 'proxies',
                      name: 'proxies',
                      builder: (context, state) => const Text('proxies-root'),
                      routes: [GoRoute(path: 'detail', builder: (context, state) => const Text('proxy-detail'))],
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/settings',
                  name: 'settings',
                  builder: (context, state) => const Text('settings-root'),
                  routes: [
                    GoRoute(
                      path: 'routing-options',
                      name: 'routingOptions',
                      builder: (context, state) => const Text('routing-root'),
                    ),
                  ],
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
        overrides: [translationsProvider.overrideWith((ref) => translations)],
        child: MaterialApp.router(
          theme: ThemeData(extensions: const [NovaThemeData.dark]),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Proxies'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/home/proxies');
    expect(find.text('proxies-root'), findsOneWidget);

    router.go('/home/proxies/detail');
    await tester.pumpAndSettle();
    expect(find.text('proxy-detail'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Proxies'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/home/proxies');
    expect(find.text('proxies-root'), findsOneWidget);
  });

  for (final textScale in [1.0, 1.5, 2.0]) {
    testWidgets('production mobile shell keeps page FAB clear of dock at ${textScale}x text', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
      addTearDown(tester.view.reset);

      await _pumpProductionProxyShell(tester, textScale: textScale);

      final fab = tester.getRect(find.byType(FloatingActionButton));
      final dock = tester.getRect(find.byKey(const ValueKey('nova_dock_surface')));
      expect(fab.overlaps(dock), isFalse, reason: 'FAB $fab overlaps dock $dock at ${textScale}x text');
    });
  }

  testWidgets('production mobile shell applies keyboard inset once to dock and page FAB', (tester) async {
    const keyboardInset = 300.0;
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.reset);

    await _pumpProductionProxyShell(tester);

    final fabBeforeKeyboard = tester.getRect(find.byType(FloatingActionButton));
    final dockBeforeKeyboard = tester.getRect(find.byKey(const ValueKey('nova_dock_surface')));
    final gapBeforeKeyboard = dockBeforeKeyboard.top - fabBeforeKeyboard.bottom;

    tester.view.padding = const FakeViewPadding(top: 59);
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboardInset);
    await tester.pumpAndSettle();

    final fab = tester.getRect(find.byType(FloatingActionButton));
    final dock = tester.getRect(find.byKey(const ValueKey('nova_dock_surface')));
    final keyboardTop = tester.view.physicalSize.height / tester.view.devicePixelRatio - keyboardInset;
    final expectedFabBottom = keyboardTop - NovaDockTokens.contentClearance - kFloatingActionButtonMargin;
    final gapWithKeyboard = dock.top - fab.bottom;

    expect(dock.bottom, lessThanOrEqualTo(keyboardTop));
    expect(fab.overlaps(dock), isFalse);
    expect(fab.bottom, closeTo(expectedFabBottom, 0.001), reason: 'keyboard inset must be consumed by the shell once');
    expect(gapWithKeyboard, closeTo(gapBeforeKeyboard, 0.001));
  });
}
