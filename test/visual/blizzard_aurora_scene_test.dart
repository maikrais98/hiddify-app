import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_scene.dart';

const _frame = ValueKey('aurora-frame');
const _control = ValueKey('connection-control');
const _staticStars = ValueKey('blizzard_static_stars');

Widget _fixture({
  required List<BlizzardParticlePreset> presets,
  MediaQueryData media = const MediaQueryData(disableAnimations: true),
  bool visible = true,
  String? auroraAsset,
}) => MediaQuery(
  data: media,
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: TickerMode(
      enabled: visible,
      child: RepaintBoundary(
        key: _frame,
        child: Row(
          children: [
            for (final preset in presets)
              Expanded(
                child: auroraAsset == null
                    ? BlizzardScene(key: ValueKey(preset), preset: preset)
                    : BlizzardScene(key: ValueKey(preset), preset: preset, auroraAsset: auroraAsset),
              ),
          ],
        ),
      ),
    ),
  ),
);

Widget _sameSceneFixture(BlizzardParticlePreset preset) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: TickerMode(
      enabled: true,
      child: RepaintBoundary(
        key: _frame,
        child: BlizzardScene(key: const ValueKey('same-aurora-scene'), preset: preset),
      ),
    ),
  ),
);

List<BlizzardAuroraPainter> _auroraPainters(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<BlizzardAuroraPainter>()
    .toList();

({ui.FragmentShader glow, double scale}) _softResourceOf(BlizzardAuroraPainter painter) {
  expect(painter, isA<BlizzardSoftAuroraPainter>());
  final soft = painter as BlizzardSoftAuroraPainter;
  expect(soft.resolutionScale, greaterThan(0));
  expect(soft.resolutionScale, lessThan(1));
  return (glow: soft.shader, scale: soft.resolutionScale);
}

Future<List<BlizzardAuroraPainter>> _waitForAurora(
  WidgetTester tester, {
  int count = 1,
}) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    final painters = _auroraPainters(tester);
    if (painters.length == count) return painters;
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
  }
  fail(
    'Aurora did not finish loading: expected $count painter(s), '
    'found ${_auroraPainters(tester).length}',
  );
}

Future<Uint8List> _pixelsFor(WidgetTester tester, Finder finder) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
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

Future<Uint8List> _pixels(WidgetTester tester) => _pixelsFor(tester, find.byKey(_frame));

Widget _interactiveFixture({
  MediaQueryData media = const MediaQueryData(),
  bool visible = true,
  VoidCallback? onTap,
}) => MediaQuery(
  data: media,
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: TickerMode(
      enabled: visible,
      child: RepaintBoundary(
        key: _frame,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const BlizzardScene(preset: BlizzardParticlePreset.snowfall),
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

Future<void> _mount(
  WidgetTester tester, {
  required List<BlizzardParticlePreset> presets,
  MediaQueryData media = const MediaQueryData(disableAnimations: true),
  bool visible = true,
  String? auroraAsset,
}) async {
  await tester.binding.setSurfaceSize(const Size(600, 300));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _fixture(presets: presets, media: media, visible: visible, auroraAsset: auroraAsset),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized().handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized().handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('existing scene presets render Aurora and dispose their per-scene shaders', (tester) async {
    const auroraPresets = [
      BlizzardParticlePreset.hero,
      BlizzardParticlePreset.staticHero,
      BlizzardParticlePreset.quiet,
      BlizzardParticlePreset.envelope,
      BlizzardParticlePreset.snowfall,
    ];
    await _mount(tester, presets: auroraPresets);

    final painters = await _waitForAurora(tester, count: auroraPresets.length);
    expect(painters, hasLength(auroraPresets.length));
    expect(painters.map((painter) => painter.shader).toSet(), hasLength(auroraPresets.length));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(painters.map((painter) => painter.shader.debugDisposed), everyElement(isTrue));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('snowfall owns one soft-glow shader until unmount', (tester) async {
    await _mount(tester, presets: const [BlizzardParticlePreset.snowfall]);

    final resource = _softResourceOf((await _waitForAurora(tester)).single);
    expect(resource.glow.debugDisposed, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(resource.glow.debugDisposed, isTrue);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-key snow quiet snow replaces its one shader and retains phase', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_sameSceneFixture(BlizzardParticlePreset.snowfall));
    final firstSnow = (await _waitForAurora(tester)).single;
    final firstResource = _softResourceOf(firstSnow);
    await tester.pump(const Duration(milliseconds: 600));
    final movingPhase = firstSnow.phase.value;

    await tester.pumpWidget(_sameSceneFixture(BlizzardParticlePreset.quiet));
    await tester.pump();
    final quiet = (await _waitForAurora(tester)).single;
    expect(quiet.runtimeType, BlizzardAuroraPainter);
    expect(quiet.motion, isFalse);
    expect(quiet.phase.value, movingPhase);
    expect(identical(quiet.shader, firstResource.glow), isFalse);
    expect(firstResource.glow.debugDisposed, isTrue);
    final quietPhase = quiet.phase.value;

    await tester.pumpWidget(_sameSceneFixture(BlizzardParticlePreset.snowfall));
    await tester.pump();
    final secondSnow = (await _waitForAurora(tester)).single;
    final secondResource = _softResourceOf(secondSnow);
    expect(secondSnow.phase.value, quietPhase);
    expect(identical(secondResource.glow, firstResource.glow), isFalse);
    expect(identical(secondResource.glow, quiet.shader), isFalse);
    expect(quiet.shader.debugDisposed, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(secondResource.glow.debugDisposed, isTrue);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('snowfall keeps static-star pixels fixed while its actual glow clock advances', (tester) async {
    const preset = [BlizzardParticlePreset.snowfall];
    await _mount(tester, presets: preset);
    await tester.pumpWidget(_fixture(presets: preset, media: const MediaQueryData()));
    await tester.pump();
    final aurora = (await _waitForAurora(tester)).single;
    final staticBoundary = find.byKey(_staticStars);
    expect(staticBoundary, findsOneWidget);
    final staticPaint = find.descendant(of: staticBoundary, matching: find.byType(CustomPaint));
    expect(staticPaint, findsOneWidget);
    final staticPainter = tester.widget<CustomPaint>(staticPaint).painter!;
    expect(staticPainter, isA<BlizzardStaticStarsPainter>());
    expect((staticPainter as BlizzardStaticStarsPainter).shouldRepaint(const BlizzardStaticStarsPainter()), isFalse);

    final starsBefore = await _pixelsFor(tester, staticBoundary);
    final glowBefore = await _pixels(tester);
    final phaseBefore = aurora.phase.value;
    await tester.pump(const Duration(milliseconds: 600));
    final starsAfter = await _pixelsFor(tester, staticBoundary);
    final glowAfter = await _pixels(tester);

    expect(_auroraPainters(tester).single.phase.value, isNot(phaseBefore));
    expect(listEquals(starsAfter, starsBefore), isTrue, reason: 'Stars must never drift or twinkle');
    expect(listEquals(glowAfter, glowBefore), isFalse, reason: 'The Aurora glow must retain its existing motion');
    expect(
      [for (var i = 3; i < starsBefore.length; i += 4) starsBefore[i]].any((alpha) => alpha > 5),
      isTrue,
      reason: 'Static stars must remain visible',
    );
  });

  testWidgets('snowfall soft resolution tracks physical pixel density', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final (devicePixelRatio, expectedScale) in [(1.0, .75), (2.0, .375), (3.0, .25)]) {
      await tester.pumpWidget(
        _fixture(
          presets: const [BlizzardParticlePreset.snowfall],
          media: MediaQueryData(disableAnimations: true, devicePixelRatio: devicePixelRatio),
        ),
      );
      await tester.pumpAndSettle();
      final soft = _softResourceOf((await _waitForAurora(tester)).single);
      expect(soft.scale, expectedScale, reason: 'DPR $devicePixelRatio must target 0.75 physical pixels per point');
    }
  });

  testWidgets('immediate off and unmount during soft setup settle without pending frames', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_sameSceneFixture(BlizzardParticlePreset.snowfall));
    await tester.pumpWidget(_sameSceneFixture(BlizzardParticlePreset.off));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(_auroraPainters(tester), isEmpty);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_sameSceneFixture(BlizzardParticlePreset.snowfall));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(_auroraPainters(tester), isEmpty);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing Aurora asset settles on the dark fallback without leaking a clock', (tester) async {
    await _mount(
      tester,
      presets: const [BlizzardParticlePreset.hero],
      media: const MediaQueryData(),
      auroraAsset: 'assets/shaders/missing_blizzard_aurora.frag',
    );

    expect(_auroraPainters(tester), isEmpty);
    expect(
      tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<BlizzardScenePainter>(),
      hasLength(1),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bounded Aurora contributes light without an opaque rectangular sky', (tester) async {
    await _mount(tester, presets: const [BlizzardParticlePreset.envelope]);
    await _waitForAurora(tester);
    final pixels = await _pixels(tester);
    for (final point in [(0, 0), (599, 0), (0, 299), (599, 299), (0, 150), (599, 150)]) {
      final offset = (point.$2 * 600 + point.$1) * 4;
      expect(pixels[offset + 3], lessThanOrEqualTo(1), reason: 'Scene edges must blend into the existing background');
    }
    expect(
      [for (var i = 3; i < pixels.length; i += 4) pixels[i]].any((alpha) => alpha > 5),
      isTrue,
      reason: 'The transparent scene must still render visible aurora light',
    );
  });

  for (final preset in [BlizzardParticlePreset.envelope, BlizzardParticlePreset.snowfall]) {
    testWidgets('$preset motion changes visible light within 600 milliseconds', (tester) async {
      final presets = [preset];
      await _mount(tester, presets: presets);
      await _waitForAurora(tester);
      final before = await _pixels(tester);
      await tester.pumpWidget(_fixture(presets: presets, media: const MediaQueryData()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final after = await _pixels(tester);
      var changed = 0;
      for (var pixel = 0; pixel < before.length; pixel += 4) {
        if (List.generate(
          3,
          (channel) => (before[pixel + channel] - after[pixel + channel]).abs(),
        ).any((delta) => delta >= 4)) {
          changed++;
        }
      }
      expect(changed, greaterThan(600 * 300 * .01), reason: 'A running clock alone does not prove perceptible motion');
    });
  }

  for (final preset in [BlizzardParticlePreset.quiet, BlizzardParticlePreset.off]) {
    testWidgets('$preset stays static without scheduling animation frames', (tester) async {
      await _mount(tester, presets: [preset], media: const MediaQueryData());
      if (preset == BlizzardParticlePreset.off) {
        expect(_auroraPainters(tester), isEmpty);
      } else {
        expect((await _waitForAurora(tester)).single.motion, isFalse);
      }
      final frozen = await _pixels(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(listEquals(await _pixels(tester), frozen), isTrue);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Aurora stays decorative and leaves the existing control interactive and semantic', (tester) async {
    var taps = 0;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const BlizzardScene(preset: BlizzardParticlePreset.snowfall),
              Center(
                child: Semantics(
                  button: true,
                  label: 'Connection control',
                  child: GestureDetector(
                    key: _control,
                    behavior: HitTestBehavior.opaque,
                    onTap: () => taps++,
                    child: const SizedBox.square(dimension: 148),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _waitForAurora(tester);

    expect(find.bySemanticsLabel('Connection control'), findsOneWidget);
    expect(find.byType(IgnorePointer), findsOneWidget);
    expect(find.byType(ExcludeSemantics), findsOneWidget);
    await tester.tap(find.byKey(_control));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('full-screen Aurora repaints a closed loop without moving the existing control', (tester) async {
    var taps = 0;
    await tester.binding.setSurfaceSize(const Size(393, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _interactiveFixture(media: const MediaQueryData(disableAnimations: true), onTap: () => taps++),
    );
    await tester.pumpAndSettle();
    await _waitForAurora(tester);
    final controlBounds = tester.getRect(find.byKey(_control));
    final initial = await _pixels(tester);

    await tester.pumpWidget(_interactiveFixture(onTap: () => taps++));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(listEquals(await _pixels(tester), initial), isFalse);
    expect(tester.getRect(find.byKey(_control)), controlBounds);
    await tester.tap(find.byKey(_control));
    expect(taps, 1);

    await tester.pump(const Duration(milliseconds: 11400));
    expect(listEquals(await _pixels(tester), initial), isTrue, reason: 'Aurora must not jump at the loop boundary');
    expect(tester.getRect(find.byKey(_control)), controlBounds);
  });

  for (final media in [
    const MediaQueryData(disableAnimations: true),
    const MediaQueryData(accessibleNavigation: true),
  ]) {
    testWidgets('accessibility freezes a still-rendered Aurora without a pending frame: $media', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_interactiveFixture(media: media));
      await tester.pumpAndSettle();
      final painter = (await _waitForAurora(tester)).single;
      final phase = painter.phase.value;
      final frozen = await _pixels(tester);

      expect(painter.motion, isFalse);
      await tester.pump(const Duration(seconds: 2));
      expect(listEquals(await _pixels(tester), frozen), isTrue);
      expect(_auroraPainters(tester).single.phase.value, phase);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Increase Contrast does not silently enable Reduce Motion', (tester) async {
    await _mount(tester, presets: const [BlizzardParticlePreset.envelope]);
    await _waitForAurora(tester);
    await tester.pumpWidget(
      _fixture(presets: const [BlizzardParticlePreset.envelope], media: const MediaQueryData(highContrast: true)),
    );
    await tester.pump();
    final phase = _auroraPainters(tester).single.phase.value;
    await tester.pump(const Duration(milliseconds: 600));
    expect(_auroraPainters(tester).single.motion, isTrue);
    expect(_auroraPainters(tester).single.phase.value, isNot(phase));
  });

  testWidgets('offstage and Reduce Motion retain the existing Aurora clock phase', (tester) async {
    const preset = [BlizzardParticlePreset.hero];
    await _mount(tester, presets: preset);
    final loaded = (await _waitForAurora(tester)).single.phase.value;

    await tester.pumpWidget(_fixture(presets: preset, media: const MediaQueryData()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final moving = _auroraPainters(tester).single.phase.value;
    expect(moving, isNot(loaded));

    await tester.pumpWidget(_fixture(presets: preset, media: const MediaQueryData(), visible: false));
    await tester.pump();
    final hidden = _auroraPainters(tester).single.phase.value;
    await tester.pump(const Duration(minutes: 1));
    expect(_auroraPainters(tester).single.phase.value, hidden);
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(_fixture(presets: preset, media: const MediaQueryData()));
    await tester.pump();
    expect(_auroraPainters(tester).single.phase.value, hidden);
    await tester.pump(const Duration(milliseconds: 600));
    expect(_auroraPainters(tester).single.phase.value, isNot(hidden));

    await tester.pumpWidget(_fixture(presets: preset));
    await tester.pump();
    final reduced = _auroraPainters(tester).single.phase.value;
    await tester.pump(const Duration(seconds: 2));
    expect(_auroraPainters(tester).single.phase.value, reduced);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final lifecycle in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
    testWidgets('lifecycle $lifecycle pauses Aurora and resumes from the retained phase', (tester) async {
      const preset = [BlizzardParticlePreset.hero];
      await _mount(tester, presets: preset);
      await _waitForAurora(tester);
      await tester.pumpWidget(_fixture(presets: preset, media: const MediaQueryData()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      tester.binding.handleAppLifecycleStateChanged(lifecycle);
      await tester.pump();
      final paused = _auroraPainters(tester).single.phase.value;
      await tester.pump(const Duration(minutes: 1));
      expect(_auroraPainters(tester).single.phase.value, paused);
      expect(tester.binding.hasScheduledFrame, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(_auroraPainters(tester).single.phase.value, paused);
      await tester.pump(const Duration(milliseconds: 600));
      expect(_auroraPainters(tester).single.phase.value, isNot(paused));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
