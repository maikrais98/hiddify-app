import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_scene.dart';
import 'package:hiddify/features/home/widget/home_page.dart';

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

  _testIosWidgets('actual Home keeps the fullscreen snowfall and local connection envelope moving', (tester) async {
    final fixture = await mountHomeFixture(tester, child: _appliedHome());
    addTearDown(() => fixture.close(tester));

    final scenes = tester.widgetList<BlizzardScene>(find.byType(BlizzardScene)).toList(growable: false);

    expect(scenes, hasLength(2));
    expect(scenes.where((scene) => _motionPresets.contains(scene.preset)).map((scene) => scene.preset), [
      BlizzardParticlePreset.snowfall,
      BlizzardParticlePreset.envelope,
    ]);
    expect(
      tester.widget<BlizzardScene>(find.byKey(const ValueKey('blizzard_shell_snowfall'))).preset,
      BlizzardParticlePreset.snowfall,
    );
  });

  _testIosWidgets('root modal pauses both actual Home Aurora clocks until dismissal', (tester) async {
    final fixture = await mountHomeFixture(tester, child: _appliedHome());
    addTearDown(() => fixture.close(tester));
    final envelope = find.byKey(const ValueKey('blizzard_home_wave_envelope'));
    final envelopeScene = find.descendant(of: envelope, matching: find.byType(BlizzardScene));
    final shellScene = find.byKey(const ValueKey('blizzard_shell_snowfall'));
    final shellRouteTicker = find.byKey(const ValueKey('blizzard_shell_root_route_gate'));

    expect(envelopeScene, findsOneWidget);
    expect(shellScene, findsOneWidget);
    expect(shellRouteTicker, findsOneWidget);
    expect(TickerMode.of(tester.element(envelopeScene)), isTrue);
    expect(tester.widget<TickerMode>(shellRouteTicker).enabled, isTrue);

    final shown = showModalBottomSheet<void>(
      context: rootNavKey.currentContext!,
      builder: (_) => const SizedBox(height: 120, child: Text('root sheet')),
    );
    await tester.pump();

    expect(TickerMode.of(tester.element(envelopeScene)), isFalse);
    expect(tester.widget<TickerMode>(shellRouteTicker).enabled, isFalse);

    Navigator.of(rootNavKey.currentContext!, rootNavigator: true).pop();
    await shown;
    await tester.pump();
    expect(TickerMode.of(tester.element(envelopeScene)), isTrue);
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

const _motionPresets = {BlizzardParticlePreset.hero, BlizzardParticlePreset.envelope, BlizzardParticlePreset.snowfall};

Widget _appliedHome() => Builder(
  builder: (context) => Theme(
    data: BlizzardTheme.from(Theme.of(context)).copyWith(platform: TargetPlatform.iOS),
    child: const HomePage(),
  ),
);
