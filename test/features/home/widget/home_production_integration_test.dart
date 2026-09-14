import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/home/widget/home_page.dart';
import 'package:hiddify/features/home/widget/nova_ritual_hero.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('preserves Home server-card route decisions', () {
    final profile = ProfileEntity.local(id: 'local', active: true, name: 'Local', lastUpdate: DateTime(2026));

    expect(
      novaHomeServerActionForStates(
        profile: const AsyncData<ProfileEntity?>(null),
        proxy: const AsyncLoading<OutboundInfo?>(),
      ),
      NovaHomeServerAction.addProfile,
    );
    expect(
      novaHomeServerActionForStates(
        profile: AsyncData<ProfileEntity?>(profile),
        proxy: const AsyncData<OutboundInfo?>(null),
      ),
      NovaHomeServerAction.showProfiles,
    );
    expect(
      novaHomeServerActionForStates(
        profile: AsyncData<ProfileEntity?>(profile),
        proxy: AsyncData<OutboundInfo?>(OutboundInfo(tag: 'auto')),
      ),
      NovaHomeServerAction.showProxies,
    );
  });

  test('keeps server-card actions disabled while profile or proxy state is unresolved', () {
    final profile = ProfileEntity.local(id: 'local', active: true, name: 'Local', lastUpdate: DateTime(2026));

    expect(
      novaHomeServerActionForStates(
        profile: const AsyncLoading<ProfileEntity?>(),
        proxy: const AsyncData<OutboundInfo?>(null),
      ),
      isNull,
    );
    expect(
      novaHomeServerActionForStates(
        profile: AsyncError<ProfileEntity?>(StateError('profile failed'), StackTrace.empty),
        proxy: const AsyncData<OutboundInfo?>(null),
      ),
      isNull,
    );
    expect(
      novaHomeServerActionForStates(
        profile: AsyncData<ProfileEntity?>(profile),
        proxy: const AsyncLoading<OutboundInfo?>(),
      ),
      isNull,
    );
    expect(
      novaHomeServerActionForStates(
        profile: AsyncData<ProfileEntity?>(profile),
        proxy: AsyncError<OutboundInfo?>(StateError('proxy failed'), StackTrace.empty),
      ),
      isNull,
    );
  });

  test('distinguishes Home recovery states before choosing an action', () {
    final profile = ProfileEntity.local(id: 'local', active: true, name: 'Local', lastUpdate: DateTime(2026));

    expect(
      novaHomeServerStateForStates(
        profile: const AsyncData<ProfileEntity?>(null),
        proxy: const AsyncLoading<OutboundInfo?>(),
      ),
      NovaHomeServerState.empty,
    );
    expect(
      novaHomeServerStateForStates(
        profile: const AsyncLoading<ProfileEntity?>(),
        proxy: const AsyncData<OutboundInfo?>(null),
      ),
      NovaHomeServerState.loading,
    );
    expect(
      novaHomeServerStateForStates(
        profile: AsyncError<ProfileEntity?>(StateError('profile failed'), StackTrace.empty),
        proxy: const AsyncData<OutboundInfo?>(null),
      ),
      NovaHomeServerState.profileError,
    );
    expect(
      novaHomeServerStateForStates(
        profile: AsyncData<ProfileEntity?>(profile),
        proxy: AsyncError<OutboundInfo?>(StateError('proxy failed'), StackTrace.empty),
      ),
      NovaHomeServerState.proxyError,
    );
    expect(
      novaHomeServerStateForStates(
        profile: AsyncData<ProfileEntity?>(profile),
        proxy: const AsyncError<OutboundInfo?>(ServiceNotRunning(), StackTrace.empty),
      ),
      NovaHomeServerState.serviceStopped,
    );
  });

  test('maps connection failures to the error ritual state', () {
    expect(
      novaRitualStateForConnection(
        const AsyncData<ConnectionStatus>(ConnectionStatus.disconnected(ConnectionFailure.unexpected())),
      ),
      NovaRitualState.error,
    );
    expect(
      novaRitualStateForConnection(const AsyncData<ConnectionStatus>(ConnectionStatus.disconnected())),
      NovaRitualState.disconnected,
    );
    expect(
      novaRitualStateForConnection(AsyncError<ConnectionStatus>(StateError('provider failed'), StackTrace.empty)),
      NovaRitualState.error,
    );
  });

  testWidgets('server card disables navigation and shows progress while loading', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [NovaThemeData.dark]),
        home: const Scaffold(
          body: NovaServerCard(
            profile: null,
            proxy: null,
            addProfileLabel: 'Add profile',
            profilesLabel: 'Profiles',
            errorLabel: 'Failed to load',
            isLoading: true,
            hasError: false,
            onTap: null,
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
  });

  testWidgets('server card disables navigation and surfaces provider errors', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [NovaThemeData.dark]),
        home: const Scaffold(
          body: NovaServerCard(
            profile: null,
            proxy: null,
            addProfileLabel: 'Add profile',
            profilesLabel: 'Profiles',
            errorLabel: 'Failed to load',
            isLoading: false,
            hasError: true,
            onTap: null,
          ),
        ),
      ),
    );

    expect(find.text('Failed to load'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
  });

  testWidgets('Home recovery card exposes retry and import actions', (tester) async {
    var retries = 0;
    var imports = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [NovaThemeData.dark]),
        home: Scaffold(
          body: NovaHomeRecoveryCard(
            title: 'Could not load access',
            message: 'Try again or add access',
            primaryLabel: 'Retry',
            onPrimary: () => retries++,
            secondaryLabel: 'Add VPN access',
            onSecondary: () => imports++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Retry'));
    await tester.tap(find.text('Add VPN access'));

    expect(retries, 1);
    expect(imports, 1);
  });

  testWidgets('Home loading card has progress without a misleading action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [NovaThemeData.dark]),
        home: const Scaffold(
          body: NovaHomeRecoveryCard(title: 'Loading access', message: 'Please wait', loading: true),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Add VPN access'), findsNothing);
  });
}
