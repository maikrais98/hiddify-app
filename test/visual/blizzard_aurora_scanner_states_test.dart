import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final denied in [false, true]) {
    testWidgets(
      'Aurora scanner pending then ${denied ? "permission error" : "camera composition"} keeps close reachable',
      (tester) async {
        final original = MobileScannerPlatform.instance;
        final camera = _CameraBoundary();
        MobileScannerPlatform.instance = camera;
        addTearDown(() => MobileScannerPlatform.instance = original);
        final fixture = await mountHomeFixture(
          tester,
          child: Builder(
            builder: (context) =>
                Theme(data: BlizzardTheme.from(Theme.of(context)), child: const QrCodeScannerDialog()),
          ),
        );
        expect(find.byType(QrCodeScannerDialog), findsOneWidget);
        expect(
          Theme.of(tester.element(find.byType(MobileScanner))).scaffoldBackgroundColor,
          BlizzardPalette.background,
        );
        expect(find.byType(CircularProgressIndicator), findsWidgets);
        final close = find.descendant(of: find.byType(QrCodeScannerDialog), matching: find.byType(IconButton));
        expect(close.hitTestable(), findsOneWidget);
        expect(tester.getSize(close).shortestSide, greaterThanOrEqualTo(44));
        if (denied) {
          camera.started.completeError(
            const MobileScannerException(errorCode: MobileScannerErrorCode.permissionDenied),
          );
        } else {
          camera.started.complete(
            const MobileScannerViewAttributes(
              cameraDirection: CameraFacing.back,
              currentTorchMode: TorchState.off,
              size: Size(640, 480),
            ),
          );
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        if (denied) {
          final text = fixture.container.read(translationsProvider).requireValue.common.msg.permission.denied;
          expect(find.text(text), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);
        } else {
          expect(find.byKey(const ValueKey('camera-platform-boundary')), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);
        }
        expect(close.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await fixture.close(tester);
        await tester.pump();
      },
    );
  }
}
