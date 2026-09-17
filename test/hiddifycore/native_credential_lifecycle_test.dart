import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/hiddifycore/core_interface/native_control_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/native-control-session');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('native setup owns and returns the stable control session', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final arguments = call.arguments! as Map<Object?, Object?>;
      expect(arguments, isNot(contains('controlSecret')));
      return <String, Object>{
        'generation': 'generation-1',
        'controlSecret': 'ab' * 32,
        'certificate': Uint8List.fromList(const [1, 2, 3]),
      };
    });

    const provider = NativeControlSessionProvider(channel);
    final first = await provider.setup(const {'grpcPort': 17078});
    final afterFlutterRestart = await const NativeControlSessionProvider(channel).setup(const {'grpcPort': 17078});

    expect(first.generation, 'generation-1');
    expect(first.controlSecret, 'ab' * 32);
    expect(first.certificate, orderedEquals(const [1, 2, 3]));
    expect(afterFlutterRestart, first);
    expect(calls.map((call) => call.method), everyElement('setup'));
  });

  test('malformed native session fails closed', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      return <String, Object>{
        'generation': 'generation-1',
        'controlSecret': 'short',
        'certificate': Uint8List.fromList(const [1]),
      };
    });

    await expectLater(
      const NativeControlSessionProvider(channel).setup(const {'grpcPort': 17078}),
      throwsA(isA<StateError>()),
    );
  });

  test('protected storage failure is not replaced in Dart', () async {
    messenger.setMockMethodCallHandler(channel, (_) {
      throw PlatformException(
        code: 'CONTROL_CREDENTIAL_UNAVAILABLE',
        details: const {'domain': 'LocalControlCredential', 'nativeCode': 1},
      );
    });

    await expectLater(
      const NativeControlSessionProvider(channel).setup(const {'grpcPort': 17078}),
      throwsA(isA<PlatformException>().having((error) => error.code, 'code', 'CONTROL_CREDENTIAL_UNAVAILABLE')),
    );
  });
}
