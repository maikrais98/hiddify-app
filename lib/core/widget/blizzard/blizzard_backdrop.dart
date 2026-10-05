import 'package:flutter/material.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_presentation.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_scene.dart';

/// Keeps the content slot stable while decoration follows presentation scope.
class BlizzardBackdrop extends StatelessWidget {
  const BlizzardBackdrop({super.key, required this.child, this.preset = BlizzardParticlePreset.quiet});

  final Widget child;
  final BlizzardParticlePreset preset;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Positioned.fill(
        child: BlizzardPresentation.isActive(context) ? BlizzardScene(preset: preset) : const SizedBox.shrink(),
      ),
      // Tile ink must paint above the scene, on an opaque content surface.
      Material(type: MaterialType.transparency, child: child),
    ],
  );
}
