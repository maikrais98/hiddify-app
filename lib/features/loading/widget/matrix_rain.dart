import 'package:flutter/material.dart';
import 'package:hiddify/features/loading/model/matrix_rain_column.dart';

class MatrixRain extends StatefulWidget {
  const MatrixRain({super.key, this.animate = true, this.seed = 47, this.fontFamily});

  final bool animate;
  final int seed;
  final String? fontFamily;

  @override
  State<MatrixRain> createState() => _MatrixRainState();
}

class _MatrixRainState extends State<MatrixRain> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 12), value: 0.37);
    _syncAnimation();
  }

  @override
  void didUpdateWidget(MatrixRain oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.animate) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0.37;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          if (!size.isFinite || size.isEmpty) return const SizedBox.expand();
          final columns = buildMatrixRainColumns(size, seed: widget.seed);
          return CustomPaint(
            size: size,
            painter: _MatrixRainPainter(columns: columns, animation: _controller, fontFamily: widget.fontFamily),
          );
        },
      ),
    );
  }
}

class _MatrixRainPainter extends CustomPainter {
  _MatrixRainPainter({required this.columns, required Animation<double> animation, required String? fontFamily})
    : _animation = animation,
      _runs = columns.map((column) => _MatrixGlyphRun(column, fontFamily)).toList(growable: false),
      super(repaint: animation);

  final List<MatrixRainColumn> columns;
  final Animation<double> _animation;
  final List<_MatrixGlyphRun> _runs;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xFF030306), BlendMode.src);

    for (var index = 0; index < columns.length; index++) {
      final column = columns[index];
      final run = _runs[index];
      final columnExtent = run.extent;
      final speedScale = const Duration(seconds: 12).inMilliseconds / column.period.inMilliseconds;
      final progress = (_animation.value * speedScale + column.phase) % 1.0;
      final y = -columnExtent + columnExtent * progress;
      run.paint(canvas, y);
      run.paint(canvas, y + columnExtent);
    }

    final vignette = Paint()
      ..shader = const RadialGradient(
        radius: 0.92,
        colors: [Color(0x00030306), Color(0x72030306)],
        stops: [0.42, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, vignette);
  }

  @override
  bool shouldRepaint(covariant _MatrixRainPainter oldDelegate) => oldDelegate.columns != columns;
}

class _MatrixGlyphRun {
  _MatrixGlyphRun(this.column, String? fontFamily) {
    final tailColor = const Color(0xFFC10B3A).withValues(alpha: column.opacity * 0.55);
    final blurShadow = column.blur > 0
        ? [
            Shadow(
              color: const Color(0xFFD10B3A).withValues(alpha: column.opacity * 0.72),
              blurRadius: column.blur * 2.5,
            ),
          ]
        : null;
    tail = TextPainter(
      text: TextSpan(
        text: column.glyphs.split('').join('\n'),
        style: TextStyle(
          color: tailColor,
          fontFamily: fontFamily,
          fontSize: 13,
          height: 17 / 13,
          fontWeight: FontWeight.w500,
          shadows: blurShadow,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 16, maxWidth: 16);
    head = TextPainter(
      text: TextSpan(
        text: column.glyphs[column.glyphs.length - 1],
        style: TextStyle(
          color: const Color(0xFFFFE5EC),
          fontFamily: fontFamily,
          fontSize: 13,
          height: 17 / 13,
          fontWeight: FontWeight.w700,
          shadows: const [Shadow(color: Color(0xFFFF174D), blurRadius: 7)],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 16, maxWidth: 16);
  }

  final MatrixRainColumn column;
  late final TextPainter tail;
  late final TextPainter head;

  double get extent => tail.height;

  void paint(Canvas canvas, double y) {
    final origin = Offset(column.x - 8, y);
    tail.paint(canvas, origin);
    head.paint(canvas, origin + Offset(0, extent - head.height));
  }
}
