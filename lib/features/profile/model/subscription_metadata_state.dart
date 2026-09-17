import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/subscription_metadata_constants.dart';

enum SubscriptionExpiryStatus { finite, unlimited, unknown }

enum SubscriptionQuotaStatus { available, exhausted, unlimited, unknown }

enum SubscriptionMetadataFreshness { current, stale, unknown }

class SubscriptionMetadataState {
  static const _maxDateTimeSeconds = 8_640_000_000_000;
  static const _maxSigned64BitInteger = 9_223_372_036_854_775_807;

  const SubscriptionMetadataState({
    required this.expiry,
    required this.quota,
    required this.freshness,
    required this.lastUpdate,
    this.expiresAt,
  });

  final SubscriptionExpiryStatus expiry;
  final SubscriptionQuotaStatus quota;
  final SubscriptionMetadataFreshness freshness;
  final DateTime lastUpdate;
  final DateTime? expiresAt;

  bool isExpiredAt(DateTime now) => expiry == SubscriptionExpiryStatus.finite && !expiresAt!.isAfter(now);

  factory SubscriptionMetadataState.fromProfile(ProfileEntity profile, {required DateTime now}) {
    return profile.map(
      local: (profile) => SubscriptionMetadataState(
        expiry: SubscriptionExpiryStatus.unknown,
        quota: SubscriptionQuotaStatus.unknown,
        freshness: SubscriptionMetadataFreshness.unknown,
        lastUpdate: profile.lastUpdate,
      ),
      remote: (profile) {
        final raw = _rawSubscriptionInfo(profile.populatedHeaders?['subscription-userinfo']);
        final parsed = _parseFields(raw);
        final rawExpire = _parseCompatibleNonNegativeInt(parsed?['expire']);
        final rawTotal = _parseCompatibleNonNegativeInt(parsed?['total']);
        final rawUpload = _parseCompatibleNonNegativeInt(parsed?['upload']);
        final rawDownload = _parseCompatibleNonNegativeInt(parsed?['download']);

        final (expiry, expiresAt) = _expiry(
          hasRawMetadata: raw != null,
          rawExpire: rawExpire,
          hasRawExpire: parsed?.containsKey('expire') ?? false,
          subInfo: profile.subInfo,
        );
        final quota = _quota(
          hasRawMetadata: raw != null,
          rawTotal: rawTotal,
          hasRawTotal: parsed?.containsKey('total') ?? false,
          rawConsumption: rawUpload != null && rawDownload != null ? rawUpload + rawDownload : null,
          subInfo: profile.subInfo,
        );
        final updateInterval = profile.options?.updateInterval;
        final freshness = updateInterval == null || updateInterval <= Duration.zero
            ? SubscriptionMetadataFreshness.unknown
            : now.difference(profile.lastUpdate) > updateInterval
            ? SubscriptionMetadataFreshness.stale
            : SubscriptionMetadataFreshness.current;

        return SubscriptionMetadataState(
          expiry: expiry,
          quota: quota,
          freshness: freshness,
          lastUpdate: profile.lastUpdate,
          expiresAt: expiresAt,
        );
      },
    );
  }

  static (SubscriptionExpiryStatus, DateTime?) _expiry({
    required bool hasRawMetadata,
    required int? rawExpire,
    required bool hasRawExpire,
    required SubscriptionInfo? subInfo,
  }) {
    if (hasRawMetadata) {
      if (!hasRawExpire || rawExpire == null) return (SubscriptionExpiryStatus.unknown, null);
      if (rawExpire == 0) return (SubscriptionExpiryStatus.unlimited, null);
      final expiresAt = _safeDateTimeFromSeconds(rawExpire);
      return expiresAt == null
          ? (SubscriptionExpiryStatus.unknown, null)
          : (SubscriptionExpiryStatus.finite, expiresAt);
    }
    if (subInfo == null ||
        subInfo.expire.millisecondsSinceEpoch == subscriptionInfiniteTimeThreshold * Duration.millisecondsPerSecond) {
      return (SubscriptionExpiryStatus.unknown, null);
    }
    return (SubscriptionExpiryStatus.finite, subInfo.expire);
  }

  static SubscriptionQuotaStatus _quota({
    required bool hasRawMetadata,
    required int? rawTotal,
    required bool hasRawTotal,
    required int? rawConsumption,
    required SubscriptionInfo? subInfo,
  }) {
    if (hasRawMetadata) {
      if (!hasRawTotal || rawTotal == null) return SubscriptionQuotaStatus.unknown;
      if (rawTotal == 0) return SubscriptionQuotaStatus.unlimited;
      if (rawConsumption == null) return SubscriptionQuotaStatus.unknown;
      return rawConsumption >= rawTotal ? SubscriptionQuotaStatus.exhausted : SubscriptionQuotaStatus.available;
    }
    if (subInfo == null ||
        subInfo.total == subscriptionInfiniteTrafficThreshold + 1 ||
        subInfo.total == subscriptionLegacyInfiniteTrafficSentinel ||
        subInfo.total <= 0) {
      return SubscriptionQuotaStatus.unknown;
    }
    return subInfo.consumption >= subInfo.total ? SubscriptionQuotaStatus.exhausted : SubscriptionQuotaStatus.available;
  }

  static String? _rawSubscriptionInfo(Object? value) => switch (value) {
    final String value when value.trim().isNotEmpty => value,
    [final String value] => value,
    _ => null,
  };

  static Map<String, String>? _parseFields(String? raw) {
    if (raw == null) return null;
    final fields = <String, String>{};
    for (final part in raw.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      fields[part.substring(0, separator).trim().toLowerCase()] = part.substring(separator + 1).trim();
    }
    return fields;
  }

  static int? _parseCompatibleNonNegativeInt(String? value) {
    final parsed = num.tryParse(value?.trim() ?? '');
    if (parsed == null || !parsed.isFinite || parsed < 0 || parsed > _maxSigned64BitInteger) return null;
    if (parsed > 0 && parsed < 1) return null;
    return parsed.toInt();
  }

  static DateTime? _safeDateTimeFromSeconds(int seconds) {
    if (seconds > _maxDateTimeSeconds) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * Duration.millisecondsPerSecond);
  }
}
