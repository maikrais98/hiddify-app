import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_native_connection_control.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_native_tab_bar.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/blizzard_stage_ack.dart';

// Exact-source native capture recipe (run only after the source freeze):
//
// flutter test --no-pub integration_test/blizzard_native_glass_optics_test.dart \
//   -d <simulator-udid> --dart-define=BLIZZARD_OPTICS_CAPTURE=true
//
// For each emitted `BLIZZARD_CAPTURE_READY <name> <run-id> <ack-path>`, run:
//
// printf 'accepted\n' > <ack-path>
// xcrun simctl io <simulator-udid> screenshot --type=png <output>/<name>.png
// printf 'captured\n' > <ack-path>
//
// The accepted ACK extends the runner completion window; the target advances
// only after the screenshot finishes and the nonce-specific ACK says captured.
// At the required 393x852 logical viewport, compare identical phase A/B crops
// inside the primary control (x=122.5..270.5, y=164..312) and the tab bar
// (x=36.5..356.5, y=692..780). The native control state stays fixed while the
// high-contrast bands beneath both crops move, isolating backdrop sampling.
const _captureEnabled = bool.fromEnvironment('BLIZZARD_OPTICS_CAPTURE');
final _stageRunId = DateTime.now().microsecondsSinceEpoch.toRadixString(16);

Future<void> _capture(WidgetTester tester, String name) async {
  final ack = File('${Directory.systemTemp.path}/blizzard_capture_${name}_$_stageRunId.ack');
  final result = await tester.runAsync<StageAckRunResult>(
    () => StageAckRunResult.guard(
      () => waitForStageAck(
        ack: ack,
        emitMarker: () => debugPrint('BLIZZARD_CAPTURE_READY $name $_stageRunId ${ack.path}'),
        policy: captureStageAckPolicy(name),
        stage: 'capture/$name',
      ),
    ),
  );
  if (result == null) {
    throw StateError('Runner ack result missing: capture/$name');
  }
  result.rethrowFailure();
}

Future<void> _settleNativeComposition(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 750)));
  await tester.pump();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  setUpAll(() async {
    // Match the primary visual harness: warm the live iOS renderer and its
    // platform-owned accessibility client before the measured target mounts.
    runApp(const MaterialApp(home: SizedBox.shrink()));
    await binding.endOfFrame;
    await Future<void>.delayed(const Duration(seconds: 1));
  });

  testWidgets('production Blizzard native controls sample two controlled backdrops', (tester) async {
    expect(Platform.isIOS, isTrue, reason: 'Native optical evidence requires an actual iOS process');
    expect(defaultTargetPlatform, TargetPlatform.iOS);

    final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
    if (_captureEnabled) {
      expect(viewport.width, closeTo(393, .01));
      expect(viewport.height, closeTo(852, .01));
    }

    final sceneKey = GlobalKey<_NativeGlassOpticsSceneState>();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: _NativeGlassOpticsScene(key: sceneKey),
      ),
    );
    await _settleNativeComposition(tester);

    expect(find.byKey(const ValueKey('optics_backdrop_phase_a')), findsOneWidget);
    expect(find.byType(BlizzardNativeConnectionControl), findsOneWidget);
    expect(find.byType(BlizzardNativeTabBar), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('optics_primary'))), const Size.square(148));
    expect(tester.getSize(find.byKey(const ValueKey('optics_tab_bar'))), const Size(320, 88));

    final nativeViews = tester.widgetList<UiKitView>(find.byType(UiKitView)).toList();
    expect(nativeViews, hasLength(2));
    expect(
      nativeViews.map((view) => view.viewType),
      unorderedEquals(['app.blizzard/native-connection-control', 'app.blizzard/native-tab-bar']),
    );
    expect(
      nativeViews.map((view) => view.creationParams),
      unorderedEquals([
        {'enabled': true, 'visible': true, 'label': 'Connect', 'connectionState': 'disconnected'},
        {
          'titles': ['Home', 'Settings'],
          'selectedIndex': 0,
          'tint': BlizzardPalette.accent.toARGB32(),
          'dark': true,
        },
      ]),
    );
    expect(nativeViews.every((view) => view.creationParamsCodec is StandardMessageCodec), isTrue);
    expect(tester.takeException(), isNull);

    // This target measures compositor output only. The callbacks satisfy the
    // production constructors; neither synthetic taps nor physical touches
    // participate in the phase comparison.
    if (_captureEnabled) await _capture(tester, 'native_glass_optics_phase_a');

    sceneKey.currentState!.showPhaseB();
    await _settleNativeComposition(tester);
    expect(find.byKey(const ValueKey('optics_backdrop_phase_b')), findsOneWidget);
    expect(find.byType(UiKitView), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    if (_captureEnabled) await _capture(tester, 'native_glass_optics_phase_b');

    // Reduce Transparency belongs to UIKit and the production native controls.
    // MediaQuery.highContrast is a different preference, so this target makes
    // no Reduce Transparency claim and leaves the OS setting untouched.
    debugPrint(
      'BLIZZARD_OPTICS_COMPLETE phases=2 primary=148x148 tabbar=320x88 '
      'native_views=2 controls=production backdrop_ab=controlled reduce_transparency=os_owned_unasserted',
    );
  });
}

class _NativeGlassOpticsScene extends StatefulWidget {
  const _NativeGlassOpticsScene({super.key});

  @override
  State<_NativeGlassOpticsScene> createState() => _NativeGlassOpticsSceneState();
}

class _NativeGlassOpticsSceneState extends State<_NativeGlassOpticsScene> {
  var _phase = 0;

  void showPhaseB() => setState(() => _phase = 1);

  @override
  Widget build(BuildContext context) {
    final phaseName = _phase == 0 ? 'a' : 'b';
    return Scaffold(
      backgroundColor: BlizzardPalette.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          KeyedSubtree(
            key: ValueKey('optics_backdrop_phase_$phaseName'),
            child: CustomPaint(painter: _ControlledBackdropPainter(_phase)),
          ),
          const Positioned(
            top: 72,
            left: 20,
            right: 20,
            child: Text(
              'SYSTEM COMPOSITOR · CONTROLLED BACKDROP',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.1),
            ),
          ),
          Positioned(
            top: 164,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox.square(
                key: const ValueKey('optics_primary'),
                dimension: 148,
                child: BlizzardNativeConnectionControl(
                  enabled: true,
                  label: 'Connect',
                  connectionState: 'disconnected',
                  onPressed: _ignorePrimaryAction,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 72,
            child: Center(
              child: SizedBox(
                key: const ValueKey('optics_tab_bar'),
                width: 320,
                height: 88,
                child: BlizzardNativeTabBar(
                  titles: const ['Home', 'Settings'],
                  selectedIndex: 0,
                  tint: BlizzardPalette.accent,
                  onDestinationSelected: _ignoreTabSelection,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _ignorePrimaryAction() {}

  void _ignoreTabSelection(int _) {}
}

class _ControlledBackdropPainter extends CustomPainter {
  const _ControlledBackdropPainter(this.phase);

  final int phase;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = BlizzardPalette.background);

    const colors = [Color(0xFFFF3B81), Color(0xFF00D4FF), Color(0xFFFFD60A), Color(0xFF8B5CFF)];
    final bandWidth = size.width / 4;
    final shift = phase == 0 ? 0.0 : bandWidth * 1.5;
    for (var index = -2; index < 7; index++) {
      final color = colors[(index - (phase * 2)).abs() % colors.length];
      final left = index * bandWidth + shift;
      canvas.drawRect(Rect.fromLTWH(left, 112, bandWidth, 270), Paint()..color = color);
    }

    final lowerTop = size.height - 190;
    const lowerColors = [Color(0xFF00F0A8), Color(0xFFFF5A36), Color(0xFF72D1FF), Color(0xFFFFE66D)];
    for (var index = -1; index < 8; index++) {
      final color = lowerColors[(index + phase + lowerColors.length) % lowerColors.length];
      final left = index * 64.0 + (phase == 0 ? 0 : 32);
      canvas.drawRect(Rect.fromLTWH(left, lowerTop, 40, 130), Paint()..color = color);
    }

    final orbCenter = phase == 0
        ? Offset(size.width * .34, size.height * .43)
        : Offset(size.width * .72, size.height * .34);
    canvas.drawCircle(orbCenter, 74, Paint()..color = const Color(0xEFFFFFFF));
    canvas.drawCircle(
      phase == 0 ? Offset(size.width * .72, size.height * .55) : Offset(size.width * .26, size.height * .52),
      58,
      Paint()..color = const Color(0xE6000812),
    );

    final linePaint = Paint()
      ..color = const Color(0xCCFFFFFF)
      ..strokeWidth = 5;
    final diagonalShift = phase == 0 ? -80.0 : 30.0;
    for (var x = diagonalShift; x < size.width + 160; x += 52) {
      canvas.drawLine(Offset(x, 110), Offset(x - 150, 390), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ControlledBackdropPainter oldDelegate) => oldDelegate.phase != phase;
}
