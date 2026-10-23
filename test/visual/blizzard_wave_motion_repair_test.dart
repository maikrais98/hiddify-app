import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_scene.dart';

const _canvas = ValueKey('wave-motion-canvas');
const _size = Size(353, 260);
const _pixelRatio = 2.0;
const _pixelWidth = 706;

Future<void> _mount(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(_size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    const MediaQuery(
      data: MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: _canvas,
          child: SizedBox(width: 353, height: 260, child: BlizzardScene(preset: BlizzardParticlePreset.envelope)),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<Uint8List> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_canvas));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _pixelRatio);
    try {
      expect(image.width, _pixelWidth);
      expect(image.height, _size.height * _pixelRatio);
      final data = await image.toByteData();
      return Uint8List.fromList(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }))!;
}

int _changedPixels(Uint8List before, Uint8List after, Rect region) {
  var changed = 0;
  for (var y = (region.top * _pixelRatio).round(); y < (region.bottom * _pixelRatio).round(); y++) {
    for (var x = (region.left * _pixelRatio).round(); x < (region.right * _pixelRatio).round(); x++) {
      final offset = (y * _pixelWidth + x) * 4;
      final delta =
          (before[offset] - after[offset]).abs() +
          (before[offset + 1] - after[offset + 1]).abs() +
          (before[offset + 2] - after[offset + 2]).abs() +
          (before[offset + 3] - after[offset + 3]).abs();
      if (delta > 18) changed++;
    }
  }
  return changed;
}

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized().handleAppLifecycleStateChanged(AppLifecycleState.resumed));

  testWidgets('procedural vortex visibly flows through every quadrant around the control', (tester) async {
    await _mount(tester);
    final before = await _pixels(tester);
    await tester.pump(const Duration(milliseconds: 600));
    final after = await _pixels(tester);

    const quadrants = <String, Rect>{
      'upper-left': Rect.fromLTRB(60, 35, 170, 90),
      'upper-right': Rect.fromLTRB(180, 35, 290, 90),
      'lower-left': Rect.fromLTRB(35, 155, 110, 225),
      'lower-right': Rect.fromLTRB(240, 155, 315, 225),
    };
    for (final entry in quadrants.entries) {
      expect(
        _changedPixels(before, after, entry.value),
        greaterThan(250),
        reason: '${entry.key} fold must visibly flow instead of moving as a rigid image',
      );
    }
  });

  testWidgets('procedural vortex closes the shared twelve-second loop without a pixel seam', (tester) async {
    await _mount(tester);
    final initial = await _pixels(tester);

    await tester.pump(BlizzardMetrics.waveDuration);
    expect(listEquals(await _pixels(tester), initial), isTrue);
  });
}
