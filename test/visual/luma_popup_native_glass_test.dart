import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_glass.dart';

// Build 48 cut sheets off on iPhone: a native glass view inside a popup above Home's own
// platform views split the popup into overlay layers. Any route that does not cover the
// screen (dialog, menu, sheet) must draw Flutter glass, while full screens keep the native one.
void main() {
  Widget glass() => BlizzardGlass(
    active: true,
    radius: 24,
    child: IconButton(onPressed: () {}, icon: const Icon(Icons.close)),
  );

  testWidgets('a dialog above Home creates no native glass view', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => Dialog(child: glass()),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(UiKitView), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a full screen keeps the native glass view', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: glass())),
      ),
    );
    expect(find.byType(UiKitView), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
