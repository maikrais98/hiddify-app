import 'dart:async';

import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:loggy/loggy.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'hiddify_core_service_provider.g.dart';

typedef HiddifyCoreServiceFactory = HiddifyCoreService Function(Ref ref);

@visibleForTesting
final hiddifyCoreServiceFactoryProvider = Provider<HiddifyCoreServiceFactory>((ref) => HiddifyCoreService.new);

final _logger = Loggy('HiddifyCoreServiceProvider');

@Riverpod(keepAlive: true, dependencies: [AppDirectories, DebugModeNotifier, inAppNotificationController])
HiddifyCoreService hiddifyCoreService(Ref ref) {
  final service = ref.read(hiddifyCoreServiceFactoryProvider)(ref);
  ref.onDispose(() {
    unawaited(
      service.dispose().catchError((Object _, StackTrace _) {
        _logger.warning('hiddify-core service disposal failed');
      }),
    );
  });
  return service;
}
