import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/home/widget/home_page.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart';
import 'package:hiddify/features/proxy/active/active_proxy_card.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../support/blizzard_capture.dart';
import '../support/connection_fixtures.dart';
import '../support/home_fixture.dart';
import '../support/surface_fixtures.dart' show contrastRatio;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final t = AppLocale.en.buildSync();

  tearDown(() => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));

  for (final state
      in <
        ({
          String designId,
          AsyncValue<ConnectionStatus> status,
          String statusLabel,
          String actionLabel,
          bool enabled,
          List<String> events,
        })
      >[
        (
          designId: 'snmZp',
          status: const AsyncData(Disconnected()),
          statusLabel: t.connection.tapToConnect,
          actionLabel: t.connection.connect,
          enabled: true,
          events: const ['notice', 'toggle'],
        ),
        (
          designId: 'nCVBL',
          status: const AsyncData(Connecting()),
          statusLabel: t.connection.connecting,
          actionLabel: t.connection.disconnect,
          enabled: true,
          events: const ['toggle'],
        ),
        (
          designId: 'qyVqN',
          status: const AsyncData(Disconnecting()),
          statusLabel: t.connection.disconnecting,
          actionLabel: t.connection.disconnecting,
          enabled: false,
          events: const [],
        ),
      ]) {
    testWidgets('${state.designId} mounts the complete Home connection context', (tester) async {
      final events = <String>[];
      final fixture = await _mountConnectionHome(
        tester,
        status: state.status,
        profile: connectionProfile,
        events: events,
      );
      addTearDown(() => fixture.close(tester));

      _expectCompleteHome(tester, hasProfile: true);
      _expectStatus(tester, state.statusLabel);
      expect(_actionLabel(tester), state.actionLabel);
      expect(_connectionSemantics(tester).properties.enabled, state.enabled);

      await tester.tap(find.byKey(const ValueKey('home_connection_button')));
      await tester.pump();
      expect(events, state.events);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('U1dZz mounts the source-reachable no-profile Home and preserves its action sequence', (tester) async {
    final events = <String>[];
    final fixture = await _mountConnectionHome(
      tester,
      status: const AsyncData(Disconnected()),
      profile: null,
      events: events,
    );
    addTearDown(() => fixture.close(tester));

    _expectCompleteHome(tester, hasProfile: false);
    _expectStatus(tester, t.connection.tapToConnect);
    expect(_actionLabel(tester), t.connection.connect);
    expect(find.byType(ProfileTile), findsNothing);
    expect(_connectionSemantics(tester).properties.enabled, isTrue);

    await tester.tap(find.byKey(const ValueKey('home_connection_button')));
    await tester.pump();
    expect(events, ['no-profile', 'add-profile:null']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('configuration changes retain the official disconnect action in the complete Home', (tester) async {
    final events = <String>[];
    final fixture = await _mountConnectionHome(
      tester,
      status: const AsyncData(Connected()),
      profile: connectionProfile,
      reconnectRequired: true,
      events: events,
    );
    addTearDown(() => fixture.close(tester));

    _expectCompleteHome(tester, hasProfile: true);
    _expectStatus(tester, 'VPN ${t.connection.connected}');
    expect(_actionLabel(tester), t.connection.disconnect);
    expect(_connectionSemantics(tester).properties.enabled, isTrue);
    expect(find.text('Synthetic Finland'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home_connection_button')));
    await tester.pump();
    expect(events, ['toggle']);
  });

  testWidgets('V98Y4 mounts the complete connected WARP Home with secure and disconnect actions', (tester) async {
    final events = <String>[];
    final fixture = await _mountConnectionHome(
      tester,
      status: const AsyncData(Connected()),
      profile: connectionProfile,
      events: events,
    );
    addTearDown(() => fixture.close(tester));

    await fixture.container.read(ConfigOptions.chainStatus.notifier).update(ChainStatus.extraSecurity);
    await fixture.container.read(ConfigOptions.extraSecurityMode.notifier).update(ChainMode.warp);
    fixture.container.read(mainOutboundsNotifierProvider.notifier).state = AsyncData(
      fixtureOutbounds()..chainHop = OutboundInfo(tag: 'warp', type: 'WARP', status: Status.READY, urlTestDelay: 50),
    );
    await tester.pump();

    _expectCompleteHome(tester, hasProfile: true);
    _expectStatus(tester, 'VPN ${t.connection.connected}');
    expect(_actionLabel(tester), t.connection.disconnect);
    expect(find.text(t.pages.settings.chain.levels.extraSecurity.title), findsOneWidget);
    expect(find.text('Synthetic Finland'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home_connection_button')));
    await tester.pump();
    expect(events, ['toggle']);
  });

  testWidgets('fRoyp locks the current full-Home error boundary and keeps retry usable', (tester) async {
    final events = <String>[];
    final fixture = await _mountConnectionHome(
      tester,
      status: AsyncError(StateError('private synthetic failure'), StackTrace.empty),
      profile: connectionProfile,
      events: events,
    );
    addTearDown(() => fixture.close(tester));

    _expectCompleteHome(tester, hasProfile: true);
    _expectStatus(tester, t.connection.failed);
    expect(_actionLabel(tester), t.connection.connect);
    expect(_connectionSemantics(tester).properties.enabled, isTrue);
    expect(find.textContaining('private synthetic failure'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('home_connection_button')));
    await tester.pump();
    expect(events, ['notice', 'toggle']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('official main-list updates refresh latency without changing the connection action', (tester) async {
    final updates = StreamController<OutboundGroupList>.broadcast();
    final fixture = await mountHomeFixture(
      tester,
      child: const _BlizzardHome(),
      extraOverrides: [mainOutboundsNotifierProvider.overrideWith(() => FixtureMainOutbounds(events: updates.stream))],
    );
    addTearDown(() async {
      await fixture.close(tester);
      await updates.close();
    });
    _expectCompleteHome(tester, hasProfile: true);
    expect(find.text(t.pages.proxies.delay.result(delay: 84).replaceFirst(': ', ' ')), findsOneWidget);
    updates.add(fixtureOutbounds(delay: 112));
    await tester.pump();
    await tester.pump();
    expect(fixture.container.read(activeProxyNotifierProvider).requireValue.urlTestDelay, 112);
    _expectStatus(tester, 'VPN ${t.connection.connected}');
    expect(find.text(t.pages.proxies.delay.result(delay: 112).replaceFirst(': ', ' ')), findsOneWidget);
    expect(_actionLabel(tester), t.connection.disconnect);
    expect(find.text('Synthetic Finland'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unavailable selected server shows official health and retains stop and selection', (tester) async {
    final fixture = await mountHomeFixture(
      tester,
      child: const _BlizzardHome(),
      extraOverrides: [mainOutboundsNotifierProvider.overrideWith(() => FixtureMainOutbounds(delay: 65535))],
    );
    addTearDown(() => fixture.close(tester));
    _expectStatus(tester, t.connection.health.pickDead);
    expect(find.text(t.pages.proxies.delay.unavailable), findsOneWidget);
    expect(_actionLabel(tester), t.connection.disconnect);
    expect(_connectionSemantics(tester).properties.enabled, isTrue);
    expect(find.text('Synthetic Finland'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<HomeFixture> _mountConnectionHome(
  WidgetTester tester, {
  required AsyncValue<ConnectionStatus> status,
  required ProfileEntity? profile,
  required List<String> events,
  bool reconnectRequired = false,
}) {
  return mountHomeFixture(
    tester,
    child: const _BlizzardHome(),
    extraOverrides: [
      connectionNotifierProvider.overrideWith(() => ButtonConnectionSpy(status, events)),
      activeProfileProvider.overrideWith(() => FixtureProfile(profile)),
      configOptionNotifierProvider.overrideWith(() => FixtureConfig(reconnectRequired)),
      dialogNotifierProvider.overrideWith(() => FixtureDialogs(events)),
      bottomSheetsNotifierProvider.overrideWith(() => FixtureSheets(events)),
    ],
  );
}

void _expectCompleteHome(WidgetTester tester, {required bool hasProfile}) {
  expect(find.byType(HomePage), findsOneWidget);
  expect(find.byType(ConnectionButton), findsOneWidget);
  expect(find.byType(ActiveProxyFooter), findsOneWidget);
  expect(find.byType(AppVersionLabel), findsOneWidget);
  expect(find.byKey(const ValueKey('profile_quick_settings')), findsOneWidget);
  expect(find.byKey(const ValueKey('profile_add_button')), findsOneWidget);
  expect(find.byType(ProfileTile), hasProfile ? findsOneWidget : findsNothing);

  final canvas = tester.getRect(find.byKey(blizzardFixtureCanvas));
  for (final finder in [
    find.byKey(const ValueKey('blizzard_home_status_slot')),
    find.byKey(const ValueKey('blizzard_home_control_group')),
  ]) {
    final rect = tester.getRect(finder);
    expect(canvas.contains(rect.topLeft), isTrue);
    expect(canvas.contains(rect.bottomRight), isTrue);
  }
  if (hasProfile) {
    final profile = tester.getRect(find.byType(ProfileTile));
    expect(profile.left, greaterThanOrEqualTo(canvas.left));
    expect(profile.right, lessThanOrEqualTo(canvas.right));
    expect(profile.bottom, lessThanOrEqualTo(canvas.bottom));
  }

  final theme = Theme.of(tester.element(find.byType(HomePage)));
  expect(contrastRatio(theme.colorScheme.onSurface, theme.scaffoldBackgroundColor), greaterThanOrEqualTo(4.5));
}

void _expectStatus(WidgetTester tester, String label) {
  final status = find.descendant(
    of: find.byKey(const ValueKey('blizzard_home_status_slot')),
    matching: find.byWidgetPredicate((widget) => widget is Text && widget.data == label),
  );
  expect(status, findsOneWidget);
}

String _actionLabel(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('blizzard_home_action_label'))).data!;

Semantics _connectionSemantics(WidgetTester tester) => tester
    .widgetList<Semantics>(find.descendant(of: find.byType(ConnectionButton), matching: find.byType(Semantics)))
    .singleWhere((semantics) => semantics.properties.button == true && semantics.properties.enabled != null);

class _BlizzardHome extends StatelessWidget {
  const _BlizzardHome();

  @override
  Widget build(BuildContext context) => Theme(
    data: BlizzardTheme.from(Theme.of(context)).copyWith(platform: TargetPlatform.iOS),
    child: const HomePage(),
  );
}
