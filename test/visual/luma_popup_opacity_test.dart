import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
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
import 'package:hiddify/core/widget/blizzard/blizzard_tooltip.dart';
import 'package:hiddify/features/app_update/widget/store_upgrade_alert.dart';
import 'package:hiddify/features/log/overview/logs_page.dart';
import 'package:hiddify/features/profile/details/json_editor.dart';
import 'package:logging/logging.dart';
import 'package:upgrader/upgrader.dart';

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

class _OfflineUpgrader extends Upgrader {
  _OfflineUpgrader({required this.requiredUpdate});

  final bool requiredUpdate;
  int shown = 0;
  int ignored = 0;
  int openedStore = 0;

  @override
  Future<bool> initialize() async => true;

  @override
  bool blocked() => requiredUpdate;

  @override
  Future<bool> saveLastAlerted() async {
    shown++;
    return true;
  }

  @override
  Future<bool> saveIgnored() async {
    ignored++;
    return true;
  }

  @override
  void sendUserToAppStore() => openedStore++;
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

  for (final requiredUpdate in [false, true]) {
    testWidgets('upgrade prompt is opaque and honors mandatory updates (required=$requiredUpdate)', (tester) async {
      final probe = _Probe(tester);
      final upgrader = _OfflineUpgrader(requiredUpdate: requiredUpdate);
      final key = GlobalKey<UpgradeAlertState>();
      final fixture = await probe.mount(
        style: BlizzardMenuStyle.glass,
        content: StoreUpgradeAlert(key: key, upgrader: upgrader, child: const SizedBox.expand()),
      );
      final messages = UpgraderMessages(code: 'en');
      void show() => key.currentState!.showTheDialog(
        context: tester.element(find.byKey(key)),
        title: 'Update',
        message: 'Version available',
        releaseNotes: 'Offline release notes',
        barrierDismissible: false,
        messages: messages,
      );

      show();
      await tester.pump();
      final dialog = find.byType(AlertDialog);
      for (final elapsed in [16, 34, 200]) {
        await tester.pump(Duration(milliseconds: elapsed));
        final card = find.ancestor(of: find.text('Version available'), matching: find.byType(Material)).first;
        final box = tester.getRect(card);
        await probe.opaqueAt(Offset(box.left + 12, box.center.dy), 'upgrade frame after ${elapsed}ms');
      }
      expect(find.text('Offline release notes'), findsOneWidget);
      final later = find.text(messages.message(UpgraderMessage.buttonTitleLater)!);
      final ignore = find.text(messages.message(UpgraderMessage.buttonTitleIgnore)!);
      final update = find.text(messages.message(UpgraderMessage.buttonTitleUpdate)!);
      expect(later, requiredUpdate ? findsNothing : findsOneWidget);
      expect(ignore, requiredUpdate ? findsNothing : findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(dialog, findsOneWidget);
      await tester.tap(update);
      await tester.pump();
      expect(upgrader.openedStore, 1);
      expect(dialog, requiredUpdate ? findsOneWidget : findsNothing);
      if (!requiredUpdate) {
        show();
        await tester.pump();
        await tester.tap(later);
        await tester.pump();
        expect(dialog, findsNothing);
        expect(upgrader.ignored, 0);
        show();
        await tester.pump();
        await tester.tap(ignore);
        await tester.pump();
        expect(dialog, findsNothing);
        expect(upgrader.ignored, 1);
      }
      expect(upgrader.shown, requiredUpdate ? 1 : 3);
      await fixture.close(tester);
    });
  }

  for (final style in BlizzardMenuStyle.values) {
    testWidgets('a tooltip stays opaque on its first frame [${style.name}]', (tester) async {
      final probe = _Probe(tester);
      final fixture = await probe.mount(
        style: style,
        content: const Center(
          child: BlizzardTooltip(message: 'Status information', child: Text('Status')),
        ),
      );
      final trigger = find.text('Status');
      expect(tester.getSemantics(trigger).getSemanticsData().tooltip, 'Status information');
      await tester.longPress(trigger);
      await tester.pump();
      final text = find.text('Status information', findRichText: true);
      for (final elapsed in [16, 34, 200]) {
        await tester.pump(Duration(milliseconds: elapsed));
        final surface = find.ancestor(of: text, matching: find.byType(DecoratedBox)).first;
        final box = tester.getRect(surface);
        await probe.opaqueAt(Offset(box.left + 5, box.center.dy), 'tooltip frame after ${elapsed}ms');
      }
      await tester.tapAt(const Offset(30, 30));
      await tester.pump();
      expect(text, findsNothing);
      await fixture.close(tester);
    });
  }

  testWidgets('Escape dismisses a hovered tooltip without moving focus', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var escapes = 0;
    final probe = _Probe(tester);
    final fixture = await probe.mount(
      style: BlizzardMenuStyle.glass,
      content: Center(
        child: Focus(
          focusNode: focus,
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape) {
              return KeyEventResult.ignored;
            }
            escapes++;
            return KeyEventResult.handled;
          },
          child: const BlizzardTooltip(message: 'Hover hint', child: Text('Tooltip target')),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Tooltip target')));
    await tester.pump();
    final tooltip = find.text('Hover hint', findRichText: true);
    expect(tooltip, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 180));
    expect(tooltip, findsNothing);
    expect(focus.hasPrimaryFocus, isTrue);
    expect(escapes, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(escapes, 1);
    await mouse.removePointer();
    await fixture.close(tester);
  });

  testWidgets(
    'JSON choice has button semantics and initially focuses the current value',
    (tester) async {
      final probe = _Probe(tester);
      final fixture = await probe.mount(style: BlizzardMenuStyle.glass, content: _editor());
      final trigger = find.byKey(const ValueKey('json-value-dropdown'));
      final current = find.descendant(of: trigger, matching: find.text('tcp'));
      Focus.of(tester.element(current)).requestFocus();
      await tester.pump();
      final data = tester.getSemantics(current).getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      final items = find.byType(PopupMenuItem<String>);
      final selected = find.descendant(of: items, matching: find.text('tcp'));
      final focusedOnCurrent = Focus.of(tester.element(selected)).hasFocus;
      expect((data.flagsCollection.isButton, focusedOnCurrent), (true, true));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(items, findsNothing);
      expect(Focus.of(tester.element(current)).hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(tester.widget<PopupMenuButton<String>>(trigger).initialValue, 'udp');
      await fixture.close(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

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
