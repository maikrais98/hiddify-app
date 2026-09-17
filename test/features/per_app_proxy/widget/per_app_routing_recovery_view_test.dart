import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/per_app_proxy/data/per_app_routing_repository.dart';
import 'package:hiddify/features/per_app_proxy/widget/per_app_routing_recovery_view.dart';

void main() {
  testWidgets('restricted inventory offers retry and continue without per-app, not Android settings', (tester) async {
    var retried = false;
    var continued = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: const [Locale('en'), Locale('ru')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: PerAppRoutingRecoveryView(
            failure: const PerAppRoutingException(kind: PerAppRoutingFailureKind.denied),
            onRetry: () => retried = true,
            onContinueWithoutPerApp: () => continued = true,
          ),
        ),
      ),
    );

    expect(find.text('Маршрутизация приложений недоступна'), findsOneWidget);
    expect(find.textContaining('нельзя включить в настройках Android'), findsOneWidget);
    expect(find.text('Открыть настройки Android'), findsNothing);

    await tester.tap(find.text('Повторить'));
    await tester.tap(find.text('Продолжить без маршрутизации приложений'));
    expect(retried, isTrue);
    expect(continued, isTrue);
  });

  testWidgets('unavailable inventory uses truthful temporary-failure copy', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PerAppRoutingRecoveryView(
            failure: const PerAppRoutingException(kind: PerAppRoutingFailureKind.unavailable),
            onRetry: () {},
            onContinueWithoutPerApp: () {},
          ),
        ),
      ),
    );

    expect(find.text('App routing unavailable'), findsOneWidget);
    expect(find.textContaining('could not read the installed-app list'), findsOneWidget);
    expect(find.text('Open Android settings'), findsNothing);
  });
}
