import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/adaptive_layout/blizzard_dock.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_route_action.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/router/go_router/routing_config_notifier.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_native_connection_control.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_presentation.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_scene.dart';
import 'package:hiddify/features/stats/widget/side_bar_stats_overview.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MyAdaptiveLayout extends HookConsumerWidget {
  const MyAdaptiveLayout({
    super.key,
    required this.navigationShell,
    required this.isMobileBreakpoint,
    required this.showProfilesAction,
  });
  // managed by go router(Shell Route)
  final StatefulNavigationShell navigationShell;
  final bool isMobileBreakpoint;
  final bool showProfilesAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    // focus switch management
    final primaryFocusHash = useState<int?>(null);
    final navScopeNode = useFocusScopeNode();
    useEffect(() {
      bool handler(KeyEvent event) {
        final arrows = isMobileBreakpoint ? KeyboardConst.verticalArrows : KeyboardConst.horizontalArrows;
        if (!arrows.contains(event.logicalKey)) return false;
        if (event is KeyDownEvent) {
          primaryFocusHash.value = FocusManager.instance.primaryFocus.hashCode;
        } else {
          // focus node does not change => true.
          if (primaryFocusHash.value == FocusManager.instance.primaryFocus.hashCode) {
            if (branchesScope.values.any((node) => node.hasFocus)) {
              navScopeNode.requestFocus();
            } else if (navScopeNode.hasFocus) {
              branchesScope[getNameOfBranch(isMobileBreakpoint, showProfilesAction, navigationShell.currentIndex)]
                  ?.requestFocus();
            }
          }
        }
        return true;
      }

      HardwareKeyboard.instance.addHandler(handler);
      return () {
        HardwareKeyboard.instance.removeHandler(handler);
      };
    }, [isMobileBreakpoint, showProfilesAction, navigationShell.currentIndex]);
    final blizzard = BlizzardPresentation.isActive(context);
    final rootRoute = ModalRoute.of(context);
    final rootRouteVisible = rootRoute?.isCurrent ?? true;
    final snowVisible =
        blizzard &&
        isMobileBreakpoint &&
        navigationShell.currentIndex == 0 &&
        GoRouterState.of(context).uri.path == '/home';
    return BlizzardRootRouteVisibility(
      visible: rootRouteVisible,
      homeVisible: navigationShell.currentIndex == 0,
      route: rootRoute,
      child: BlizzardPresentation(
        child: Material(
          color: blizzard ? BlizzardPalette.background : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: TickerMode(
                  key: const ValueKey('blizzard_shell_root_route_gate'),
                  enabled: rootRouteVisible,
                  child: TickerMode(
                    key: const ValueKey('blizzard_shell_motion_gate'),
                    enabled: snowVisible,
                    child: Opacity(
                      opacity: snowVisible ? 1 : 0,
                      child: const BlizzardScene(
                        key: ValueKey('blizzard_shell_snowfall'),
                        preset: BlizzardParticlePreset.snowfall,
                      ),
                    ),
                  ),
                ),
              ),
              Scaffold(
                backgroundColor: blizzard ? Colors.transparent : null,
                extendBody: blizzard && isMobileBreakpoint && navigationShell.currentIndex == 1,
                body: isMobileBreakpoint
                    ? TickerMode(enabled: rootRouteVisible, child: navigationShell)
                    : Row(
                        children: [
                          FocusScope(
                            node: navScopeNode,
                            child: NavigationRail(
                              extended: Breakpoint(context).isDesktop(),
                              destinations: _navRailDests(_actions(t, showProfilesAction, isMobileBreakpoint)),
                              selectedIndex: navigationShell.currentIndex,
                              onDestinationSelected: (index) => _onTap(context, index),
                              trailing: Breakpoint(context).isDesktop()
                                  ? const Expanded(
                                      child: Align(
                                        alignment: Alignment.bottomCenter,
                                        child: SizedBox(width: 220, child: SideBarStatsOverview()),
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                          Expanded(child: navigationShell),
                        ],
                      ),
                bottomNavigationBar: isMobileBreakpoint
                    ? Builder(
                        builder: (dockContext) => FocusScope(
                          node: navScopeNode,
                          child: blizzard
                              ? BlizzardDock(
                                  actions: _actions(t, showProfilesAction, isMobileBreakpoint),
                                  selectedIndex: navigationShell.currentIndex <= 1 ? navigationShell.currentIndex : 0,
                                  onDestinationSelected: (index) => _onTap(context, index),
                                )
                              : NavigationBar(
                                  selectedIndex: navigationShell.currentIndex <= 1 ? navigationShell.currentIndex : 0,
                                  destinations: _navDests(_actions(t, showProfilesAction, isMobileBreakpoint)),
                                  onDestinationSelected: (index) => _onTap(context, index),
                                ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // shell route action onTap
  void _onTap(BuildContext context, int index) {
    navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
  }

  List<ShellRouteAction> _actions(Translations t, bool showProfilesAction, bool isMobileBreakpoint) => [
    ShellRouteAction(Icons.power_settings_new_rounded, t.pages.home.title),
    if (showProfilesAction && !isMobileBreakpoint) ShellRouteAction(Icons.view_list_rounded, t.pages.profiles.title),
    ShellRouteAction(Icons.settings_rounded, t.pages.settings.title),
    if (!isMobileBreakpoint) ShellRouteAction(Icons.description_rounded, t.pages.logs.title),
    if (!isMobileBreakpoint) ShellRouteAction(Icons.info_rounded, t.pages.about.title),
  ];

  List<NavigationDestination> _navDests(List<ShellRouteAction> actions) =>
      actions.map((e) => NavigationDestination(icon: Icon(e.icon), label: e.title)).toList();
  List<NavigationRailDestination> _navRailDests(List<ShellRouteAction> actions) =>
      actions.map((e) => NavigationRailDestination(icon: Icon(e.icon), label: Text(e.title))).toList();
}
