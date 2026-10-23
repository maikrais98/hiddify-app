import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/blizzard_stage_ack.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('blizzard-stage-ack-test-');
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test('capture waits through accepted until captured', () async {
    final ack = File('${temporary.path}/capture.ack');
    final observed = <String>[];
    var completed = false;
    final future = waitForStageAck(
      ack: ack,
      emitMarker: () => observed.add('marker'),
      policy: const StageAckPolicy.capture(
        handshakeTimeout: Duration(milliseconds: 40),
        completionTimeout: Duration(milliseconds: 120),
      ),
      pollInterval: const Duration(milliseconds: 2),
    );
    unawaited(future.then((_) => completed = true));

    await Future<void>.delayed(const Duration(milliseconds: 10));
    await ack.writeAsString('accepted\n');
    observed.add('accepted');
    await Future<void>.delayed(const Duration(milliseconds: 45));
    expect(observed, ['marker', 'accepted']);
    expect(completed, isFalse);
    await ack.writeAsString('captured\n');
    await future;

    expect(await ack.exists(), isFalse);
  });

  test('capture fails when controller never accepts the stage', () async {
    final ack = File('${temporary.path}/missing.ack');

    await expectLater(
      waitForStageAck(
        ack: ack,
        emitMarker: () {},
        policy: const StageAckPolicy.capture(
          handshakeTimeout: Duration(milliseconds: 20),
          completionTimeout: Duration(milliseconds: 80),
        ),
        pollInterval: const Duration(milliseconds: 2),
      ),
      throwsA(isA<StateError>().having((error) => error.message, 'message', contains('handshake'))),
    );
  });

  test('capture fails when accepted stage never completes', () async {
    final ack = File('${temporary.path}/accepted.ack');
    final future = waitForStageAck(
      ack: ack,
      emitMarker: () {},
      policy: const StageAckPolicy.capture(
        handshakeTimeout: Duration(milliseconds: 40),
        completionTimeout: Duration(milliseconds: 30),
      ),
      pollInterval: const Duration(milliseconds: 2),
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await ack.writeAsString('accepted\n');

    await expectLater(
      future,
      throwsA(isA<StateError>().having((error) => error.message, 'message', contains('completion'))),
    );
  });

  test('stage policies keep capture completion bounds scoped', () {
    expect(captureStageAckPolicy('home_initial').handshakeTimeout, const Duration(seconds: 30));
    expect(captureStageAckPolicy('home_initial').completionTimeout, const Duration(seconds: 135));
    expect(captureStageAckPolicy('settings').completionTimeout, const Duration(seconds: 75));
    expect(videoStageAckPolicy.handshakeTimeout, const Duration(seconds: 30));
    expect(videoStageAckPolicy.acceptedState, 'accepted');
    expect(videoStageAckPolicy.completionTimeout, const Duration(seconds: 25));
    expect(videoStageAckPolicy.completedState, 'recording');
  });

  test('guard returns an error that is rethrown by the caller', () async {
    final result = await StageAckRunResult.guard(() => Future<void>.error(StateError('late capture')));

    expect(result.isSuccess, isFalse);
    expect(result.rethrowFailure, throwsA(isA<StateError>()));
  });
}
