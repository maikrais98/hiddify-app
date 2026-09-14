import 'dart:convert';
import 'dart:math';

import 'package:dartx/dartx.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';

part 'profile_entity.freezed.dart';
part 'profile_entity.g.dart';

enum ProfileType { remote, local }

const int minProfileUpdateIntervalHours = 0;
const int maxProfileUpdateIntervalHours = 96;

int normalizeProfileUpdateIntervalHours(int hours) =>
    hours.clamp(minProfileUpdateIntervalHours, maxProfileUpdateIntervalHours);

int resolveProfileUpdateIntervalHours({int? userOverrideHours, Duration? profileInterval}) {
  final hours = userOverrideHours != null && userOverrideHours > minProfileUpdateIntervalHours
      ? userOverrideHours
      : profileInterval?.inHours ?? minProfileUpdateIntervalHours;
  return normalizeProfileUpdateIntervalHours(hours);
}

@freezed
sealed class ProfileEntity with _$ProfileEntity {
  const ProfileEntity._();

  const factory ProfileEntity.remote({
    required String id,
    required bool active,
    required String name,
    required String url,
    required DateTime lastUpdate,
    ProfileOptions? options,
    SubscriptionInfo? subInfo,
    Map<String, dynamic>? populatedHeaders,
    UserOverride? userOverride,
  }) = RemoteProfileEntity;

  const factory ProfileEntity.local({
    required String id,
    required bool active,
    required String name,
    required DateTime lastUpdate,
    Map<String, dynamic>? populatedHeaders,
    UserOverride? userOverride,
  }) = LocalProfileEntity;

  String profileOverride() =>
      ProfileParser.profileOverride(populatedHeaders: populatedHeaders, userOverride: userOverride);
}

@freezed
class ProfileOptions with _$ProfileOptions {
  const factory ProfileOptions({@Default(Duration.zero) Duration updateInterval}) = _ProfileOptions;
}

@freezed
class SubscriptionInfo with _$SubscriptionInfo {
  const SubscriptionInfo._();

  const factory SubscriptionInfo({
    required int upload,
    required int download,
    required int total,
    required DateTime expire,
    String? webPageUrl,
    String? supportUrl,
  }) = _SubscriptionInfo;

  bool get isExpired => expire <= DateTime.now();

  int get consumption => upload + download;
  int get remainingBW => total - consumption;
  double get remainingBWratio => (remainingBW / total).clamp(0, 1);
  double get ratio => (consumption / total).clamp(0, 1);

  Duration get remaining => expire.difference(DateTime.now());
  double get remainingRatio => min(remaining.inDays, 30) / 30;
}

const int latestUserOverrideVersion = 1;

@freezed
abstract class UserOverride with _$UserOverride {
  const UserOverride._();

  const factory UserOverride({
    @Default(latestUserOverrideVersion) int version,
    String? name,
    @Default(false) bool isAutoUpdateDisable,
    // hours
    int? updateInterval,
    bool? enableWarp,
    bool? enablePsiphon,
    bool? enableFragment,
  }) = _UserOverride;

  factory UserOverride.fromJson(Map<String, Object?> json) => _$UserOverrideFromJson(json);

  String toStr() => jsonEncode(
    copyWith(
      updateInterval: updateInterval == null ? null : normalizeProfileUpdateIntervalHours(updateInterval!),
    ).toJson(),
  );

  static UserOverride? fromStr(String? str) {
    if (str != null) {
      final m = (jsonDecode(str) as Map).cast<String, Object?>();
      final override = UserOverride.fromJson(_migrate(m));
      return override.copyWith(
        updateInterval: override.updateInterval == null
            ? null
            : normalizeProfileUpdateIntervalHours(override.updateInterval!),
      );
    }
    return null;
  }

  static Map<String, dynamic> _migrate(Map<String, Object?> json) {
    final version = json['version'] as int? ?? 1;

    if (version < 2) {
      // Migration 1 to 2
    }
    json['version'] = latestUserOverrideVersion;
    return json;
  }
}
