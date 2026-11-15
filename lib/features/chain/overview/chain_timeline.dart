import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_presentation.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_system_symbol.dart';
import 'package:hiddify/features/chain/model/chain_enum.dart';
import 'package:hiddify/features/chain/overview/chain_mode_menu.dart';
import 'package:hiddify/features/chain/overview/chain_timeline_arrow.dart';
import 'package:hiddify/features/chain/overview/chain_timeline_header.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ChainTimeline extends HookConsumerWidget {
  const ChainTimeline({super.key, required this.level, this.childeren = const []});
  final ChainTimelineLevel level;
  final List<Widget> childeren;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    if (BlizzardPresentation.isActive(context)) {
      final status = ref.watch(ConfigOptions.chainStatus);
      final description = level.present(t);
      Widget row({VoidCallback? onTap, required String subtitle}) => ListTile(
        title: Text(description.title),
        subtitle: Text(subtitle),
        leading: level.isApp() ? null : const BlizzardSystemSymbol(icon: Icons.settings_outlined),
        trailing: onTap == null
            ? null
            : const BlizzardSystemSymbol(icon: Icons.chevron_right_rounded, color: BlizzardPalette.secondary),
        onTap: onTap,
      );
      if (level.isApp() || level.isFiltering()) {
        return row(subtitle: description.message);
      }
      if (level.isMainProfile()) {
        final name = ref.watch(activeProfileProvider).value?.name ?? t.common.notSet;
        return row(subtitle: status.isExtraSecurity() ? name : '$name · ${t.pages.settings.chain.finalIp}');
      }
      final type = level.isExtraSecurity() ? ChainType.extraSecurity : ChainType.unblocker;
      final enabled = type.isEnable(status);
      final mode = level.isExtraSecurity()
          ? ref.watch(ConfigOptions.extraSecurityMode)
          : ref.watch(ConfigOptions.unblockerMode);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChainModeMenu(
            (context, toggleVisibility, _) => row(
              onTap: toggleVisibility,
              subtitle: enabled
                  ? '${mode.present(t)}${level.isExtraSecurity() ? ' · ${t.pages.settings.chain.finalIp}' : ''}'
                  : t.pages.settings.chain.quick.off,
            ),
            type: type,
            showConfiguration: false,
          ),
          if (enabled) ...childeren,
        ],
      );
    }
    return Column(
      children: [
        ChainTimelineHeader(level),
        Stack(
          children: [
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              child: ChainTimelineArrow(showArrow: !level.isFiltering()),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 20.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!level.isMainProfile())
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 10, 16, childeren.isEmpty ? 10 : 4),
                      child: Text(
                        level.present(t).message,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ...childeren,
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
