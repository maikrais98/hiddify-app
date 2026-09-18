import 'dart:async';

/// Owns one upstream subscription and absorbs transient errors without emitting
/// fabricated status values. Cancelling the consumer cancels the active source
/// and prevents a pending backoff from creating another subscription.
Stream<T> retryStatusStream<T>(
  Stream<T> Function() connect, {
  Future<void> Function(Duration)? delay,
  bool Function(Object)? isCancellation,
  void Function()? onExhausted,
}) {
  const backoff = [Duration(milliseconds: 250), Duration(seconds: 1), Duration(seconds: 4)];
  final cancelled = Completer<void>();
  StreamSubscription<T>? upstream;
  late final StreamController<T> controller;

  Future<void> run() async {
    var retries = 0;
    while (!cancelled.isCompleted) {
      final ended = Completer<Object?>();
      try {
        upstream = connect().listen(
          (event) {
            if (cancelled.isCompleted) return;
            retries = 0;
            controller.add(event);
          },
          onError: (Object error) {
            if (!ended.isCompleted) ended.complete(error);
          },
          onDone: () {
            if (!ended.isCompleted) ended.complete();
          },
          cancelOnError: true,
        );
        if (controller.isPaused) upstream?.pause();
      } catch (error) {
        ended.complete(error);
      }
      final error = await Future.any<Object?>([ended.future, cancelled.future.then((_) => null)]);
      await upstream?.cancel();
      upstream = null;
      if (cancelled.isCompleted) return;
      if (error == null || (isCancellation?.call(error) ?? false)) break;
      if (retries == backoff.length) {
        onExhausted?.call();
        break;
      }
      final duration = backoff[retries++];
      await Future.any<void>([(delay ?? Future<void>.delayed)(duration), cancelled.future]);
    }
    if (!cancelled.isCompleted) unawaited(controller.close());
  }

  controller = StreamController<T>(
    onListen: () => unawaited(run()),
    onPause: () => upstream?.pause(),
    onResume: () => upstream?.resume(),
    onCancel: () async {
      if (!cancelled.isCompleted) cancelled.complete();
      await upstream?.cancel();
    },
  );
  return controller.stream;
}
