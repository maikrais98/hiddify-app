import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hiddify/core/analytics/analytics_filter.dart';
import 'package:hiddify/core/analytics/analytics_logger.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';

import 'package:hiddify/core/logger/logger_controller.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/observability/better_stack_log_printer.dart';
import 'package:hiddify/core/observability/telemetry_budget.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'analytics_controller.g.dart';

const String enableAnalyticsPrefKey = "enable_analytics";

bool _testCrashReport = false;

@visibleForTesting
Future<bool> initializeTelemetrySafely({
  required Future<void> Function() initialize,
  required Future<void> Function() recover,
}) async {
  try {
    await initialize();
    return true;
  } catch (_) {
    try {
      await recover();
    } catch (_) {
      // Telemetry cleanup must never become an application-startup dependency.
    }
    return false;
  }
}

@Riverpod(keepAlive: true)
class AnalyticsController extends _$AnalyticsController with AppLogger {
  BetterStackLogPrinter? _remoteLogs;
  AppLifecycleListener? _lifecycle;

  @override
  Future<bool> build() async {
    ref.onDispose(_stopRemoteLogs);
    return const TelemetryPolicy().enabled(_preferences.getBool(enableAnalyticsPrefKey) ?? false);
  }

  SharedPreferences get _preferences => ref.read(sharedPreferencesProvider).requireValue;

  void _stopRemoteLogs() {
    _lifecycle?.dispose();
    _lifecycle = null;
    final logs = _remoteLogs;
    _remoteLogs = null;
    if (logs != null) unawaited(logs.dispose());
  }

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
      final budget = TelemetryBudget(
        read: () => _preferences.getString(TelemetryBudget.preferenceKey),
        write: (value) => _preferences.setString(TelemetryBudget.preferenceKey, value),
      );
      final endpoint = Uri.tryParse(Environment.betterStackLogsUrl);
      final logsEnabled =
          (!kDebugMode || _testCrashReport) &&
          endpoint != null &&
          isBetterStackLogsEndpoint(endpoint) &&
          Environment.betterStackSourceToken.isNotEmpty;
      final sentryLogger = SentryLoggyIntegration(captureDurationTerminals: !logsEnabled);
      final initialized = await initializeTelemetrySafely(
        initialize: () => SentryFlutter.init((options) {
          options.dsn = dsn;
          options.environment = env == Environment.dev ? 'dev' : const TelemetryPolicy().environment;
          options.release = '${appInfo.name}@${appInfo.version}';
          options.dist = appInfo.buildNumber;
          options.debug = false;
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
          options.enableUserInteractionTracing = false;
          options.addIntegration(sentryLogger);
          options.beforeSend = (event, hint) async {
            final safe = await sentryBeforeSend(event, hint);
            if (safe == null || !await budget.reserveException()) return null;
            return safe;
          };
          options.beforeBreadcrumb = sentryBeforeBreadcrumb;
          // SDK transactions retain arbitrary tracer children/data. Fail closed
          // until a typed exporter exists; P0 latency uses duration_ms events.
          options.beforeSendTransaction = (_) => null;
        }),
        recover: () async {
          LoggerController.instance.removePrinter("analytics");
          await Sentry.close();
        },
      );
      if (initialized) {
        LoggerController.instance.addPrinter("analytics", sentryLogger);
      } else {
        loggy.warning("analytics initialization unavailable");
      }
      _stopRemoteLogs();
      LoggerController.instance.removePrinter('betterstack');
      if (logsEnabled) {
        final logs = BetterStackLogPrinter(
          endpoint: endpoint,
          token: Environment.betterStackSourceToken,
          budget: budget,
        );
        _remoteLogs = logs;
        LoggerController.instance.addPrinter('betterstack', logs);
        _lifecycle = AppLifecycleListener(
          onInactive: () => unawaited(logs.flush()),
          onPause: () => unawaited(logs.flush()),
        );
      }
      state = AsyncData(initialized || logsEnabled);
    }
  }

  Future<void> disableAnalytics() async {
    if (!const TelemetryPolicy().canDisable) return;
    if (state case AsyncData()) {
      loggy.debug("disabling analytics");
      state = const AsyncLoading();
      await _preferences.setBool(enableAnalyticsPrefKey, false);
      _stopRemoteLogs();
      LoggerController.instance.removePrinter('betterstack');
      await Sentry.close();
      LoggerController.instance.removePrinter("analytics");
      state = const AsyncData(false);
    }
  }
}
