import 'package:flutter/material.dart';
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
    final materials = BlizzardMaterials(highContrast: MediaQuery.highContrastOf(context));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: materials.content,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: materials.edge),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
