import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/analytics/analytics_controller.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/features/about/widget/about_page.dart';
import 'package:hiddify/features/app_update/notifier/app_update_notifier.dart';
import 'package:hiddify/features/app_update/notifier/app_update_state.dart';
import 'package:hiddify/features/intro/widget/intro_page.dart';
import 'package:hiddify/features/profile/add/add_profile_modal.dart';
import 'package:hiddify/features/profile/add/model/free_profiles_model.dart';
import 'package:hiddify/features/profile/add/widgets/free_btn.dart';
import 'package:hiddify/features/profile/add/widgets/free_btns.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/overview/sections/dns_options_page.dart';
import 'package:hiddify/features/settings/overview/sections/inbound_options_page.dart';
import 'package:hiddify/features/settings/overview/sections/tls_tricks_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../support/home_fixture.dart';
import '../support/surface_fixtures.dart' show contrastRatio;

class _PendingAnalytics extends AnalyticsController {
  final pending = Completer<void>();
  int disableCalls = 0;

  @override
  Future<bool> build() async => false;

  @override
  Future<void> disableAnalytics() {
    disableCalls++;
    return pending.future;
  }
}

class _FreeProfiles extends FreeProfilesNotifier {
  _FreeProfiles(this.result);

  final Future<List<FreeProfile>> Function() result;

  @override
  Future<List<FreeProfile>> build() => result();
}

class _CheckingAppUpdate extends AppUpdateNotifier {
  @override
  AppUpdateState build() => const AppUpdateState.checking();
}

Widget _underAurora(Widget child) => Builder(
  builder: (context) => Theme(data: BlizzardTheme.from(Theme.of(context)), child: child),
);

Finder _switchRow(String title) => find.ancestor(of: find.text(title), matching: find.byType(SwitchListTile));

Finder _valueRow(String title) => find.ancestor(of: find.text(title), matching: find.byType(ListTile));

void _expectAuroraReadable(WidgetTester tester, Finder visibleText) {
  expect(visibleText.hitTestable(), findsOneWidget);
  final theme = Theme.of(tester.element(visibleText));
  expect(theme.extension<BlizzardEligibility>()?.applied, isTrue);
  expect(contrastRatio(theme.colorScheme.onSurface, theme.colorScheme.surface), greaterThanOrEqualTo(4.5));
}

Future<void> _reveal(WidgetTester tester, String text) async {
  final target = find.text(text);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  _expectAuroraReadable(tester, target);
}

const _freeProfile = FreeProfile(
  region: [],
  title: StringByLocale(en: 'Aurora free profile', fa: 'Aurora free profile'),
  sublink: 'https://example.invalid/aurora-free',
  tags: ListOfStringByLocale(en: ['Fast', 'Private'], fa: ['Fast', 'Private']),
  consent: StringByLocale(en: 'Synthetic consent', fa: 'Synthetic consent'),
  neededFeatures: ['fragment'],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('o80654 real Intro Start-in-progress keeps its label and ignores duplicate press', (tester) async {
    final previous = IntroPage.locationInfoLoaded;
    IntroPage.locationInfoLoaded = true;
    addTearDown(() => IntroPage.locationInfoLoaded = previous);
    final analytics = _PendingAnalytics();
    final fixture = await mountHomeFixture(
      tester,
      child: _underAurora(const IntroPage()),
      extraOverrides: [analyticsControllerProvider.overrideWith(() => analytics)],
    );
    final t = fixture.container.read(translationsProvider).requireValue;
    final start = find.text(t.common.start);
    final button = find.byType(FloatingActionButton);

    expect(start, findsOneWidget);
    await tester.tap(button);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(start, findsOneWidget);
    expect(find.byIcon(Icons.rocket_launch), findsNothing);
    _expectAuroraReadable(tester, start);

    await tester.tap(button);
    await tester.pump();
    expect(analytics.disableCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    analytics.pending.complete();
    await tester.pump();
    await fixture.close(tester);
  });

  testWidgets('Q5QQY real DNS FakeDNS-on is visible and readable under Aurora', (tester) async {
    final fixture = await mountHomeFixture(tester, child: _underAurora(const DnsOptionsPage()));
    await fixture.container.read(ConfigOptions.enableFakeDns.notifier).update(true);
    await tester.pump();
    final title = fixture.container.read(translationsProvider).requireValue.pages.settings.dns.enableFakeDns;

    await _reveal(tester, title);
    final row = tester.widget<SwitchListTile>(_switchRow(title));
    expect(row.value, isTrue);
    expect(row.onChanged, isNotNull);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('w70xUE real Inbound LAN-sharing-on is visible and readable under Aurora', (tester) async {
    final fixture = await mountHomeFixture(tester, child: _underAurora(const InboundOptionsPage()));
    await fixture.container.read(ConfigOptions.allowConnectionFromLan.notifier).update(true);
    await tester.pump();
    final title = fixture.container
        .read(translationsProvider)
        .requireValue
        .pages
        .settings
        .inbound
        .allowConnectionFromLan;

    await _reveal(tester, title);
    final row = tester.widget<SwitchListTile>(_switchRow(title));
    expect(row.value, isTrue);
    expect(row.onChanged, isNotNull);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  for (final padding in [false, true]) {
    final designId = padding ? 'v73SG' : 'iBEdy';
    final description = padding ? 'fragment-and-padding-on' : 'fragment-on-padding-off';
    testWidgets('$designId real TLS $description keeps dependent controls readable under Aurora', (tester) async {
      final fixture = await mountHomeFixture(tester, child: _underAurora(const TlsTricksPage()));
      await fixture.container.read(ConfigOptions.enableTlsFragment.notifier).update(true);
      await fixture.container.read(ConfigOptions.enableTlsPadding.notifier).update(padding);
      await tester.pump();
      final t = fixture.container.read(translationsProvider).requireValue;
      final fragmentTitle = t.pages.settings.tlsTricks.enable;
      final paddingTitle = t.pages.settings.tlsTricks.padding.enable;
      final paddingSizeTitle = t.pages.settings.tlsTricks.padding.size;

      expect(tester.widget<SwitchListTile>(_switchRow(fragmentTitle)).value, isTrue);
      await _reveal(tester, paddingTitle);
      expect(tester.widget<SwitchListTile>(_switchRow(paddingTitle)).value, padding);
      await _reveal(tester, paddingSizeTitle);
      expect(tester.widget<ListTile>(_valueRow(paddingSizeTitle)).enabled, isTrue);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    });
  }

  for (final state in ['loading', 'data', 'empty', 'error']) {
    final designId = switch (state) {
      'loading' => 'Kccup',
      'data' => 'hX9Ov',
      'empty' => 'N9McZ',
      _ => 'fdH04',
    };
    testWidgets('$designId real Add Profile free-$state is visible and readable under Aurora', (tester) async {
      Future<List<FreeProfile>> profiles() => switch (state) {
        'loading' => Completer<List<FreeProfile>>().future,
        'data' => Future.value(const [_freeProfile]),
        'empty' => Future.value(const <FreeProfile>[]),
        _ => Future<List<FreeProfile>>.error(StateError('Synthetic free-profile failure'), StackTrace.current),
      };
      final fixture = await mountHomeFixture(
        tester,
        child: _underAurora(const AddProfileModal()),
        extraOverrides: [
          freeProfilesNotifierProvider.overrideWith(() => _FreeProfiles(profiles)),
          freeProfilesFilteredByRegionProvider.overrideWith((ref) => profiles()),
        ],
      );
      await fixture.container.read(freeSwitchNotifierProvider.notifier).onChange(true);
      await tester.pump();
      await tester.pump();
      final t = fixture.container.read(translationsProvider).requireValue;

      final visibleText = switch (state) {
        'data' => find.text('Aurora free profile'),
        'empty' => find.text(t.pages.profiles.freeSubNotFound),
        'error' => find.text(t.pages.profiles.failedToLoad),
        _ => find.text(t.common.free),
      };
      if (state == 'loading') {
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      } else if (state == 'data') {
        expect(find.byType(FreeBtns), findsOneWidget);
        expect(find.byType(FreeBtn), findsOneWidget);
        expect(find.byType(GridView), findsOneWidget);
      } else {
        expect(find.byType(FreeBtn), findsNothing);
      }
      _expectAuroraReadable(tester, visibleText);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    });
  }

  testWidgets('Ok4Ca real About checking-update row is visible and readable under Aurora', (tester) async {
    final fixture = await mountHomeFixture(
      tester,
      child: _underAurora(const AboutPage()),
      extraOverrides: [appUpdateNotifierProvider.overrideWith(_CheckingAppUpdate.new)],
    );
    final t = fixture.container.read(translationsProvider).requireValue;
    final title = t.pages.about.checkForUpdate;
    final row = _valueRow(title);

    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.byType(CircularProgressIndicator)), findsOneWidget);
    expect(tester.widget<ListTile>(row).onTap, isNotNull);
    _expectAuroraReadable(tester, find.text(title));
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });
}
