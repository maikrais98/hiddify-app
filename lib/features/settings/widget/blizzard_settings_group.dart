import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_surface.dart';

class BlizzardSettingsGroup extends StatelessWidget {
  const BlizzardSettingsGroup({super.key, required this.groupKey, required this.title, required this.children});

  final Key groupKey;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = theme.extension<BlizzardEligibility>()?.applied ?? false;
    final rows = _settingsRows(children, roomy: active);
    final panelTheme = ListTileTheme.merge(
      shape: const RoundedRectangleBorder(),
      tileColor: active ? Colors.transparent : null,
      selectedTileColor: active ? Colors.transparent : null,
      contentPadding: active ? const EdgeInsetsDirectional.symmetric(horizontal: BlizzardSpacing.s16) : null,
      minLeadingWidth: active ? BlizzardSpacing.s20 : null,
      horizontalTitleGap: active ? BlizzardSpacing.s12 : null,
      minVerticalPadding: active ? BlizzardSpacing.s8 : 0,
      minTileHeight: active ? BlizzardMetrics.rowMinHeight : 48,
      child: rows,
    );
    final panel = active
        ? BlizzardSurface(
            key: groupKey,
            child: Material(type: MaterialType.transparency, child: panelTheme),
          )
        : Material(
            key: groupKey,
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: panelTheme,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const Gap(BlizzardSpacing.s8),
        panel,
      ],
    );
  }
}

/// A single material owner around an existing settings row collection.
/// In legacy themes it returns the original rows without adding a surface.
class BlizzardSettingsPanel extends StatelessWidget {
  const BlizzardSettingsPanel({
    super.key,
    required this.children,
    this.minTileHeight,
    this.radius = BlizzardRadii.card,
    this.legacySurface = false,
  });

  final List<Widget> children;
  final double? minTileHeight;
  final double radius;
  final bool legacySurface;

  @override
  Widget build(BuildContext context) {
    final content = Column(mainAxisSize: MainAxisSize.min, children: children);
    final active = Theme.of(context).extension<BlizzardEligibility>()?.applied ?? false;
    if (!active) {
      if (!legacySurface) return content;
      return Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: ListTileTheme.merge(
          shape: const RoundedRectangleBorder(),
          minVerticalPadding: minTileHeight == null ? null : 0,
          minTileHeight: minTileHeight,
          child: content,
        ),
      );
    }

    return BlizzardSurface(
      radius: radius,
      child: Material(
        type: MaterialType.transparency,
        child: ListTileTheme.merge(
          shape: const RoundedRectangleBorder(),
          tileColor: Colors.transparent,
          selectedTileColor: Colors.transparent,
          contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: BlizzardSpacing.s16),
          minLeadingWidth: BlizzardSpacing.s20,
          horizontalTitleGap: BlizzardSpacing.s12,
          minVerticalPadding: BlizzardSpacing.s8,
          minTileHeight: minTileHeight == null || minTileHeight! < BlizzardMetrics.rowMinHeight
              ? BlizzardMetrics.rowMinHeight
              : minTileHeight,
          child: _settingsRows(children, roomy: true),
        ),
      ),
    );
  }
}

/// Shared inset separators and flexible rows for grouped settings content.
Widget _settingsRows(List<Widget> children, {required bool roomy}) => Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    for (var index = 0; index < children.length; index++)
      Stack(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: roomy ? BlizzardMetrics.rowMinHeight : 48),
            child: children[index],
          ),
          if (index != children.length - 1)
            PositionedDirectional(
              start: roomy ? BlizzardSpacing.s16 : 46,
              end: roomy ? BlizzardSpacing.s16 : 0,
              bottom: 0,
              child: Divider(
                height: BlizzardMetrics.hairline,
                thickness: BlizzardMetrics.hairline,
                color: roomy ? BlizzardPalette.separator : BlizzardPalette.secondary.withValues(alpha: 0.07),
              ),
            ),
        ],
      ),
  ],
);
