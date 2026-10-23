import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_scene.dart';

const _canvas = ValueKey('vortex-envelope-canvas');
const _control = ValueKey('vortex-envelope-control');
const _size = Size(353, 260);

Future<void> _mount(WidgetTester tester, {MediaQueryData media = const MediaQueryData(), VoidCallback? onTap}) async {
  await tester.binding.setSurfaceSize(_size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MediaQuery(
      data: media,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: _canvas,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const BlizzardScene(preset: BlizzardParticlePreset.envelope),
              if (onTap != null)
                Center(
                  child: Semantics(
                    button: true,
                    label: 'Connection control',
                    child: GestureDetector(
                      key: _control,
                      behavior: HitTestBehavior.opaque,
                      onTap: onTap,
                      child: const SizedBox.square(dimension: 148),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.getSize(find.byKey(_canvas)), _size);
}

Future<Uint8List> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_canvas));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData();
      return Uint8List.fromList(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }))!;
}

int _visiblePixels(Uint8List pixels) {
  var visible = 0;
  for (var offset = 3; offset < pixels.length; offset += 4) {
    if (pixels[offset] > 12) visible++;
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

  testWidgets('procedural vortex is decorative and leaves the connection control interactive and semantic', (
    tester,
  ) async {
    var taps = 0;
    final semantics = tester.ensureSemantics();
    await _mount(tester, onTap: () => taps++);

    expect(find.byType(Image), findsNothing);
    expect(find.bySemanticsLabel('Connection control'), findsOneWidget);
    expect(find.byType(IgnorePointer), findsOneWidget);
    expect(find.byType(ExcludeSemantics), findsOneWidget);
    await tester.tap(find.byKey(_control));
    expect(taps, 1);
    semantics.dispose();
  });

  testWidgets('inactive lifecycle freezes rendered vortex and resumes from the retained phase', (tester) async {
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

  for (final media in [
    const MediaQueryData(disableAnimations: true),
    const MediaQueryData(accessibleNavigation: true),
    const MediaQueryData(highContrast: true),
  ]) {
    testWidgets('accessibility setting freezes a still-visible vortex: $media', (tester) async {
      await _mount(tester, media: media);
      final frozen = await _pixels(tester);

      expect(_visiblePixels(frozen), greaterThan(1500));
      await tester.pump(const Duration(seconds: 2));
      expect(listEquals(await _pixels(tester), frozen), isTrue);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }
}
