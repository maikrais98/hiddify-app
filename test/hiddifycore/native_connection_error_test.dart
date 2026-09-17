import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/hiddifycore/core_interface/native_connection_error.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/native-vpn-errors');
  for (final operation in ['SETUP', 'SETUP_CONNECTION']) {
    test('$operation preserves native identity through a platform error to the UI', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) => Future<Object?>.error(
          PlatformException(
            code: operation,
            message: 'private config must not be displayed',
            details: {'domain': 'NEVPNErrorDomain', 'nativeCode': 5},
          ),
        ),
      );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
      );
      try {
        await channel.invokeMethod<void>('start');
        fail('native failure must not return success');
      } on PlatformException catch (error) {
        final failure = NativeConnectionError.fromPlatform(error);
        final presentation = failure.failure.present(await AppLocale.en.build());
        expect(presentation.message, contains('NEVPNErrorDomain: 5'));
        expect(presentation.message, contains(operation == 'SETUP' ? 'setup failed' : 'start failed'));
        expect(presentation.message, isNot(contains('private config')));
      }
    });
  }

  test('unexpected details and messages cannot leak through native presentation', () {
    final error = NativeConnectionError.fromPlatform(
      PlatformException(
        code: 'unknown private value',
        message: 'private URL',
        details: {'domain': 'private URL', 'nativeCode': 'private URL'},
      ),
    );
    expect(error.operation, 'platform');
    expect(error.domain, 'system');
    expect(error.code, isNull);
  });
}
