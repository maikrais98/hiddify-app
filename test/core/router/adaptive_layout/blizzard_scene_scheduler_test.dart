import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_scene.dart';
import 'package:hiddify/features/home/widget/home_page.dart';

import '../../../support/blizzard_capture.dart';
import '../../../support/home_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (_) async => null,
    );
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        null,
      );
    });
  });

  _testIosWidgets('actual Home keeps one fullscreen snowfall behind the fixed control and native views', (tester) async {
    final fixture = await mountHomeFixture(tester, child: _appliedHome());
    addTearDown(() => fixture.close(tester));

    final scenes = tester.widgetList<BlizzardScene>(find.byType(BlizzardScene)).toList(growable: false);
    final snow = find.byKey(const ValueKey('blizzard_shell_snowfall'));
    final envelope = find.byKey(const ValueKey('blizzard_home_wave_envelope'));
    final button = find.byKey(const ValueKey('home_connection_button'));
    final nativeViewTypes = tester.widgetList<UiKitView>(find.byType(UiKitView)).map((view) => view.viewType);

    expect(scenes, hasLength(1));
    expect(scenes.single.preset, BlizzardParticlePreset.snowfall);
    expect(snow, findsOneWidget);
    expect(envelope, findsOneWidget, reason: 'The reserved Home geometry slot must remain in place');
    expect(find.descendant(of: envelope, matching: find.byType(BlizzardScene)), findsNothing);
    expect(tester.getRect(snow), tester.getRect(find.byKey(blizzardFixtureCanvas)));
    expect(tester.getSize(button), const Size.square(148));
    expect(
      nativeViewTypes,
      containsAll(['app.blizzard/native-connection-control', 'app.blizzard/native-liquid-glass']),
    );
  });

  _testIosWidgets('root modal pauses the actual Home Aurora clock until dismissal', (tester) async {
    final fixture = await mountHomeFixture(tester, child: _appliedHome());
    addTearDown(() => fixture.close(tester));
    final shellScene = find.byKey(const ValueKey('blizzard_shell_snowfall'));
    final shellRouteTicker = find.byKey(const ValueKey('blizzard_shell_root_route_gate'));

    expect(shellScene, findsOneWidget);
    expect(find.byType(BlizzardScene), findsOneWidget);
    expect(shellRouteTicker, findsOneWidget);
    expect(tester.widget<TickerMode>(shellRouteTicker).enabled, isTrue);

    final shown = showModalBottomSheet<void>(
      context: rootNavKey.currentContext!,
      builder: (_) => const SizedBox(height: 120, child: Text('root sheet')),
    );
    await tester.pump();

    expect(tester.widget<TickerMode>(shellRouteTicker).enabled, isFalse);

    Navigator.of(rootNavKey.currentContext!, rootNavigator: true).pop();
    await shown;
    await tester.pump();
    expect(tester.widget<TickerMode>(shellRouteTicker).enabled, isTrue);
  });
}

void _testIosWidgets(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    try {
      await callback(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Widget _appliedHome() => Builder(
  builder: (context) => Theme(
    data: BlizzardTheme.from(Theme.of(context)).copyWith(platform: TargetPlatform.iOS),
    child: const HomePage(),
  ),
);
