import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
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
      if (BlizzardPresentation.isActive(context))
        const Positioned.fill(
          child: IgnorePointer(child: ColoredBox(color: BlizzardPalette.scrim)),
        ),
      // Text outside panels needs a stable backdrop as well.
      Material(type: MaterialType.transparency, child: child),
    ],
  );
}
