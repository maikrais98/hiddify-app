import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';

enum BlizzardParticlePreset { hero, quiet, off }

/// Static decoration has no semantics, gestures, clocks, or application state.
class BlizzardScene extends StatelessWidget {
  const BlizzardScene({super.key, this.preset = BlizzardParticlePreset.quiet});
  final BlizzardParticlePreset preset;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final effective = media.disableAnimations || media.accessibleNavigation || media.highContrast
        ? BlizzardParticlePreset.off
        : preset;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: BlizzardScenePainter(preset: effective),
            isComplex: effective != BlizzardParticlePreset.off,
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class BlizzardScenePainter extends CustomPainter {
  const BlizzardScenePainter({required this.preset});
  final BlizzardParticlePreset preset;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = BlizzardPalette.background);
    if (preset == BlizzardParticlePreset.off) return;
    final hero = preset == BlizzardParticlePreset.hero;
    final paint = Paint();
    // A fine parametric cloth folds around the control. Its lower edge stays
    // above the status/latency area; the footer receives no dense decoration.
    if (hero) {
      const columns = 144;
      const rows = 72;
      for (var row = 0; row < rows; row++) {
        final v = row / (rows - 1);
        for (var column = 0; column < columns; column++) {
          final u = column / (columns - 1);
          final fold = math.sin(u * math.pi * 2 - v * 1.8);
          final x = 0.1 + 0.8 * u + math.sin(v * math.pi * 2) * 0.035;
          final y = 0.36 + fold * 0.075 + (v - 0.5) * 0.19 + math.sin(u * math.pi) * math.sin(v * math.pi * 2) * 0.04;
          final edge = math.sin(u * math.pi) * math.sin(v * math.pi);
          final depth = 0.5 + 0.5 * math.cos(u * math.pi * 2 - v * 2.8);
          paint.color = BlizzardPalette.accent.withValues(alpha: (0.06 + depth * 0.2) * edge);
          canvas.drawCircle(Offset(x * size.width, y * size.height), 0.28 + depth * 0.15, paint);
        }
      }
    }
    // Sparse, quiet ambient points retain depth without crossing readable text.
    final count = hero ? 130 : 80;
    for (var i = 0; i < count; i++) {
      final x = ((i * 293) % 769) / 769;
      final y = ((i * 137) % 547) / 547;
      if (y < 0.14 || y > 0.78 || (y > 0.48 && x > 0.2 && x < 0.8)) continue;
      final near = i % 11 == 0;
      paint.color = (near ? BlizzardPalette.particleNear : BlizzardPalette.particleFar).withValues(
        alpha: hero ? (near ? 0.24 : 0.12) : (near ? 0.1 : 0.05),
      );
      canvas.drawCircle(Offset(x * size.width, y * size.height), near ? 0.85 : 0.45, paint);
    }
  }

  @override
  bool shouldRepaint(covariant BlizzardScenePainter oldDelegate) => oldDelegate.preset != preset;
}
