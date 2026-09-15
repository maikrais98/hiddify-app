import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/features/profile/data/profile_data_mapper.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/subscription_metadata_state.dart';

ProfileEntry _rowFrom(ProfileEntriesCompanion companion) => ProfileEntry(
  id: companion.id.value,
  type: companion.type.value,
  active: companion.active.value,
  name: companion.name.value,
  url: companion.url.value,
  lastUpdate: companion.lastUpdate.value,
  updateInterval: companion.updateInterval.value,
  upload: companion.upload.value,
  download: companion.download.value,
  total: companion.total.value,
  expire: companion.expire.value,
  webPageUrl: companion.webPageUrl.value,
  supportUrl: companion.supportUrl.value,
  populatedHeaders: companion.populatedHeaders.value,
  userOverride: companion.userOverride.value,
);

void main() {
  test('preserves explicit unlimited metadata through mapper roundtrip', () {
    const raw = 'upload=0;download=0;total=0;expire=0';
    final source = ProfileEntity.remote(
      id: 'profile',
      active: true,
      name: 'Profile',
      url: 'https://example.com/subscription',
      lastUpdate: DateTime.utc(2026, 9, 15, 12),
      populatedHeaders: const {'subscription-userinfo': raw},
    );

    final restored = _rowFrom(source.toInsertEntry()).toEntity();

    expect(restored.populatedHeaders?['subscription-userinfo'], raw);
    final state = SubscriptionMetadataState.fromProfile(restored, now: source.lastUpdate);
    expect(state.expiry, SubscriptionExpiryStatus.unlimited);
    expect(state.quota, SubscriptionQuotaStatus.unlimited);
    expect(state.expiresAt, isNull);
  });
}
