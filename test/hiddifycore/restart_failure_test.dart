import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Call<T> implements ClientCall<dynamic, T> {
  _Call(this.response);
  @override
  final Stream<T> response;
  @override
  Future<void> cancel() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RestartClient implements CoreClient {
  _RestartClient(this.response);
  final Stream<CoreInfoResponse> response;
  StartRequest? request;
  @override
  ResponseFuture<CoreInfoResponse> restart(StartRequest request, {CallOptions? options}) {
    this.request = request;
    return ResponseFuture(_Call(response));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  HiddifyCoreService serviceFor(_RestartClient client) {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final refProvider = Provider<Ref>((ref) => ref);
    final service = HiddifyCoreService(container.read(refProvider), core: CoreInterface()..bgClient = client);
    addTearDown(service.statusController.close);
    addTearDown(service.logController.close);
    return service;
  }

  for (final error in [
    const GrpcError.unavailable('RPC unavailable'),
    const GrpcError.unknown('restart rejected'),
    const GrpcError.unknown('HTTP/2 error: stream closed'),
    const GrpcError.deadlineExceeded('restart timed out'),
  ]) {
    test('restart returns Left for asynchronous gRPC ${error.code}: ${error.message}', () async {
      final client = _RestartClient(Stream.error(error));
      final result = await serviceFor(client).restart('/synthetic/config', 'synthetic', false).run();
      expect(result.isLeft(), isTrue, reason: 'A failed restart RPC must not report acceptance.');
      expect(client.request?.delayStart, isTrue);
    });
  }

  test('restart gRPC failure exposes only the status code, not native message', () async {
    final client = _RestartClient(Stream.error(const GrpcError.unknown('PRIVATE_RESTART_CANARY')));
    final result = await serviceFor(client).restart('/synthetic/config', 'synthetic', false).run();
    result.match(
      (message) => expect(message, 'VPN restart failed (gRPC: 2).'),
      (_) => fail('RPC failure must not succeed'),
    );
  });

  test('accepted delayed restart remains Right without claiming tunnel readiness', () async {
    final client = _RestartClient(Stream.value(CoreInfoResponse(messageType: MessageType.EMPTY)));
    final result = await serviceFor(client).restart('/synthetic/config', 'synthetic', true).run();
    expect(result.isRight(), isTrue);
    expect(client.request?.configPath, '/synthetic/config');
    expect(client.request?.disableMemoryLimit, isTrue);
    expect(client.request?.delayStart, isTrue);
  });

  test('explicit restart response rejection remains Left', () async {
    final client = _RestartClient(
      Stream.value(CoreInfoResponse(messageType: MessageType.UNEXPECTED_ERROR, message: 'rejected')),
    );
    final result = await serviceFor(client).restart('/synthetic/config', 'synthetic', false).run();
    expect(result.isLeft(), isTrue);
  });
}
