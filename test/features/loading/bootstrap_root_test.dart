import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/loading/widget/bootstrap_root.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets('shows loading until initialization and minimum duration complete', (tester) async {
    final completer = Completer<ProviderContainer>();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      BootstrapRoot(
        initialize: () => completer.future,
        minimumDuration: const Duration(seconds: 1),
        appBuilder: (_) => const MaterialApp(home: Text('ready')),
        onFirstFrame: () {},
      ),
    );

    expect(find.text('Следуй за белым кроликом'), findsOneWidget);
    completer.complete(container);
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('ready'), findsNothing);
    await tester.pump(const Duration(milliseconds: 101));
    await tester.pumpAndSettle();
    expect(find.text('ready'), findsOneWidget);
  });

  testWidgets('required failure offers retry', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      BootstrapRoot(
        initialize: () async {
          attempts++;
          throw StateError('boom');
        },
        minimumDuration: Duration.zero,
        onFirstFrame: () {},
      ),
    );
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    await tester.tap(find.text('Повторить'));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(attempts, 2);
  });
}
