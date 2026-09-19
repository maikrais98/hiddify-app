import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service_provider.dart';
import 'package:hiddify/hiddifycore/status_stream_retry.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  late ProviderContainer container;
  late HiddifyCoreService service;

  setUp(() {
    container = ProviderContainer();
    final refProvider = Provider<Ref>((ref) => ref);
    service = HiddifyCoreService(container.read(refProvider), core: CoreInterface());
  });

  tearDown(() async {
    try {
      await service.dispose();
    } catch (_) {
      // Individual tests assert the direct-dispose error contract.
    }
    container.dispose();
  });

  test('same-key replacement keeps one listener without cancelling prefix peers', () async {
    final first = _TrackedStream();
    final replacement = _TrackedStream();
    final prefixPeer = _TrackedStream();

    await service.listenSingle<int>('fg', () => first.stream);
    await service.listenSingle<int>('fgStatus', () => prefixPeer.stream);
    first.add(1);
    prefixPeer.add(1);
    await _flushEvents();

    await service.listenSingle<int>('fg', () => replacement.stream);
    first.add(2);
    replacement.add(1);
    prefixPeer.add(2);
    await _flushEvents();

    expect(first.listenCount, 1);
    expect(first.cancelCount, 1);
    expect(first.callbackCount, 1);
    expect(replacement.listenCount, 1);
    expect(replacement.callbackCount, 1);
    expect(prefixPeer.cancelCount, 0);
    expect(prefixPeer.callbackCount, 2);
    expect(service.subscriptions.keys, containsAll(<String>['fg', 'fgStatus']));

    await service.stopListenSingle('fg');
    expect(replacement.cancelCount, 1);
    expect(prefixPeer.cancelCount, 1);
    expect(service.subscriptions, isEmpty);

    await first.close();
    await replacement.close();
    await prefixPeer.close();
  });

  test('dispose owns recovery subscription and suppresses pending reconnection', () async {
    var connections = 0;
    final waiting = Completer<void>();
    final release = Completer<void>();
    await service.listenSingle<int>(
      'bgStatusListener',
      () => retryStatusStream<int>(
        () {
          connections++;
          return Stream<int>.error(StateError('transient'));
        },
        delay: (_) {
          waiting.complete();
          return release.future;
        },
      ),
    );
    await waiting.future;
    await service.dispose();
    release.complete();
    await _flushEvents();
    expect(connections, 1);
    expect(service.listenerStateIsEmpty, isTrue);
  });

  test('overlapping replacements serialize cancellation and leave the last listener active', () async {
    final cancellationGate = Completer<void>();
    final first = _TrackedStream(cancelGate: cancellationGate);
    final second = _TrackedStream();
    final third = _TrackedStream();
    addTearDown(() {
      if (!cancellationGate.isCompleted) cancellationGate.complete();
    });

    await service.listenSingle<int>('status', () => first.stream);
    final firstReplacement = service.listenSingle<int>('status', () => second.stream);
    await _flushEvents();
    expect(first.cancelCount, 1);
    expect(second.listenCount, 0);

    final secondReplacement = service.listenSingle<int>('status', () => third.stream);
    await _flushEvents();
    expect(third.listenCount, 0);

    cancellationGate.complete();
    await Future.wait([firstReplacement, secondReplacement]);

    expect(second.listenCount, 1);
    expect(second.cancelCount, 1);
    expect(third.listenCount, 1);
    expect(third.cancelCount, 0);
    expect(service.subscriptions.keys, ['status']);

    await first.close();
    await second.close();
    await third.close();
  });

  test('error and normal completion remove only their own listener once', () async {
    final failing = _TrackedStream();
    final completing = _TrackedStream();
    var handledErrors = 0;

    await service.listenSingle<int>('failing', () => failing.stream, onError: (_) => handledErrors++);
    failing.addError(StateError('expected test failure'));
    await _flushEvents();

    expect(handledErrors, 1);
    expect(failing.cancelCount, 1);
    expect(service.subscriptions, isNot(contains('failing')));

    await service.listenSingle<int>('completing', () => completing.stream);
    await completing.close();
    await _flushEvents();

    expect(completing.cancelCount, 1);
    expect(service.subscriptions, isNot(contains('completing')));
    await failing.close();
  });

  test('stream creation failure does not leave stale bookkeeping', () async {
    await expectLater(
      service.listenSingle<int>('broken', () => throw StateError('stream unavailable')),
      throwsStateError,
    );

    expect(service.subscriptions, isNot(contains('broken')));
  });

  test('dispose cancels resources once, closes controllers, and rejects new listeners', () async {
    final status = _TrackedStream();
    final logs = _TrackedStream();
    final afterDispose = _TrackedStream();

    await service.listenSingle<int>('status', () => status.stream);
    await service.listenSingle<int>('logs', () => logs.stream);
    await service.dispose();
    await service.dispose();

    expect(status.cancelCount, 1);
    expect(logs.cancelCount, 1);
    expect(service.subscriptions, isEmpty);
    expect(service.statusController.isClosed, isTrue);
    expect(service.logController.isClosed, isTrue);

    final subscription = await service.listenSingle<int>('late', () => afterDispose.stream);
    expect(subscription, isNull);
    expect(afterDispose.listenCount, 0);

    await status.close();
    await logs.close();
    await afterDispose.close();
  });

  test('dispose attempts every cancellation and closes subjects before rethrowing the first error', () async {
    final cancellationError = StateError('expected cancellation failure');
    final failing = _TrackedStream(cancelError: cancellationError);
    final succeeding = _TrackedStream();

    await service.listenSingle<int>('failing', () => failing.stream);
    await service.listenSingle<int>('succeeding', () => succeeding.stream);

    await expectLater(service.dispose(), throwsA(same(cancellationError)));

    expect(failing.cancelCount, 1);
    expect(succeeding.cancelCount, 1);
    expect(service.listenerStateIsEmpty, isTrue);
    expect(service.statusController.isClosed, isTrue);
    expect(service.logController.isClosed, isTrue);

    await failing.close();
    await succeeding.close();
  });

  test('provider disposal awaits service cleanup through the actual provider lifecycle', () async {
    final providerContainer = ProviderContainer(
      overrides: [
        hiddifyCoreServiceFactoryProvider.overrideWithValue((ref) => HiddifyCoreService(ref, core: CoreInterface())),
      ],
    );
    final providerService = providerContainer.read(hiddifyCoreServiceProvider);
    final tracked = _TrackedStream();

    await providerService.listenSingle<int>('provider-owned', () => tracked.stream);
    final cleanupObserved = Future.wait<void>([
      tracked.cancelled,
      providerService.statusController.done,
      providerService.logController.done,
    ]);
    providerContainer.dispose();
    await cleanupObserved.timeout(const Duration(seconds: 2));

    expect(tracked.cancelCount, 1);
    expect(providerService.listenerStateIsEmpty, isTrue);
    expect(providerService.statusController.isClosed, isTrue);
    expect(providerService.logController.isClosed, isTrue);

    await tracked.close();
  });
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

class _TrackedStream {
  _TrackedStream({this.cancelGate, this.cancelError}) {
    controller = StreamController<int>(
      onListen: () => listenCount++,
      onCancel: () async {
        cancelCount++;
        if (!_cancelled.isCompleted) _cancelled.complete();
        await cancelGate?.future;
        if (cancelError case final error?) throw error;
      },
    );
  }

  final Completer<void>? cancelGate;
  final Object? cancelError;
  late final StreamController<int> controller;
  int listenCount = 0;
  int cancelCount = 0;
  int callbackCount = 0;
  final _cancelled = Completer<void>();

  Future<void> get cancelled => _cancelled.future;

  Stream<int> get stream => controller.stream.map((event) {
    callbackCount++;
    return event;
  });

  void add(int event) => controller.add(event);

  void addError(Object error) => controller.addError(error);

  Future<void> close() async {
    if (controller.isClosed) return;
    final closed = controller.close();
    if (listenCount > 0) await closed;
  }
}
