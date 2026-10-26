import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_glass.dart';
import 'package:hiddify/features/profile/details/profile_details_notifier.dart';
import 'package:hiddify/features/profile/details/profile_details_page.dart';
import 'package:hiddify/features/profile/details/profile_details_state.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../support/home_fixture.dart';
import '../support/surface_fixtures.dart';

Widget _appliedBlizzard(Widget child) => Builder(
  builder: (context) => Theme(data: BlizzardTheme.from(Theme.of(context)), child: child),
);

ProfileEntity _remoteProfile(String id, {UserOverride? userOverride, SubscriptionInfo? subInfo}) =>
    ProfileEntity.remote(
      id: id,
      active: true,
      name: 'Aurora fixture',
      url: 'https://example.invalid/aurora',
      lastUpdate: DateTime.utc(2026, 10, 24),
      options: const ProfileOptions(updateInterval: Duration(hours: 24)),
      userOverride: userOverride,
      subInfo: subInfo,
    );

ProfileDetailsState _detailsState(
  String id, {
  AsyncValue<void> loadingState = const AsyncData(null),
  bool changed = false,
  UserOverride? userOverride,
}) => ProfileDetailsState(
  loadingState: loadingState,
  profile: _remoteProfile(id, userOverride: userOverride),
  configContent: 'outbound = aurora-fixture',
  isDetailsChanged: changed,
);

Future<HomeFixture> _mountDetails(
  WidgetTester tester, {
  required String id,
  required ProfileDetailsNotifier Function() notifier,
}) => mountHomeFixture(
  tester,
  child: _appliedBlizzard(ProfileDetailsPage(id: id)),
  extraOverrides: [profileDetailsNotifierProvider(id).overrideWith(notifier)],
);

Finder _saveAction(String label) =>
    find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((widget) => widget is TextButton));

void _expectSaveAction(WidgetTester tester, String label, {required bool enabled}) {
  final save = _saveAction(label);
  expect(save, findsOneWidget);
  final button = tester.widget<TextButton>(save);
  expect(button.enabled, enabled);
  expect(button.onPressed, enabled ? isNotNull : isNull);
  expect(tester.getSize(save).shortestSide, greaterThanOrEqualTo(44));
  final semantics = tester
      .widgetList<Semantics>(find.descendant(of: save, matching: find.byType(Semantics)))
      .singleWhere((widget) => widget.properties.button == true && widget.properties.enabled != null);
  expect(semantics.properties.enabled, enabled);
  if (enabled) expect(save.hitTestable(), findsOneWidget);
}

void _expectReadableDetailsChrome(WidgetTester tester, String title) {
  expect(find.text(title), findsOneWidget);
  final scaffold = find.descendant(of: find.byType(ProfileDetailsPage), matching: find.byType(Scaffold)).first;
  final theme = Theme.of(tester.element(scaffold));
  expect(contrastRatio(theme.colorScheme.onSurface, theme.scaffoldBackgroundColor), greaterThanOrEqualTo(4.5));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Wuhqa real ProfileDetailsPage keeps changed content readable and enables Save', (tester) async {
    const id = 'Wuhqa';
    final fixture = await _mountDetails(
      tester,
      id: id,
      notifier: () => SurfaceDetails(_detailsState(id, changed: true)),
    );
    final t = fixture.container.read(translationsProvider).requireValue;

    _expectReadableDetailsChrome(tester, t.pages.profileDetails.title);
    expect(find.text('https://example.invalid/aurora'), findsOneWidget);
    expect(tester.widget<TextFormField>(find.byType(TextFormField).first).initialValue, 'Aurora fixture');
    _expectSaveAction(tester, t.common.save, enabled: true);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('VvqTh real ProfileDetailsPage preserves fields and disables Save while saving', (tester) async {
    const id = 'VvqTh';
    final fixture = await _mountDetails(
      tester,
      id: id,
      notifier: () => SurfaceDetails(_detailsState(id, loadingState: const AsyncLoading(), changed: true)),
    );
    final t = fixture.container.read(translationsProvider).requireValue;

    _expectReadableDetailsChrome(tester, t.pages.profileDetails.title);
    expect(find.text('https://example.invalid/aurora'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNotNull);
    _expectSaveAction(tester, t.common.save, enabled: false);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('W7BEO2 real ProfileDetailsPage loading keeps its title and progress visible', (tester) async {
    const id = 'W7BEO2';
    final fixture = await _mountDetails(tester, id: id, notifier: _PendingDetails.new);
    final t = fixture.container.read(translationsProvider).requireValue;

    _expectReadableDetailsChrome(tester, t.pages.profileDetails.title);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(_saveAction(t.common.save), findsNothing);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('cSBpG real ProfileDetailsPage error keeps its title and cause readable', (tester) async {
    const id = 'cSBpG';
    final error = StateError('Aurora profile unavailable');
    final fixture = await _mountDetails(tester, id: id, notifier: () => _ErrorDetails(error));
    final t = fixture.container.read(translationsProvider).requireValue;

    _expectReadableDetailsChrome(tester, t.pages.profileDetails.title);
    expect(find.text(t.presentShortError(error)), findsOneWidget);
    expect(find.text(error.toString()), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('H6Jx8 real ProfileDetailsPage hides interval controls when auto-update is disabled', (tester) async {
    const id = 'H6Jx8';
    final fixture = await _mountDetails(
      tester,
      id: id,
      notifier: () => SurfaceDetails(
        _detailsState(id, userOverride: const UserOverride(isAutoUpdateDisable: true, updateInterval: 24)),
      ),
    );
    final t = fixture.container.read(translationsProvider).requireValue;

    _expectReadableDetailsChrome(tester, t.pages.profileDetails.title);
    final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(toggle.value, isTrue);
    expect(toggle.onChanged, isNotNull);
    expect(find.text(t.pages.profileDetails.form.disableAutoUpdate), findsOneWidget);
    expect(find.text(t.pages.profileDetails.form.autoUpdateInterval), findsNothing);
    expect(find.byType(Slider), findsNothing);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  for (final state in <({String id, String description, SubscriptionInfo subInfo, String Function(AppLocale) label})>[
    (
      id: 'mCOsb',
      description: 'expired',
      subInfo: SubscriptionInfo(upload: 20, download: 30, total: 100, expire: DateTime.utc(2020)),
      label: (locale) => locale.buildSync().components.subscriptionInfo.expired,
    ),
    (
      id: 't39jA9',
      description: 'exhausted quota',
      subInfo: SubscriptionInfo(upload: 40, download: 60, total: 100, expire: DateTime.utc(2099)),
      label: (locale) => locale.buildSync().components.subscriptionInfo.noTraffic,
    ),
  ]) {
    testWidgets('${state.id} real Home profile keeps ${state.description} status and actions visible', (tester) async {
      final profile = _remoteProfile(state.id, subInfo: state.subInfo);
      final update = TileUpdateSpy();
      final fixture = await mountHomeFixture(
        tester,
        profile: profile,
        child: Center(
          child: SizedBox(width: 353, child: _appliedBlizzard(ProfileTile(profile: profile, isMain: true))),
        ),
        extraOverrides: [updateProfileNotifierProvider(state.id).overrideWith(() => update)],
      );
      final label = state.label(AppLocale.en);
      final status = find.byWidgetPredicate((widget) => widget is Text && widget.data?.contains(label) == true);

      final card = find.descendant(of: find.byType(ProfileTile), matching: find.byType(Card));
      expect(find.ancestor(of: card, matching: find.byType(BlizzardGlass)), findsOneWidget);
      expect(tester.widget<Card>(card).color, Colors.transparent);
      expect(status, findsOneWidget);
      final statusText = tester.widget<Text>(status);
      expect(statusText.style?.color, Theme.of(tester.element(status)).colorScheme.error);
      expect(find.byIcon(Icons.update_rounded).hitTestable(), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_ios), findsOneWidget);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    });
  }
}

class _PendingDetails extends ProfileDetailsNotifier {
  final _pending = Completer<ProfileDetailsState>();

  @override
  Future<ProfileDetailsState> build(String id) => _pending.future;
}

class _ErrorDetails extends ProfileDetailsNotifier {
  _ErrorDetails(this.error);

  final Object error;

  @override
  Future<ProfileDetailsState> build(String id) => Future.error(error, StackTrace.empty);
}
