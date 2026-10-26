import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';

import '../support/blizzard_capture.dart';
import '../support/home_fixture.dart';
import '../support/surface_fixtures.dart';

const _captureDirectory = String.fromEnvironment('BLIZZARD_CAPTURE_DIR');

Widget _underLuma(Widget child) => Builder(
  builder: (context) => Theme(data: BlizzardTheme.from(Theme.of(context)), child: child),
);

Future<void> _capture(WidgetTester tester, String label) async {
  if (_captureDirectory.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(blizzardFixtureCanvas));
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(_captureDirectory);
      await directory.create(recursive: true);
      await File('${directory.path}/$label.png').writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _scrollAndExpectNoOverflow(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isEmpty) return;

  final scrollable = scrollables.first;
  for (var step = 0; step < 20; step++) {
    final position = tester.state<ScrollableState>(scrollable).position;
    if (!position.hasContentDimensions || position.pixels >= position.maxScrollExtent - 1) break;
    await tester.drag(scrollable, const Offset(0, -240));
    await tester.pump();
    expect(tester.takeException(), isNull);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final surfaces = <String, Widget>{'overview': SettingsPage(), ...settingsSurfaces};

  for (final scale in [1.0, 2.0]) {
    for (final entry in surfaces.entries) {
      testWidgets('Luma ${entry.key} preserves layout at 320pt and ${scale}x text', (tester) async {
        final fixture = await mountHomeFixture(tester, width: 320, scale: scale, child: _underLuma(entry.value));

        await _capture(tester, 'luma-settings-${entry.key}-320-${scale}x-top');
        await _scrollAndExpectNoOverflow(tester);
        await _capture(tester, 'luma-settings-${entry.key}-320-${scale}x-bottom');

        expect(find.byType(entry.value.runtimeType), findsOneWidget);
        expect(tester.takeException(), isNull);
        await fixture.close(tester);
      });
    }
  }
}
