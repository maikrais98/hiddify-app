import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_glass.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_presentation.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_system_symbol.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_tooltip.dart';
import 'package:hiddify/features/chain/overview/chain_quick_toggles.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/widget/blizzard_settings_group.dart';
import 'package:hiddify/features/settings/widget/lan_sharing_tile.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class QuickSettingsModal extends HookConsumerWidget {
  const QuickSettingsModal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = BlizzardPresentation.themeOf(context);
    final blizzard =
        BlizzardPresentation.isActive(context) || (theme.extension<BlizzardEligibility>()?.applied ?? false);

    return BlizzardSheetScope(
      child: BlizzardPresentation(
        child: ColoredBox(
          color: Colors.transparent,
          child: SafeArea(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: blizzard
                      ? (BlizzardMetrics.quickSettingsMinHeight - MediaQuery.paddingOf(context).bottom).clamp(
                          0,
                          double.infinity,
                        )
                      : 0,
                ),
                child: Column(
                  children: [
                    if (blizzard)
                      Padding(
                        padding: const EdgeInsets.all(BlizzardSpacing.s16),
                        child: Row(
                          children: [
                            Expanded(child: Text(t.pages.home.quickSettings, style: theme.textTheme.titleLarge)),
                            BlizzardGlass(
                              active: true,
                              radius: BlizzardRadii.pill,
                              child: IconButton(
                                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const BlizzardSystemSymbol(icon: Icons.close_rounded),
                              ).withBlizzardTooltip(),
                            ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: blizzard ? BlizzardMetrics.screenMargin : 16,
                      ).copyWith(top: blizzard ? BlizzardSpacing.s16 : 16),
                      child: ConstrainedBox(
                        key: blizzard ? const ValueKey('quick-settings-service-mode-glass') : null,
                        constraints: BoxConstraints(minHeight: blizzard ? BlizzardMetrics.toolbarButton : 0),
                        child: Builder(
                          builder: (context) {
                            final selector = SegmentedButton(
                              showSelectedIcon: false,
                              // A non-null zero inset opts into equal-width expanded segments.
                              expandedInsets: blizzard ? EdgeInsets.zero : null,
                              style: blizzard
                                  ? ButtonStyle(
                                      backgroundColor: WidgetStateProperty.resolveWith(
                                        (states) => states.contains(WidgetState.selected)
                                            ? BlizzardPalette.selected
                                            : Colors.transparent,
                                      ),
                                      foregroundColor: WidgetStateProperty.resolveWith(
                                        (states) => states.contains(WidgetState.selected)
                                            ? BlizzardPalette.accent
                                            : BlizzardPalette.secondary,
                                      ),
                                      textStyle: WidgetStateProperty.resolveWith(
                                        (states) => states.contains(WidgetState.selected)
                                            ? theme.textTheme.titleMedium
                                            : theme.textTheme.bodyLarge,
                                      ),
                                      shape: WidgetStatePropertyAll(
                                        RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(BlizzardRadii.control),
                                        ),
                                      ),
                                      side: const WidgetStatePropertyAll(BorderSide.none),
                                    )
                                  : null,
                              segments: ServiceMode.choices
                                  .map(
                                    (e) => ButtonSegment(
                                      value: e,
                                      label: Padding(
                                        padding: EdgeInsets.symmetric(vertical: blizzard ? 0 : 8),
                                        child: Text(e.presentShort(t), textAlign: TextAlign.center),
                                      ),
                                      // tooltip: e.isExperimental ? t.settings.experimental : null,
                                    ),
                                  )
                                  .toList(),
                              selected: {ref.watch(ConfigOptions.serviceMode)},
                              onSelectionChanged: (newSet) =>
                                  ref.read(ConfigOptions.serviceMode.notifier).update(newSet.first),
                            );
                            return blizzard
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(BlizzardRadii.control),
                                    child: ColoredBox(
                                      color: BlizzardPalette.elevated,
                                      child: Material(type: MaterialType.transparency, child: selector),
                                    ),
                                  )
                                : selector;
                          },
                        ),
                      ),
                    ),
                    Gap(blizzard ? BlizzardSpacing.s16 : 12),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: blizzard ? BlizzardMetrics.screenMargin : 0),
                      child: const BlizzardSettingsPanel(
                        key: ValueKey('quick-settings-chain-glass'),
                        children: [LanSharingPreferenceWidget(showLeading: false), ChainQuickToggles()],
                      ),
                    ),
                    const Gap(16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
