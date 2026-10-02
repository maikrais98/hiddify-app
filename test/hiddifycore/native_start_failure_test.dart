import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcommon/common.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _waitTimeout = Duration(seconds: 2);

class _Call<T> implements ClientCall<dynamic, T> {
  _Call(this.response);

  @override
  final Stream<T> response;

  @override
  Future<void> cancel() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StartClient implements CoreClient {
  _StartClient(this.startResponse);

  final Stream<CoreInfoResponse> startResponse;
  final statusController = StreamController<CoreInfoResponse>();

  @override
  ResponseFuture<CoreInfoResponse> start(StartRequest request, {CallOptions? options}) =>
      ResponseFuture(_Call(startResponse));

  @override
  ResponseStream<CoreInfoResponse> coreInfoListener(Empty request, {CallOptions? options}) =>
      ResponseStream(_Call(statusController.stream));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StartedNativeCore extends CoreInterface {
  _StartedNativeCore(CoreClient client) {
    fgClient = client;
    bgClient = client;
  }
}

class _FailingNativeCore implements CoreInterface {
  _FailingNativeCore(this.code);
  final int code;
  @override
  Future<CoreStatus> setupBackground(String path, String name, {String? operationId}) async =>
      throw PlatformException(code: 'SETUP_CONNECTION', details: {'domain': 'NEVPNErrorDomain', 'nativeCode': code});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final code in [4, 5]) {
    test('native start code $code error returns typed Left and leaves Starting immediately', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final refProvider = Provider<Ref>((ref) => ref);
      final service = HiddifyCoreService(container.read(refProvider), core: _FailingNativeCore(code));
      addTearDown(service.statusController.close);
      addTearDown(service.logController.close);
      final states = <CoreStatus>[];
      final subscription = service.statusController.listen(states.add);
      addTearDown(subscription.cancel);

      final result = await service.start('/unused/test-config', 'test', false).run();
      await Future<void>.delayed(Duration.zero);

      result.match((failure) {
        expect(failure, isA<BackgroundCoreNotAvailable>());
        expect((failure as BackgroundCoreNotAvailable).message, contains('NEVPNErrorDomain: $code'));
      }, (_) => fail('native failure must reach the repository as Left'));
      expect(service.currentState, const CoreStatus.stopped());
      expect(states, [const CoreStatus.starting(), const CoreStatus.stopped()]);
    });
  }

  for (final error in [const GrpcError.unavailable('RPC unavailable'), const GrpcError.unknown('RPC rejected')]) {
    test('gRPC start failure ${error.code} publishes its correlated terminal state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final refProvider = Provider<Ref>((ref) => ref);
      final client = _StartClient(Stream.error(error));
      addTearDown(client.statusController.close);
      final service = HiddifyCoreService(container.read(refProvider), core: _StartedNativeCore(client));
      addTearDown(service.statusController.close);
      addTearDown(service.logController.close);
      final states = <CoreStatus>[];
      final subscription = service.statusController.listen(states.add);
      addTearDown(subscription.cancel);
      const operationId = 'grpc-start-operation';

      final result = await service.start('/unused/test-config', 'test', false, operationId: operationId).run();
      await Future<void>.delayed(Duration.zero);

      expect(result.isLeft(), isTrue);
      const terminal = CoreStatus.stopped(operationId: operationId);
      expect(service.currentState, terminal);
      expect(states, [const CoreStatus.starting(), terminal]);
      expect(
        await service.watchStatus().first.timeout(_waitTimeout),
        terminal,
        reason: 'a subscriber arriving after start returns must observe the terminal state',
      );
    });
  }
}
