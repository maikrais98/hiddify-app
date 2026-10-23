import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_scene.dart';
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

  testWidgets('native snowfall spans status bar through dock without moving Home controls', (tester) async {
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
      expect(snow, findsOneWidget);
      expect(tester.getRect(snow), tester.getRect(canvas));
      final button = find.byKey(const ValueKey('home_connection_button'));
      final dock = find.byKey(const ValueKey('blizzard_bottom_dock'));
      final initialButton = tester.getRect(button);
      final initialDock = tester.getRect(dock);
      expect(initialButton.size, const Size(148, 148));

      Future<List<int>> pixels() async {
        final image = await tester.renderObject<RenderRepaintBoundary>(canvas).toImage();
        try {
          return (await image.toByteData())!.buffer.asUint8List().toList();
        } finally {
          image.dispose();
        }
      }

      final first = await pixels();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
      await tester.pump();
      final next = await pixels();
      for (final region in [
        Rect.fromLTWH(0, 0, viewport.width, 100),
        Rect.fromLTWH(0, viewport.height - 90, viewport.width, 90),
      ]) {
        var changed = 0;
        for (var y = region.top.toInt(); y < region.bottom.toInt(); y++) {
          for (var x = region.left.toInt(); x < region.right.toInt(); x++) {
            final p = (y * viewport.width.toInt() + x) * 4;
            if ((first[p + 2] - next[p + 2]).abs() > 4) changed++;
          }
        }
        expect(changed, greaterThan(15), reason: 'Snow must move outside the body, including $region');
      }
      expect(tester.getRect(button), initialButton);
      expect(tester.getRect(dock), initialDock);
      await tester.tap(button);
      await tester.pump();
      expect(fixture.events, ['toggle']);
      final clock = tester
          .widgetList<CustomPaint>(find.descendant(of: snow, matching: find.byType(CustomPaint)))
          .single;
      expect(clock.willChange, isTrue);
      await activateFixtureDockDestination(tester, 1);
      await tester.pump(const Duration(seconds: 1));
      final ticker = find.ancestor(of: snow, matching: find.byType(TickerMode)).first;
      final opacity = find.ancestor(of: snow, matching: find.byType(Opacity)).first;
      expect(tester.widget<TickerMode>(ticker).enabled, isFalse);
      expect(tester.widget<Opacity>(opacity).opacity, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await activateFixtureDockDestination(tester, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<TickerMode>(ticker).enabled, isTrue);
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
  geometry.main();
}
