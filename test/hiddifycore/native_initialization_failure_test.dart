import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
import 'package:hiddify/features/connection/data/connection_data_providers.dart';
import 'package:hiddify/features/connection/data/connection_repository.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Repository implements ConnectionRepository {
  static const failure = ConnectionFailure.backgroundCoreNotAvailable('VPN setup failed (NEVPNErrorDomain: 5).');
  int setupCalls = 0;
  int watchCalls = 0;
  bool failSetup = true;

  @override
  TaskEither<ConnectionFailure, Unit> setup() {
    setupCalls++;
    return TaskEither.fromEither(failSetup ? left(failure) : right(unit));
  }

  @override
  Stream<ConnectionStatus> watchConnectionStatus() {
    watchCalls++;
    if (failSetup) throw StateError('native clients are uninitialized');
    return Stream.value(const ConnectionStatus.disconnected());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Profile extends ActiveProfile {
  @override
  Stream<ProfileEntity?> build() => Stream.value(null);
}

class _Options extends ConfigOptionNotifier {
  @override
  Future<bool> build() async => false;
}

void main() {
  testWidgets('iOS production initialization preserves typed failure, blocks watch and exposes working retry', (
    tester,
  ) async {
    final repository = _Repository();
    final translations = await AppLocale.en.build();
    final container = ProviderContainer(
      overrides: [
        translationsProvider.overrideWith((ref) => translations),
        connectionRepositoryProvider.overrideWith((ref) => repository),
        connectionNotifierProvider.overrideWith(() => ConnectionNotifier(initializeOnBuild: true)),
        activeProfileProvider.overrideWith(_Profile.new),
        configOptionNotifierProvider.overrideWith(_Options.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: const [NovaThemeData.dark]),
          home: const Scaffold(body: ConnectionButton()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(connectionNotifierProvider).error, same(_Repository.failure));
    expect(repository.watchCalls, 0);
    expect(find.textContaining('NEVPNErrorDomain: 5'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    // A repeated failure remains typed and retryable, even without a profile.
    await tester.tap(find.byKey(const ValueKey('home_connection_button')));
    await tester.pumpAndSettle();
    expect(repository.setupCalls, 2);
    expect(repository.watchCalls, 0);
    expect(container.read(connectionNotifierProvider).error, same(_Repository.failure));

    repository.failSetup = false;
    await tester.tap(find.byKey(const ValueKey('home_connection_button')));
    await tester.pumpAndSettle();
    expect(repository.setupCalls, 3);
    expect(repository.watchCalls, 1);
    expect(container.read(connectionNotifierProvider).requireValue, const ConnectionStatus.disconnected());
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Add VPN access'), findsOneWidget);
  });
}
