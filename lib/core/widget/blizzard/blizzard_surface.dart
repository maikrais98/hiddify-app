import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_glass.dart';

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
    if (active) {
      return BlizzardGlass(active: true, radius: radius, contentSurface: true, child: content);
    }
    final materials = BlizzardMaterials(highContrast: MediaQuery.highContrastOf(context));
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
