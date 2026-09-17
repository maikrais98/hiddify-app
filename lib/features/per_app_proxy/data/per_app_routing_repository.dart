import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:hiddify/features/per_app_proxy/model/app_package_info.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum PerAppRoutingFailureKind { denied, unavailable, unsupported }

class PerAppRoutingException implements Exception {
  const PerAppRoutingException({required this.kind, this.canOpenSettings = false});

  final PerAppRoutingFailureKind kind;
  final bool canOpenSettings;
}

abstract interface class PerAppRoutingRepository {
  Future<List<AppPackageInfo>> getInstalledApps({bool excludeSystemApps = false});
}

class MethodChannelPerAppRoutingRepository implements PerAppRoutingRepository {
  const MethodChannelPerAppRoutingRepository({this.channel = const MethodChannel('com.hiddify.app/platform')});

  final MethodChannel channel;

  @override
  Future<List<AppPackageInfo>> getInstalledApps({bool excludeSystemApps = false}) async {
    try {
      final encoded = await channel.invokeMethod<String>('get_installed_packages', {
        'excludeSystemApps': excludeSystemApps,
        'withIcons': true,
      });
      if (encoded == null) throw const FormatException('Missing installed-app inventory');
      final items = (jsonDecode(encoded) as List).cast<Map<String, dynamic>>();
      return items
          .map((item) {
            final encodedIcon = item['icon'] as String?;
            return AppPackageInfo(
              packageName: item['package-name']! as String,
              name: item['name']! as String,
              icon: encodedIcon == null ? null : base64Decode(encodedIcon),
            );
          })
          .toList(growable: false);
    } on MissingPluginException {
      throw const PerAppRoutingException(kind: PerAppRoutingFailureKind.unsupported);
    } on PlatformException catch (error) {
      final details = error.details is Map
          ? (error.details as Map).cast<Object?, Object?>()
          : const <Object?, Object?>{};
      final kind = switch (details['state']) {
        'denied' => PerAppRoutingFailureKind.denied,
        'unsupported' => PerAppRoutingFailureKind.unsupported,
        _ => PerAppRoutingFailureKind.unavailable,
      };
      throw PerAppRoutingException(kind: kind, canOpenSettings: details['canOpenSettings'] == true);
    } on PerAppRoutingException {
      rethrow;
    } catch (_) {
      throw const PerAppRoutingException(kind: PerAppRoutingFailureKind.unavailable);
    }
  }
}

final perAppRoutingRepositoryProvider = Provider<PerAppRoutingRepository>(
  (ref) => const MethodChannelPerAppRoutingRepository(),
);
