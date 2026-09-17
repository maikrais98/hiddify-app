import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/app_update/widget/post_update_outcome_dialog.dart';

void main() {
  Widget subject({VoidCallback? onReconnect, bool isConnected = false}) => MaterialApp(
    locale: const Locale('ru'),
    supportedLocales: const [Locale('ru'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Scaffold(
      body: PostUpdateOutcomeDialog(
        currentVersion: '4.1.2',
        isConnected: isConnected,
        onReconnect: onReconnect,
        onClose: () {},
      ),
    ),
  );

  testWidgets('shows only the verified running version and preserved-settings outcome', (tester) async {
    await tester.pumpWidget(subject());

    expect(find.text('Обновление установлено'), findsOneWidget);
    expect(find.textContaining('4.1.2'), findsOneWidget);
    expect(find.textContaining('Проверка версии не изменяла настройки и профили'), findsOneWidget);
    expect(find.textContaining('Откат'), findsNothing);
    expect(find.textContaining('rollback'), findsNothing);
  });

  testWidgets('offers reconnect only when a safe reconnect callback exists', (tester) async {
    var reconnects = 0;
    await tester.pumpWidget(subject(onReconnect: () => reconnects++));

    await tester.tap(find.text('Подключиться снова'));

    expect(reconnects, 1);
  });

  testWidgets('does not offer reconnect while the VPN is already connected', (tester) async {
    await tester.pumpWidget(subject(isConnected: true, onReconnect: () {}));

    expect(find.text('Подключиться снова'), findsNothing);
    expect(find.textContaining('VPN уже подключён'), findsOneWidget);
  });
}
