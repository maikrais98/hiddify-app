import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';

/// Pure surface styling around existing content and existing interactions.
class BlizzardSurface extends StatelessWidget {
  const BlizzardSurface({
    super.key,
    required this.child,
    this.radius = BlizzardRadii.card,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final active = Theme.of(context).extension<BlizzardEligibility>()?.applied ?? false;
    final content = Padding(padding: padding, child: child);
    final materials = BlizzardMaterials(highContrast: MediaQuery.highContrastOf(context));
    if (active) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: ColoredBox(color: materials.content, child: content),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: materials.content,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: materials.edge),
      ),
      child: content,
    );
  }
}
