import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/loading/model/matrix_rain_column.dart';

void main() {
  test('columns deterministically cover the viewport', () {
    const size = Size(390, 844);
    final first = buildMatrixRainColumns(size, seed: 47);
    final second = buildMatrixRainColumns(size, seed: 47);

    expect(first, second);
    expect(first.first.x, lessThanOrEqualTo(8));
    expect(first.last.x, greaterThanOrEqualTo(size.width - 24));
    expect(first.every((column) => column.glyphs.length >= 32), isTrue);
    expect(first.every((column) => column.period > Duration.zero), isTrue);
  });
}
