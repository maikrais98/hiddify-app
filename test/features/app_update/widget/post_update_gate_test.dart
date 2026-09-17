import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/features/app_update/notifier/post_update_notifier.dart';
import 'package:hiddify/features/app_update/widget/post_update_gate.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ConnectionState extends ConnectionNotifier {
  _ConnectionState(this.source);

  final Stream<ConnectionStatus> source;
  int connectRequests = 0;

  @override
  Stream<ConnectionStatus> build() => source;

  @override
  Future<void> mayConnect() async => connectRequests++;
}

class _ProfileState extends ActiveProfile {
  _ProfileState(this.source);

  final Stream<ProfileEntity?> source;

  @override
  Stream<ProfileEntity?> build() => source;
}

void main() {
  test('reconnect is available only for a user-started disconnected VPN with an active profile', () {
    expect(
      canReconnectAfterUpdate(
        connection: const ConnectionStatus.disconnected(),
        startedByUser: true,
        hasActiveProfile: true,
      ),
      isTrue,
    );

    for (final connection in const [
      ConnectionStatus.connected(),
      ConnectionStatus.connecting(),
      ConnectionStatus.disconnecting(),
    ]) {
      expect(canReconnectAfterUpdate(connection: connection, startedByUser: true, hasActiveProfile: true), isFalse);
    }
    expect(
      canReconnectAfterUpdate(
        connection: const ConnectionStatus.disconnected(),
        startedByUser: false,
        hasActiveProfile: true,
      ),
      isFalse,
    );
    expect(
      canReconnectAfterUpdate(
        connection: const ConnectionStatus.disconnected(),
        startedByUser: true,
        hasActiveProfile: false,
      ),
      isFalse,
    );
  });

  testWidgets('waits for startup state, acknowledges after action, and reconnects once', (tester) async {
    SharedPreferences.setMockInitialValues({PostUpdateNotifier.lastAcknowledgedRevisionKey: '4.1.1+40101'});
    final preferences = await SharedPreferences.getInstance();
    final postUpdate = PostUpdateNotifier(
      preferences: preferences,
      currentVersion: '4.1.2',
      currentBuildNumber: '40102',
    );
    final connectionEvents = StreamController<ConnectionStatus>();
    final profileEvents = StreamController<ProfileEntity?>();
    final connection = _ConnectionState(connectionEvents.stream);
    final profile = ProfileEntity.local(
      id: 'active',
      active: true,
      name: 'Active profile',
      lastUpdate: DateTime.utc(2026),
    );
    addTearDown(connectionEvents.close);
    addTearDown(profileEvents.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          postUpdateNotifierProvider.overrideWith((ref) => postUpdate),
          postUpdateReconnectIntentProvider.overrideWith((ref) => true),
          connectionNotifierProvider.overrideWith(() => connection),
          activeProfileProvider.overrideWith(() => _ProfileState(profileEvents.stream)),
        ],
        child: MaterialApp(
          navigatorKey: rootNavKey,
          home: const PostUpdateGate(child: Scaffold(body: Text('Home'))),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Update installed'), findsNothing);
    expect(preferences.getString(PostUpdateNotifier.lastAcknowledgedRevisionKey), '4.1.1+40101');

    connectionEvents.add(const ConnectionStatus.disconnected());
    profileEvents.add(profile);
    await tester.pumpAndSettle();

    expect(find.text('Update installed'), findsOneWidget);
    expect(find.text('Reconnect'), findsOneWidget);
    expect(preferences.getString(PostUpdateNotifier.lastAcknowledgedRevisionKey), '4.1.1+40101');

    await tester.tap(find.text('Reconnect'));
    await tester.pumpAndSettle();

    expect(connection.connectRequests, 1);
    expect(preferences.getString(PostUpdateNotifier.lastAcknowledgedRevisionKey), '4.1.2+40102');
    expect(find.text('Update installed'), findsNothing);

    await tester.pump();
    expect(find.text('Update installed'), findsNothing);
  });

  testWidgets('shows a bounded unknown outcome when startup providers never resolve', (tester) async {
    SharedPreferences.setMockInitialValues({PostUpdateNotifier.lastAcknowledgedRevisionKey: '4.1.1+40101'});
    final preferences = await SharedPreferences.getInstance();
    final postUpdate = PostUpdateNotifier(
      preferences: preferences,
      currentVersion: '4.1.2',
      currentBuildNumber: '40102',
    );
    final connectionEvents = StreamController<ConnectionStatus>();
    final profileEvents = StreamController<ProfileEntity?>();
    addTearDown(connectionEvents.close);
    addTearDown(profileEvents.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          postUpdateNotifierProvider.overrideWith((ref) => postUpdate),
          postUpdateReconnectIntentProvider.overrideWith((ref) => false),
          postUpdateStartupResolutionTimeoutProvider.overrideWith((ref) => const Duration(milliseconds: 1)),
          connectionNotifierProvider.overrideWith(() => _ConnectionState(connectionEvents.stream)),
          activeProfileProvider.overrideWith(() => _ProfileState(profileEvents.stream)),
        ],
        child: MaterialApp(
          navigatorKey: rootNavKey,
          home: const PostUpdateGate(child: Scaffold(body: Text('Home'))),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 5));
    await tester.pumpAndSettle();

    expect(find.text('Update installed'), findsOneWidget);
    expect(find.text('Reconnect'), findsNothing);
    expect(find.textContaining('Check the active profile'), findsOneWidget);
  });
}
