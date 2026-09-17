import 'dart:math';

import 'package:flutter/material.dart';

const _glyphAlphabet = <String>[
  'カ',
  'ヌ',
  'メ',
  'ヲ',
  'ヰ',
  '界',
  '中',
  '雨',
  '秘',
  '密',
  '火',
  '女',
  '暗',
  '影',
  'Ж',
  'Я',
  'Ч',
  'Ф',
  'Ю',
  'λ',
  'Ψ',
  '∆',
  '⌁',
  '⌬',
  '⋮',
  '⌗',
  '⊕',
  '⌘',
  'A',
  'V',
  'X',
  'R',
  'Q',
  '7',
  '3',
  '9',
  '0',
];

@immutable
class MatrixRainColumn {
  const MatrixRainColumn({
    required this.x,
    required this.glyphs,
    required this.period,
    required this.phase,
    required this.opacity,
    required this.blur,
  });

  final double x;
  final String glyphs;
  final Duration period;
  final double phase;
  final double opacity;
  final double blur;

  @override
  bool operator ==(Object other) =>
      other is MatrixRainColumn &&
      x == other.x &&
      glyphs == other.glyphs &&
      period == other.period &&
      phase == other.phase &&
      opacity == other.opacity &&
      blur == other.blur;

  @override
  int get hashCode => Object.hash(x, glyphs, period, phase, opacity, blur);
}

List<MatrixRainColumn> buildMatrixRainColumns(Size size, {int seed = 47}) {
  if (size.isEmpty) return const [];

  final random = Random(seed);
  const stride = 18.0;
  const lineHeight = 17.0;
  final glyphCount = max(48, (size.height * 1.35 / lineHeight).ceil());
  final columnCount = (size.width / stride).ceil() + 1;

  return List.generate(columnCount, (index) {
    final glyphs = List.generate(glyphCount, (_) => _glyphAlphabet[random.nextInt(_glyphAlphabet.length)]).join();
    return MatrixRainColumn(
      x: index * stride,
      glyphs: glyphs,
      period: Duration(milliseconds: 4100 + random.nextInt(4400)),
      phase: random.nextDouble(),
      opacity: 0.26 + random.nextDouble() * 0.64,
      blur: random.nextDouble() < 0.22 ? 1.8 : 0,
    );
  }, growable: false);
}
