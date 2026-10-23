import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/locale_extensions.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/dialog/widgets/setting_input_dialog.dart';
import 'package:hiddify/core/router/dialog/widgets/setting_picker_dialog.dart';
import 'package:hiddify/core/router/dialog/widgets/setting_slider_dialog.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
import 'package:hiddify/features/about/widget/about_page.dart';
import 'package:hiddify/features/app_update/notifier/app_update_notifier.dart';
import 'package:hiddify/features/log/model/log_level.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/overview/profiles_modal.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_page.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/overview/sections/general_page.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart' show OutboundGroup, OutboundInfo;
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../support/home_fixture.dart';
import '../support/surface_fixtures.dart';

Widget _underAurora(Widget child) => Builder(
  builder: (context) => Theme(data: BlizzardTheme.from(Theme.of(context)), child: child),
);

Future<void> _revealGeneralRow(WidgetTester tester, String title) async {
  final scrollable = find.descendant(of: find.byType(GeneralPage), matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(find.text(title), 160, scrollable: scrollable);
  await tester.pumpAndSettle();
  expect(find.text(title).hitTestable(), findsOneWidget);
}

String _subtitleFor(WidgetTester tester, String title) {
  final tile = tester.widget<ListTile>(find.ancestor(of: find.text(title), matching: find.byType(ListTile)).first);
  return (tile.subtitle! as Text).data!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('NxPCd real Settings overflow opens the source-backed import submenu', (tester) async {
    final fixture = await mountHomeFixture(tester, locale: AppLocale.ru, child: _underAurora(SettingsPage()));
    final t = fixture.container.read(translationsProvider).requireValue;
    final overflow = find.descendant(of: find.byType(MenuAnchor), matching: find.byType(IconButton));

    expect(overflow, findsOneWidget);
    await tester.tap(overflow);
    await tester.pumpAndSettle();
    expect(find.byType(SubmenuButton), findsNWidgets(2));
    expect(find.text(t.common.import), findsOneWidget);
    expect(find.text(t.common.export), findsOneWidget);
    expect(find.text(t.pages.settings.options.reset), findsOneWidget);

    await tester.tap(find.text(t.common.import));
    await tester.pumpAndSettle();
    expect(find.text(t.pages.settings.options.import.clipboard), findsOneWidget);
    expect(find.text(t.pages.settings.options.import.file), findsOneWidget);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('C8dczk real General locale picker preserves the source-backed English value', (tester) async {
    final fixture = await mountHomeFixture(tester, child: _underAurora(const GeneralPage()));
    final title = fixture.container.read(translationsProvider).requireValue.pages.settings.general.locale;

    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
    final dialog = tester.widget<SettingPickerDialog<AppLocale>>(find.byType(SettingPickerDialog<AppLocale>));
    expect(dialog.selected, AppLocale.en);
    expect(dialog.options, contains(AppLocale.en));
    final selectedChoice = find.descendant(
      of: find.byType(SettingPickerDialog<AppLocale>),
      matching: find.widgetWithText(RadioListTile<AppLocale>, AppLocale.en.localeName),
    );
    expect(selectedChoice, findsOneWidget);
    expect(tester.widget<RadioListTile<AppLocale>>(selectedChoice).value, AppLocale.en);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('mOjxM real General appearance picker preserves the source-backed dark value', (tester) async {
    final fixture = await mountHomeFixture(tester, child: _underAurora(const GeneralPage()));
    final t = fixture.container.read(translationsProvider).requireValue;
    final title = t.pages.settings.general.themeMode;

    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
    final dialog = tester.widget<SettingPickerDialog<AppThemeMode>>(find.byType(SettingPickerDialog<AppThemeMode>));
    expect(dialog.selected, AppThemeMode.dark);
    expect(dialog.options, contains(AppThemeMode.dark));
    final selectedChoice = find.descendant(
      of: find.byType(SettingPickerDialog<AppThemeMode>),
      matching: find.widgetWithText(RadioListTile<AppThemeMode>, AppThemeMode.dark.present(t)),
    );
    expect(selectedChoice, findsOneWidget);
    expect(tester.widget<RadioListTile<AppThemeMode>>(selectedChoice).value, AppThemeMode.dark);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('LmQf1 real General log-level picker preserves the source-backed WARN value', (tester) async {
    final fixture = await mountHomeFixture(tester, child: _underAurora(const GeneralPage()));
    final title = fixture.container.read(translationsProvider).requireValue.pages.settings.general.logLevel;

    await _revealGeneralRow(tester, title);
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
    final dialog = tester.widget<SettingPickerDialog<LogLevel>>(find.byType(SettingPickerDialog<LogLevel>));
    expect(dialog.selected, LogLevel.warn);
    expect(dialog.options, LogLevel.choices);
    final selectedChoice = find.descendant(
      of: find.byType(SettingPickerDialog<LogLevel>),
      matching: find.widgetWithText(RadioListTile<LogLevel>, 'WARN'),
    );
    expect(selectedChoice, findsOneWidget);
    expect(tester.widget<RadioListTile<LogLevel>>(selectedChoice).value, LogLevel.warn);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('YGpxn real General test-URL input preserves the source-backed captive URL', (tester) async {
    final fixture = await mountHomeFixture(tester, child: _underAurora(const GeneralPage()));
    final title = fixture.container.read(translationsProvider).requireValue.pages.settings.general.connectionTestUrl;

    await _revealGeneralRow(tester, title);
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
    final dialog = tester.widget<SettingInputDialog<String>>(find.byType(SettingInputDialog<String>));
    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(dialog.initialValue, 'http://captive.apple.com/hotspot-detect.html');
    expect(dialog.possibleValues, contains('https://www.gstatic.com/generate_204'));
    expect(field.controller!.text, dialog.initialValue);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('pHe0a real General interval slider preserves the source-backed ten-minute value', (tester) async {
    final fixture = await mountHomeFixture(tester, child: _underAurora(const GeneralPage()));
    final title = fixture.container.read(translationsProvider).requireValue.pages.settings.general.urlTestInterval;

    await _revealGeneralRow(tester, title);
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
    final dialog = tester.widget<SettingsSliderDialog>(find.byType(SettingsSliderDialog));
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(dialog.initialValue, 10);
    expect(slider.value, 10);
    expect(slider.min, 1);
    expect(slider.max, 60);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('UqpbS real General API-port input preserves the source-backed 16756 value', (tester) async {
    final fixture = await mountHomeFixture(tester, child: _underAurora(const GeneralPage()));
    final title = fixture.container.read(translationsProvider).requireValue.pages.settings.general.clashApiPort;

    await _revealGeneralRow(tester, title);
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
    final dialog = tester.widget<SettingInputDialog<int>>(find.byType(SettingInputDialog<int>));
    final field = tester.widget<TextFormField>(find.byType(TextFormField).last);
    expect(dialog.initialValue, 16756);
    expect(dialog.digitsOnly, isTrue);
    expect(field.controller!.text, '16756');
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('z2zWO6 real General renders persisted custom values together', (tester) async {
    final fixture = await mountHomeFixture(tester, child: _underAurora(const GeneralPage()));
    final t = fixture.container.read(translationsProvider).requireValue;
    const customUrl = 'https://probe.example.invalid/aurora';

    await fixture.container.read(localePreferencesProvider.notifier).changeLocale(AppLocale.ru);
    await fixture.container.read(themePreferencesProvider.notifier).changeThemeMode(AppThemeMode.black);
    await fixture.container.read(ConfigOptions.logLevel.notifier).update(LogLevel.debug);
    await fixture.container.read(ConfigOptions.connectionTestUrl.notifier).update(customUrl);
    await fixture.container.read(ConfigOptions.urlTestInterval.notifier).update(const Duration(minutes: 37));
    await fixture.container.read(ConfigOptions.clashApiPort.notifier).update(23456);
    await fixture.container.read(ConfigOptions.useXrayCoreWhenPossible.notifier).update(true);
    await tester.pumpAndSettle();

    expect(_subtitleFor(tester, t.pages.settings.general.locale), AppLocale.ru.localeName);
    expect(_subtitleFor(tester, t.pages.settings.general.themeMode), AppThemeMode.black.present(t));
    await _revealGeneralRow(tester, t.pages.settings.general.logLevel);
    expect(_subtitleFor(tester, t.pages.settings.general.logLevel), 'DEBUG');
    await _revealGeneralRow(tester, t.pages.settings.general.connectionTestUrl);
    expect(_subtitleFor(tester, t.pages.settings.general.connectionTestUrl), customUrl);
    await _revealGeneralRow(tester, t.pages.settings.general.urlTestInterval);
    expect(_subtitleFor(tester, t.pages.settings.general.urlTestInterval), contains('37'));
    await _revealGeneralRow(tester, t.pages.settings.general.clashApiPort);
    expect(_subtitleFor(tester, t.pages.settings.general.clashApiPort), '23456');
    await _revealGeneralRow(tester, t.pages.settings.general.useXrayCoreWhenPossible);
    final xray = tester.widget<SwitchListTile>(
      find.ancestor(
        of: find.text(t.pages.settings.general.useXrayCoreWhenPossible),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(xray.value, isTrue);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('A7RqB shared iOS Settings menu keeps long Portuguese labels reachable at 393pt', (tester) async {
    final fixture = await mountHomeFixture(
      tester,
      locale: AppLocale.ptBr,
      scale: 1.6,
      child: _underAurora(const Scaffold(body: BlizzardSettingsMenu())),
    );
    final t = fixture.container.read(translationsProvider).requireValue;
    final menu = find.byType(BlizzardSettingsMenu);
    final list = find.descendant(of: menu, matching: find.byType(ListView));
    expect(menu, findsOneWidget);
    expect(list, findsOneWidget);
    final labels = [
      t.pages.settings.general.title,
      t.pages.about.title,
      t.pages.settings.routing.title,
      t.pages.settings.dns.title,
      t.pages.settings.inbound.title,
      t.pages.settings.tlsTricks.title,
      t.pages.settings.warp.title,
      t.pages.logs.title,
    ];
    var grewForLongText = false;

    for (final label in labels) {
      final visibleLabel = find.descendant(of: list, matching: find.text(label)).hitTestable();
      for (var attempt = 0; visibleLabel.evaluate().isEmpty && attempt < 8; attempt++) {
        await tester.drag(list, const Offset(0, -120));
        await tester.pumpAndSettle();
      }
      expect(visibleLabel, findsOneWidget, reason: label);
      final tile = find.ancestor(of: visibleLabel, matching: find.byType(ListTile)).first;
      final height = tester.getSize(tile).height;
      expect(height, greaterThanOrEqualTo(48), reason: label);
      grewForLongText = grewForLongText || height > 48;
      expect(tester.takeException(), isNull, reason: label);
    }
    expect(grewForLongText, isTrue);
    await fixture.close(tester);
  });

  testWidgets('W7Ainm real About More menu copies the source app-info payload', (tester) async {
    final clipboard = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard.add(call.arguments);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final fixture = await mountHomeFixture(
      tester,
      locale: AppLocale.ru,
      child: _underAurora(const AboutPage()),
      extraOverrides: [appUpdateNotifierProvider.overrideWith(SurfaceAppUpdate.new)],
    );
    final t = fixture.container.read(translationsProvider).requireValue;
    final expectedPayload = fixture.container.read(appInfoProvider).requireValue.format();

    expect(find.text(t.pages.about.title), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton));
    await tester.pumpAndSettle();
    final copyAction = find.widgetWithText(PopupMenuItem, t.common.addToClipboard);
    expect(copyAction, findsOneWidget);
    expect(tester.widget<PopupMenuItem>(copyAction).onTap, isNotNull);
    await tester.tap(copyAction);
    await tester.pumpAndSettle();
    expect(clipboard, [
      {'text': expectedPayload},
    ]);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('GskHG real Servers opens its dedicated sort menu over the server list', (tester) async {
    final group = OutboundGroup(
      tag: 'select',
      selected: 'Aurora Finland',
      items: [OutboundInfo(tag: 'Aurora Finland', tagDisplay: 'Aurora Finland', type: 'vless', urlTestDelay: 84)],
    );
    final fixture = await mountHomeFixture(
      tester,
      locale: AppLocale.ru,
      child: _underAurora(const ProxiesOverviewPage()),
      extraOverrides: [proxiesOverviewNotifierProvider.overrideWith(() => SurfaceProxies(AsyncData(group)))],
    );
    final t = fixture.container.read(translationsProvider).requireValue;

    expect(find.text('Серверы'), findsOneWidget);
    expect(find.text('Aurora Finland'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<ProxiesSort>));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<ProxiesSort>), findsNWidgets(ProxiesSort.values.length));
    for (final sort in ProxiesSort.values) {
      expect(find.text(sort.present(t)), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('hfaw4 real Profiles sheet exposes its dedicated sort and update menu actions', (tester) async {
    final profiles = TileProfilesSpy()
      ..profiles = [
        ProfileEntity.local(id: 'aurora-profile', active: true, name: 'Aurora Profile', lastUpdate: DateTime.utc(2026)),
      ];
    final fixture = await mountHomeFixture(
      tester,
      locale: AppLocale.ru,
      child: _underAurora(const ProfilesModal()),
      extraOverrides: [profilesNotifierProvider.overrideWith(() => profiles)],
    );
    final t = fixture.container.read(translationsProvider).requireValue;

    expect(find.byType(ProfilesModal), findsOneWidget);
    expect(find.text(t.pages.profiles.title), findsOneWidget);
    expect(find.text('Aurora Profile'), findsOneWidget);
    expect(find.byTooltip(t.common.sort).hitTestable(), findsOneWidget);
    expect(find.byTooltip(t.pages.profiles.updateSubscriptions).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });
}
