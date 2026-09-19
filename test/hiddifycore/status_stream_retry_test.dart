import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/hiddifycore/status_stream_retry.dart';

void main() {
  test('status listener uses recovery without synthetic stopped or raw errors', () {
    final source = File('lib/hiddifycore/hiddify_core_service.dart').readAsStringSync();
    final status = source.substring(
      source.indexOf('Future<void> startListeningStatus'),
      source.indexOf('Future<void> startListeningLogs'),
    );
    expect(status, contains('retryStatusStream'));
    expect(status, isNot(contains('.endWith(')));
    expect(status, isNot(contains('loggy.error')));
    expect(status, contains('StatusCode.cancelled'));
  });
  test('consumer cancellation during backoff prevents reconnect and exhaustion', () async {
    var subscriptions = 0;
    var exhausted = 0;
    final backoffStarted = Completer<void>();
    final releaseBackoff = Completer<void>();
    final subscription = retryStatusStream<int>(
      () {
        subscriptions++;
        return Stream<int>.error(StateError('transient'));
      },
      delay: (_) {
        backoffStarted.complete();
        return releaseBackoff.future;
      },
      onExhausted: () => exhausted++,
    ).listen((_) {});
    await backoffStarted.future;
    await subscription.cancel();
    releaseBackoff.complete();
    await Future<void>.delayed(Duration.zero);
    expect(subscriptions, 1);
    expect(exhausted, 0);
  });
  test('reconnects after an error with bounded backoff', () async {
    var subscriptions = 0;
    final delays = <Duration>[];

    Stream<int> connect() async* {
      subscriptions++;
      if (subscriptions == 1) {
        yield 1;
        throw StateError('raw secret must not be observed');
      }
      yield 2;
    }

    final values = await retryStatusStream(connect, delay: (duration) async => delays.add(duration)).toList();

    expect(values, [1, 2]);
    expect(subscriptions, 2);
    expect(delays, [const Duration(milliseconds: 250)]);
  });

  test('stops after three retries and emits one closed exhaustion callback', () async {
    var subscriptions = 0;
    var exhausted = 0;
    final delays = <Duration>[];

    final values = await retryStatusStream<int>(
      () {
        subscriptions++;
        return Stream<int>.error(StateError('host.example token=secret'));
      },
      delay: (duration) async => delays.add(duration),
      onExhausted: () => exhausted++,
    ).toList();

    expect(values, isEmpty);
    expect(subscriptions, 4);
    expect(delays, const [Duration(milliseconds: 250), Duration(seconds: 1), Duration(seconds: 4)]);
    expect(exhausted, 1);
  });

  test('normal completion and cancellation errors do not retry', () async {
    var normalSubscriptions = 0;
    await retryStatusStream<int>(() {
      normalSubscriptions++;
      return const Stream<int>.empty();
    }, delay: (_) async {}).drain<void>();
    expect(normalSubscriptions, 1);

    var cancelledSubscriptions = 0;
    await retryStatusStream<int>(
      () {
        cancelledSubscriptions++;
        return Stream<int>.error(const StatusStreamCancelled());
      },
      delay: (_) async {},
      isCancellation: (error) => error is StatusStreamCancelled,
    ).drain<void>();
    expect(cancelledSubscriptions, 1);
  });

  test('successful data resets the retry budget', () async {
    var subscriptions = 0;
    final delays = <Duration>[];
    Stream<int> connect() async* {
      subscriptions++;
      if (subscriptions <= 4) {
        yield subscriptions;
        throw StateError('transient');
      }
      yield 5;
    }

    expect(await retryStatusStream(connect, delay: (duration) async => delays.add(duration)).toList(), [1, 2, 3, 4, 5]);
    expect(delays, everyElement(const Duration(milliseconds: 250)));
  });
}

final class StatusStreamCancelled implements Exception {
  const StatusStreamCancelled();
}
