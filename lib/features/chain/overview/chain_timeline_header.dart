import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/chain/model/chain_enum.dart';
import 'package:hiddify/features/chain/overview/chain_mode_button.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ChainTimelineHeader extends HookConsumerWidget {
  const ChainTimelineHeader(this.level, {super.key});

  final ChainTimelineLevel level;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    final showFinalIp =
        (level.isMainProfile() && !ref.watch(ConfigOptions.chainStatus).isExtraSecurity()) ||
        level.isExtraSecurity() && ref.watch(ConfigOptions.chainStatus).isExtraSecurity();
    final modeButton = level.isExtraSecurity()
        ? const ChainModeButton.extraSecurity()
        : level.isUnblocker()
        ? const ChainModeButton.unblocker()
        : null;
    final useStackedLayout = modeButton != null || MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final finalIp = AnimatedOpacity(
      duration: ChainConst.finalIpDuration,
      opacity: showFinalIp ? 1 : 0,
      child: Text(
        t.pages.settings.chain.finalIp,
        style: theme.textTheme.labelMedium?.copyWith(color: ChainConst.finalIpColor(theme)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
      ),
    );
    final title = Row(
      children: [
        Icon(level.icon(), size: 20, color: theme.colorScheme.onSurfaceVariant),
        const Gap(12),
        Expanded(
          child: Text(
            level.present(t).title,
            style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurface),
            maxLines: useStackedLayout ? 2 : 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    return Container(
      margin: const EdgeInsetsDirectional.only(end: 16),
      constraints: const BoxConstraints(minHeight: 32),
      padding: EdgeInsetsDirectional.fromSTEB(4, useStackedLayout ? 6 : 0, 0, useStackedLayout ? 6 : 0),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? theme.colorScheme.surfaceContainerHighest
            : Colors.black12,
        borderRadius: const BorderRadiusDirectional.only(topEnd: Radius.circular(100), bottomEnd: Radius.circular(100)),
      ),
      child: useStackedLayout
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                title,
                if (modeButton != null || showFinalIp) ...[
                  const Gap(6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (showFinalIp) Expanded(child: finalIp) else const Spacer(),
                      if (modeButton != null) ...[const Gap(12), Flexible(child: modeButton)],
                    ],
                  ),
                ],
              ],
            )
          : Row(
              children: [
                Expanded(child: title),
                const Gap(12),
                if (showFinalIp) finalIp,
                if (modeButton != null) ...[const Gap(12), modeButton],
              ],
            ),
    );
  }
}
