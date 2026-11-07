import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/data/connection_data_providers.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/connection_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final t = AppLocale.en.buildSync();
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'haptic_feedback': false, 'disable_memory_limit': false});
    prefs = await SharedPreferences.getInstance();
  });

  Future<(ButtonConnectionSpy, FixtureDialogs, List<String>)> mount(
    WidgetTester tester,
    AsyncValue<ConnectionStatus> status, {
    int delay = 84,
    bool profile = true,
  }) async {
    final events = <String>[];
    final spy = ButtonConnectionSpy(status, events);
    final dialogs = FixtureDialogs(events);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => prefs),
          translationsProvider.overrideWith((ref) => t),
          connectionNotifierProvider.overrideWith(() => spy),
          activeProfileProvider.overrideWith(() => FixtureProfile(profile ? connectionProfile : null)),
          mainOutboundsNotifierProvider.overrideWith(() => FixtureMainOutbounds(delay: delay)),
          statsNotifierProvider.overrideWith(ConnectionFixtureStats.new),
          dialogNotifierProvider.overrideWith(() => dialogs),
          bottomSheetsNotifierProvider.overrideWith(() => FixtureSheets(events)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: TickerMode(enabled: false, child: Center(child: ConnectionButton())),
          ),
        ),
      ),
    );
    ProviderScope.containerOf(tester.element(find.byType(ConnectionButton))).read(activeProfileProvider);
    await tester.pump();
    await tester.pump();
    return (spy, dialogs, events);
  }

  Finder button() => find.byKey(const ValueKey('home_connection_button'));
  Semantics semantics(WidgetTester tester) => tester
      .widgetList<Semantics>(find.byType(Semantics))
      .singleWhere((s) => s.properties.button == true && s.properties.enabled != null);

  for (final entry in <(AsyncValue<ConnectionStatus>, String, bool, List<String>)>[
    (const AsyncData(Disconnected()), t.connection.tapToConnect, true, ['notice', 'toggle']),
    (const AsyncData(Connecting()), t.connection.connecting, true, ['toggle']),
    (const AsyncData(Waiting()), t.connection.waiting, true, ['toggle']),
    (const AsyncData(NoAvailableProxies()), t.connection.noAvailableProxies, true, ['toggle']),
    (const AsyncData(Connected()), t.connection.connected, true, ['toggle']),
    (const AsyncData(HotReloading()), t.connection.hotReloading, true, ['toggle']),
    (const AsyncData(Disconnecting()), t.connection.disconnecting, false, []),
    (const AsyncLoading(), '', false, []),
    (AsyncError(StateError('synthetic'), StackTrace.empty), t.connection.failed, true, ['notice', 'toggle']),
  ]) {
    testWidgets('official ${entry.$1} label and primary action', (tester) async {
      final (_, _, events) = await mount(tester, entry.$1);
      expect(semantics(tester).properties.label, entry.$2);
      expect(semantics(tester).properties.enabled, entry.$3);
      await tester.tap(button());
      await tester.pump();
      expect(events, entry.$4);
      expect(tester.takeException(), isNull);
    });
  }

  for (final delay in [0, 1, 65000, 65001]) {
    testWidgets('official Connected remains stoppable at proxy latency $delay', (tester) async {
      final (_, _, events) = await mount(tester, const AsyncData(Connected()), delay: delay);
      expect(semantics(tester).properties.enabled, isTrue);
      expect(semantics(tester).properties.label, isNot(t.connection.connecting));
      await tester.tap(button());
      await tester.pump();
      expect(events, ['toggle']);
    });
  }

  testWidgets('no profile awaits dialog and opens import without starting', (tester) async {
    final (_, dialogs, events) = await mount(tester, const AsyncData(Disconnected()), profile: false);
    dialogs.noProfile = Completer<void>();
    await tester.tap(button());
    await tester.pump();
    expect(events, ['no-profile']);
    dialogs.noProfile!.complete();
    await tester.pump();
    expect(events, ['no-profile', 'add-profile:null']);
  });

  testWidgets('cancelled experimental notice prevents start', (tester) async {
    final (_, dialogs, events) = await mount(tester, const AsyncData(Disconnected()));
    dialogs.noticeResult = false;
    await tester.tap(button());
    await tester.pump();
    expect(events, ['notice']);
  });

  testWidgets('disconnected failure stays retryable and keeps its error details action', (tester) async {
    final (_, _, events) = await mount(tester, const AsyncData(Disconnected(MissingVpnPermission())));
    expect(semantics(tester).properties.label, t.connection.failed);
    await tester.tap(find.bySemanticsLabel(t.connection.errorDetails));
    await tester.pump();
    expect(events, ['error-dialog']);
    await tester.tap(button());
    await tester.pump();
    expect(events, ['error-dialog', 'notice', 'toggle']);
  });

  group('real official notifier at repository boundary', () {
    late ProviderContainer container;
    late RecordingConnectionRepository repo;
    Future<void> flush() async {
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    Future<ConnectionNotifier> initialize({bool profile = true}) async {
      repo = RecordingConnectionRepository();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => prefs),
          translationsProvider.overrideWith((ref) => t),
          connectionRepositoryProvider.overrideWithValue(repo),
          activeProfileProvider.overrideWith(() => FixtureProfile(profile ? connectionProfile : null)),
          dialogNotifierProvider.overrideWith(() => FixtureDialogs([])),
        ],
      );
      final notifier = container.read(connectionNotifierProvider.notifier);
      await flush();
      return notifier;
    }

    tearDown(() async {
      container.dispose();
      await repo.statuses.close();
    });

    test('each official state reaches consumers unchanged', () async {
      await initialize();
      for (final status in [
        const Disconnected(),
        const Connecting(),
        const Waiting(),
        const NoAvailableProxies(),
        const Connected(),
        const HotReloading(),
        const Disconnecting(),
      ]) {
        repo.statuses.add(status);
        await flush();
        expect(container.read(connectionNotifierProvider), AsyncData<ConnectionStatus>(status));
      }
      expect(repo.calls, isEmpty);
    });

    test('start passes the retained profile and memory preference', () async {
      final notifier = await initialize();
      repo.statuses.add(const Disconnected());
      await flush();
      await notifier.toggleConnection();
      expect(repo.calls, ['connect']);
      expect(repo.args, [(connectionProfile, false)]);
      expect(container.read(Preferences.startedByUser), isTrue);
      expect(container.read(connectionNotifierProvider).valueOrNull, const Connecting());
    });

    for (final status in [
      const Connecting(),
      const Waiting(),
      const NoAvailableProxies(),
      const Connected(),
      const HotReloading(),
    ]) {
      test('$status stops immediately through the official action', () async {
        final notifier = await initialize();
        repo.statuses.add(status);
        await flush();
        await notifier.toggleConnection();
        expect(repo.calls, ['disconnect']);
        expect(container.read(Preferences.startedByUser), isFalse);
        expect(container.read(connectionNotifierProvider).valueOrNull, const Disconnecting());
      });
    }

    test('a pending start can be stopped without a second start', () async {
      final notifier = await initialize();
      repo.statuses.add(const Disconnected());
      await flush();
      repo.connectGate = Completer<void>();
      final starting = notifier.toggleConnection();
      await flush();
      await notifier.toggleConnection();
      expect(repo.calls, ['connect', 'disconnect']);
      repo.connectGate!.complete();
      await starting;
      expect(container.read(connectionNotifierProvider).valueOrNull, const Disconnecting());
    });

    test('loading and disconnecting ignore another toggle', () async {
      final notifier = await initialize();
      await notifier.toggleConnection();
      repo.statuses.add(const Disconnecting());
      await flush();
      await notifier.toggleConnection();
      expect(repo.calls, isEmpty);
    });

    test('no profile never invokes repository start', () async {
      final notifier = await initialize(profile: false);
      repo.statuses.add(const Disconnected());
      await flush();
      await notifier.toggleConnection();
      expect(repo.calls, isEmpty);
    });

    for (final status in [const Connected(), const Waiting(), const NoAvailableProxies(), const HotReloading()]) {
      test('$status reconnects through the official running-state API', () async {
        final notifier = await initialize();
        repo.statuses.add(status);
        await flush();
        await notifier.reconnect(connectionProfile);
        expect(repo.calls, ['reconnect']);
        expect(repo.args, [(connectionProfile, false)]);
        await notifier.reconnect(null);
        expect(repo.calls, ['reconnect', 'disconnect']);
      });
    }

    test('failed start publishes Disconnected with failure and clears started flag', () async {
      final notifier = await initialize();
      repo.statuses.add(const Disconnected());
      await flush();
      repo.failure = const MissingVpnPermission();
      await notifier.toggleConnection();
      await flush();
      expect(repo.calls, ['connect']);
      expect(container.read(connectionNotifierProvider).valueOrNull, const Disconnected(MissingVpnPermission()));
      expect(container.read(Preferences.startedByUser), isFalse);
    });
  });
}
