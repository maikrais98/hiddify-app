import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_scene.dart';
import 'package:hiddify/features/settings/overview/sections/general_page.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/blizzard_capture.dart';
import '../test/support/blizzard_dock_fixture_action.dart';
import '../test/support/home_fixture.dart';
import '../test/visual/blizzard_v3_home_geometry_test.dart' as geometry;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  setUpAll(() async {
    runApp(const MaterialApp(home: SizedBox.shrink()));
    await binding.endOfFrame;
    await Future<void>.delayed(const Duration(seconds: 1));
  });

  testWidgets('native Home keeps two live Aurora clocks and pauses both below a root modal', (tester) async {
    expect(Platform.isIOS, isTrue);
    final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
    final fixture = await mountHomeFixture(
      tester,
      width: viewport.width,
      height: viewport.height,
      nativeViewport: true,
    );
    try {
      final canvas = find.byKey(blizzardFixtureCanvas);
      final snow = find.byKey(const ValueKey('blizzard_shell_snowfall'));
      final shellRouteTicker = find.byKey(const ValueKey('blizzard_shell_root_route_gate'));
      final shellVisibilityTicker = find.byKey(const ValueKey('blizzard_shell_motion_gate'));
      expect(snow, findsOneWidget);
      expect(shellRouteTicker, findsOneWidget);
      expect(shellVisibilityTicker, findsOneWidget);
      expect(tester.getRect(snow), tester.getRect(canvas));
      final button = find.byKey(const ValueKey('home_connection_button'));
      final dock = find.byKey(const ValueKey('blizzard_bottom_dock'));
      final initialButton = tester.getRect(button);
      final initialDock = tester.getRect(dock);
      expect(initialButton.size, const Size(148, 148));

      for (var attempt = 0; attempt < 40; attempt++) {
        final painters = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .where((paint) => paint.painter is BlizzardAuroraPainter);
        if (painters.length >= 2) break;
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
      expect(
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .where((paint) => paint.painter is BlizzardAuroraPainter),
        hasLength(2),
        reason: 'Both actual-shell Aurora shaders must finish loading before pixel capture',
      );

      Future<List<int>> pixels() async {
        final image = await tester.renderObject<RenderRepaintBoundary>(canvas).toImage();
        try {
          return (await image.toByteData())!.buffer.asUint8List().toList();
        } finally {
          image.dispose();
        }
      }

      final first = await pixels();
      await tester.pump(const Duration(milliseconds: 600));
      final next = await pixels();
      for (final region in [
        Rect.fromLTWH(0, 0, viewport.width, 100),
        Rect.fromLTWH(0, viewport.height - 90, viewport.width, 90),
      ]) {
        var changed = 0;
        for (var y = region.top.toInt(); y < region.bottom.toInt(); y++) {
          for (var x = region.left.toInt(); x < region.right.toInt(); x++) {
            final p = (y * viewport.width.toInt() + x) * 4;
            if ((first[p] - next[p]).abs() > 4 ||
                (first[p + 1] - next[p + 1]).abs() > 4 ||
                (first[p + 2] - next[p + 2]).abs() > 4) {
              changed++;
            }
          }
        }
        debugPrint('BLIZZARD_PIXEL_MOTION region=$region changed=$changed');
        expect(changed, greaterThanOrEqualTo(4), reason: 'Fullscreen Aurora must move visible pixels in $region');
      }

      expect(tester.getRect(button), initialButton);
      expect(tester.getRect(dock), initialDock);
      final shellClock = tester
          .widgetList<CustomPaint>(find.descendant(of: snow, matching: find.byType(CustomPaint)))
          .single;
      expect(tester.widget<BlizzardScene>(snow).preset, BlizzardParticlePreset.snowfall);
      expect(shellClock.willChange, isTrue);
      final envelope = find.byKey(const ValueKey('blizzard_home_wave_envelope'));
      final envelopeScene = find.descendant(of: envelope, matching: find.byType(BlizzardScene));
      final envelopeClock = tester
          .widgetList<CustomPaint>(find.descendant(of: envelopeScene, matching: find.byType(CustomPaint)))
          .single;
      expect(tester.widget<BlizzardScene>(envelopeScene).preset, BlizzardParticlePreset.envelope);
      expect(envelopeClock.willChange, isTrue);
      expect(tester.widget<TickerMode>(shellRouteTicker).enabled, isTrue);
      expect(tester.widget<TickerMode>(shellVisibilityTicker).enabled, isTrue);
      expect(TickerMode.of(tester.element(envelopeScene)), isTrue);

      final shown = showModalBottomSheet<void>(
        context: rootNavKey.currentContext!,
        builder: (_) => const SizedBox(height: 120, child: Text('root sheet')),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<TickerMode>(shellRouteTicker).enabled, isFalse);
      expect(TickerMode.of(tester.element(envelopeScene)), isFalse);
      expect(tester.binding.hasScheduledFrame, isFalse);
      Navigator.of(rootNavKey.currentContext!, rootNavigator: true).pop();
      await shown;
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<TickerMode>(shellRouteTicker).enabled, isTrue);
      expect(TickerMode.of(tester.element(envelopeScene)), isTrue);
      expect(tester.binding.hasScheduledFrame, isTrue);

      await activateFixtureDockDestination(tester, 1);
      await tester.pump(const Duration(seconds: 1));
      final opacity = find.ancestor(of: snow, matching: find.byType(Opacity)).first;
      expect(tester.widget<TickerMode>(shellVisibilityTicker).enabled, isFalse);
      expect(tester.widget<Opacity>(opacity).opacity, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await activateFixtureDockDestination(tester, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<TickerMode>(shellVisibilityTicker).enabled, isTrue);
      expect(tester.widget<Opacity>(opacity).opacity, 1);
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(find.byType(BlizzardScene), findsNWidgets(2));
    } finally {
      await fixture.close(tester);
    }
  });
  testWidgets('settings scrolls beneath native glass and its final action stays reachable', (tester) async {
    final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
    final fixture = await mountHomeFixture(
      tester,
      width: viewport.width,
      height: viewport.height,
      nativeViewport: true,
      settingsChild: SettingsPage(),
    );
    try {
      final button = find.byKey(const ValueKey('home_connection_button'));
      final originalButton = tester.getRect(button);
      await activateFixtureDockDestination(tester, 1);
      await tester.pump(const Duration(seconds: 1));
      final menu = find.byType(BlizzardSettingsMenu);
      final list = find.descendant(of: menu, matching: find.byType(ListView));
      final dock = find.byKey(const ValueKey('blizzard_bottom_dock'));
      expect(tester.getRect(list).bottom, greaterThan(tester.getRect(dock).top));
      final padding = tester.widget<ListView>(list).padding! as EdgeInsets;
      expect(padding.top, 16);
      expect(padding.left, 20);
      expect(padding.right, 20);
      await tester.drag(list, const Offset(0, -2000));
      await tester.pump(const Duration(seconds: 1));
      final reset = find.byKey(const ValueKey('settings-reset-tunnel'));
      expect(tester.getRect(reset).bottom, lessThanOrEqualTo(tester.getRect(dock).top));
      await activateFixtureDockDestination(tester, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getRect(button), originalButton);
      expect(fixture.events, isEmpty);
    } finally {
      await fixture.close(tester);
    }
  });
  testWidgets('actual shell General final group clears the native floating dock', (tester) async {
    expect(Platform.isIOS, isTrue);
    final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
    final fixture = await mountHomeFixture(
      tester,
      width: viewport.width,
      height: viewport.height,
      nativeViewport: true,
      settingsChild: const GeneralPage(),
    );
    try {
      await activateFixtureDockDestination(tester, 1);
      await tester.pump(const Duration(seconds: 1));
      final list = find.descendant(of: find.byType(GeneralPage), matching: find.byType(ListView));
      await tester.drag(list, const Offset(0, -3000));
      await tester.pump(const Duration(seconds: 1));
      final lastGroup = find.byKey(const ValueKey('general-settings-group-connection'));
      final dock = find.byKey(const ValueKey('blizzard_bottom_dock'));
      expect(tester.getRect(lastGroup).bottom, lessThanOrEqualTo(tester.getRect(dock).top));
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.close(tester);
    }
  });
  testWidgets('records programmatically initiated cold and warm Home transition frame timings', (tester) async {
    expect(Platform.isIOS, isTrue);
    final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
    final fixture = await mountHomeFixture(
      tester,
      width: viewport.width,
      height: viewport.height,
      nativeViewport: true,
      settingsChild: SettingsPage(),
    );
    try {
      await _recordTransitionTimings(binding, tester, 'programmatic_home_to_settings_cold', () async {
        await activateFixtureDockDestination(tester, 1);
      });
      await activateFixtureDockDestination(tester, 0);
      await tester.pump(const Duration(milliseconds: 600));

      await _recordTransitionTimings(binding, tester, 'programmatic_home_to_settings_warm', () async {
        await activateFixtureDockDestination(tester, 1);
      });
      await activateFixtureDockDestination(tester, 0);
      await tester.pump(const Duration(milliseconds: 600));

      late Future<void> sheet;
      await _recordTransitionTimings(binding, tester, 'programmatic_root_sheet_open_cold', () async {
        sheet = showModalBottomSheet<void>(
          context: rootNavKey.currentContext!,
          builder: (_) => const SizedBox(height: 120, child: Text('timed root sheet')),
        );
        await tester.pump();
      });
      Navigator.of(rootNavKey.currentContext!, rootNavigator: true).pop();
      await sheet;
      await tester.pump(const Duration(milliseconds: 600));

      await _recordTransitionTimings(binding, tester, 'programmatic_root_sheet_open_warm', () async {
        sheet = showModalBottomSheet<void>(
          context: rootNavKey.currentContext!,
          builder: (_) => const SizedBox(height: 120, child: Text('timed root sheet')),
        );
        await tester.pump();
      });
      Navigator.of(rootNavKey.currentContext!, rootNavigator: true).pop();
      await sheet;
      await tester.pump(const Duration(milliseconds: 600));
    } finally {
      await fixture.close(tester);
    }
  });
  testWidgets('nested Home pages keep the dark background beneath the floating dock', (tester) async {
    final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
    final fixture = await mountHomeFixture(
      tester,
      width: viewport.width,
      height: viewport.height,
      nativeViewport: true,
      proxiesChild: const ColoredBox(color: BlizzardPalette.background),
    );
    try {
      fixture.router.go('/home/proxies');
      await tester.pump(const Duration(seconds: 1));
      final image = await tester.renderObject<RenderRepaintBoundary>(find.byKey(blizzardFixtureCanvas)).toImage();
      try {
        final pixels = (await image.toByteData())!.buffer.asUint8List();
        final offset = ((viewport.height.toInt() - 50) * image.width + 10) * 4;
        final color = Color.fromARGB(pixels[offset + 3], pixels[offset], pixels[offset + 1], pixels[offset + 2]);
        expect(color, BlizzardPalette.background, reason: 'No light canvas band outside the native dock');
      } finally {
        image.dispose();
      }
      expect(fixture.events, isEmpty);
    } finally {
      await fixture.close(tester);
    }
  });
  geometry.main();
}

Future<void> _recordTransitionTimings(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String label,
  Future<void> Function() transition,
) async {
  final timings = <ui.FrameTiming>[];
  void collect(List<ui.FrameTiming> values) => timings.addAll(values);

  binding.addTimingsCallback(collect);
  try {
    await transition();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await tester.pump();
    await binding.endOfFrame;
  } finally {
    binding.removeTimingsCallback(collect);
  }

  final builds = timings.map((timing) => timing.buildDuration).toList(growable: false);
  final rasters = timings.map((timing) => timing.rasterDuration).toList(growable: false);
  debugPrint(
    'BLIZZARD_FRAME_TIMING label=$label frames=${timings.length} '
    'build_p50_ms=${_percentileMilliseconds(builds, 0.50)} '
    'build_p95_ms=${_percentileMilliseconds(builds, 0.95)} '
    'build_p99_ms=${_percentileMilliseconds(builds, 0.99)} '
    'raster_p50_ms=${_percentileMilliseconds(rasters, 0.50)} '
    'raster_p95_ms=${_percentileMilliseconds(rasters, 0.95)} '
    'raster_p99_ms=${_percentileMilliseconds(rasters, 0.99)} '
    'build_over_8_33_ms=${builds.where((duration) => duration.inMicroseconds > 8333).length} '
    'build_over_16_67_ms=${builds.where((duration) => duration.inMicroseconds > 16667).length} '
    'raster_over_8_33_ms=${rasters.where((duration) => duration.inMicroseconds > 8333).length} '
    'raster_over_16_67_ms=${rasters.where((duration) => duration.inMicroseconds > 16667).length}',
  );
}

String _percentileMilliseconds(List<Duration> values, double percentile) {
  if (values.isEmpty) return 'n/a';
  final micros = values.map((value) => value.inMicroseconds).toList()..sort();
  final index = ((micros.length - 1) * percentile).ceil();
  return (micros[index] / Duration.microsecondsPerMillisecond).toStringAsFixed(3);
}
