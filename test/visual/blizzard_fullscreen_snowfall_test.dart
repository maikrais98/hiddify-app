import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_scene.dart';

const _frameSize = Size(393, 700);
const _canvas = ValueKey('fullscreen-snowfall-canvas');
const _control = ValueKey('fullscreen-snowfall-control');
const _background = (red: 0x06, green: 0x12, blue: 0x1D);

BlizzardParticlePreset get _snowfall => BlizzardParticlePreset.values.byName('snowfall');

Widget _scene({MediaQueryData media = const MediaQueryData(), bool visible = true, VoidCallback? onTap}) => MediaQuery(
  data: media,
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: SizedBox.fromSize(
      size: _frameSize,
      child: RepaintBoundary(
        key: _canvas,
        child: TickerMode(
          enabled: visible,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: BlizzardScene(preset: _snowfall)),
              if (onTap != null)
                Center(
                  child: GestureDetector(
                    key: _control,
                    behavior: HitTestBehavior.opaque,
                    onTap: onTap,
                    child: const SizedBox.square(dimension: 148),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  ),
);

Future<void> _mount(
  WidgetTester tester, {
  MediaQueryData media = const MediaQueryData(),
  bool visible = true,
  VoidCallback? onTap,
}) async {
  await tester.binding.setSurfaceSize(_frameSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_scene(media: media, visible: visible, onTap: onTap));
  await tester.pump();
  expect(tester.getSize(find.byKey(_canvas)), _frameSize);
}

Future<Uint8List> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_canvas));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      expect(image.width, _frameSize.width);
      expect(image.height, _frameSize.height);
      final data = await image.toByteData();
      return Uint8List.fromList(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }))!;
}

int _changedPixels(Uint8List before, Uint8List after, Rect region) {
  var changed = 0;
  for (var y = region.top.round(); y < region.bottom.round(); y++) {
    for (var x = region.left.round(); x < region.right.round(); x++) {
      final offset = (y * _frameSize.width.toInt() + x) * 4;
      final delta =
          (before[offset] - after[offset]).abs() +
          (before[offset + 1] - after[offset + 1]).abs() +
          (before[offset + 2] - after[offset + 2]).abs();
      if (delta > 8) changed++;
    }
  }
  return changed;
}

int _nonBackgroundPixels(Uint8List pixels, Rect region) {
  var visible = 0;
  for (var y = region.top.round(); y < region.bottom.round(); y++) {
    for (var x = region.left.round(); x < region.right.round(); x++) {
      final offset = (y * _frameSize.width.toInt() + x) * 4;
      final delta =
          (pixels[offset] - _background.red).abs() +
          (pixels[offset + 1] - _background.green).abs() +
          (pixels[offset + 2] - _background.blue).abs();
      if (delta > 6) visible++;
    }
  }
  return visible;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized().handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized().handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('snowfall moves across every region outside the central 353x260 envelope', (tester) async {
    await _mount(tester);
    final before = await _pixels(tester);
    await tester.pump(const Duration(milliseconds: 600));
    final after = await _pixels(tester);

    const regions = <String, Rect>{
      'top': Rect.fromLTWH(0, 0, 393, 220),
      'bottom': Rect.fromLTWH(0, 480, 393, 220),
      'left': Rect.fromLTWH(0, 220, 20, 260),
      'right': Rect.fromLTWH(373, 220, 20, 260),
    };
    for (final entry in regions.entries) {
      expect(
        _nonBackgroundPixels(before, entry.value),
        greaterThan(entry.key == 'top' || entry.key == 'bottom' ? 30 : 4),
        reason: '${entry.key} must contain visible snow outside the old envelope',
      );
      expect(
        _changedPixels(before, after, entry.value),
        greaterThan(entry.key == 'top' || entry.key == 'bottom' ? 20 : 3),
        reason: '${entry.key} must contain moving snow outside the old envelope',
      );
    }
  });

  testWidgets('snowfall owns no legacy ribbon or wave image', (tester) async {
    await _mount(tester);

    final ribbonPainters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<BlizzardRibbonPainter>();
    expect(ribbonPainters, isEmpty);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('Reduce Motion freezes a still-visible full-screen snowfall', (tester) async {
    await _mount(tester, media: const MediaQueryData(disableAnimations: true));
    final frozen = await _pixels(tester);

    expect(_nonBackgroundPixels(frozen, const Rect.fromLTWH(0, 0, 393, 220)), greaterThan(30));
    expect(_nonBackgroundPixels(frozen, const Rect.fromLTWH(0, 480, 393, 220)), greaterThan(30));
    await tester.pump(const Duration(seconds: 2));
    expect(listEquals(await _pixels(tester), frozen), isTrue);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('offstage snowfall retains its phase and resumes without a jump', (tester) async {
    await _mount(tester);
    await tester.pump(const Duration(seconds: 2));
    await _mount(tester, visible: false);
    final hidden = await _pixels(tester);

    await tester.pump(const Duration(minutes: 1));
    expect(listEquals(await _pixels(tester), hidden), isTrue);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await _mount(tester);
    expect(listEquals(await _pixels(tester), hidden), isTrue);
    await tester.pump(const Duration(milliseconds: 600));
    expect(listEquals(await _pixels(tester), hidden), isFalse);
  });

  testWidgets('inactive lifecycle freezes snowfall and resumes from the retained phase', (tester) async {
    await _mount(tester);
    await tester.pump(const Duration(seconds: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    final paused = await _pixels(tester);

    await tester.pump(const Duration(minutes: 1));
    expect(listEquals(await _pixels(tester), paused), isTrue);
    expect(tester.binding.hasScheduledFrame, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(listEquals(await _pixels(tester), paused), isTrue);
    await tester.pump(const Duration(milliseconds: 600));
    expect(listEquals(await _pixels(tester), paused), isFalse);
  });

  testWidgets('snowfall closes its shared twelve-second loop without a seam', (tester) async {
    await _mount(tester);
    final initial = await _pixels(tester);

    await tester.pump(BlizzardMetrics.waveDuration);
    expect(listEquals(await _pixels(tester), initial), isTrue);
  });

  testWidgets('snowfall ignores pointers and leaves the connection control tappable', (tester) async {
    var taps = 0;
    await _mount(tester, onTap: () => taps++);

    await tester.tap(find.byKey(_control));
    expect(taps, 1);
  });
}
