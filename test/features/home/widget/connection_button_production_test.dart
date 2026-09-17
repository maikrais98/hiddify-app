import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/home/widget/home_page.dart';
import 'package:hiddify/features/home/widget/nova_connection_control.dart';
import 'package:hiddify/features/identity/data/identity_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _ConnectionState extends ConnectionNotifier {
  _ConnectionState(this.source);

  final Stream<ConnectionStatus> source;

  @override
  Stream<ConnectionStatus> build() => source;
}

class _ProfileState extends ActiveProfile {
  _ProfileState(this.source);

  final Stream<ProfileEntity?> source;
  int buildCount = 0;

  @override
  Stream<ProfileEntity?> build() {
    buildCount++;
    return source;
  }
}

class _ProxyState extends ActiveProxyNotifier {
  @override
  Stream<OutboundInfo> build() => const Stream.empty();
}

class _ReconnectState extends ConfigOptionNotifier {
  @override
  Future<bool> build() async => false;
}

class _RecordingBottomSheets extends BottomSheetsNotifier {
  int addProfileCount = 0;

  @override
  void build() {}

  @override
  Future<void> showAddProfile({String? url, bool triggeredByDeepLink = false}) async {
    addProfileCount++;
  }
}

class _RecordingDialogs extends DialogNotifier {
  int noActiveProfileCount = 0;

  @override
  void build() {}

  @override
  Future<void> showNoActiveProfile() async {
    noActiveProfileCount++;
  }
}

void main() {
  Future<void> pumpProductionHome(
    WidgetTester tester,
    Stream<ProfileEntity?> profiles, {
    bool wholePage = false,
    double textScale = 1,
    _ProfileState? profileState,
    _RecordingBottomSheets? bottomSheets,
    _RecordingDialogs? dialogs,
    Stream<ConnectionStatus>? connection,
  }) async {
    final translations = await AppLocale.en.build();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWith((ref) => translations),
          connectionNotifierProvider.overrideWith(
            () => _ConnectionState(connection ?? Stream.value(const ConnectionStatus.disconnected())),
          ),
          activeProfileProvider.overrideWith(() => profileState ?? _ProfileState(profiles)),
          activeProxyNotifierProvider.overrideWith(_ProxyState.new),
          configOptionNotifierProvider.overrideWith(_ReconnectState.new),
          installationIdentityProvider.overrideWith((ref) => 'test-installation'),
          if (bottomSheets != null) bottomSheetsNotifierProvider.overrideWith(() => bottomSheets),
          if (dialogs != null) dialogNotifierProvider.overrideWith(() => dialogs),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [NovaThemeData.dark]),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: wholePage ? const HomePage() : const Scaffold(body: ConnectionButton()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('connected with unknown reachability offers disconnect, never connecting', (tester) async {
    final profile = ProfileEntity.local(
      id: 'connected-profile',
      active: true,
      name: 'Profile',
      lastUpdate: DateTime.utc(2026),
    );
    await pumpProductionHome(
      tester,
      Stream.value(profile),
      connection: Stream.value(const ConnectionStatus.connected()),
    );
    await tester.pump();
    final control = tester.widget<NovaConnectionControl>(find.byType(NovaConnectionControl));
    expect(control.connected, isTrue);
    expect(control.loading, isFalse);
    expect(control.enabled, isTrue);
    expect(control.label, 'Disconnect');
    expect(find.text('Connecting...'), findsNothing);
  });

  testWidgets('disables the production connection action while profile state is loading', (tester) async {
    await pumpProductionHome(tester, const Stream.empty());

    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('home_connection_button'))).flagsCollection.isEnabled,
      Tristate.isFalse,
    );
  });

  testWidgets('disables the production connection action when profile loading fails', (tester) async {
    await pumpProductionHome(tester, Stream.error(StateError('profile failed')));
    await tester.pump();

    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('home_connection_button'))).flagsCollection.isEnabled,
      Tristate.isFalse,
    );
  });

  testWidgets('opens Add VPN access directly from the no-profile connection action', (tester) async {
    final bottomSheets = _RecordingBottomSheets();
    final dialogs = _RecordingDialogs();
    await pumpProductionHome(tester, Stream.value(null), bottomSheets: bottomSheets, dialogs: dialogs);
    await tester.pump();

    expect(find.text('Add VPN access'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home_connection_button')));
    await tester.pump();

    expect(bottomSheets.addProfileCount, 1);
    expect(dialogs.noActiveProfileCount, 0);
  });

  for (final textScale in const [1.0, 2.0]) {
    testWidgets('keeps the production hero action available at ${textScale}x text scale', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final bottomSheets = _RecordingBottomSheets();

      await pumpProductionHome(
        tester,
        Stream.value(null),
        wholePage: true,
        textScale: textScale,
        bottomSheets: bottomSheets,
        connection: Stream.value(const ConnectionStatus.disconnected(ConnectionFailure.unexpected())),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final action = find.byKey(const ValueKey('home_connection_button'));
      expect(action, findsOneWidget);
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pump();
      expect(bottomSheets.addProfileCount, 1);
    });
  }

  for (final connection in <Stream<ConnectionStatus>>[
    Stream.value(const ConnectionStatus.connected()),
    const Stream.empty(),
  ]) {
    testWidgets('keeps no-profile import primary across independent connection states', (tester) async {
      final bottomSheets = _RecordingBottomSheets();
      await pumpProductionHome(tester, Stream.value(null), bottomSheets: bottomSheets, connection: connection);
      await tester.pump();

      final control = tester.widget<NovaConnectionControl>(find.byType(NovaConnectionControl));
      expect(control.enabled, isTrue);
      expect(control.connected, isFalse);
      expect(control.loading, isFalse);
      expect(find.text('Add VPN access'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('home_connection_button')));
      await tester.pump();
      expect(bottomSheets.addProfileCount, 1);
    });
  }

  testWidgets('Home no-access state has one import action and no expert server action', (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final bottomSheets = _RecordingBottomSheets();
    final dialogs = _RecordingDialogs();
    await pumpProductionHome(tester, Stream.value(null), wholePage: true, bottomSheets: bottomSheets, dialogs: dialogs);
    await tester.pump();

    expect(find.byType(NovaNoAccessCard), findsOneWidget);
    expect(find.text('Set up your own VPN server (advanced)'), findsNothing);
    expect(find.byKey(const ValueKey('home_server_card')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home_server_card')));
    await tester.pump();

    expect(dialogs.noActiveProfileCount, 0);
    expect(bottomSheets.addProfileCount, 1);
  });

  testWidgets('HomePage presents loading without a recovery action while the profile provider loads', (tester) async {
    await pumpProductionHome(tester, const Stream.empty(), wholePage: true);

    expect(find.byType(NovaHomeRecoveryCard), findsOneWidget);
    expect(find.text('Loading VPN access'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('HomePage retries a profile-provider error and keeps import available', (tester) async {
    final profileState = _ProfileState(Stream.error(StateError('profile failed')));
    await pumpProductionHome(tester, const Stream.empty(), wholePage: true, profileState: profileState);
    await tester.pump();

    expect(find.byType(NovaHomeRecoveryCard), findsOneWidget);
    expect(find.text('Could not load VPN access'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Add VPN access'), findsOneWidget);

    final initialBuildCount = profileState.buildCount;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(profileState.buildCount, greaterThan(initialBuildCount));
  });

  testWidgets('HomePage shows stale subscription metadata explicitly', (tester) async {
    final now = DateTime.now();
    final lastUpdate = now.subtract(const Duration(hours: 25));
    final expiresAt = now.add(const Duration(days: 10));
    final profile = ProfileEntity.remote(
      id: 'profile',
      active: true,
      name: 'Profile',
      url: 'https://example.com/subscription',
      lastUpdate: lastUpdate,
      options: const ProfileOptions(updateInterval: Duration(hours: 24)),
      subInfo: SubscriptionInfo(upload: 10, download: 20, total: 100, expire: expiresAt),
      populatedHeaders: {
        'subscription-userinfo':
            'upload=10; download=20; total=100; expire=${expiresAt.millisecondsSinceEpoch ~/ 1000}',
      },
    );

    await pumpProductionHome(tester, Stream.value(profile), wholePage: true);
    await tester.pump();

    expect(find.text('Last access update: ${lastUpdate.format()} · Update subscriptions'), findsOneWidget);
  });
}
