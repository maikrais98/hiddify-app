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
      contentPadding: active ? const EdgeInsetsDirectional.symmetric(horizontal: 16) : null,
      minLeadingWidth: active ? 24 : null,
      horizontalTitleGap: active ? 12 : null,
      minVerticalPadding: active ? 8 : 0,
      minTileHeight: active ? 52 : 48,
      child: rows,
    );
    final panel = active
        ? BlizzardSurface(
            key: groupKey,
            radius: 18,
            padding: const EdgeInsets.all(4),
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
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: active ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
            fontSize: 13,
            height: 1.3,
          ),
        ),
        const Gap(8),
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
    this.radius = 18,
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
      padding: const EdgeInsets.all(4),
      child: Material(
        type: MaterialType.transparency,
        child: ListTileTheme.merge(
          shape: const RoundedRectangleBorder(),
          tileColor: Colors.transparent,
          selectedTileColor: Colors.transparent,
          contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
          minLeadingWidth: 24,
          horizontalTitleGap: 12,
          minVerticalPadding: 8,
          minTileHeight: minTileHeight == null || minTileHeight! < 52 ? 52 : minTileHeight,
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
          ConstrainedBox(constraints: BoxConstraints(minHeight: roomy ? 52 : 48), child: children[index]),
          if (index != children.length - 1)
            PositionedDirectional(
              start: roomy ? 52 : 46,
              end: roomy ? 16 : 0,
              bottom: 0,
              child: Divider(height: 1, thickness: 1, color: BlizzardPalette.secondary.withValues(alpha: roomy ? 0.12 : 0.07)),
            ),
        ],
      ),
  ],
);
