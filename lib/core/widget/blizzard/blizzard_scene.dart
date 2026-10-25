import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';

enum BlizzardParticlePreset { hero, staticHero, quiet, off, envelope, snowfall }

const _auroraAsset = 'assets/shaders/blizzard_aurora.frag';
const _softAuroraAsset = 'assets/shaders/blizzard_aurora_soft.frag';
const _softAuroraResolutionScale = 0.75;

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
    _reduced = media.disableAnimations || media.accessibleNavigation;
    _visible = TickerMode.of(context);
    _syncClock();
  }

  @override
  void didUpdateWidget(covariant BlizzardScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    final usedAurora = oldWidget.preset != BlizzardParticlePreset.off;
    final usedSoftAurora = oldWidget.preset == BlizzardParticlePreset.snowfall && oldWidget.auroraAsset == _auroraAsset;
    if (oldWidget.auroraAsset != widget.auroraAsset || usedAurora != _usesAurora || usedSoftAurora != _usesSoftAurora) {
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
    final useSoftAurora = _usesSoftAurora;
    final shaderAsset = useSoftAurora ? _softAuroraAsset : asset;
    try {
      final program = await _loadAuroraProgram(shaderAsset);
      if (!mounted ||
          generation != _loadGeneration ||
          asset != widget.auroraAsset ||
          useSoftAurora != _usesSoftAurora) {
        return;
      }
      final shader = program.fragmentShader();
      setState(() {
        _shader = shader;
      });
      _syncClock();
    } catch (_) {
      _auroraPrograms.remove(shaderAsset);
      if (!mounted ||
          generation != _loadGeneration ||
          asset != widget.auroraAsset ||
          useSoftAurora != _usesSoftAurora) {
        return;
      }
      _syncClock();
    }
  }

  bool get _canAnimate =>
      widget.preset == BlizzardParticlePreset.hero ||
      widget.preset == BlizzardParticlePreset.envelope ||
      widget.preset == BlizzardParticlePreset.snowfall;

  bool get _usesAurora => widget.preset != BlizzardParticlePreset.off;

  bool get _usesSoftAurora => widget.preset == BlizzardParticlePreset.snowfall && widget.auroraAsset == _auroraAsset;

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
    final shaderReady = shader != null;
    final painter = !shaderReady || effective == BlizzardParticlePreset.off
        ? BlizzardScenePainter(preset: effective)
        : _usesSoftAurora
        ? BlizzardSoftAuroraPainter(
            phase: _drift,
            shader: shader,
            intensity: _intensityFor(effective),
            motion: !_reduced && _canAnimate,
            resolutionScale: _softAuroraResolutionScale / math.max(1.0, MediaQuery.devicePixelRatioOf(context)),
          )
        : BlizzardAuroraPainter(
            phase: _drift,
            shader: shader,
            intensity: _intensityFor(effective),
            motion: !_reduced && _canAnimate,
          );
    return IgnorePointer(
      child: ExcludeSemantics(
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                child: CustomPaint(
                  painter: painter,
                  isComplex: shaderReady && effective != BlizzardParticlePreset.off,
                  willChange: shaderReady && !_reduced && _canAnimate,
                  size: Size.infinite,
                ),
              ),
              if (_usesSoftAurora)
                const RepaintBoundary(
                  key: ValueKey('blizzard_static_stars'),
                  child: CustomPaint(painter: BlizzardStaticStarsPainter(), size: Size.infinite),
                ),
            ],
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

  void _setUniforms(ui.FragmentShader target, Size size) {
    final time = math.sin(phase.value * math.pi * 2) * 24;
    target
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time)
      ..setFloat(3, intensity)
      ..setFloat(4, motion ? 1 : 0)
      ..setFloat(5, motion ? 0 : time * 0.035);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.isFinite) return;
    _setUniforms(shader, size);
    canvas.drawRect(Offset.zero & size, _paint);
  }

  @override
  bool shouldRepaint(covariant BlizzardAuroraPainter oldDelegate) =>
      oldDelegate.shader != shader ||
      oldDelegate.phase != phase ||
      oldDelegate.intensity != intensity ||
      oldDelegate.motion != motion;
}

class BlizzardSoftAuroraPainter extends BlizzardAuroraPainter {
  BlizzardSoftAuroraPainter({
    required super.phase,
    required super.shader,
    required super.intensity,
    required super.motion,
    this.resolutionScale = _softAuroraResolutionScale,
  }) : assert(resolutionScale > 0 && resolutionScale < 1);

  final double resolutionScale;
  late final Float64List _upscaleMatrix = Float64List.fromList([
    1 / resolutionScale,
    0,
    0,
    0,
    0,
    1 / resolutionScale,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
  ]);
  late final Paint _glowLayerPaint = Paint()
    ..imageFilter = ui.ImageFilter.matrix(_upscaleMatrix, filterQuality: FilterQuality.low);
  late final Paint _glowPaint = Paint()..shader = shader;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.isFinite) return;
    final glowSize = Size(size.width * resolutionScale, size.height * resolutionScale);
    _setUniforms(shader, glowSize);
    canvas.saveLayer(Offset.zero & glowSize, _glowLayerPaint);
    canvas.drawRect(Offset.zero & glowSize, _glowPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BlizzardAuroraPainter oldDelegate) =>
      oldDelegate is! BlizzardSoftAuroraPainter ||
      super.shouldRepaint(oldDelegate) ||
      oldDelegate.resolutionScale != resolutionScale;
}

/// Immutable snowfall stars. The separate repaint boundary records this once;
/// Aurora clock ticks only repaint the glow layer beneath it.
class BlizzardStaticStarsPainter extends CustomPainter {
  const BlizzardStaticStarsPainter();

  static const _stars = <(Offset, double)>[
    (Offset(.621059, .116680), .190302),
    (Offset(.069074, .437844), .139633),
    (Offset(.435617, .995295), .261961),
    (Offset(.365133, .580627), .262721),
    (Offset(.006135, .787869), .118359),
    (Offset(.614723, .498155), .251305),
    (Offset(.502135, .745822), .133427),
    (Offset(.941131, .189813), .106104),
    (Offset(.632687, .265439), .181477),
    (Offset(.092330, .738126), .065707),
    (Offset(.052051, .314862), .229629),
    (Offset(.636097, .328187), .186984),
    (Offset(.094697, .620773), .100222),
    (Offset(.468843, .952884), .277392),
    (Offset(.366243, .388480), .254080),
    (Offset(.734561, .572849), .117213),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.isFinite) return;
    final paint = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, .7);
    for (final (position, opacity) in _stars) {
      paint.color = const Color(0xFFB3D4D9).withValues(alpha: opacity);
      canvas.drawCircle(Offset(position.dx * size.width, position.dy * size.height), .7, paint);
    }
  }

  @override
  bool shouldRepaint(covariant BlizzardStaticStarsPainter oldDelegate) => false;
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
