import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/home/protection/protected_reachability.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/data/proxy_repository.dart';
import 'package:hiddify/features/proxy/model/ip_info_entity.dart' as model;
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('reports verified only after a protected proxy request succeeds', () async {
    final repository = _ProbeRepository(TaskEither.right(const model.IpInfo(ip: '203.0.113.7', countryCode: 'ZZ')));

    final result = await measureProtectedReachability(repository, CancelToken());

    expect(result, ProtectionReachability.verified);
    expect(repository.probeCount, 1);
  });

  test('keeps a failed protected proxy request distinct from tunnel state', () async {
    final repository = _ProbeRepository(
      TaskEither.left(ProxyUnexpectedFailure(StateError('synthetic failure'), StackTrace.empty)),
    );

    final result = await measureProtectedReachability(repository, CancelToken());

    expect(result, ProtectionReachability.failed);
    expect(repository.probeCount, 1);
  });

  test('does not probe before the tunnel lifecycle is connected', () async {
    final repository = _ProbeRepository(TaskEither.right(const model.IpInfo(ip: '203.0.113.7', countryCode: 'ZZ')));
    final container = ProviderContainer(
      overrides: [
        connectionNotifierProvider.overrideWith(
          () => _ConnectionState(Stream.value(const ConnectionStatus.disconnected())),
        ),
        proxyRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(protectedReachabilityProvider, (_, _) {});
    addTearDown(subscription.close);

    final result = await container.read(protectedReachabilityProvider.future);

    expect(result, ProtectionReachability.notChecked);
    expect(repository.probeCount, 0);
  });

  test('connected lifecycle still requires a successful independent probe', () async {
    final repository = _ProbeRepository(
      TaskEither.left(ProxyUnexpectedFailure(StateError('synthetic failure'), StackTrace.empty)),
    );
    final container = ProviderContainer(
      overrides: [
        connectionNotifierProvider.overrideWith(
          () => _ConnectionState(Stream.value(const ConnectionStatus.connected())),
        ),
        proxyRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(protectedReachabilityProvider, (_, _) {});
    addTearDown(subscription.close);

    final result = await container.read(protectedReachabilityProvider.future);

    expect(result, ProtectionReachability.failed);
    expect(repository.probeCount, 1);
  });

  test('rechecks after disconnect and reconnect instead of keeping a stale result', () async {
    final connectionStates = StreamController<ConnectionStatus>();
    final repository = _ProbeRepository(TaskEither.right(const model.IpInfo(ip: '203.0.113.7', countryCode: 'ZZ')));
    final container = ProviderContainer(
      overrides: [
        connectionNotifierProvider.overrideWith(() => _ConnectionState(connectionStates.stream)),
        proxyRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await connectionStates.close();
    });

    final subscription = container.listen(protectedReachabilityProvider, (_, _) {});
    addTearDown(subscription.close);

    connectionStates.add(const ConnectionStatus.disconnected());
    await _waitForReachability(container, ProtectionReachability.notChecked);
    expect(repository.probeCount, 0);

    connectionStates.add(const ConnectionStatus.connected());
    await _waitForReachability(container, ProtectionReachability.verified);
    expect(repository.probeCount, 1);

    connectionStates.add(const ConnectionStatus.disconnected());
    await _waitForReachability(container, ProtectionReachability.notChecked);

    connectionStates.add(const ConnectionStatus.connected());
    await _waitForReachability(
      container,
      ProtectionReachability.verified,
      minimumProbeCount: 2,
      repository: repository,
    );
    expect(repository.probeCount, 2);
  });
}

Future<void> _waitForReachability(
  ProviderContainer container,
  ProtectionReachability expected, {
  int minimumProbeCount = 0,
  _ProbeRepository? repository,
}) async {
  final completer = Completer<void>();
  late final ProviderSubscription<AsyncValue<ProtectionReachability>> subscription;
  subscription = container.listen(protectedReachabilityProvider, (_, next) {
    if (next.valueOrNull == expected && (repository?.probeCount ?? 0) >= minimumProbeCount && !completer.isCompleted) {
      completer.complete();
    }
  }, fireImmediately: true);
  try {
    await completer.future.timeout(const Duration(seconds: 2));
  } finally {
    subscription.close();
  }
}

class _ConnectionState extends ConnectionNotifier {
  _ConnectionState(this.source);

  final Stream<ConnectionStatus> source;

  @override
  Stream<ConnectionStatus> build() => source;
}

class _ProbeRepository implements ProxyRepository {
  _ProbeRepository(this.result);

  final TaskEither<ProxyFailure, model.IpInfo> result;
  int probeCount = 0;

  @override
  TaskEither<ProxyFailure, model.IpInfo> getCurrentIpInfo(CancelToken cancelToken) {
    probeCount++;
    return result;
  }

  @override
  TaskEither<ProxyFailure, Unit> selectProxy(String groupTag, String outboundTag) => throw UnimplementedError();

  @override
  TaskEither<ProxyFailure, Unit> urlTest(String groupTag) => throw UnimplementedError();

  @override
  Stream<Either<ProxyFailure, List<OutboundGroup>>> watchActiveProxies() => throw UnimplementedError();

  @override
  Stream<Either<ProxyFailure, OutboundGroup?>> watchProxies() => throw UnimplementedError();
}
