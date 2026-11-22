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
        Positioned.fill(
          child: IgnorePointer(
            child: MediaQuery.highContrastOf(context)
                ? const ColoredBox(color: BlizzardPalette.scrim)
                : const _BlizzardDim(),
          ),
        ),
      // Text outside panels needs a stable backdrop as well.
      Material(type: MaterialType.transparency, child: child),
    ],
  );
}

/// Static dimming gradient: bright title zone, calm reading area below.
class _BlizzardDim extends StatelessWidget {
  const _BlizzardDim();

  static const _steps = 16;

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.paddingOf(context).top;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        if (!height.isFinite || height <= 0) return const SizedBox.shrink();
        final start = safeTop + BlizzardBackdropMetrics.dimStart;
        final end = safeTop + BlizzardBackdropMetrics.dimEnd;
        final ys = [
          0.0,
          for (var i = 0; i <= _steps; i++) start + (end - start) * i / _steps,
          height,
        ].map((y) => y.clamp(0.0, height)).toList();
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                for (final y in ys)
                  BlizzardPalette.background.withValues(alpha: BlizzardBackdropMetrics.dimAt(y, safeTop)),
              ],
              stops: [for (final y in ys) y / height],
            ),
          ),
        );
      },
    );
  }
}
