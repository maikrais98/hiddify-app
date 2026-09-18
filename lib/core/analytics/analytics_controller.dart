import 'package:flutter/foundation.dart';
import 'package:hiddify/core/analytics/analytics_filter.dart';
import 'package:hiddify/core/analytics/analytics_logger.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';

import 'package:hiddify/core/logger/logger_controller.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'analytics_controller.g.dart';

const String enableAnalyticsPrefKey = "enable_analytics";

bool _testCrashReport = false;

@Riverpod(keepAlive: true)
class AnalyticsController extends _$AnalyticsController with AppLogger {
  @override
  Future<bool> build() async {
    return const TelemetryPolicy().enabled(_preferences.getBool(enableAnalyticsPrefKey) ?? false);
  }

  SharedPreferences get _preferences => ref.read(sharedPreferencesProvider).requireValue;

  Future<void> enableAnalytics() async {
    if (state case AsyncData(value: final enabled)) {
      loggy.debug("enabling analytics");
      state = const AsyncLoading();
      if (!enabled) {
        await _preferences.setBool(enableAnalyticsPrefKey, true);
      }

      final env = ref.read(environmentProvider);
      final appInfo = await ref.read(appInfoProvider.future);
      final dsn = !kDebugMode || _testCrashReport ? Environment.sentryDSN : "";
      final sentryLogger = SentryLoggyIntegration();
      LoggerController.instance.addPrinter("analytics", sentryLogger);

      await SentryFlutter.init((options) {
        options.dsn = dsn;
        options.environment = env == Environment.dev ? 'dev' : const TelemetryPolicy().environment;
        options.release = '${appInfo.name}@${appInfo.version}';
        options.dist = appInfo.buildNumber;
        options.debug = kDebugMode;
        // Cocoa crash events bypass the Dart beforeSend sanitizer. Keep this
        // path fail-closed until a native typed exporter enforces our schema.
        options.enableNativeCrashHandling = false;
        options.enableNdkScopeSync = false;
        // options.autoAppStart = false;
        // options.attachScreenshot = true;
        options.serverName = "";
        options.attachThreads = false;
        options.sendDefaultPii = false;
        options.tracesSampleRate = const TelemetryPolicy().tracesSampleRate;
        options.enableUserInteractionTracing = true;
        options.addIntegration(sentryLogger);
        options.beforeSend = sentryBeforeSend;
        options.beforeBreadcrumb = sentryBeforeBreadcrumb;
        // SDK transactions retain arbitrary tracer children/data. Fail closed
        // until a typed exporter exists; P0 latency uses duration_ms events.
        options.beforeSendTransaction = (_) => null;
      });

      state = const AsyncData(true);
    }
  }

  Future<void> disableAnalytics() async {
    if (!const TelemetryPolicy().canDisable) return;
    if (state case AsyncData()) {
      loggy.debug("disabling analytics");
      state = const AsyncLoading();
      await _preferences.setBool(enableAnalyticsPrefKey, false);
      await Sentry.close();
      LoggerController.instance.removePrinter("analytics");
      state = const AsyncData(false);
    }
  }
}
