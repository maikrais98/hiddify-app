import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/logger/logger_setup.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_presentation.dart';
import 'package:hiddify/features/log/overview/logs_page.dart';
import 'package:hiddify/features/profile/details/json_editor.dart';
import 'package:logging/logging.dart';

import '../support/blizzard_capture.dart';
import '../support/home_fixture.dart';

const _red = Color(0xFFFF0000);
const _blue = Color(0xFF0000FF);

class _DelayedAurora extends CachingAssetBundle {
  final requested = Completer<void>();
  final release = Completer<void>();

  @override
  Future<ByteData> load(String key) async {
    if (key == 'assets/images/luma_aurora_popup.png') {
      if (!requested.isCompleted) requested.complete();
      await release.future;
    }
    return rootBundle.load(key);
  }
}

class _Probe {
  _Probe(this.tester);

  final WidgetTester tester;
  final homeColor = ValueNotifier(_red);
  late ScaffoldMessengerState messenger;

  Future<HomeFixture> mount({
    required BlizzardMenuStyle style,
    Widget? content,
    AssetBundle? assetBundle,
    bool disableAnimations = false,
  }) async {
    addTearDown(homeColor.dispose);
    tester.view.physicalSize = const Size(440, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = await mountHomeFixture(
      tester,
      width: 440,
      height: 780,
      nativeViewport: true,
      disableAnimations: disableAnimations,
      assetBundle: assetBundle,
      child: SnackBarHost(
        child: Builder(
          builder: (context) {
            messenger = ScaffoldMessenger.of(context);
            return Stack(
              fit: StackFit.expand,
              children: [
                if (content != null) content,
                IgnorePointer(
                  child: ValueListenableBuilder<Color>(
                    valueListenable: homeColor,
                    builder: (context, value, _) => ColoredBox(color: value),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    await fixture.container.read(Preferences.menuStyle.notifier).update(style);
    await tester.pump();
    if (style == BlizzardMenuStyle.glass && assetBundle == null) {
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/images/luma_aurora_popup.png'),
          tester.element(find.byKey(blizzardFixtureCanvas)),
        ),
      );
    }
    return fixture;
  }

  Future<List<int>> _pixel(Offset point) async {
    final canvas = find.byKey(blizzardFixtureCanvas);
    final boundary = tester.renderObject<RenderRepaintBoundary>(canvas);
    final relative = point - tester.getTopLeft(canvas);
    return (await tester.runAsync(() async {
      final image = await boundary.toImage();
      try {
        final pixels = (await image.toByteData())!;
        final index = 4 * (image.width * relative.dy.floor() + relative.dx.floor());
        return [for (var channel = 0; channel < 3; channel++) pixels.getUint8(index + channel)];
      } finally {
        image.dispose();
      }
    }))!;
  }

  Future<void> opaqueAt(Offset point, String frame) async {
    homeColor.value = _red;
    await tester.pump();
    final red = await _pixel(point);
    homeColor.value = _blue;
    await tester.pump();
    final blue = await _pixel(point);
    final difference = List.generate(3, (i) => (red[i] - blue[i]).abs()).reduce((a, b) => a + b);
    expect(difference, lessThanOrEqualTo(3), reason: 'Home changes the pixel at $point on $frame ($red vs $blue)');
  }

  Future<void> checkFrames(Finder surface, VoidCallback close, {Finder? marker}) async {
    // Prime the route and sample the visible part of its panel. Repaint it
    // over two backgrounds without advancing the transition between reads.
    await tester.pump();
    final present = marker ?? surface;
    final viewport = tester.getRect(find.byKey(blizzardFixtureCanvas));
    Future<bool> sample(String frame) async {
      if (present.evaluate().isEmpty) return false;
      final visible = tester.getRect(surface).intersect(viewport);
      if (visible.width < 8 || visible.height < 8) return false;
      await opaqueAt(visible.center, frame);
      return true;
    }

    var count = 0;
    for (final elapsed in [16, 34, 50, 250]) {
      await tester.pump(Duration(milliseconds: elapsed));
      expect(surface, findsOneWidget);
      if (await sample('entry frame after ${elapsed}ms')) count++;
    }
    expect(count, greaterThanOrEqualTo(2));
    close();
    for (final elapsed in [0, 16, 34, 50, 250]) {
      await tester.pump(Duration(milliseconds: elapsed));
      await sample('exit frame after ${elapsed}ms');
    }
    expect(present, findsNothing);
  }
}

Widget _editor() => Align(
  alignment: Alignment.topCenter,
  child: JsonEditor(
    json: '{"outbounds":{"network":"tcp"}}',
    expandedObjects: const ['outbounds'],
    onChanged: (_) {},
    enableMoreOptions: false,
    enableHorizontalScroll: true,
  ),
);

void main() {
  setUp(() => BlizzardPresentation.debugAssumeIOS = true);
  tearDown(() => BlizzardPresentation.debugAssumeIOS = false);

  for (final style in BlizzardMenuStyle.values) {
    testWidgets('dialog stays opaque on every sampled frame [${style.name}]', (tester) async {
      final probe = _Probe(tester);
      final fixture = await probe.mount(style: style);
      final closed = fixture.container
          .read(dialogNotifierProvider.notifier)
          .showConfirmation(title: 'Continue?', message: 'Changes will be saved.');
      final dialog = find.byType(Dialog);
      await probe.checkFrames(dialog, () => Navigator.of(tester.element(dialog)).pop());
      await closed;
      await fixture.close(tester);
    });

    testWidgets('popup menu stays opaque on every sampled frame [${style.name}]', (tester) async {
      final probe = _Probe(tester);
      final fixture = await probe.mount(style: style, content: _editor());
      await tester.tap(find.byTooltip('Change editor'));
      final items = find.byType(PopupMenuItem<Editors>);
      final menu = find.ancestor(of: items.last, matching: find.byType(Material)).first;
      await probe.checkFrames(menu, () => Navigator.of(tester.element(menu)).pop(), marker: items);
      await fixture.close(tester);
    });

    testWidgets('log row context menu stays opaque on every sampled frame [${style.name}]', (tester) async {
      logRing.clear();
      addTearDown(logRing.clear);
      const record = 'Synthetic log entry';
      logRing.add(LogRecord(Level.WARNING, record, 'app.opacity'));
      final probe = _Probe(tester);
      final fixture = await probe.mount(style: style, content: const LogsPage());
      await tester.longPress(find.text(record));
      final item = find.byType(PopupMenuItem<bool>);
      final menu = find.ancestor(of: item, matching: find.byType(Material)).first;
      await probe.checkFrames(menu, () => Navigator.of(tester.element(menu)).pop(), marker: item);
      await fixture.close(tester);
    });

    testWidgets('JSON dropdown stays opaque on every sampled frame [${style.name}]', (tester) async {
      final probe = _Probe(tester);
      final fixture = await probe.mount(style: style, content: _editor());
      await tester.tap(find.byKey(const ValueKey('json-value-dropdown')));
      final option = find.text('udp');
      final menu = find.ancestor(of: option, matching: find.byType(Scrollable)).first;
      await probe.checkFrames(menu, () => Navigator.of(tester.element(menu)).pop(), marker: option);
      await fixture.close(tester);
    });

    testWidgets('floating snackbar stays opaque on every sampled frame [${style.name}]', (tester) async {
      final probe = _Probe(tester);
      final fixture = await probe.mount(style: style);
      showAppSnackBar(probe.messenger, 'Changes saved');
      final bar = find.byType(SnackBar);
      final surface = find.descendant(of: bar, matching: find.byType(Material)).first;
      await probe.checkFrames(surface, probe.messenger.hideCurrentSnackBar, marker: bar);
      await fixture.close(tester);
    });

    testWidgets('sheet stays opaque on every sampled frame [${style.name}]', (tester) async {
      final probe = _Probe(tester);
      final fixture = await probe.mount(style: style);
      final closed = fixture.container.read(bottomSheetsNotifierProvider.notifier).showQuickSettings();
      final sheet = find.byType(BottomSheet);
      await probe.checkFrames(sheet, () => Navigator.of(tester.element(sheet)).pop());
      await closed;
      await fixture.close(tester);
    });
  }

  for (final style in BlizzardMenuStyle.values) {
    for (final highContrast in [false, true]) {
      testWidgets('profile action tooltip uses opaque Aurora colors [${style.name}, contrast=$highContrast]', (
        tester,
      ) async {
        final fixture = await mountHomeFixture(tester, highContrast: highContrast);
        await fixture.container.read(Preferences.menuStyle.notifier).update(style);
        final tooltip = (await fixture.container.read(translationsProvider.future)).common.sort;
        final closed = fixture.container.read(bottomSheetsNotifierProvider.notifier).showProfilesOverview();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.longPress(find.byTooltip(tooltip));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        final label = find.text(tooltip, findRichText: true);
        expect(label, findsOneWidget);
        final background = tester.widget<DecoratedBox>(
          find.ancestor(of: label, matching: find.byType(DecoratedBox)).first,
        );
        final fill = (background.decoration as BoxDecoration).color;
        expect(fill, highContrast ? BlizzardPalette.background : BlizzardPalette.sheet);
        expect(tester.widget<RichText>(label).text.style!.color, BlizzardPalette.primary);
        Navigator.of(tester.element(find.byType(BottomSheet))).pop();
        await tester.pump(const Duration(milliseconds: 350));
        await closed;
        await fixture.close(tester);
      });
    }
  }

  testWidgets('Reduce Motion opens and closes a sheet on its first frame', (tester) async {
    final probe = _Probe(tester);
    final fixture = await probe.mount(style: BlizzardMenuStyle.glass, disableAnimations: true);
    final closed = fixture.container.read(bottomSheetsNotifierProvider.notifier).showQuickSettings();
    await tester.pump();
    final sheet = find.byType(BottomSheet);
    final initial = tester.getRect(sheet);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getRect(sheet), initial);
    Navigator.of(tester.element(sheet)).pop();
    await tester.pump();
    expect(sheet, findsNothing);
    await closed;
    await fixture.close(tester);
  });

  testWidgets('the first glass dialog stays opaque while its PNG is held and Reduce Motion is active', (tester) async {
    final artwork = _DelayedAurora();
    final probe = _Probe(tester);
    final fixture = await probe.mount(style: BlizzardMenuStyle.glass, assetBundle: artwork, disableAnimations: true);
    final closed = fixture.container
        .read(dialogNotifierProvider.notifier)
        .showConfirmation(title: 'Cold start', message: 'The artwork is still decoding.');
    await tester.pump();
    final dialog = find.byType(Dialog);
    final image = find.descendant(of: dialog, matching: find.byType(RawImage));
    expect(artwork.requested.isCompleted, isTrue);
    expect(tester.widget<RawImage>(image).image, isNull);
    for (final elapsed in [0, 16, 34]) {
      await tester.pump(Duration(milliseconds: elapsed));
      await probe.opaqueAt(tester.getCenter(dialog), 'cold frame with no texture');
    }
    artwork.release.complete();
    final texture = find.descendant(of: dialog, matching: find.byType(Image));
    await tester.runAsync(() => precacheImage(tester.widget<Image>(texture).image, tester.element(texture)));
    await tester.pump();
    expect(tester.widget<RawImage>(image).image, isNotNull);
    await probe.opaqueAt(tester.getCenter(dialog), 'decoded frame');
    Navigator.of(tester.element(dialog)).pop();
    await tester.pump();
    expect(dialog, findsNothing);
    await closed;
    await fixture.close(tester);
  });
}
