import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/home/widget/home_page.dart';
import 'package:hiddify/features/identity/data/identity_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _ConnectionState extends ConnectionNotifier {
  @override
  Stream<ConnectionStatus> build() => Stream.value(const ConnectionStatus.disconnected());
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

void main() {
  Future<void> pumpProductionHome(
    WidgetTester tester,
    Stream<ProfileEntity?> profiles, {
    bool wholePage = false,
    _ProfileState? profileState,
  }) async {
    final translations = await AppLocale.en.build();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWith((ref) => translations),
          connectionNotifierProvider.overrideWith(_ConnectionState.new),
          activeProfileProvider.overrideWith(() => profileState ?? _ProfileState(profiles)),
          activeProxyNotifierProvider.overrideWith(_ProxyState.new),
          configOptionNotifierProvider.overrideWith(_ReconnectState.new),
          installationIdentityProvider.overrideWith((ref) => 'test-installation'),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [NovaThemeData.dark]),
          home: wholePage ? const HomePage() : const Scaffold(body: ConnectionButton()),
        ),
      ),
    );
    await tester.pump();
  }

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
}
