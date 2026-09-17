import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
import 'package:hiddify/features/home/widget/nova_protection_status.dart';

void main() {
  testWidgets('checking state does not claim protection is confirmed', (tester) async {
    await _pump(tester, state: NovaProtectionState.checking);

    expect(find.text('CHECKING PROTECTION'), findsOneWidget);
    expect(find.text('Protection confirmed'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('verified state appears only after the protected probe succeeds', (tester) async {
    await _pump(tester, state: NovaProtectionState.verified);

    expect(find.text('PROTECTION CONFIRMED'), findsOneWidget);
    expect(find.byIcon(Icons.verified_user_rounded), findsOneWidget);
  });

  testWidgets('failed check stays retryable without claiming the tunnel disconnected', (tester) async {
    var retried = false;
    await _pump(tester, state: NovaProtectionState.failed, onRetry: () => retried = true);

    expect(find.text('PROTECTION NOT CONFIRMED'), findsOneWidget);
    expect(find.text('Tunnel disconnected'), findsNothing);
    await tester.tap(find.text('Retry check'));
    expect(retried, isTrue);
  });
}

Future<void> _pump(WidgetTester tester, {required NovaProtectionState state, VoidCallback? onRetry}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const [NovaThemeData.dark]),
      home: Scaffold(
        body: NovaProtectionStatus(
          state: state,
          checkingTitle: 'CHECKING PROTECTION',
          verifiedTitle: 'PROTECTION CONFIRMED',
          failedTitle: 'PROTECTION NOT CONFIRMED',
          tunnelStartedLabel: 'Tunnel started',
          checkingMessage: 'Checking internet through the protected connection…',
          verifiedMessage: 'Protection confirmed',
          failedMessage: 'The tunnel is running, but protected internet did not answer.',
          retryLabel: 'Retry check',
          onRetry: onRetry,
        ),
      ),
    ),
  );
  await tester.pump();
}
