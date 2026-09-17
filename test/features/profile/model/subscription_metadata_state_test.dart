import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/subscription_metadata_constants.dart';
import 'package:hiddify/features/profile/model/subscription_metadata_state.dart';

void main() {
  final now = DateTime.utc(2026, 9, 15, 12);

  ProfileEntity remote({
    SubscriptionInfo? subInfo,
    String? rawSubscriptionInfo,
    DateTime? lastUpdate,
    Duration? updateInterval,
  }) => ProfileEntity.remote(
    id: 'profile',
    active: true,
    name: 'Profile',
    url: 'https://example.com/subscription',
    lastUpdate: lastUpdate ?? now,
    options: updateInterval == null ? null : ProfileOptions(updateInterval: updateInterval),
    subInfo: subInfo,
    populatedHeaders: rawSubscriptionInfo == null ? null : {'subscription-userinfo': rawSubscriptionInfo},
  );

  test('keeps a finite expiration beyond 365 days finite', () {
    final expiresAt = now.add(const Duration(days: 400));
    final rawExpire = expiresAt.millisecondsSinceEpoch ~/ 1000;
    final state = SubscriptionMetadataState.fromProfile(
      remote(
        subInfo: SubscriptionInfo(upload: 10, download: 20, total: 100, expire: expiresAt),
        rawSubscriptionInfo: 'upload=10; download=20; total=100; expire=$rawExpire',
      ),
      now: now,
    );

    expect(state.expiry, SubscriptionExpiryStatus.finite);
    expect(state.expiresAt, DateTime.fromMillisecondsSinceEpoch(rawExpire * 1000));
    expect(state.expiresAt!.isUtc, isFalse);
  });

  test('preserves parser-compatible positive decimal metadata', () {
    final state = SubscriptionMetadataState.fromProfile(
      remote(rawSubscriptionInfo: 'upload=0; download=1024; total=10240.5; expire=1704054600.55'),
      now: now,
    );

    expect(state.quota, SubscriptionQuotaStatus.available);
    expect(state.expiry, SubscriptionExpiryStatus.finite);
    expect(state.expiresAt, DateTime.fromMillisecondsSinceEpoch(1704054600 * 1000));
  });

  test('preserves parser-compatible positive scientific metadata', () {
    final state = SubscriptionMetadataState.fromProfile(
      remote(rawSubscriptionInfo: 'upload=0; download=1e3; total=1.02405e4; expire=1.70405460055e9'),
      now: now,
    );

    expect(state.quota, SubscriptionQuotaStatus.available);
    expect(state.expiry, SubscriptionExpiryStatus.finite);
    expect(state.expiresAt, DateTime.fromMillisecondsSinceEpoch(1704054600 * 1000));
  });

  for (final raw in ['upload=10; download=20; total=100', 'upload=10; download=20; total=100; expire=invalid']) {
    test('treats missing or invalid expiration "$raw" as unknown', () {
      final state = SubscriptionMetadataState.fromProfile(remote(rawSubscriptionInfo: raw), now: now);

      expect(state.expiry, SubscriptionExpiryStatus.unknown);
      expect(state.expiresAt, isNull);
    });
  }

  test('treats an oversized expiration as unknown instead of throwing', () {
    final state = SubscriptionMetadataState.fromProfile(
      remote(rawSubscriptionInfo: 'upload=10; download=20; total=100; expire=8640000000001'),
      now: now,
    );

    expect(state.expiry, SubscriptionExpiryStatus.unknown);
    expect(state.expiresAt, isNull);
  });

  for (final rawExpire in ['0.5', '1e-1']) {
    test('does not coerce non-integer expiration "$rawExpire" to unlimited', () {
      final state = SubscriptionMetadataState.fromProfile(
        remote(rawSubscriptionInfo: 'upload=10; download=20; total=100; expire=$rawExpire'),
        now: now,
      );

      expect(state.expiry, SubscriptionExpiryStatus.unknown);
    });
  }

  test('uses unlimited only for explicit zero expiration', () {
    final unlimited = SubscriptionMetadataState.fromProfile(
      remote(
        subInfo: SubscriptionInfo(
          upload: 10,
          download: 20,
          total: 100,
          expire: DateTime.fromMillisecondsSinceEpoch(subscriptionInfiniteTimeThreshold * 1000),
        ),
        rawSubscriptionInfo: 'upload=10; download=20; total=100; expire=0',
      ),
      now: now,
    );
    final legacySentinelWithoutSource = SubscriptionMetadataState.fromProfile(
      remote(
        subInfo: SubscriptionInfo(
          upload: 10,
          download: 20,
          total: 100,
          expire: DateTime.fromMillisecondsSinceEpoch(subscriptionInfiniteTimeThreshold * 1000),
        ),
      ),
      now: now,
    );

    expect(unlimited.expiry, SubscriptionExpiryStatus.unlimited);
    expect(legacySentinelWithoutSource.expiry, SubscriptionExpiryStatus.unknown);
  });

  test('marks metadata stale only after its configured refresh interval', () {
    final state = SubscriptionMetadataState.fromProfile(
      remote(
        rawSubscriptionInfo: 'upload=10; download=20; total=100; expire=0',
        lastUpdate: now.subtract(const Duration(hours: 25)),
        updateInterval: const Duration(hours: 24),
      ),
      now: now,
    );

    expect(state.freshness, SubscriptionMetadataFreshness.stale);
  });

  test('reports exhausted finite quota independently from expiration', () {
    final state = SubscriptionMetadataState.fromProfile(
      remote(
        subInfo: SubscriptionInfo(upload: 40, download: 60, total: 100, expire: now.add(const Duration(days: 400))),
        rawSubscriptionInfo:
            'upload=40; download=60; total=100; expire=${now.add(const Duration(days: 400)).millisecondsSinceEpoch ~/ 1000}',
      ),
      now: now,
    );

    expect(state.quota, SubscriptionQuotaStatus.exhausted);
    expect(state.expiry, SubscriptionExpiryStatus.finite);
  });

  test('does not treat an invalid quota as unlimited', () {
    final state = SubscriptionMetadataState.fromProfile(
      remote(rawSubscriptionInfo: 'upload=10; download=20; total=invalid; expire=0'),
      now: now,
    );

    expect(state.quota, SubscriptionQuotaStatus.unknown);
  });

  test('explicit zero total is unlimited without usage fields', () {
    final state = SubscriptionMetadataState.fromProfile(remote(rawSubscriptionInfo: 'total=0; expire=0'), now: now);

    expect(state.quota, SubscriptionQuotaStatus.unlimited);
  });

  test('treats the legacy traffic sentinel without source metadata as unknown', () {
    final state = SubscriptionMetadataState.fromProfile(
      remote(
        subInfo: SubscriptionInfo(
          upload: 10,
          download: 20,
          total: subscriptionLegacyInfiniteTrafficSentinel,
          expire: now.add(const Duration(days: 10)),
        ),
      ),
      now: now,
    );

    expect(state.quota, SubscriptionQuotaStatus.unknown);
  });

  for (final rawUsage in ['upload=invalid; download=20', 'upload=-1; download=20', 'upload=10; download=invalid']) {
    test('does not use cached consumption when raw usage is malformed: "$rawUsage"', () {
      final state = SubscriptionMetadataState.fromProfile(
        remote(
          subInfo: SubscriptionInfo(upload: 10, download: 20, total: 100, expire: now.add(const Duration(days: 10))),
          rawSubscriptionInfo: '$rawUsage; total=100; expire=0',
        ),
        now: now,
      );

      expect(state.quota, SubscriptionQuotaStatus.unknown);
    });
  }

  for (final rawTotal in ['0.5', '1e-1']) {
    test('does not coerce non-integer quota "$rawTotal" to unlimited', () {
      final state = SubscriptionMetadataState.fromProfile(
        remote(rawSubscriptionInfo: 'upload=10; download=20; total=$rawTotal; expire=0'),
        now: now,
      );

      expect(state.quota, SubscriptionQuotaStatus.unknown);
    });
  }
}
