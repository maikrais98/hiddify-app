import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Builds compare.png from the renders of luma_menus_render_test.dart (rows: screens,
// columns: now / A / B). Skipped unless LUMA_RENDER_DIR points at the renders.
void main() {
  final dir = Platform.environment['LUMA_RENDER_DIR'];
  testWidgets('compare sheet', skip: dir == null, (tester) async {
    final root = Platform.environment['FLUTTER_ROOT'];
    final loader = FontLoader('Cmp')
      ..addFont(
        Future.value(
          ByteData.sublistView(File('$root/bin/cache/artifacts/material_fonts/Roboto-Bold.ttf').readAsBytesSync()),
        ),
      );
    await loader.load();
    const columns = [('now', 'Сейчас (сборка 49)'), ('A', 'A: как шторка'), ('B', 'B: liquid glass')];
    const rows = [
      ('quick-settings-sheet', 'Быстрые настройки'),
      ('quick-settings-sheet-bright', 'Быстрые настройки, яркая сцена'),
      ('settings-overflow-menu', 'Меню «⋯» в Настройках'),
      ('picker-dialog', 'Диалог выбора'),
      ('confirm-dialog-bright', 'Подтверждение над Home'),
    ];
    const cellW = 330.0;
    const cellH = 715.0;
    const gap = 14.0;
    const head = 44.0;
    const label = 30.0;
    final width = columns.length * cellW + (columns.length + 1) * gap;
    final height = head + rows.length * (cellH + label + gap) + gap;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = const Color(0xFF1B1C1F));
      void text(String s, Offset at, double size, Color color) {
        final painter = TextPainter(
          text: TextSpan(
            text: s,
            style: TextStyle(fontFamily: 'Cmp', fontSize: size, color: color),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, at);
      }

      for (var c = 0; c < columns.length; c++) {
        text(columns[c].$2, Offset(gap + c * (cellW + gap), 10), 22, const Color(0xFFF2F6F5));
      }
      for (var r = 0; r < rows.length; r++) {
        final top = head + r * (cellH + label + gap);
        text(rows[r].$2, Offset(gap, top + 4), 17, const Color(0xFF8DDED8));
        for (var c = 0; c < columns.length; c++) {
          final bytes = File('$dir/${columns[c].$1}/${rows[r].$1}.png').readAsBytesSync();
          final codec = await ui.instantiateImageCodec(bytes);
          final image = (await codec.getNextFrame()).image;
          final scale = cellW / image.width;
          final shownH = (image.height * scale).clamp(0.0, cellH);
          final dst = Rect.fromLTWH(gap + c * (cellW + gap), top + label, cellW, shownH);
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(0, 0, image.width.toDouble(), shownH / scale),
            dst,
            Paint()..filterQuality = FilterQuality.high,
          );
          image.dispose();
        }
      }
      final picture = recorder.endRecording();
      final out = await picture.toImage(width.toInt(), height.toInt());
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/../compare.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
