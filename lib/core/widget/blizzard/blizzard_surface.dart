import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_popup.dart';

enum BlizzardSurfaceKind {
  /// List/settings cards: neutral, translucent, over the dimmed scene.
  plate,

  /// Modal sheets: neutral and almost opaque, they float over any screen.
  sheet,

  /// Cards over the undimmed scene (Home): denser than list plates.
  onScene,
}

/// Pure surface styling around existing content and existing interactions.
class BlizzardSurface extends StatelessWidget {
  const BlizzardSurface({
    super.key,
    required this.child,
    this.radius = BlizzardRadii.card,
    this.padding = EdgeInsets.zero,
    this.kind = BlizzardSurfaceKind.plate,
  });
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final BlizzardSurfaceKind kind;

  @override
  Widget build(BuildContext context) {
    final active = Theme.of(context).extension<BlizzardEligibility>()?.applied ?? false;
    final content = Padding(padding: padding, child: child);
    final materials = BlizzardMaterials(highContrast: MediaQuery.highContrastOf(context));
    if (active && kind == BlizzardSurfaceKind.sheet && !BlizzardMenuStyleSwitch.isCurrent) {
      // Candidate sheet looks (variant A is today's material plus the same border).
      return BlizzardPopupMaterial(radius: radius, role: BlizzardPopupRole.sheet, child: content);
    }
    if (active) {
      final onGlass =
          kind == BlizzardSurfaceKind.plate && BlizzardMenuStyleSwitch.isGlass && BlizzardGlassPopupScope.of(context);
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: switch (kind) {
              BlizzardSurfaceKind.sheet => materials.sheet,
              BlizzardSurfaceKind.onScene => materials.plateOnScene,
              BlizzardSurfaceKind.plate =>
                onGlass && !materials.highContrast ? BlizzardPopupGlass.plateTint : materials.plate,
            },
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: materials.highContrast ? materials.edge : BlizzardPalette.separator),
          ),
          child: content,
        ),
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
