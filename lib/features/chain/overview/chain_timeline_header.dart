import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/chain/model/chain_enum.dart';
import 'package:hiddify/features/chain/overview/chain_mode_button.dart';
import 'package:hiddify/features/chain/overview/chain_mode_icon.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ChainTimelineHeader extends HookConsumerWidget {
  const ChainTimelineHeader(this.level, {super.key});

  final ChainTimelineLevel level;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    final chain = ref.watch(ConfigOptions.chainStatus);

    final compact = MediaQuery.sizeOf(context).width < 400 || MediaQuery.textScalerOf(context).scale(16) > 20;
    final marker = SizedBox.square(
      dimension: 22,
      child: switch (level) {
        ChainTimelineLevel.extraSecurity => ChainTypeIcon(
          type: ChainType.extraSecurity,
          mode: ref.watch(ConfigOptions.extraSecurityMode),
          animate: chain.isExtraSecurity(),
        ),
        ChainTimelineLevel.unblocker => ChainTypeIcon(
          type: ChainType.unblocker,
          mode: ref.watch(ConfigOptions.unblockerMode),
          animate: chain.isUnblocker(),
        ),
        _ => Icon(level.icon(), size: 20, color: theme.colorScheme.onSurfaceVariant),
      },
    );
    final title = Text(
      level.present(t).title,
      style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurface),
      maxLines: compact ? 2 : 1,
      overflow: TextOverflow.ellipsis,
    );
    final finalIp = AnimatedOpacity(
      duration: ChainConst.finalIpDuration,
      opacity: (level.isMainProfile() && !chain.isExtraSecurity() || level.isExtraSecurity() && chain.isExtraSecurity())
          ? 1
          : 0,
      child: Text(
        t.pages.settings.chain.finalIp,
        style: theme.textTheme.labelMedium?.copyWith(color: ChainConst.finalIpColor(theme)),
        maxLines: 1,
      ),
    );
    return Container(
      margin: const EdgeInsetsDirectional.only(end: 16),
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? theme.colorScheme.surfaceContainerHighest
            : Colors.black12,
        borderRadius: const BorderRadiusDirectional.only(topEnd: Radius.circular(100), bottomEnd: Radius.circular(100)),
      ),
      child: compact
          ? Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(3, 6, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      marker,
                      const Gap(11),
                      Expanded(child: title),
                    ],
                  ),
                  if (level.isMainProfile() || level.isExtraSecurity() || level.isUnblocker())
                    Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        finalIp,
                        if (level.isExtraSecurity()) const ChainModeButton.extraSecurity(),
                        if (level.isUnblocker()) const ChainModeButton.unblocker(),
                      ],
                    ),
                ],
              ),
            )
          : SizedBox(
              height: 44,
              child: Row(
                children: [
                  const Gap(3),
                  marker,
                  const Gap(11),
                  Expanded(child: title),
                  const Gap(12),
                  finalIp,
                  const Gap(12),
                  if (level.isExtraSecurity()) const ChainModeButton.extraSecurity(),
                  if (level.isUnblocker()) const ChainModeButton.unblocker(),
                ],
              ),
            ),
    );
  }
}
