import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/home/widget/home_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../support/connection_fixtures.dart';
import '../support/home_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('luma Home paints official status changes made while its route is offstage', (tester) async {
    final fixture = await mountHomeFixture(
      tester,
      locale: AppLocale.ru,
      child: Builder(
        builder: (context) => Theme(
          data: BlizzardTheme.from(Theme.of(context)).copyWith(platform: TargetPlatform.iOS),
          child: const HomePage(),
        ),
      ),
    );
    addTearDown(() => fixture.close(tester));
    final t = fixture.container.read(translationsProvider).requireValue;
    final notifier = fixture.container.read(connectionNotifierProvider.notifier) as ButtonConnectionSpy;
    notifier.state = const AsyncData(Connecting());
    await tester.pump();
    expect(find.text(t.connection.connecting), findsOneWidget);

    fixture.router.go('/settings');
    await tester.pump();
    notifier.state = const AsyncData(Waiting());
    await tester.pump();
    fixture.router.go('/home');
    await tester.pump();
    expect(find.text(t.connection.waiting), findsOneWidget);
    expect(find.text(t.connection.connecting), findsNothing);

    notifier.state = const AsyncData(Connected());
    await tester.pump();
    expect(find.text('VPN подключён'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
