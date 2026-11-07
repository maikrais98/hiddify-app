import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_native_connection_control.dart';
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

  testWidgets('native Home keeps static Aurora and native controls stable through modal and tab visibility', (
    tester,
  ) async {
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

      // The approved shell now caches raster glow and SVG stars. The former
      // shader painters and animated envelope were removed before this merge.
      expect(tester.widget<BlizzardScene>(snow).preset, BlizzardParticlePreset.staticHero);
      final image = find.descendant(of: snow, matching: find.byType(Image));
      expect(image, findsOneWidget);
      expect(tester.widget<Image>(image).image, const AssetImage(blizzardAuroraGlowAsset));
      await tester.runAsync(() => precacheImage(tester.widget<Image>(image).image, tester.element(image)));
      await tester.pump(const Duration(seconds: 1));
      final glow = find.ancestor(of: image, matching: find.byType(RepaintBoundary)).first;
      final stars = find.descendant(of: snow, matching: find.byKey(const ValueKey('blizzard_static_stars')));
      expect(stars, findsOneWidget);

      // Capture the actual scene layers as in the existing native Home contract;
      // platform views render separately and must not enter this pixel comparison.
      Future<List<int>> pixels(Finder layer) async {
        final image = await tester.renderObject<RenderRepaintBoundary>(layer).toImage();
        try {
          expect(image.width, greaterThan(0));
          expect(image.height, greaterThan(0));
          return (await image.toByteData())!.buffer.asUint8List().toList();
        } finally {
          image.dispose();
        }
      }

      final firstGlow = await pixels(glow);
      final firstStars = await pixels(stars);
      expect(firstGlow.toSet().length, greaterThan(32), reason: 'The real glow asset must render, not a fallback');
      final firstTransform = List<double>.of(
        tester
            .widget<Transform>(
              find.descendant(of: snow, matching: find.byKey(const ValueKey('blizzard_aurora_glow_transform'))),
            )
            .transform
            .storage,
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(listEquals(await pixels(glow), firstGlow), isTrue, reason: 'The shell glow is intentionally static');
      expect(listEquals(await pixels(stars), firstStars), isTrue, reason: 'The stars are a cached static layer');
      expect(
        tester
            .widget<Transform>(
              find.descendant(of: snow, matching: find.byKey(const ValueKey('blizzard_aurora_glow_transform'))),
            )
            .transform
            .storage,
        firstTransform,
      );
      expect(tester.getRect(button), initialButton);
      expect(tester.getRect(dock), initialDock);
      expect(tester.binding.transientCallbackCount, 0, reason: 'Static Home must not run a Flutter ambient clock');
      final nativeControl = find.descendant(of: button, matching: find.byType(BlizzardNativeConnectionControl));
      expect(nativeControl, findsOneWidget);
      expect(find.descendant(of: nativeControl, matching: find.byType(UiKitView)), findsOneWidget);
      expect(tester.widget<BlizzardNativeConnectionControl>(nativeControl).enabled, isTrue);
      expect(tester.widget<BlizzardNativeConnectionControl>(nativeControl).connectionState, 'connected');
      expect(tester.widget<BlizzardNativeConnectionControl>(nativeControl).label, isNotEmpty);
      expect(tester.widget<TickerMode>(shellRouteTicker).enabled, isTrue);
      expect(tester.widget<TickerMode>(shellVisibilityTicker).enabled, isTrue);

      final shown = showModalBottomSheet<void>(
        context: rootNavKey.currentContext!,
        builder: (_) => const SizedBox(height: 120, child: Text('root sheet')),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<TickerMode>(shellRouteTicker).enabled, isFalse);
      expect(TickerMode.of(tester.element(nativeControl)), isFalse);
      expect(tester.binding.hasScheduledFrame, isFalse);
      Navigator.of(rootNavKey.currentContext!, rootNavigator: true).pop();
      await shown;
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<TickerMode>(shellRouteTicker).enabled, isTrue);
      expect(TickerMode.of(tester.element(nativeControl)), isTrue);
      expect(tester.binding.transientCallbackCount, 0, reason: 'Returning to static Home must not restart a clock');

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
      expect(tester.binding.transientCallbackCount, 0, reason: 'Returning to static Home must not restart a clock');
      expect(find.byType(BlizzardScene), findsOneWidget);
      expect(listEquals(await pixels(glow), firstGlow), isTrue);
      expect(listEquals(await pixels(stars), firstStars), isTrue);
      expect(fixture.events, isEmpty);
      expect(tester.takeException(), isNull);
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

  expect(timings, isNotEmpty, reason: 'The native renderer must report actual transition frames for $label');
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
