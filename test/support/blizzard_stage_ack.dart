import 'dart:io';

class StageAckPolicy {
  const StageAckPolicy.capture({required this.handshakeTimeout, required Duration this.completionTimeout})
    : acceptedState = 'accepted',
      completedState = 'captured';

  const StageAckPolicy.twoPhase({
    required this.handshakeTimeout,
    required this.completionTimeout,
    required this.acceptedState,
    required this.completedState,
  });

  final Duration handshakeTimeout;
  final Duration? completionTimeout;
  final String? acceptedState;
  final String completedState;
}

const videoStageAckPolicy = StageAckPolicy.twoPhase(
  handshakeTimeout: Duration(seconds: 30),
  completionTimeout: Duration(seconds: 25),
  acceptedState: 'accepted',
  completedState: 'recording',
);

StageAckPolicy captureStageAckPolicy(String name) => StageAckPolicy.capture(
  handshakeTimeout: const Duration(seconds: 30),
  completionTimeout: Duration(seconds: name == 'home_initial' ? 135 : 75),
);

Future<void> waitForStageAck({
  required File ack,
  required void Function() emitMarker,
  required StageAckPolicy policy,
  Duration pollInterval = const Duration(milliseconds: 50),
  String stage = 'stage',
}) async {
  if (await ack.exists()) await ack.delete();
  emitMarker();

  var accepted = false;
  var deadline = DateTime.now().add(policy.handshakeTimeout);
  while (true) {
    if (await ack.exists()) {
      final state = (await ack.readAsString()).trim();
      if (state == policy.completedState) {
        await ack.delete();
        return;
      }
      if (policy.acceptedState != null && state == policy.acceptedState) {
        if (!accepted) {
          accepted = true;
          deadline = DateTime.now().add(policy.completionTimeout!);
        }
      } else if (state.isNotEmpty) {
        throw StateError('Unexpected runner ack state for $stage: $state');
      }
    }
    if (DateTime.now().isAfter(deadline)) {
      final phase = accepted ? 'completion' : 'handshake';
      throw StateError('Timed out waiting for runner $phase: $stage');
    }
    await Future<void>.delayed(pollInterval);
  }
}

class StageAckRunResult {
  const StageAckRunResult._(this.error, this.stackTrace);

  final Object? error;
  final StackTrace? stackTrace;

  bool get isSuccess => error == null;

  static Future<StageAckRunResult> guard(Future<void> Function() operation) async {
    try {
      await operation();
      return const StageAckRunResult._(null, null);
    } on Object catch (error, stackTrace) {
      return StageAckRunResult._(error, stackTrace);
    }
  }

  void rethrowFailure() {
    if (error != null) Error.throwWithStackTrace(error!, stackTrace!);
  }
}
