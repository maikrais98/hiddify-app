import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';

enum BlizzardParticlePreset { hero, staticHero, quiet, off, envelope, snowfall }

const blizzardAuroraReferenceAsset = 'assets/images/luma_aurora_reference.png';
const blizzardAuroraGlowAsset = 'assets/images/luma_aurora_glow.png';
const blizzardAuroraStarsAsset = 'assets/images/luma_aurora_stars.svg';

/// Cached layers from the approved SVG: only the glow's composited transform moves.
class BlizzardScene extends StatefulWidget {
  const BlizzardScene({
    super.key,
    this.preset = BlizzardParticlePreset.quiet,
    @visibleForTesting this.auroraAsset = blizzardAuroraGlowAsset,
  });

  final BlizzardParticlePreset preset;
  final String auroraAsset;

  @override
  State<BlizzardScene> createState() => _BlizzardSceneState();
}

class _BlizzardSceneState extends State<BlizzardScene> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _drift;
  late AppLifecycleState _lifecycle;
  bool _visible = false;
  bool _reduced = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    _drift = AnimationController(vsync: this, duration: const Duration(seconds: 28));
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    _reduced = media.disableAnimations || media.accessibleNavigation;
    _visible = TickerMode.of(context) && (ModalRoute.isCurrentOf(context) ?? true);
    _syncClock();
  }

  @override
  void didUpdateWidget(covariant BlizzardScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.auroraAsset != widget.auroraAsset) _ready = false;
    _syncClock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _syncClock();
  }

  void _syncClock() {
    final animate =
        _ready &&
        _visible &&
        !_reduced &&
        widget.preset != BlizzardParticlePreset.off &&
        widget.preset != BlizzardParticlePreset.staticHero &&
        _lifecycle == AppLifecycleState.resumed;
    if (animate && !_drift.isAnimating) {
      _drift.repeat();
    } else if (!animate && _drift.isAnimating) {
      _drift.stop();
    }
  }

  Widget _image(String asset, {bool glow = false}) => Image.asset(
    asset,
    fit: BoxFit.cover,
    alignment: Alignment.topCenter,
    excludeFromSemantics: true,
    frameBuilder: glow
        ? (context, child, frame, synchronous) {
            if (frame != null && !_ready) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || asset != widget.auroraAsset) return;
                _ready = true;
                _syncClock();
              });
            }
            return child;
          }
        : null,
    errorBuilder: (context, error, stackTrace) => const SizedBox.expand(),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: ClipRect(
        child: ColoredBox(
          color: BlizzardPalette.background,
          child: widget.preset == BlizzardParticlePreset.off
              ? const SizedBox.expand()
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedBuilder(
                      animation: _drift,
                      child: RepaintBoundary(
                        child: Transform.scale(
                          scaleY: 1.4,
                          alignment: Alignment.topCenter,
                          child: _image(widget.auroraAsset, glow: true),
                        ),
                      ),
                      builder: (context, child) {
                        final angle = _drift.value * math.pi * 2;
                        return Transform(
                          key: const ValueKey('blizzard_aurora_glow_transform'),
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..translateByDouble(4 * math.sin(angle), 2 * math.sin(angle), 0, 1)
                            ..scaleByDouble(
                              1 + .008 * (1 - math.cos(angle)),
                              1 + .008 * (1 - math.cos(angle)),
                              1,
                              1,
                            ),
                          child: child,
                        );
                      },
                    ),
                    RepaintBoundary(
                      key: const ValueKey('blizzard_static_stars'),
                      child: SvgPicture.asset(
                        blizzardAuroraStarsAsset,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
}
