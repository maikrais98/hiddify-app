import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/account_lab/account_lab_page.dart';
import 'package:hiddify/features/account_lab/account_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'repository_test.dart' show FakeApi, MemoryStore;

void main() {
  testWidgets('synthetic login, masked account, logout and no automatic OTP fill', (tester) async {
    final repository = AccountRepository(FakeApi(), MemoryStore());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [accountLabProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: AccountLabPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Получить тестовый код'));
    await tester.pumpAndSettle();
    expect(find.text('Код из тестового почтового ящика'), findsOneWidget);
    final field = find.byKey(const Key('lab-code'));
    expect(tester.widget<TextField>(field).obscureText, isTrue);
    expect(tester.widget<TextField>(field).autofillHints, isNull);
    await tester.enterText(field, '123456');
    await tester.tap(find.text('Войти'));
    await tester.pumpAndSettle();
    expect(find.text('email: a***@example.test'), findsOneWidget);
    expect(find.byKey(const Key('lab-code')), findsNothing);
    await tester.tap(find.text('Выйти из аккаунта'));
    await tester.pumpAndSettle();
    expect(find.text('email: a***@example.test'), findsNothing);
    expect(find.text('Получить тестовый код'), findsOneWidget);
  });
}
