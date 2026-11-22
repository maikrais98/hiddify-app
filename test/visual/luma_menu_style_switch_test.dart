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

Finder _blurIn(Finder scope) => find.descendant(
  of: scope,
  matching: find.byWidgetPredicate((widget) => widget is BackdropFilter && widget.enabled),
);

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
    expect(_blurIn(find.byType(Dialog)), findsNothing);

    await fixture.container.read(Preferences.menuStyle.notifier).update(BlizzardMenuStyle.glass);
    await _settle(tester);
    expect(_blurIn(find.byType(Dialog)), findsOneWidget);

    await fixture.container.read(Preferences.menuStyle.notifier).update(BlizzardMenuStyle.neutral);
    await _settle(tester);
    expect(_blurIn(find.byType(Dialog)), findsNothing);
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
    expect(_blurIn(find.byType(Dialog)), findsOneWidget);

    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(highContrast: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _settle(tester);
    expect(tester.state<EditableTextState>(find.byType(EditableText)), same(field));
    expect(field.widget.focusNode.hasFocus, isTrue);
    expect(_blurIn(find.byType(Dialog)), findsNothing);
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
    expect(background().color, const Color(0xF0111214));

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
    expect(tester.widget<Material>(card).color, const Color(0xF0111214));
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
    final button = find.byType(DropdownButton<String>);
    final originalCanvas = Theme.of(tester.element(button)).canvasColor;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await _settle(tester);
    final option = find.text('udp');
    Color menuColor() => Theme.of(tester.element(option)).canvasColor;
    expect(menuColor(), BlizzardPalette.sheet);

    await fixture.container.read(Preferences.menuStyle.notifier).update(BlizzardMenuStyle.glass);
    await _settle(tester);
    expect(menuColor(), const Color(0xF0111214));
    expect(Theme.of(tester.element(button)).canvasColor, originalCanvas);
    await tester.tap(option);
    await _settle(tester);
    expect(tester.widget<DropdownButton<String>>(button).value, 'udp');
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

  testWidgets('the quick settings sheet changes its material with the setting', (tester) async {
    final fixture = await _mount(tester);
    final shown = fixture.container.read(bottomSheetsNotifierProvider.notifier).showQuickSettings();
    await _settle(tester);
    // the sheet has a backdrop filter of its own in both styles; glass adds exactly one
    final solid = _blurIn(find.byType(BottomSheet)).evaluate().length;

    await fixture.container.read(Preferences.menuStyle.notifier).update(BlizzardMenuStyle.glass);
    await _settle(tester);
    expect(_blurIn(find.byType(BottomSheet)), findsNWidgets(solid + 1));
    expect(tester.takeException(), isNull);

    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
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
      expect(_blurIn(menu), style == BlizzardMenuStyle.glass ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    });
  }
}
