import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/features/stats/data/stats_data_providers.dart';
import 'package:hiddify/features/stats/data/stats_repository.dart';
import 'package:hiddify/features/stats/model/stats_failure.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('reports stopped service as unavailable instead of measured zero', () async {
    final container = ProviderContainer(overrides: [serviceRunningProvider.overrideWithValue(false)]);
    addTearDown(container.dispose);

    await expectLater(container.read(statsNotifierProvider.future), throwsA(isA<ServiceNotRunning>()));
  });

  test('preserves repository failure instead of replacing it with empty SystemInfo', () async {
    final failure = StatsFailure.unexpected(StateError('stats failed'));
    final container = ProviderContainer(
      overrides: [
        serviceRunningProvider.overrideWithValue(true),
        statsRepositoryProvider.overrideWithValue(_StatsRepository(Stream.value(left(failure)))),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(container.read(statsNotifierProvider.future), throwsA(same(failure)));
  });

  test('preserves a successful measured zero', () async {
    final stats = SystemInfo.create();
    final container = ProviderContainer(
      overrides: [
        serviceRunningProvider.overrideWithValue(true),
        statsRepositoryProvider.overrideWithValue(_StatsRepository(Stream.value(right(stats)))),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(statsNotifierProvider.future), same(stats));
  });
}

class _StatsRepository implements StatsRepository {
  const _StatsRepository(this.events);

  final Stream<Either<StatsFailure, SystemInfo>> events;

  @override
  Stream<Either<StatsFailure, SystemInfo>> watchStats() => events;
}
