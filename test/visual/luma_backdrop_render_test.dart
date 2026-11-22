import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_presentation.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/settings/overview/sections/general_page.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';

import '../support/blizzard_capture.dart';
import '../support/home_fixture.dart';

// Render script, not an assertion suite: with LUMA_RENDER_DIR set it writes
// 440x956 @3x PNGs of the Aurora surfaces under review. Without it the screens are
// only built, which keeps them from rotting.
Widget _aurora(Widget child) => Builder(
  builder: (context) => Theme(data: BlizzardTheme.from(Theme.of(context)), child: child),
);

final _profiles = [
  ProfileEntity.remote(
    id: 'a',
    active: true,
    name: 'Akonit Premium',
    url: 'https://example.invalid/first',
    lastUpdate: DateTime.utc(2026),
  ),
  ProfileEntity.remote(
    id: 'b',
    active: false,
    name: 'Second subscription',
    url: 'https://example.invalid/second',
    lastUpdate: DateTime.utc(2026),
  ),
];

Future<void> _snap(WidgetTester tester, String name) async {
  final dir = Platform.environment['LUMA_RENDER_DIR'];
  if (dir == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(blizzardFixtureCanvas));
  final layer = boundary.debugLayer! as OffsetLayer;
  final bytes = await tester.runAsync(() async {
    final image = await layer.toImage(boundary.paintBounds, pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  Directory(dir).createSync(recursive: true);
  File('$dir/$name.png').writeAsBytesSync(bytes!);
}

Future<void> _settle(WidgetTester tester) async {
  // The scene image decodes off the test clock.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 600));
}

void _view(WidgetTester tester) {
  tester.view.physicalSize = const Size(440 * 3, 956 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _loadRenderFonts() async {
  // Readable glyphs instead of the Ahem boxes of the test font.
  final root = Platform.environment['FLUTTER_ROOT'];
  Future<ByteData> font(String name) async =>
      ByteData.sublistView(File('$root/bin/cache/artifacts/material_fonts/$name').readAsBytesSync());
  for (final family in ['.SF Pro Text', '.SF Pro Display']) {
    final loader = FontLoader(family);
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      loader.addFont(font('Roboto-$weight.ttf'));
    }
    await loader.load();
  }
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())))).load();
  }
}

void main() {
  setUpAll(_loadRenderFonts);
  setUp(() => BlizzardPresentation.debugAssumeIOS = true);
  tearDown(() => BlizzardPresentation.debugAssumeIOS = false);

  testWidgets('render settings', (tester) async {
    _view(tester);
    final fixture = await mountHomeFixture(
      tester,
      width: 440,
      height: 956,
      nativeViewport: true,
      child: _aurora(SettingsPage()),
    );
    await _settle(tester);
    await _snap(tester, 'settings');
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('render general', (tester) async {
    _view(tester);
    final fixture = await mountHomeFixture(
      tester,
      width: 440,
      height: 956,
      nativeViewport: true,
      child: _aurora(const GeneralPage()),
    );
    await _settle(tester);
    await _snap(tester, 'general');
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  for (final sheet in ['profiles', 'quick-settings']) {
    testWidgets('render $sheet sheet', (tester) async {
      _view(tester);
      final fixture = await mountHomeFixture(
        tester,
        width: 440,
        height: 956,
        nativeViewport: true,
        extraOverrides: [profilesNotifierProvider.overrideWith(() => TileProfilesSpy()..profiles = _profiles)],
      );
      final notifier = fixture.container.read(bottomSheetsNotifierProvider.notifier);
      final shown = sheet == 'profiles' ? notifier.showProfilesOverview() : notifier.showQuickSettings();
      await _settle(tester);
      await _snap(tester, '$sheet-sheet');
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await shown;
      await fixture.close(tester);
    });
  }
}
