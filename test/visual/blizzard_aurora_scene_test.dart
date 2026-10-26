import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_scene.dart';

const _frame = ValueKey('aurora-frame');

Widget _fixture(
  BlizzardParticlePreset preset, {
  MediaQueryData media = const MediaQueryData(disableAnimations: true),
  bool visible = true,
  String asset = blizzardAuroraGlowAsset,
}) => MediaQuery(
  data: media,
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: TickerMode(
      enabled: visible,
      child: RepaintBoundary(
        key: _frame,
        child: BlizzardScene(preset: preset, auroraAsset: asset),
      ),
    ),
  ),
);

Future<List<int>> _pixels(WidgetTester tester) => _pixelsFor(tester, find.byKey(_frame));

Future<List<int>> _pixelsFor(WidgetTester tester, Finder finder) async => (await tester.runAsync(() async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return bytes!.buffer.asUint8List().toList();
}))!;

Future<void> _mount(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  final images = tester.widgetList<Image>(find.byType(Image)).toList();
  if (images.isNotEmpty) {
    await tester.runAsync(() => precacheImage(images.single.image, tester.element(find.byType(Image))));
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('capture approved full-screen static background', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _mount(tester, _fixture(BlizzardParticlePreset.snowfall));
    const captureDirectory = String.fromEnvironment('BLIZZARD_CAPTURE_DIR');
    expect(tester.getSize(find.byKey(_frame)), const Size(393, 852));
    if (captureDirectory.isEmpty) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_frame));
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(captureDirectory);
      await directory.create(recursive: true);
      await File('${directory.path}/flutter-static-background.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });

  testWidgets('glow reaches the bottom of the portrait viewport', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _mount(tester, _fixture(BlizzardParticlePreset.quiet));
    final actual = await _pixels(tester);
    for (final fraction in [.90, .95, .99]) {
      final y = (852 * fraction).floor();
      final blue = actual[(y * 393 + 196) * 4 + 2];
      expect(blue, greaterThan(60), reason: 'The lower glow must remain visible at $fraction of screen height');
    }
  });

  testWidgets('a modal stops the covered route background until dismissal', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: BlizzardScene()),
      ),
    );
    await tester.runAsync(
      () => precacheImage(const AssetImage(blizzardAuroraGlowAsset), tester.element(find.byType(Image))),
    );
    await tester.pump();
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    final modal = showModalBottomSheet<void>(
      context: tester.element(find.byType(BlizzardScene)),
      builder: (_) => const SizedBox(height: 100),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    navigator.currentState!.pop();
    await modal;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('all visible presets render the identical approved background', (tester) async {
    List<int>? expected;
    for (final preset in BlizzardParticlePreset.values.where((p) => p != BlizzardParticlePreset.off)) {
      await _mount(tester, _fixture(preset));
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, const AssetImage(blizzardAuroraGlowAsset));
      expect(image.fit, BoxFit.cover);
      expect(image.alignment, Alignment.topCenter);
      final pixels = await _pixels(tester);
      expected ??= pixels;
      expect(pixels, expected, reason: '$preset must retain exact Home/settings parity');
      expect(pixels.toSet().length, greaterThan(32), reason: 'Must render artwork, not only fallback');
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
  });

  testWidgets('only glow moves and pauses for hidden routes lifecycle and reduced motion', (tester) async {
    await _mount(tester, _fixture(BlizzardParticlePreset.snowfall));
    final starsBefore = await _pixelsFor(tester, find.byKey(const ValueKey('blizzard_static_stars')));
    await tester.pumpWidget(_fixture(BlizzardParticlePreset.snowfall, media: const MediaQueryData()));
    await tester.pump();
    final before = await _pixels(tester);
    await tester.pump(const Duration(seconds: 7));
    expect(await _pixels(tester), isNot(before));
    expect(await _pixelsFor(tester, find.byKey(const ValueKey('blizzard_static_stars'))), starsBefore);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    final moving = tester.widget<Transform>(find.byKey(const ValueKey('blizzard_aurora_glow_transform'))).transform;
    expect(moving.entry(0, 3).abs(), lessThanOrEqualTo(4));
    for (final state in [AppLifecycleState.inactive, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await _mount(tester, _fixture(BlizzardParticlePreset.quiet, media: const MediaQueryData(), visible: false));
    expect(tester.binding.transientCallbackCount, 0);
    await _mount(tester, _fixture(BlizzardParticlePreset.quiet));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('accessibility modes preserve static artwork without scheduling animation', (tester) async {
    for (final media in [
      const MediaQueryData(disableAnimations: true),
      const MediaQueryData(accessibleNavigation: true),
      const MediaQueryData(highContrast: true, disableAnimations: true),
    ]) {
      await _mount(tester, _fixture(BlizzardParticlePreset.hero, media: media));
      expect(find.byType(Image), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
  });

  testWidgets('scene is decorative and off uses the approved dark base', (tester) async {
    await _mount(tester, _fixture(BlizzardParticlePreset.off));
    expect(find.byType(Image), findsNothing);
    expect(tester.widget<ColoredBox>(find.byType(ColoredBox)).color, BlizzardPalette.background);
    expect(tester.widget<IgnorePointer>(find.byType(IgnorePointer)).ignoring, isTrue);
    expect(find.byType(ExcludeSemantics), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('missing raster settles on the dark fallback without a clock', (tester) async {
    await tester.pumpWidget(_fixture(BlizzardParticlePreset.quiet, asset: 'assets/images/missing-aurora.png'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widget<ColoredBox>(find.byType(ColoredBox)).color, BlizzardPalette.background);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
