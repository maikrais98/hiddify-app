import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/loading/widget/matrix_loading_screen.dart';

void main() {
  testWidgets('shows approved copy, centered rabbit, and brand signature', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MatrixLoadingScreen(rabbit: SizedBox(key: ValueKey('rabbit'))),
      ),
    );

    expect(find.text('Следуй за белым кроликом'), findsOneWidget);
    expect(find.text('Woman in Red'), findsOneWidget);
    expect(find.byKey(const ValueKey('rabbit')), findsOneWidget);
    expect(tester.getCenter(find.byKey(const ValueKey('rabbit'))).dx, closeTo(400, 1));
  });

  testWidgets('shows retry state after bootstrap failure', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MatrixLoadingScreen(error: StateError('boom'), onRetry: () => retried = true, rabbit: const SizedBox()),
      ),
    );

    expect(find.text('Не удалось запустить приложение'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    expect(retried, isTrue);
  });
}
