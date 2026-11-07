import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_glass.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_presentation.dart';
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

    return BlizzardPresentation(
      child: ColoredBox(
        color: Colors.transparent,
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                if (blizzard)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(t.pages.home.quickSettings, style: theme.textTheme.titleLarge),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(top: blizzard ? 0 : 16),
                  child: SizedBox(
                    key: blizzard ? const ValueKey('quick-settings-service-mode-glass') : null,
                    height: blizzard ? 44 : null,
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
                                        ? BlizzardPalette.selected.withValues(alpha: 0.56)
                                        : Colors.transparent,
                                  ),
                                  shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
                                  side: WidgetStatePropertyAll(BorderSide(color: theme.colorScheme.outline)),
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
                            ? BlizzardGlass(
                                active: true,
                                radius: 0,
                                child: Material(type: MaterialType.transparency, child: selector),
                              )
                            : selector;
                      },
                    ),
                  ),
                ),
                Gap(blizzard ? 18 : 12),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: blizzard ? 16 : 0),
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
    );
  }
}
