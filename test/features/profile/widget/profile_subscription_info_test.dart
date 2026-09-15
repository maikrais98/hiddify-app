import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/subscription_metadata_constants.dart';
import 'package:hiddify/features/profile/model/subscription_metadata_state.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  late Translations translations;

  setUpAll(() async {
    translations = await AppLocale.en.build();
  });

  Future<void> pumpInfo(WidgetTester tester, SubscriptionInfo? info, {required SubscriptionMetadataState metadata}) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [translationsProvider.overrideWith((ref) => translations)],
          child: MaterialApp(
            home: Scaffold(body: ProfileSubscriptionInfo(info, metadata: metadata)),
          ),
        ),
      );

  testWidgets('finite expiration beyond 365 days is not rendered as infinity', (tester) async {
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(days: 400));
    final info = SubscriptionInfo(upload: 10, download: 20, total: 100, expire: expiresAt);
    final profile = ProfileEntity.remote(
      id: 'profile',
      active: true,
      name: 'Profile',
      url: 'https://example.com/subscription',
      lastUpdate: now,
      subInfo: info,
      populatedHeaders: {
        'subscription-userinfo':
            'upload=10; download=20; total=100; expire=${expiresAt.millisecondsSinceEpoch ~/ 1000}',
      },
    );
    final metadata = SubscriptionMetadataState.fromProfile(profile, now: now);

    await pumpInfo(tester, info, metadata: metadata);

    expect(find.text('Expire date: ${metadata.expiresAt!.format()}'), findsOneWidget);
    expect(find.textContaining('∞'), findsNothing);
  });

  testWidgets('unknown expiration is labelled without infinity', (tester) async {
    final info = SubscriptionInfo(
      upload: 10,
      download: 20,
      total: 100,
      expire: DateTime.now().add(const Duration(days: 10)),
    );
    final profile = ProfileEntity.remote(
      id: 'profile',
      active: true,
      name: 'Profile',
      url: 'https://example.com/subscription',
      lastUpdate: DateTime.now(),
      subInfo: info,
      populatedHeaders: const {'subscription-userinfo': 'upload=10; download=20; total=100'},
    );
    final metadata = SubscriptionMetadataState.fromProfile(profile, now: DateTime.now());

    await pumpInfo(tester, info, metadata: metadata);

    expect(find.text('Expire date: Unknown'), findsOneWidget);
    expect(find.textContaining('∞'), findsNothing);
  });

  testWidgets('exhausted quota is labelled without infinity', (tester) async {
    final info = SubscriptionInfo(
      upload: 40,
      download: 60,
      total: 100,
      expire: DateTime.now().add(const Duration(days: 10)),
    );
    final profile = ProfileEntity.remote(
      id: 'profile',
      active: true,
      name: 'Profile',
      url: 'https://example.com/subscription',
      lastUpdate: DateTime.now(),
      subInfo: info,
      populatedHeaders: const {'subscription-userinfo': 'upload=40; download=60; total=100'},
    );
    final metadata = SubscriptionMetadataState.fromProfile(profile, now: DateTime.now());

    await pumpInfo(tester, info, metadata: metadata);

    expect(find.text('Out of quota'), findsOneWidget);
    expect(find.textContaining('∞'), findsNothing);
  });

  testWidgets('expired and exhausted states remain independently visible', (tester) async {
    final now = DateTime.now();
    final expiresAt = now.subtract(const Duration(days: 1));
    final info = SubscriptionInfo(upload: 40, download: 60, total: 100, expire: expiresAt);
    final profile = ProfileEntity.remote(
      id: 'profile',
      active: true,
      name: 'Profile',
      url: 'https://example.com/subscription',
      lastUpdate: now,
      subInfo: info,
      populatedHeaders: {
        'subscription-userinfo':
            'upload=40; download=60; total=100; expire=${expiresAt.millisecondsSinceEpoch ~/ 1000}',
      },
    );
    final metadata = SubscriptionMetadataState.fromProfile(profile, now: now);

    await pumpInfo(tester, info, metadata: metadata);

    expect(find.text('Out of quota'), findsOneWidget);
    expect(find.text('Expired'), findsOneWidget);
  });

  testWidgets('unknown quota semantics do not announce a synthetic total', (tester) async {
    final info = SubscriptionInfo(
      upload: 10,
      download: 20,
      total: subscriptionInfiniteTrafficThreshold + 1,
      expire: DateTime.now().add(const Duration(days: 10)),
    );
    final profile = ProfileEntity.remote(
      id: 'profile',
      active: true,
      name: 'Profile',
      url: 'https://example.com/subscription',
      lastUpdate: DateTime.now(),
      subInfo: info,
      populatedHeaders: const {'subscription-userinfo': 'upload=10; download=20; total=invalid; expire=0'},
    );
    final metadata = SubscriptionMetadataState.fromProfile(profile, now: DateTime.now());

    await pumpInfo(tester, info, metadata: metadata);

    final traffic = find.text('Total traffic: Unknown');
    expect(traffic, findsOneWidget);
    expect(tester.getSemantics(traffic).label, 'Total traffic: Unknown');
  });

  testWidgets('unlimited quota semantics match the visible infinity', (tester) async {
    final info = SubscriptionInfo(
      upload: 10,
      download: 20,
      total: subscriptionInfiniteTrafficThreshold + 1,
      expire: DateTime.now().add(const Duration(days: 10)),
    );
    final profile = ProfileEntity.remote(
      id: 'profile',
      active: true,
      name: 'Profile',
      url: 'https://example.com/subscription',
      lastUpdate: DateTime.now(),
      subInfo: info,
      populatedHeaders: const {'subscription-userinfo': 'upload=10; download=20; total=0; expire=0'},
    );
    final metadata = SubscriptionMetadataState.fromProfile(profile, now: DateTime.now());

    await pumpInfo(tester, info, metadata: metadata);

    final traffic = find.text('∞ GiB');
    expect(traffic, findsOneWidget);
    expect(tester.getSemantics(traffic).label, '∞ GiB');
  });

  testWidgets('stale metadata shows last update and update action', (tester) async {
    final now = DateTime.now();
    final lastUpdate = now.subtract(const Duration(hours: 25));
    final info = SubscriptionInfo(upload: 10, download: 20, total: 100, expire: now.add(const Duration(days: 10)));
    final profile = ProfileEntity.remote(
      id: 'profile',
      active: true,
      name: 'Profile',
      url: 'https://example.com/subscription',
      lastUpdate: lastUpdate,
      options: const ProfileOptions(updateInterval: Duration(hours: 24)),
      subInfo: info,
      populatedHeaders: const {'subscription-userinfo': 'upload=10; download=20; total=100; expire=0'},
    );
    final metadata = SubscriptionMetadataState.fromProfile(profile, now: now);

    await pumpInfo(tester, info, metadata: metadata);

    expect(find.text('Last update: ${lastUpdate.format()} · Update subscriptions'), findsOneWidget);
  });
}
