import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_glass.dart';
import 'package:hiddify/features/common/qr_code_scanner_screen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../support/home_fixture.dart';

// This substitutes only the camera platform boundary. It does not prove a live
// camera session, an OS permission prompt, or native camera pixels.
class _CameraBoundary extends MobileScannerPlatform {
  final started = Completer<MobileScannerViewAttributes>();
  @override
  Stream<BarcodeCapture?> get barcodesStream => const Stream.empty();
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const SizedBox.expand(key: ValueKey('camera-platform-boundary'));
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) => started.future;
  @override
  Future<void> stop() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<void> updateScanWindow(Rect? window) async {}
}

Widget _scannerLauncher() => Builder(
  builder: (context) => TextButton(
    onPressed: () {
      final theme = BlizzardTheme.from(Theme.of(context));
      Navigator.of(context, rootNavigator: true).push<void>(
        DialogRoute(
          context: context,
          builder: (_) => Theme(data: theme, child: const QrCodeScannerDialog()),
        ),
      );
    },
    child: const Text('Open scanner'),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final state in ['pending', 'initialized', 'denied']) {
    testWidgets('Aurora scanner $state keeps its real dialog route close reachable', (tester) async {
      final original = MobileScannerPlatform.instance;
      final camera = _CameraBoundary();
      MobileScannerPlatform.instance = camera;
      addTearDown(() => MobileScannerPlatform.instance = original);
      final fixture = await mountHomeFixture(tester, child: _scannerLauncher());
      await tester.tap(find.text('Open scanner'));
      await tester.pump();
      expect(find.byType(QrCodeScannerDialog), findsOneWidget);
      expect(Theme.of(tester.element(find.byType(MobileScanner))).scaffoldBackgroundColor, BlizzardPalette.background);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      final close = find.descendant(of: find.byType(QrCodeScannerDialog), matching: find.byType(IconButton));
      final glass = find.ancestor(of: close, matching: find.byType(BlizzardGlass));
      expect(close.hitTestable(), findsOneWidget);
      expect(glass, findsOneWidget);
      expect(tester.getSize(glass), const Size.square(48));
      final safeArea = find.descendant(of: find.byType(QrCodeScannerDialog), matching: find.byType(SafeArea));
      expect(tester.getTopLeft(glass) - tester.getTopLeft(safeArea), const Offset(8, 8));
      if (state == 'denied') {
        camera.started.completeError(const MobileScannerException(errorCode: MobileScannerErrorCode.permissionDenied));
      } else if (state == 'initialized') {
        camera.started.complete(
          const MobileScannerViewAttributes(
            cameraDirection: CameraFacing.back,
            currentTorchMode: TorchState.off,
            size: Size(640, 480),
          ),
        );
      }
      if (state != 'pending') {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      }
      if (state == 'denied') {
        final text = fixture.container.read(translationsProvider).requireValue.common.msg.permission.denied;
        expect(find.text(text), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      } else if (state == 'initialized') {
        expect(find.byKey(const ValueKey('camera-platform-boundary')), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      } else {
        expect(find.byType(CircularProgressIndicator), findsWidgets);
      }
      expect(close.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(QrCodeScannerDialog), findsNothing);
      expect(find.text('Open scanner'), findsOneWidget);
      await fixture.close(tester);
    });
  }
}
