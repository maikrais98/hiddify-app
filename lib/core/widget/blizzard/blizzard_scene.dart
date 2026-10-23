import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';

enum BlizzardParticlePreset { hero, staticHero, quiet, off, envelope, snowfall }

const _auroraAsset = 'assets/shaders/blizzard_aurora.frag';

/// One immutable program is shared by every scene. Each mounted scene owns the
/// mutable FragmentShader created from it and releases that shader on dispose.
final Map<String, ui.FragmentProgram> _auroraPrograms = {};
final Map<String, Future<ui.FragmentProgram>> _auroraProgramLoads = {};

Future<ui.FragmentProgram> _loadAuroraProgram(String asset) {
  final program = _auroraPrograms[asset];
  if (program != null) return SynchronousFuture(program);
  return _auroraProgramLoads.putIfAbsent(asset, () => _loadAndCacheAuroraProgram(asset));
}

Future<ui.FragmentProgram> _loadAndCacheAuroraProgram(String asset) async {
  try {
    final program = await ui.FragmentProgram.fromAsset(asset);
    _auroraPrograms[asset] = program;
    return program;
  } finally {
    _auroraProgramLoads.remove(asset);
  }
}

/// Decoration has no semantics, gestures, or application state. It retains the
/// existing scene clock and lifecycle ownership while Aurora replaces the old
/// particle, ribbon, vortex, and snowfall renderers.
class BlizzardScene extends StatefulWidget {
  const BlizzardScene({
    super.key,
    this.preset = BlizzardParticlePreset.quiet,
    @visibleForTesting this.auroraAsset = _auroraAsset,
  });

  final BlizzardParticlePreset preset;
  final String auroraAsset;

  @override
  State<BlizzardScene> createState() => _BlizzardSceneState();
}

class _BlizzardSceneState extends State<BlizzardScene> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _drift;
  ui.FragmentShader? _shader;
  bool _visible = false;
  bool _reduced = false;
  int _loadGeneration = 0;
  late AppLifecycleState _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    _drift = AnimationController(vsync: this, duration: BlizzardMetrics.waveDuration);
    WidgetsBinding.instance.addObserver(this);
    if (_usesAurora) _loadShader();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    _reduced = media.disableAnimations || media.accessibleNavigation || media.highContrast;
    _visible = TickerMode.of(context);
    _syncClock();
  }

  @override
  void didUpdateWidget(covariant BlizzardScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    final usedAurora = oldWidget.preset != BlizzardParticlePreset.off;
    if (oldWidget.auroraAsset != widget.auroraAsset || usedAurora != _usesAurora) {
      _releaseShader();
      if (_usesAurora) _loadShader();
    }
    _syncClock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _syncClock();
  }

  Future<void> _loadShader() async {
    final generation = ++_loadGeneration;
    final asset = widget.auroraAsset;
    try {
      final program = await _loadAuroraProgram(asset);
      if (!mounted || generation != _loadGeneration || asset != widget.auroraAsset) return;
      final shader = program.fragmentShader();
      setState(() {
        _shader = shader;
      });
      _syncClock();
    } catch (_) {
      _auroraPrograms.remove(asset);
      if (!mounted || generation != _loadGeneration || asset != widget.auroraAsset) return;
      _syncClock();
    }
  }

  bool get _canAnimate =>
      widget.preset == BlizzardParticlePreset.hero ||
      widget.preset == BlizzardParticlePreset.envelope ||
      widget.preset == BlizzardParticlePreset.snowfall;

  bool get _usesAurora => widget.preset != BlizzardParticlePreset.off;

  void _syncClock() {
    final animate = _shader != null && _canAnimate && !_reduced && _visible && _lifecycle == AppLifecycleState.resumed;
    if (animate && !_drift.isAnimating) {
      _drift.repeat();
    } else if (!animate && _drift.isAnimating) {
      _drift.stop();
    }
  }

  void _releaseShader() {
    _loadGeneration++;
    _shader?.dispose();
    _shader = null;
    _drift.stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _releaseShader();
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effective = _reduced && widget.preset == BlizzardParticlePreset.hero
        ? BlizzardParticlePreset.staticHero
        : widget.preset;
    final shader = _shader;
    final painter = shader == null || effective == BlizzardParticlePreset.off
        ? BlizzardScenePainter(preset: effective)
        : BlizzardAuroraPainter(
            phase: _drift,
            shader: shader,
            intensity: _intensityFor(effective),
            motion: !_reduced && _canAnimate,
          );
    return IgnorePointer(
      child: ExcludeSemantics(
        child: ClipRect(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: painter,
              isComplex: shader != null && effective != BlizzardParticlePreset.off,
              willChange: shader != null && !_reduced && _canAnimate,
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }

  static double _intensityFor(BlizzardParticlePreset preset) => switch (preset) {
    BlizzardParticlePreset.envelope => 0.72,
    BlizzardParticlePreset.quiet => 0.18,
    BlizzardParticlePreset.snowfall => 0.42,
    BlizzardParticlePreset.hero || BlizzardParticlePreset.staticHero => 0.5,
    BlizzardParticlePreset.off => 0,
  };
}

/// Owns no clock and no resource lifetime. The scene state supplies the shader
/// and disposes it; the shared controller is the only repaint source.
class BlizzardAuroraPainter extends CustomPainter {
  BlizzardAuroraPainter({required this.phase, required this.shader, required this.intensity, required this.motion})
    : super(repaint: phase);

  final Animation<double> phase;
  final ui.FragmentShader shader;
  final double intensity;
  final bool motion;
  late final Paint _paint = Paint()..shader = shader;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.isFinite) return;
    final time = math.sin(phase.value * math.pi * 2) * 6;
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time)
      ..setFloat(3, intensity)
      ..setFloat(4, motion ? 1 : 0)
      ..setFloat(5, motion ? 0 : time * 0.035);
    canvas.drawRect(Offset.zero & size, _paint);
  }

  @override
  bool shouldRepaint(covariant BlizzardAuroraPainter oldDelegate) =>
      oldDelegate.shader != shader ||
      oldDelegate.phase != phase ||
      oldDelegate.intensity != intensity ||
      oldDelegate.motion != motion;
}

/// Deterministic fallback used while the program loads and after load failure.
class BlizzardScenePainter extends CustomPainter {
  const BlizzardScenePainter({required this.preset});

  final BlizzardParticlePreset preset;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = BlizzardPalette.background);
  }

  @override
  bool shouldRepaint(covariant BlizzardScenePainter oldDelegate) => oldDelegate.preset != preset;
}
