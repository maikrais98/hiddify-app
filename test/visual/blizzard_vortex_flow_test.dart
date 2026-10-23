import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_scene.dart';

const _size = Size(353, 260);
const _frame = ValueKey('vortex-frame');

Future<void> _mount(WidgetTester tester, {bool reduced = false}) async {
  await tester.binding.setSurfaceSize(_size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: _frame,
          child: BlizzardScene(preset: BlizzardParticlePreset.envelope),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<Uint8List> _pixels(WidgetTester tester, [String? name]) async => (await tester.runAsync(() async {
  final image = await tester.renderObject<RenderRepaintBoundary>(find.byKey(_frame)).toImage(pixelRatio: 2);
  try {
    if (name != null && const bool.fromEnvironment('BLIZZARD_CAPTURE')) {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/private/tmp/$name.png').writeAsBytes(png!.buffer.asUint8List());
    }
    return Uint8List.fromList((await image.toByteData())!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}))!;

int _lit(Uint8List pixels, Rect region) {
  var lit = 0;
  for (var y = (region.top * 2).round(); y < (region.bottom * 2).round(); y++) {
    for (var x = (region.left * 2).round(); x < (region.right * 2).round(); x++) {
      if (pixels[(y * 706 + x) * 4 + 3] > 12) lit++;
    }
  }
  return lit;
}

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized().handleAppLifecycleStateChanged(AppLifecycleState.resumed));

  testWidgets('outer dot rows fade away instead of drawing a hard perimeter', (tester) async {
    await _mount(tester);
    final pixels = await _pixels(tester);
    int peak(Rect region) {
      var alpha = 0;
      for (var y = (region.top * 2).round(); y < (region.bottom * 2).round(); y++) {
        for (var x = (region.left * 2).round(); x < (region.right * 2).round(); x++) {
          final value = pixels[(y * 706 + x) * 4 + 3];
          if (value > alpha) alpha = value;
        }
      }
      return alpha;
    }

    final middle = peak(const Rect.fromLTRB(293, 125, 302, 133));
    final edge = peak(const Rect.fromLTRB(333, 130, 340, 138));
    expect(middle, greaterThan(25));
    expect(edge, lessThan(middle * 0.6), reason: 'Outer particles must dissolve before the sheet boundary');
  });

  testWidgets('vortex continues below the glass instead of cutting out the button silhouette', (tester) async {
    await _mount(tester);
    final pixels = await _pixels(tester, 'blizzard-vortex-before');
    expect(
      _lit(pixels, const Rect.fromLTRB(210, 100, 244, 180)),
      greaterThan(300),
      reason: 'The dot sheet must continue under the right side of the glass, not stop at a baked-in knockout',
    );
    expect(
      _lit(pixels, const Rect.fromLTRB(125, 180, 220, 205)),
      greaterThan(300),
      reason: 'The lower fold must also continue underneath the control',
    );
  });

  testWidgets('all four folds flow visibly within 600ms and keep a seamless twelve-second loop', (tester) async {
    await _mount(tester);
    final first = await _pixels(tester);
    await tester.pump(const Duration(milliseconds: 600));
    final next = await _pixels(tester, 'blizzard-vortex-after');
    for (final rect in [
      const Rect.fromLTRB(60, 35, 170, 90),
      const Rect.fromLTRB(180, 35, 290, 90),
      const Rect.fromLTRB(35, 155, 110, 225),
      const Rect.fromLTRB(240, 155, 315, 225),
    ]) {
      var changed = 0;
      for (var y = (rect.top * 2).round(); y < (rect.bottom * 2).round(); y++) {
        for (var x = (rect.left * 2).round(); x < (rect.right * 2).round(); x++) {
          final p = (y * 706 + x) * 4;
          if ((first[p + 3] - next[p + 3]).abs() > 18) changed++;
        }
      }
      expect(changed, greaterThan(250), reason: 'Every visible fold must flow: $rect');
    }
    await tester.pump(const Duration(milliseconds: 11400));
    expect(listEquals(first, await _pixels(tester)), isTrue);
  });

  testWidgets('Reduce Motion keeps the complete vortex without a running clock', (tester) async {
    await _mount(tester, reduced: true);
    final first = await _pixels(tester);
    expect(_lit(first, const Rect.fromLTRB(210, 100, 244, 180)), greaterThan(300));
    await tester.pump(const Duration(seconds: 2));
    expect(listEquals(first, await _pixels(tester)), isTrue);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
