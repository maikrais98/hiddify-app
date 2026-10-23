import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_glass.dart';

void main() {
  testWidgets('native glass leaves optics to UIKit and preserves child interaction', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, (_) async => null);
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, null),
    );
    var taps = 0;
    const capture = ValueKey('optical-capture');
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: capture,
            child: ColoredBox(
              color: const Color(0xFF06121D),
              child: SizedBox(
                width: 320,
                height: 64,
                child: BlizzardGlass(
                  active: true,
                  radius: 32,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => taps++,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(UiKitView), findsOneWidget);
    await tester.tap(find.byType(BlizzardGlass));
    expect(taps, 1);
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(capture));
    final pixels = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return bytes!;
    });
    int red(int x, int y) => pixels!.getUint8((y * 320 + x) * 4);
    // Widget tests omit platform-view pixels. Any gradient here would be a
    // Flutter-drawn highlight layered over the genuine UIKit material.
    expect(red(160, 1), red(160, 32));
    expect(red(160, 8), red(160, 56));
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
