import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_scene.dart';

/// Registers the full scene viewport above the navigator and its popup routes.
class BlizzardSceneViewport extends StatefulWidget {
  const BlizzardSceneViewport({super.key, required this.child});

  final Widget child;

  @override
  State<BlizzardSceneViewport> createState() => _BlizzardSceneViewportState();
}

class _BlizzardSceneViewportState extends State<BlizzardSceneViewport> {
  final _link = LayerLink();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _SceneViewport(
      size: constraints.biggest,
      link: _link,
      child: CompositedTransformTarget(link: _link, child: widget.child),
    ),
  );
}

class _SceneViewport extends InheritedWidget {
  const _SceneViewport({required this.size, required this.link, required super.child});

  final Size size;
  final LayerLink link;

  @override
  bool updateShouldNotify(_SceneViewport oldWidget) => size != oldWidget.size || link != oldWidget.link;
}

/// An opaque popup backed by a fixed sample of Aurora. The follower keeps the
/// sample registered to the viewport while a sheet slides or a menu moves.
class BlizzardSceneGlass extends StatelessWidget {
  const BlizzardSceneGlass({
    super.key,
    required this.radius,
    required this.tint,
    this.drawSolidBorder = true,
    required this.child,
  });

  final double radius;
  final Color tint;
  final bool drawSolidBorder;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.highContrastOf(context);
    final glass = !highContrast && BlizzardMenuStyleScope.of(context) == BlizzardMenuStyle.glass;
    final viewport = glass ? context.dependOnInheritedWidgetOfExactType<_SceneViewport>() : null;
    final radius = BorderRadius.circular(this.radius);

    return ClipRRect(
      borderRadius: radius,
      clipBehavior: glass || drawSolidBorder ? Clip.antiAlias : Clip.none,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: highContrast ? BlizzardPalette.background : BlizzardPalette.sheet,
          borderRadius: radius,
          border: !glass && drawSolidBorder
              ? Border.all(color: highContrast ? BlizzardPalette.secondary : BlizzardPalette.separator)
              : null,
        ),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            if (glass)
              Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (viewport != null)
                          CompositedTransformFollower(
                            link: viewport.link,
                            showWhenUnlinked: false,
                            child: OverflowBox(
                              alignment: Alignment.topLeft,
                              minWidth: viewport.size.width,
                              maxWidth: viewport.size.width,
                              minHeight: viewport.size.height,
                              maxHeight: viewport.size.height,
                              child: const RepaintBoundary(
                                child: Image(
                                  image: AssetImage('assets/images/luma_aurora_popup.png'),
                                  fit: blizzardAuroraFit,
                                  alignment: blizzardAuroraAlignment,
                                  excludeFromSemantics: true,
                                ),
                              ),
                            ),
                          ),
                        ColoredBox(color: tint),
                        const Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: BlizzardPopupGlass.highlightDistance,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  BlizzardPopupGlass.highlight,
                                  BlizzardPopupGlass.highlightFade,
                                  Colors.transparent,
                                ],
                                stops: [
                                  0,
                                  BlizzardPopupGlass.highlightSoftness / BlizzardPopupGlass.highlightDistance,
                                  1,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            CustomPaint(
              foregroundPainter: glass ? _PopupEdgePainter(this.radius) : null,
              child: BlizzardGlassPopupScope(active: glass, child: child),
            ),
          ],
        ),
      ),
    );
  }
}

class _PopupEdgePainter extends CustomPainter {
  const _PopupEdgePainter(this.radius);
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius((Offset.zero & size).deflate(0.5), Radius.circular(radius));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height.clamp(1, 160)), [
        BlizzardPopupGlass.edgeTop,
        BlizzardPopupGlass.edgeSide,
      ]);
    canvas.drawRRect(rect, paint);
    paint.shader!.dispose();
  }

  @override
  bool shouldRepaint(covariant _PopupEdgePainter oldDelegate) => oldDelegate.radius != radius;
}

/// Marks content that sits on a glass popup, so its plates can be a little denser than the glass.
class BlizzardGlassPopupScope extends InheritedWidget {
  const BlizzardGlassPopupScope({super.key, this.active = true, required super.child});
  final bool active;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BlizzardGlassPopupScope>()?.active ?? false;

  @override
  bool updateShouldNotify(BlizzardGlassPopupScope oldWidget) => active != oldWidget.active;
}
