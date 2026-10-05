import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// Optional handoff export only; normal acceptance assertions are unchanged.
int _captureNumber = 0;
const blizzardFixtureCanvas = ValueKey('blizzard_fixture_canvas');
Future<void> captureBlizzardFixture(WidgetTester tester, String label) async {
  if (!const bool.fromEnvironment('BLIZZARD_CAPTURE') || !Platform.isIOS) return;
  final safeLabel = label.replaceAll(RegExp('[^a-zA-Z0-9_-]'), '-');
  final name = '${(++_captureNumber).toString().padLeft(3, '0')}-$safeLabel';
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(blizzardFixtureCanvas));
  final rendered = await boundary.toImage(pixelRatio: 2);
  final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
  final bytes = data!.buffer.asUint8List();
  final directory = Directory('${Directory.systemTemp.path}/blizzard-captures');
  await directory.create(recursive: true);
  await File('${directory.path}/$name.png').writeAsBytes(bytes);
  rendered.dispose();
}
