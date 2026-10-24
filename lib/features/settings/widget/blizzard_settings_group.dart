import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';

class BlizzardSettingsGroup extends StatelessWidget {
  const BlizzardSettingsGroup({super.key, required this.groupKey, required this.title, required this.children});

  final Key groupKey;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 13,
            height: 1.3,
          ),
        ),
        const Gap(8),
        Material(
          key: groupKey,
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: ListTileTheme.merge(
            shape: const RoundedRectangleBorder(),
            minVerticalPadding: 0,
            minTileHeight: 48,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  Stack(
                    children: [
                      ConstrainedBox(constraints: const BoxConstraints(minHeight: 48), child: children[index]),
                      if (index != children.length - 1)
                        Positioned(
                          left: 46,
                          right: 0,
                          bottom: 0,
                          child: Divider(
                            height: 1,
                            thickness: 1,
                            color: BlizzardPalette.secondary.withValues(alpha: 0.07),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
