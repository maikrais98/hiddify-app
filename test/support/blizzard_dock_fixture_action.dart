import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the real routing callback through the native channel in fixtures.
/// Actual UIKit touches and lens motion are verified separately by XCTest.
Future<void> activateFixtureDockDestination(WidgetTester tester, int index) async {
  final native = find.byWidgetPredicate(
    (widget) => widget is UiKitView && widget.viewType == 'app.blizzard/native-tab-bar',
  );
  if (native.evaluate().isNotEmpty) {
    RenderUiKitView? platformView;
    void visit(RenderObject render) {
      if (render is RenderUiKitView) platformView = render;
      render.visitChildren(visit);
    }

    visit(tester.renderObject(native));
    expect(platformView, isNotNull, reason: 'The native dock must be created before activation');
    final channel = MethodChannel('app.blizzard/native-tab-bar/${platformView!.viewController.id}');
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall('select', {'index': index})),
      (_) {},
    );
  } else {
    final tab = find.byKey(ValueKey('blizzard_bottom_dock_tab_$index'));
    await tester.tap(tab.evaluate().isNotEmpty ? tab : find.byType(NavigationDestination).at(index));
  }
  await tester.pump();
}
