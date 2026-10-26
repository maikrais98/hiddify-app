import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/adaptive_menu.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_backdrop.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_glass.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_presentation.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_system_symbol.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hiddify/features/settings/notifier/reset_tunnel/reset_tunnel_notifier.dart';
import 'package:hiddify/features/settings/widget/blizzard_settings_group.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum ConfigOptionSection {
  warp,
  fragment;

  static final _warpKey = GlobalKey(debugLabel: "warp-section-key");
  static final _fragmentKey = GlobalKey(debugLabel: "fragment-section-key");

  GlobalKey get key => switch (this) {
    ConfigOptionSection.warp => _warpKey,
    ConfigOptionSection.fragment => _fragmentKey,
  };
}

class SettingsPage extends HookConsumerWidget {
  SettingsPage({super.key, String? section})
    : section = section != null ? ConfigOptionSection.values.byName(section) : null;

  final ConfigOptionSection? section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final blizzard =
        BlizzardPresentation.isActive(context) ||
        (Theme.of(context).extension<BlizzardEligibility>()?.applied ?? false);
    // final scrollController = useScrollController();

    // useMemoized(
    //   () {
    //     if (section != null) {
    //       WidgetsBinding.instance.addPostFrameCallback(
    //         (_) {
    //           final box = section!.key.currentContext?.findRenderObject() as RenderBox?;

    //           final offset = box?.localToGlobal(Offset.zero);
    //           if (offset == null) return;
    //           final height = scrollController.offset + offset.dy - MediaQueryData.fromView(View.of(context)).padding.top - kToolbarHeight;
    //           scrollController.animateTo(
    //             height,
    //             duration: const Duration(milliseconds: 500),
    //             curve: Curves.decelerate,
    //           );
    //         },
    //       );
    //     }
    //   },
    // );

    return BlizzardPresentation(
      child: BlizzardBackdrop(
        child: Scaffold(
          backgroundColor: blizzard ? Colors.transparent : null,
          appBar: AppBar(
            title: Text(t.pages.settings.title),
            actions: [
              Builder(
                builder: (context) {
                  List<Widget> popupSurface(List<Widget> children, {Key? key}) =>
                      blizzard ? <Widget>[BlizzardPopupMenuSurface(key: key, children: children)] : children;

                  final importItems = <Widget>[
                    MenuItemButton(
                      onPressed: () async => await ref
                          .read(dialogNotifierProvider.notifier)
                          .showConfirmation(
                            title: t.common.msg.import.confirm,
                            message: t.dialogs.confirmation.settings.import.msg,
                          )
                          .then((shouldImport) async {
                            if (shouldImport) {
                              await ref.read(configOptionNotifierProvider.notifier).importFromClipboard();
                            }
                          }),
                      child: Text(t.pages.settings.options.import.clipboard),
                    ),
                    MenuItemButton(
                      onPressed: () async => await ref
                          .read(dialogNotifierProvider.notifier)
                          .showConfirmation(
                            title: t.common.msg.import.confirm,
                            message: t.dialogs.confirmation.settings.import.msg,
                          )
                          .then((shouldImport) async {
                            if (shouldImport) {
                              await ref.read(configOptionNotifierProvider.notifier).importFromJsonFile();
                            }
                          }),
                      child: Text(t.pages.settings.options.import.file),
                    ),
                  ];
                  final exportItems = <Widget>[
                    MenuItemButton(
                      onPressed: () async =>
                          await ref.read(configOptionNotifierProvider.notifier).exportJsonClipboard(),
                      child: Text(t.pages.settings.options.export.anonymousToClipboard),
                    ),
                    MenuItemButton(
                      onPressed: () async => await ref.read(configOptionNotifierProvider.notifier).exportJsonFile(),
                      child: Text(t.pages.settings.options.export.anonymousToFile),
                    ),
                    const PopupMenuDivider(),
                    MenuItemButton(
                      onPressed: () async => await ref
                          .read(configOptionNotifierProvider.notifier)
                          .exportJsonClipboard(excludePrivate: false),
                      child: Text(t.pages.settings.options.export.allToClipboard),
                    ),
                    MenuItemButton(
                      onPressed: () async =>
                          await ref.read(configOptionNotifierProvider.notifier).exportJsonFile(excludePrivate: false),
                      child: Text(t.pages.settings.options.export.allToFile),
                    ),
                  ];
                  final menuItems = <Widget>[
                    SubmenuButton(menuChildren: popupSurface(importItems), child: Text(t.common.import)),
                    SubmenuButton(menuChildren: popupSurface(exportItems), child: Text(t.common.export)),
                    const PopupMenuDivider(),
                    MenuItemButton(
                      child: Text(t.pages.settings.options.reset),
                      onPressed: () async => await ref.read(configOptionNotifierProvider.notifier).resetOption(),
                    ),
                  ];
                  final menu = MenuAnchor(
                    menuChildren: popupSurface(menuItems, key: const ValueKey('settings-overflow-menu-glass')),
                    builder: (context, controller, child) {
                      final button = IconButton(
                        onPressed: () {
                          if (controller.isOpen) {
                            controller.close();
                          } else {
                            controller.open();
                          }
                        },
                        icon: const BlizzardSystemSymbol(icon: Icons.more_vert_rounded),
                      );
                      return blizzard
                          ? BlizzardGlass(active: true, radius: BlizzardRadii.sheet, child: button)
                          : button;
                    },
                  );
                  return blizzard ? MenuTheme(data: blizzardPopupMenuTheme, child: menu) : menu;
                },
              ),
              const Gap(8),
            ],
          ),
          body: BlizzardPresentation.isActive(context)
              ? const BlizzardSettingsMenu()
              : ListView(
                  children: [
                    // TipCard(message: t.settings.experimentalMsg),
                    SettingsSection(
                      title: t.pages.settings.general.title,
                      icon: Icons.layers_rounded,
                      namedLocation: context.namedLocation('general'),
                    ),
                    SettingsSection(
                      title: t.pages.settings.routing.title,
                      icon: Icons.route_rounded,
                      namedLocation: context.namedLocation('routeOptions'),
                    ),
                    SettingsSection(
                      title: t.pages.settings.dns.title,
                      icon: Icons.dns_rounded,
                      namedLocation: context.namedLocation('dnsOptions'),
                    ),
                    SettingsSection(
                      title: t.pages.settings.inbound.title,
                      icon: Icons.input_rounded,
                      namedLocation: context.namedLocation('inboundOptions'),
                    ),
                    SettingsSection(
                      title: t.pages.settings.tlsTricks.title,
                      icon: Icons.content_cut_rounded,
                      namedLocation: context.namedLocation('tlsTricks'),
                    ),
                    SettingsSection(
                      title: t.pages.settings.warp.title,
                      icon: Icons.cloud_rounded,
                      namedLocation: context.namedLocation('warpOptions'),
                    ),
                    if (PlatformUtils.isIOS)
                      Material(
                        borderRadius: BlizzardPresentation.isActive(context)
                            ? BorderRadius.circular(BlizzardRadii.row)
                            : null,
                        clipBehavior: BlizzardPresentation.isActive(context) ? Clip.antiAlias : Clip.none,
                        child: ListTile(
                          title: Text(t.pages.settings.resetTunnel),
                          leading: const BlizzardSystemSymbol(icon: Icons.autorenew_rounded),
                          onTap: () async {
                            await ref.read(resetTunnelNotifierProvider.notifier).run();
                          },
                        ),
                      ),
                    if (Breakpoint(context).isMobile()) ...[
                      SettingsSection(
                        title: t.pages.logs.title,
                        icon: Icons.description_rounded,
                        namedLocation: context.namedLocation('logs'),
                      ),
                      SettingsSection(
                        title: t.pages.about.title,
                        icon: Icons.info_rounded,
                        namedLocation: context.namedLocation('about'),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class BlizzardSettingsMenu extends ConsumerWidget {
  const BlizzardSettingsMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.paddingOf(context).bottom),
      children: [
        BlizzardSettingsGroup(
          groupKey: const ValueKey('settings-group-application'),
          title: t.$meta.locale == AppLocale.ru ? 'Приложение' : 'Application',
          children: [
            SettingsSection(
              title: t.pages.settings.general.title,
              icon: Icons.tune_outlined,
              namedLocation: context.namedLocation('general'),
              blizzardStyle: true,
            ),
            SettingsSection(
              title: t.pages.about.title,
              icon: Icons.info_outline_rounded,
              namedLocation: context.namedLocation('about'),
              blizzardStyle: true,
            ),
          ],
        ),
        const Gap(16),
        BlizzardSettingsGroup(
          groupKey: const ValueKey('settings-group-connection'),
          title: t.$meta.locale == AppLocale.ru ? 'Подключение' : t.components.stats.connection,
          children: [
            SettingsSection(
              title: t.pages.settings.routing.title,
              icon: Icons.alt_route_rounded,
              namedLocation: context.namedLocation('routeOptions'),
              blizzardStyle: true,
            ),
            SettingsSection(
              title: t.pages.settings.dns.title,
              icon: Icons.dns_outlined,
              namedLocation: context.namedLocation('dnsOptions'),
              blizzardStyle: true,
            ),
            SettingsSection(
              title: t.pages.settings.inbound.title,
              icon: Icons.input_outlined,
              namedLocation: context.namedLocation('inboundOptions'),
              blizzardStyle: true,
            ),
            SettingsSection(
              title: t.pages.settings.tlsTricks.title,
              icon: Icons.build_outlined,
              namedLocation: context.namedLocation('tlsTricks'),
              blizzardStyle: true,
            ),
            SettingsSection(
              title: t.pages.settings.warp.title,
              icon: Icons.bolt_outlined,
              namedLocation: context.namedLocation('warpOptions'),
              blizzardStyle: true,
            ),
          ],
        ),
        const Gap(16),
        BlizzardSettingsGroup(
          groupKey: const ValueKey('settings-group-diagnostics'),
          title: t.$meta.locale == AppLocale.ru ? 'Диагностика' : 'Diagnostics',
          children: [
            SettingsSection(
              title: t.pages.logs.title,
              icon: Icons.article_outlined,
              namedLocation: context.namedLocation('logs'),
              blizzardStyle: true,
            ),
          ],
        ),
        const Gap(16),
        BlizzardSettingsPanel(
          key: const ValueKey('settings-reset-tunnel'),
          minTileHeight: 48,
          radius: 16,
          legacySurface: true,
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              title: Text(
                t.pages.settings.resetTunnel,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: BlizzardPalette.error, fontSize: 17),
              ),
              onTap: () async {
                await ref.read(resetTunnelNotifierProvider.notifier).run();
              },
            ),
          ],
        ),
      ],
    );
  }
}

class SettingsSection extends HookConsumerWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.icon,
    required this.namedLocation,
    this.blizzardStyle = false,
  });

  final String title;
  final IconData icon;
  final String namedLocation;
  final bool blizzardStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: blizzardStyle ? const EdgeInsets.symmetric(horizontal: 16) : null,
      minLeadingWidth: blizzardStyle ? 24 : null,
      horizontalTitleGap: blizzardStyle ? 12 : null,
      leading: BlizzardSystemSymbol(
        icon: icon,
        size: blizzardStyle ? 20 : null,
        color: blizzardStyle ? BlizzardPalette.secondary : null,
      ),
      title: Text(title),
      trailing: BlizzardSystemSymbol(
        icon: Icons.chevron_right_rounded,
        size: blizzardStyle ? 20 : null,
        color: blizzardStyle ? BlizzardPalette.secondary : null,
      ),
      onTap: () => context.go(namedLocation),
    );
  }
}
