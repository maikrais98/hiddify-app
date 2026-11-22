import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_presentation.dart';
import 'package:hiddify/features/chain/overview/chain_mode_menu.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/settings/overview/sections/general_page.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../support/blizzard_capture.dart';
import '../support/home_fixture.dart';

// Render script for the candidate popup styles (BlizzardMenuStyleSwitch). With LUMA_RENDER_DIR
// set it writes 440x956 @3x PNGs to <dir>/{A,B}/<screen>.png; without it only the shipped
// style is built, so the screens cannot rot. The variant is a fixed switch, not a user setting.
final _styles = <String, BlizzardMenuStyle>{'A': BlizzardMenuStyle.neutral, 'B': BlizzardMenuStyle.glass};

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

Future<void> _snap(WidgetTester tester, String style, String name) async {
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
  Directory('$dir/$style').createSync(recursive: true);
  File('$dir/$style/$name.png').writeAsBytesSync(bytes!);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 700));
}

Future<void> _loadRenderFonts() async {
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

Widget _aurora(Widget child) => Builder(
  builder: (context) => Theme(data: BlizzardTheme.from(Theme.of(context)), child: child),
);

// The style is the user's setting: it is chosen through the preference, as the app does.
Future<HomeFixture> mountStyled(
  WidgetTester tester,
  BlizzardMenuStyle style, {
  required double width,
  required double height,
  required bool nativeViewport,
  required AppLocale locale,
  Widget? child,
  required List<Override> extraOverrides,
}) async {
  final fixture = child == null
      ? await mountHomeFixture(
          tester,
          width: width,
          height: height,
          nativeViewport: nativeViewport,
          locale: locale,
          extraOverrides: extraOverrides,
        )
      : await mountHomeFixture(
          tester,
          width: width,
          height: height,
          nativeViewport: nativeViewport,
          locale: locale,
          child: child,
          extraOverrides: extraOverrides,
        );
  await fixture.container.read(Preferences.menuStyle.notifier).update(style);
  await tester.pump(const Duration(milliseconds: 100));
  return fixture;
}

void main() {
  setUpAll(_loadRenderFonts);
  setUp(() => BlizzardPresentation.debugAssumeIOS = true);
  tearDown(() {
    BlizzardPresentation.debugAssumeIOS = false;
    BlizzardMenuStyleSwitch.value = BlizzardMenuStyle.neutral;
  });

  final rendering = Platform.environment['LUMA_RENDER_DIR'] != null;
  for (final entry in _styles.entries) {
    if (!rendering && entry.value != BlizzardMenuStyle.neutral) continue;
    final style = entry.key;

    Future<HomeFixture> mount(WidgetTester tester, {Widget? child}) {
      tester.view.physicalSize = const Size(440 * 3, 956 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      return mountStyled(
        tester,
        entry.value,
        width: 440,
        height: 956,
        nativeViewport: true,
        locale: AppLocale.ru,
        child: child ?? const SizedBox.shrink(),
        extraOverrides: [profilesNotifierProvider.overrideWith(() => TileProfilesSpy()..profiles = _profiles)],
      );
    }

    // Home (the fixture default) under the sheets.
    Future<HomeFixture> mountHome(WidgetTester tester, {double height = 956}) {
      tester.view.physicalSize = Size(440 * 3, height * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      return mountStyled(
        tester,
        entry.value,
        width: 440,
        height: height,
        nativeViewport: true,
        locale: AppLocale.ru,
        extraOverrides: [profilesNotifierProvider.overrideWith(() => TileProfilesSpy()..profiles = _profiles)],
      );
    }

    Future<void> closeTop(WidgetTester tester, Future<void> shown) async {
      if (find.byType(BottomSheet).evaluate().isNotEmpty) Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await shown;
    }

    testWidgets('quick settings sheet [$style]', (tester) async {
      final fixture = await mountHome(tester);
      final shown = fixture.container.read(bottomSheetsNotifierProvider.notifier).showQuickSettings();
      await _settle(tester);
      await _snap(tester, style, 'quick-settings-sheet');
      expect(tester.takeException(), isNull);

      // the "Дополнительная защита" dropdown on top of the sheet
      await tester.tap(find.byType(ChainModeMenu).first);
      await _settle(tester);
      await _snap(tester, style, 'quick-settings-dropdown');
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 400));
      await closeTop(tester, shown);
      await fixture.close(tester);
    });

    // A shorter screen puts the brightest part of the scene behind the popups: the glass worst case.
    testWidgets('bright scene behind popups [$style]', (tester) async {
      final fixture = await mountHome(tester, height: 720);
      final shown = fixture.container.read(bottomSheetsNotifierProvider.notifier).showQuickSettings();
      await _settle(tester);
      await _snap(tester, style, 'quick-settings-sheet-bright');
      expect(tester.takeException(), isNull);
      await closeTop(tester, shown);
      final confirmed = fixture.container
          .read(dialogNotifierProvider.notifier)
          .showConfirmation(
            title: 'Импортировать настройки?',
            message: 'Текущие настройки будут заменены настройками из буфера обмена.',
          );
      await _settle(tester);
      await _snap(tester, style, 'confirm-dialog-bright');
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.byType(Dialog).first)).pop(false);
      await tester.pump(const Duration(milliseconds: 500));
      await confirmed;
      await fixture.close(tester);
    });

    testWidgets('profiles sheet [$style]', (tester) async {
      final fixture = await mountHome(tester);
      final shown = fixture.container.read(bottomSheetsNotifierProvider.notifier).showProfilesOverview();
      await _settle(tester);
      await _snap(tester, style, 'profiles-sheet');
      expect(tester.takeException(), isNull);
      await closeTop(tester, shown);
      await fixture.close(tester);
    });

    testWidgets('settings overflow menu [$style]', (tester) async {
      final fixture = await mount(tester, child: _aurora(SettingsPage()));
      await _settle(tester);
      await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.byType(IconButton)).last);
      await _settle(tester);
      await _snap(tester, style, 'settings-overflow-menu');
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    });

    testWidgets('general page, menu style row [$style]', (tester) async {
      final fixture = await mount(tester, child: _aurora(const GeneralPage()));
      await _settle(tester);
      await _snap(tester, style, 'general-menu-style');
      expect(find.text('Стиль меню'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    });

    testWidgets('picker and confirm dialogs [$style]', (tester) async {
      final fixture = await mount(tester, child: _aurora(SettingsPage()));
      await _settle(tester);
      final dialogs = fixture.container.read(dialogNotifierProvider.notifier);
      final picked = dialogs.showSettingPicker<String>(
        title: 'Язык',
        selected: 'ru',
        options: const ['ru', 'en', 'es', 'tr'],
        getTitle: (e) => switch (e) {
          'ru' => 'Русский',
          'en' => 'English',
          'es' => 'Español',
          _ => 'Türkçe',
        },
        onReset: () {},
      );
      await _settle(tester);
      await _snap(tester, style, 'picker-dialog');
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.byType(Dialog).first)).pop();
      await tester.pump(const Duration(milliseconds: 500));
      await picked;

      final confirmed = dialogs.showConfirmation(
        title: 'Импортировать настройки?',
        message: 'Текущие настройки будут заменены настройками из буфера обмена. Это действие нельзя отменить.',
      );
      await _settle(tester);
      await _snap(tester, style, 'confirm-dialog');
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.byType(Dialog).first)).pop(false);
      await tester.pump(const Duration(milliseconds: 500));
      await confirmed;
      await fixture.close(tester);
    });
  }
}
