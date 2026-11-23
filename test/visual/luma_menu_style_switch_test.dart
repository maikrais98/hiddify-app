import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/adaptive_menu.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_popup.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_presentation.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_scene_glass.dart';
import 'package:hiddify/features/chain/overview/chain_mode_menu.dart';
import 'package:hiddify/features/home/widget/home_page.dart';
import 'package:hiddify/features/profile/details/json_editor.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../support/home_fixture.dart';

// The menu style is a user setting (Settings > General > Appearance): solid (the sheet's material)
// by default, glass on request, applied at once. Structural checks only, no pixel goldens.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 700));
}

Widget _aurora(Widget child) => Builder(
  builder: (context) => Theme(data: BlizzardTheme.from(Theme.of(context)), child: child),
);

Future<HomeFixture> _mount(WidgetTester tester, {Widget? child}) {
  tester.view.physicalSize = const Size(440 * 3, 956 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return mountHomeFixture(
    tester,
    width: 440,
    height: 956,
    nativeViewport: true,
    highContrast: null,
    locale: AppLocale.ru,
    child: child ?? const SizedBox.shrink(),
  );
}

Finder _textureIn(Finder scope) => find.descendant(of: scope, matching: find.byType(CompositedTransformFollower));

void _expectSurface(WidgetTester tester, Finder popup, {required bool glass, bool highContrast = false}) {
  expect(find.descendant(of: popup, matching: find.byType(BackdropFilter)), findsNothing);
  final material = find.descendant(of: popup, matching: find.byType(BlizzardSceneGlass));
  expect(material, findsOneWidget);
  final painted = tester.widget<DecoratedBox>(find.descendant(of: material, matching: find.byType(DecoratedBox)).first);
  final decoration = painted.decoration as BoxDecoration;
  expect(decoration.color, highContrast ? BlizzardPalette.background : BlizzardPalette.sheet);
  expect(decoration.color!.a, 1);
  expect(_textureIn(material), glass && !highContrast ? findsOneWidget : findsNothing);
}

void main() {
  setUp(() {
    BlizzardPresentation.debugAssumeIOS = true;
  });
  tearDown(() {
    BlizzardPresentation.debugAssumeIOS = false;
  });

  testWidgets('the setting defaults to the solid style, never the old one', (tester) async {
    final fixture = await _mount(tester);
    expect(fixture.container.read(Preferences.menuStyle), BlizzardMenuStyle.neutral);
    await fixture.close(tester);
  });

  testWidgets('changing the Aurora breakpoint preserves the page draft and focus', (tester) async {
    final width = ValueNotifier(440.0);
    addTearDown(width.dispose);
    final baseTheme = AppTheme(AppThemeMode.dark, 'Roboto').darkTheme(null);
    final fixture = await _mount(
      tester,
      child: ValueListenableBuilder<double>(
        valueListenable: width,
        builder: (context, value, child) => Theme(
          data: baseTheme,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(size: Size(value, 956)),
            child: BlizzardPresentation(child: child!),
          ),
        ),
        child: const Material(child: TextField()),
      ),
    );
    final editable = find.byType(EditableText);
    bool applied() => Theme.of(tester.element(editable)).extension<BlizzardEligibility>()!.applied;
    expect(applied(), isTrue);
    await tester.enterText(editable, 'draft');
    final field = tester.state<EditableTextState>(editable);
    for (final nextWidth in [640.0, 440.0]) {
      width.value = nextWidth;
      await tester.pump();
      expect(applied(), nextWidth == 440);
      expect(tester.state<EditableTextState>(editable), same(field));
      expect(field.widget.controller.text, 'draft');
      expect(field.widget.focusNode.hasFocus, isTrue);
    }
    await fixture.close(tester);
  });

  testWidgets('a dialog changes its material as soon as the setting changes', (tester) async {
    final fixture = await _mount(tester, child: _aurora(SettingsPage()));
    await _settle(tester);
    final dialogs = fixture.container.read(dialogNotifierProvider.notifier);
    final shown = dialogs.showConfirmation(title: 'Заголовок', message: 'Сообщение');
    await _settle(tester);
    _expectSurface(tester, find.byType(Dialog), glass: false);

    await fixture.container.read(Preferences.menuStyle.notifier).update(BlizzardMenuStyle.glass);
    await _settle(tester);
    _expectSurface(tester, find.byType(Dialog), glass: true);

    await fixture.container.read(Preferences.menuStyle.notifier).update(BlizzardMenuStyle.neutral);
    await _settle(tester);
    _expectSurface(tester, find.byType(Dialog), glass: false);
    expect(tester.takeException(), isNull);

    Navigator.of(tester.element(find.byType(Dialog).first)).pop(false);
    await tester.pump(const Duration(milliseconds: 500));
    await shown;
    await fixture.close(tester);
  });

  testWidgets('a dialog keeps its editable field, focus and alert role across style and contrast changes', (
    tester,
  ) async {
    late BuildContext anchor;
    final fixture = await _mount(
      tester,
      child: BlizzardPresentation(
        child: Builder(
          builder: (context) {
            anchor = context;
            return const SizedBox();
          },
        ),
      ),
    );
    final editing = TextEditingController();
    addTearDown(editing.dispose);
    final result = showDialog<String>(
      context: anchor,
      builder: (context) => BlizzardPresentation(
        child: BlizzardAlertDialog(
          title: const Text('Input'),
          content: TextField(controller: editing, autofocus: true),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(editing.text), child: const Text('Save'))],
        ),
      ),
    );
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'draft');
    final field = tester.state<EditableTextState>(find.byType(EditableText));

    await fixture.container.read(Preferences.menuStyle.notifier).update(BlizzardMenuStyle.glass);
    await _settle(tester);
    expect(tester.state<EditableTextState>(find.byType(EditableText)), same(field));
    expect(field.widget.focusNode.hasFocus, isTrue);
    expect(tester.widget<Dialog>(find.byType(Dialog)).semanticsRole, SemanticsRole.alertDialog);
    _expectSurface(tester, find.byType(Dialog), glass: true);

    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(highContrast: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _settle(tester);
    expect(tester.state<EditableTextState>(find.byType(EditableText)), same(field));
    expect(field.widget.focusNode.hasFocus, isTrue);
    _expectSurface(tester, find.byType(Dialog), glass: true, highContrast: true);
    await tester.tap(find.text('Save'));
    expect(await result, 'draft');
    await fixture.close(tester);
  });

  testWidgets('a secondary action keeps the Aurora button style and its disabled color', (tester) async {
    final fixture = await _mount(
      tester,
      child: const BlizzardPresentation(
        child: BlizzardAlertDialog(
          title: Text('Title'),
          actions: [
            TextButton(onPressed: null, child: Text('Disabled')),
            TextButton(onPressed: null, child: Text('Primary')),
          ],
        ),
      ),
    );
    final context = tester.element(find.widgetWithText(TextButton, 'Disabled'));
    final actionStyle = TextButtonTheme.of(context).style!;
    final auroraStyle = Theme.of(context).textButtonTheme.style!;
    expect(actionStyle.padding, auroraStyle.padding);
    expect(actionStyle.foregroundColor!.resolve({WidgetState.disabled}), BlizzardPalette.disabled);
    expect(actionStyle.foregroundColor!.resolve({}), BlizzardPalette.secondary);
    await fixture.close(tester);
  });

  testWidgets('the visible snackbar uses the latest preference and goes opaque in high contrast', (tester) async {
    late ScaffoldMessengerState messenger;
    final fixture = await _mount(
      tester,
      child: SnackBarHost(
        child: Builder(
          builder: (context) {
            messenger = ScaffoldMessenger.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    showAppSnackBar(messenger, 'Changing style');
    await tester.pump(const Duration(milliseconds: 300));
    final bar = find.byType(SnackBar);
    Material background() => tester.widget<Material>(find.descendant(of: bar, matching: find.byType(Material)).first);
    expect(background().color, BlizzardPalette.sheet);

    await fixture.container.read(Preferences.menuStyle.notifier).update(BlizzardMenuStyle.glass);
    await tester.pump();
    expect(background().color, const Color(0xFF131416));

    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(highContrast: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    expect(background().color!.a, 1);
    await fixture.close(tester);
  });

  testWidgets('an open PopupMenuButton updates and keeps its surface 12 points from the edge', (tester) async {
    final fixture = await _mount(
      tester,
      child: BlizzardPresentation(
        child: Align(
          alignment: Alignment.topRight,
          child: PopupMenuButton<int>(
            itemBuilder: (context) => const [PopupMenuItem(value: 1, child: Text('Selection'))],
          ),
        ),
      ),
    );
    await tester.tap(find.byType(PopupMenuButton<int>));
    await _settle(tester);
    final card = find.ancestor(of: find.text('Selection'), matching: find.byType(Material)).first;
    final material = tester.widget<Material>(card);
    expect(material.color, BlizzardPalette.sheet);
    final rect = tester.getRect(card);
    expect(material.shape!.getOuterPath(rect).getBounds().right, lessThanOrEqualTo(428));

    await fixture.container.read(Preferences.menuStyle.notifier).update(BlizzardMenuStyle.glass);
    await _settle(tester);
    expect(tester.widget<Material>(card).color, const Color(0xFF131416));
    await fixture.close(tester);
  });

  testWidgets('the open JSON editor dropdown updates its palette and still commits the value', (tester) async {
    final fixture = await _mount(
      tester,
      child: BlizzardPresentation(
        child: Scaffold(
          body: JsonEditor(
            json: '{"outbounds":{"network":"tcp"}}',
            expandedObjects: const ['outbounds'],
            onChanged: (_) {},
            enableMoreOptions: false,
            enableHorizontalScroll: true,
          ),
        ),
      ),
    );
    final button = find.byKey(const ValueKey('json-value-dropdown'));
    final originalCanvas = Theme.of(tester.element(button)).canvasColor;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await _settle(tester);
    final option = find.text('udp');
    final card = find.ancestor(of: option, matching: find.byType(Material)).first;
    Color? menuColor() => tester.widget<Material>(card).color;
    expect(menuColor(), BlizzardPalette.sheet);

    await fixture.container.read(Preferences.menuStyle.notifier).update(BlizzardMenuStyle.glass);
    await _settle(tester);
    expect(menuColor(), const Color(0xFF131416));
    expect(Theme.of(tester.element(button)).canvasColor, originalCanvas);
    await tester.tap(option);
    await _settle(tester);
    expect(tester.widget<PopupMenuButton<String>>(button).initialValue, 'udp');
    await fixture.close(tester);
  });

  testWidgets('the Settings import submenu leaves 12 points on both sides', (tester) async {
    final fixture = await _mount(tester, child: _aurora(SettingsPage()));
    final t = fixture.container.read(translationsProvider).requireValue;
    await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.byType(IconButton)).last);
    await _settle(tester);
    await tester.tap(find.text(t.common.import));
    await _settle(tester);

    final submenu = find
        .ancestor(
          of: find.text(t.pages.settings.options.import.clipboard),
          matching: find.byType(BlizzardPopupMenuSurface),
        )
        .first;
    final surface = find.descendant(of: submenu, matching: find.byType(ClipRRect)).first;
    final outer = tester.getRect(submenu);
    final painted = tester.getRect(surface);
    expect(painted.left - outer.left, 12);
    expect(outer.right - painted.right, 12);
    expect(painted.left, greaterThanOrEqualTo(12));
    expect(painted.right, lessThanOrEqualTo(428));
    await fixture.close(tester);
  });

  testWidgets('Quick Settings and its anchored menu stay opaque in both styles and high contrast', (tester) async {
    final fixture = await _mount(tester, child: const HomePage());
    final styles = fixture.container.read(Preferences.menuStyle.notifier);
    final shown = fixture.container.read(bottomSheetsNotifierProvider.notifier).showQuickSettings();
    final sheet = find.byType(BottomSheet);
    final menu = find.byType(BlizzardPopupMenuSurface);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _settle(tester);
    _expectSurface(tester, sheet, glass: false);

    await tester.tap(find.byType(ChainModeMenu).first);
    await _settle(tester);
    _expectSurface(tester, menu, glass: false);
    await styles.update(BlizzardMenuStyle.glass);
    await _settle(tester);
    _expectSurface(tester, menu, glass: true);
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(highContrast: true);
    await _settle(tester);
    _expectSurface(tester, menu, glass: true, highContrast: true);

    await tester.tap(find.descendant(of: menu, matching: find.byType(MenuItemButton)).first);
    await _settle(tester);
    expect(menu, findsNothing);
    _expectSurface(tester, sheet, glass: true, highContrast: true);
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    await _settle(tester);
    _expectSurface(tester, sheet, glass: true);

    Navigator.of(tester.element(sheet)).pop();
    await tester.pump(const Duration(milliseconds: 700));
    await shown;
    await fixture.close(tester);
  });

  testWidgets('Profiles samples the same viewport as Home while the sheet moves', (tester) async {
    final fixture = await _mount(tester, child: const HomePage());
    final sheets = fixture.container.read(bottomSheetsNotifierProvider.notifier);
    final shown = sheets.showProfilesOverview();
    final sheet = find.byType(BottomSheet);
    await _settle(tester);
    _expectSurface(tester, sheet, glass: false);
    await fixture.container.read(Preferences.menuStyle.notifier).update(BlizzardMenuStyle.glass);
    await _settle(tester);
    _expectSurface(tester, sheet, glass: true);

    final sample = find.descendant(of: _textureIn(sheet), matching: find.byType(Image));
    final home = find.byKey(const ValueKey('blizzard_shell_snowfall'));
    final original = find.descendant(of: home, matching: find.byType(Image));
    expect(tester.getRect(sample), tester.getRect(original));
    expect(tester.widget<Image>(sample).fit, tester.widget<Image>(original).fit);
    expect(tester.widget<Image>(sample).alignment, tester.widget<Image>(original).alignment);

    final panel = find.descendant(of: sheet, matching: find.byType(BlizzardSceneGlass));
    final before = tester.getTopLeft(panel);
    await tester.dragFrom(before + const Offset(220, 7), const Offset(0, -150));
    await tester.pump();
    expect(tester.getTopLeft(panel).dy, lessThan(before.dy));
    expect(tester.getRect(sample), tester.getRect(original));

    Navigator.of(tester.element(sheet)).pop();
    await tester.pump(const Duration(milliseconds: 700));
    await shown;
    await fixture.close(tester);
  });

  for (final style in [BlizzardMenuStyle.neutral, BlizzardMenuStyle.glass]) {
    testWidgets('the overflow menu keeps clear of the right screen edge [${style.name}]', (tester) async {
      final fixture = await _mount(tester, child: _aurora(SettingsPage()));
      await fixture.container.read(Preferences.menuStyle.notifier).update(style);
      await _settle(tester);
      await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.byType(IconButton)).last);
      await _settle(tester);
      final menu = find.byKey(const ValueKey('settings-overflow-menu-glass'));
      expect(menu, findsOneWidget);
      // the visible material, not the transparent gap around it
      final material = find.descendant(of: menu, matching: find.byType(ClipRRect)).first;
      final right = tester.getRect(material).right;
      expect(right, lessThanOrEqualTo(440 - 12));
      _expectSurface(tester, menu, glass: style == BlizzardMenuStyle.glass);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    });
  }
}
