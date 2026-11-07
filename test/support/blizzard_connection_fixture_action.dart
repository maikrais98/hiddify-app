import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises the same callback channel as UIKit; Flutter taps exercise the painted fallback.
/// Actual UIKit touch delivery and system Reduce Motion timing require native test evidence.
Future<void> activateFixtureConnection(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('home_connection_button'));
  final native = find.descendant(
    of: button,
    matching: find.byWidgetPredicate(
      (widget) => widget is UiKitView && widget.viewType == 'app.blizzard/native-connection-control',
    ),
  );
  if (native.evaluate().isNotEmpty) {
    expect(native, findsOneWidget);
    RenderUiKitView? platformView;
    void visit(RenderObject render) {
      if (render is RenderUiKitView) platformView = render;
      render.visitChildren(visit);
    }

    visit(tester.renderObject(native));
    expect(platformView, isNotNull, reason: 'The native control must exist before its callback is delivered');
    final channel = MethodChannel('app.blizzard/native-connection-control/${platformView!.viewController.id}');
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('pressed')),
      (_) {},
    );
  } else {
    await tester.tap(button);
  }
  await tester.pump();
}
