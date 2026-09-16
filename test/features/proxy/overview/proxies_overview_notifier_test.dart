import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/data/proxy_repository.dart';
import 'package:hiddify/features/proxy/model/ip_info_entity.dart' as oldipinfo;
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SortState extends ProxiesSortNotifier {
  @override
  ProxiesSort build() => ProxiesSort.unsorted;
}

class _ProxyRepository implements ProxyRepository {
  _ProxyRepository(this.group);

  final OutboundGroup group;
  final selected = <(String, String)>[];

  @override
  Stream<Either<ProxyFailure, OutboundGroup?>> watchProxies() => Stream.value(right(group));

  @override
  TaskEither<ProxyFailure, Unit> urlTest(String groupTag) => TaskEither.right(unit);

  @override
  TaskEither<ProxyFailure, Unit> selectProxy(String groupTag, String outboundTag) {
    selected.add((groupTag, outboundTag));
    return TaskEither.right(unit);
  }

  @override
  Stream<Either<ProxyFailure, List<OutboundGroup>>> watchActiveProxies() => const Stream.empty();

  @override
  TaskEither<ProxyFailure, oldipinfo.IpInfo> getCurrentIpInfo(CancelToken cancelToken) => throw UnimplementedError();
}

void main() {
  test('urlTest proposes the best server without changing the current selection', () async {
    SharedPreferences.setMockInitialValues({'haptic_feedback': false});
    final preferences = await SharedPreferences.getInstance();
    final group = OutboundGroup(
      tag: 'select',
      selected: 'Vienna',
      items: [
        OutboundInfo(tag: 'Vienna', type: 'direct', urlTestDelay: 80),
        OutboundInfo(tag: 'Stockholm', type: 'direct', urlTestDelay: 42),
      ],
    );
    final repository = _ProxyRepository(group);
    final container = ProviderContainer(
      overrides: [
        serviceRunningProvider.overrideWithValue(true),
        sharedPreferencesProvider.overrideWith((ref) => preferences),
        proxyRepositoryProvider.overrideWithValue(repository),
        proxiesSortNotifierProvider.overrideWith(_SortState.new),
      ],
    );
    addTearDown(container.dispose);

    await container.read(proxiesOverviewNotifierProvider.future);
    final result = await container.read(proxiesOverviewNotifierProvider.notifier).urlTest('select');

    expect(result?.outboundTag, 'Stockholm');
    expect(repository.selected, isEmpty);
    expect(group.selected, 'Vienna');
  });
}
