import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/adaptive_layout/my_adaptive_layout.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final fixtureTranslations = AppLocale.en.buildSync();

ProviderContainer navigationContainer(SharedPreferences prefs) => ProviderContainer(
  overrides: [
    sharedPreferencesProvider.overrideWith((ref) => Future.value(prefs)),
    translationsProvider.overrideWith((ref) => fixtureTranslations),
    statsNotifierProvider.overrideWith(FixtureStats.new),
  ],
);

class FixtureStats extends StatsNotifier {
  @override
  Stream<SystemInfo> build() => Stream.value(SystemInfo.create());
}

class ContractApp extends ConsumerWidget {
  const ContractApp(this.router, {super.key});
  final GoRouter router;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themePreferencesProvider);
    final theme = AppTheme(mode, 'Roboto');
    return MaterialApp.router(
      routerConfig: router,
      themeMode: mode.flutterThemeMode,
      theme: theme.lightTheme(null),
      darkTheme: theme.darkTheme(null),
    );
  }
}

GoRouter singlePageRouter(Widget child) => GoRouter(
  navigatorKey: rootNavKey,
  initialLocation: '/home',
  routes: [
    GoRoute(
      path: '/home',
      builder: (_, _) => Scaffold(body: child),
    ),
  ],
);

/// Only content pages are synthetic: shell, navigation widgets and goBranch are production.
GoRouter shellRouter() => GoRouter(
  navigatorKey: rootNavKey,
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
                  builder: (_, _) => BranchProbe(name, key: ValueKey(name)),
                  routes: [
                    GoRoute(
                      path: 'child',
                      builder: (_, _) => Scaffold(appBar: AppBar(title: Text('$name child'))),
                    ),
                  ],
                ),
              ],
            ),
          )
          .toList(),
    ),
  ],
);

class BranchProbe extends StatefulWidget {
  const BranchProbe(this.name, {super.key});
  final String name;
  @override
  State<BranchProbe> createState() => BranchProbeState();
}

class BranchProbeState extends State<BranchProbe> {
  final draft = TextEditingController();
  final scroll = ScrollController();
  @override
  void dispose() {
    draft.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextField(key: ValueKey('${widget.name}-draft'), controller: draft),
      TextButton(onPressed: () => context.push('/${widget.name}/child'), child: Text('${widget.name} open child')),
      Expanded(
        child: ListView.builder(
          controller: scroll,
          itemCount: 50,
          itemBuilder: (_, index) => SizedBox(height: 48, child: Text('${widget.name} item $index')),
        ),
      ),
    ],
  );
}
