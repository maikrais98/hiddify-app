import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hiddify/core/analytics/analytics_filter.dart';
import 'package:hiddify/core/analytics/analytics_logger.dart';
import 'package:hiddify/core/analytics/telemetry_delivery_provider.dart';
import 'package:hiddify/core/logger/logger_controller.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/observability/better_stack_log_printer.dart';
import 'package:hiddify/core/observability/telemetry_budget.dart';
import 'package:hiddify/core/observability/telemetry_delivery_status.dart';
import 'package:hiddify/core/observability/telemetry_transport_attempt.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/diagnostics/diagnostic_providers.dart';
import 'package:hiddify/features/diagnostics/native_diagnostic_importer.dart';
import 'package:hiddify/features/diagnostics/remote_diagnostic_subscription.dart';
import 'package:hiddify/features/diagnostics/remote_ios_ping_subscription.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

part 'analytics_controller.g.dart';

const String nativeDiagnosticDisabledPrefKey = "native_diagnostic_disabled_v1";
const String enableAnalyticsPrefKey = "enable_analytics";
const String nativeDiagnosticBaselinePendingPrefKey = "native_diagnostic_baseline_pending_v1";

/// The enabled bit is written only after the exact native consent boundary.
@visibleForTesting
Future<bool> persistAnalyticsEnableBoundary({
  required SharedPreferences preferences,
  Future<String> Function()? captureNativeBaseline,
}) async {
  final frozen = await captureNativeBaseline?.call();
  if (frozen != null && !NativeDiagnosticImporter.isValidBaseline(frozen)) return false;
  final saved = frozen == null
      ? await preferences.setBool(nativeDiagnosticBaselinePendingPrefKey, true)
      : await preferences.setString(nativeDiagnosticBaselinePendingPrefKey, frozen);
  if (!saved || !await preferences.setBool(enableAnalyticsPrefKey, true)) return false;
  if (preferences.getBool(nativeDiagnosticDisabledPrefKey) == true &&
      !await preferences.remove(nativeDiagnosticDisabledPrefKey)) {
    return false;
  }
  return true;
}

@Riverpod(keepAlive: true)
class AnalyticsController extends _$AnalyticsController with AppLogger {
  BetterStackLogPrinter? _remote;
  NativeDiagnosticImporter? _nativeImporter;
  RemoteDiagnosticSubscription? _journalSubscription;
  RemoteIosPingSubscription? _pingSubscription;
  StreamSubscription<TelemetryDeliveryStatus>? _deliverySubscription;
  TelemetryDeliveryMonitor? _deliveryMonitor;
  int? _lastPingSequence;

  void _publishDelivery(TelemetryDeliveryStatus status) {
    _deliveryMonitor?.update(status);
  }

  @override
  Future<bool> build() async {
    _deliveryMonitor = ref.read(telemetryDeliveryMonitorProvider);
    ref.onDispose(() {
      unawaited(_stopRemote());
    });
    final boundary = _preferences.get(nativeDiagnosticBaselinePendingPrefKey);
    if (boundary != null && boundary != true && !NativeDiagnosticImporter.isValidBaseline(boundary)) return false;
    if (_preferences.getBool(nativeDiagnosticDisabledPrefKey) == true ||
        (_nativeRemoteEligible && _preferences.get(nativeDiagnosticBaselinePendingPrefKey) == true)) {
      return false;
    }
    return _preferences.getBool(enableAnalyticsPrefKey) ?? Environment.telemetryBeta;
  }

  bool get _nativeRemoteEligible => !kDebugMode && !kIsWeb && Platform.isIOS && Environment.telemetryBeta;

  SharedPreferences get _preferences => ref.read(sharedPreferencesProvider).requireValue;

  Future<void> _stopRemote({bool clearPending = false}) async {
    _nativeImporter?.detachRemote();
    _nativeImporter = null;
    _pingSubscription?.dispose();
    _pingSubscription = null;
    _journalSubscription?.dispose();
    _journalSubscription = null;
    final remote = _remote;
    _remote = null;
    await _deliverySubscription?.cancel();
    _deliverySubscription = null;
    _publishDelivery(const TelemetryDeliveryStatus.disabled());
    if (remote != null) await remote.dispose(clearPending: clearPending);
    if (clearPending) {
      await _preferences.remove(BetterStackLogPrinter.preferenceKey);
      await _preferences.remove(TelemetryTransportAttempt.preferenceKey);
      await _preferences.remove(TelemetryTransportAttempt.lastTestPreferenceKey);
    }
  }

  Future<void> enableAnalytics() async {
    if (state case AsyncData(value: final enabled)) {
      state = const AsyncLoading();
      if (!enabled) {
        // Freeze the native OFF boundary while consent is still durably OFF.
        // A later process must never choose a newer snapshot for this consent.
        try {
          if (!await persistAnalyticsEnableBoundary(
            preferences: _preferences,
            captureNativeBaseline: _nativeRemoteEligible
                ? ref.read(nativeDiagnosticImporterProvider).captureBaseline
                : null,
          )) {
            state = const AsyncData(false);
            return;
          }
        } on Object {
          state = const AsyncData(false);
          return;
        }
      }
      await _stopRemote();
      final preferences = _preferences;
      final budget = TelemetryBudget(
        read: () => preferences.getString(TelemetryBudget.preferenceKey),
        write: (value) => preferences.setString(TelemetryBudget.preferenceKey, value),
      );
      final sentryLogger = SentryLoggyIntegration();
      LoggerController.instance.removePrinter("analytics");
      LoggerController.instance.addPrinter("analytics", sentryLogger);

      await SentryFlutter.init((options) {
        options.dsn = kDebugMode ? "" : Environment.sentryDSN;
        options.debug = false;
        options.serverName = "";
        options.tracesSampleRate = 0;
        options.enableUserInteractionTracing = false;
        options.addIntegration(sentryLogger);
        options.beforeSend = sentryBeforeSend;
        if (!kIsWeb && Platform.isIOS) configureIosSafeSentryOptions(options);
        final filter = options.beforeSend;
        options.beforeSend = (event, hint) async {
          final safe = filter == null ? event : await filter(event, hint);
          if (safe == null || !await budget.reserveException()) return null;
          return safe;
        };
      });

      if (_nativeRemoteEligible) {
        final endpoint = Uri.tryParse(Environment.betterStackLogsURL);
        if (endpoint != null && isBetterStackLogsEndpoint(endpoint) && Environment.betterStackSourceToken.isNotEmpty) {
          final metadata = ref.read(safeDiagnosticMetadataProvider);
          final remote = BetterStackLogPrinter(
            endpoint: endpoint,
            token: Environment.betterStackSourceToken,
            budget: budget,
            sessionId: const Uuid().v4(),
            version: metadata.version,
            buildNumber: metadata.buildNumber,
            readOutbox: () => preferences.getString(BetterStackLogPrinter.preferenceKey),
            writeOutbox: (value) => preferences.setString(BetterStackLogPrinter.preferenceKey, value),
            readLastAttempt: () => preferences.getString(TelemetryTransportAttempt.preferenceKey),
            writeLastAttempt: (value) => preferences.setString(TelemetryTransportAttempt.preferenceKey, value),
            readLastTestAttempt: () => preferences.getString(TelemetryTransportAttempt.lastTestPreferenceKey),
            writeLastTestAttempt: (value) =>
                preferences.setString(TelemetryTransportAttempt.lastTestPreferenceKey, value),
          );
          _remote = remote;
          _deliverySubscription = remote.deliveryStatuses.listen(_publishDelivery);
          _publishDelivery(remote.deliveryStatus);
          _journalSubscription = RemoteDiagnosticSubscription(ref.read(safeDiagnosticJournalProvider), remote);
          final importer = ref.read(nativeDiagnosticImporterProvider);
          _nativeImporter = importer;
          final boundary = preferences.get(nativeDiagnosticBaselinePendingPrefKey);
          await importer.attachRemote(
            remote,
            baseline: boundary != null,
            persistedBaseline: boundary is String ? boundary : null,
            persistBaseline: (value) => preferences.setString(nativeDiagnosticBaselinePendingPrefKey, value),
            onBaselinePersisted: () async {
              if (preferences.get(nativeDiagnosticBaselinePendingPrefKey) != boundary ||
                  !await preferences.remove(nativeDiagnosticBaselinePendingPrefKey)) {
                throw StateError('native diagnostic baseline persistence failed');
              }
            },
          );
          final trace = ref.read(iosPingTraceProvider);
          final events = trace.snapshot.events;
          final cursor = enabled ? (_lastPingSequence ?? 0) : (events.isEmpty ? 0 : events.last.sequence);
          _lastPingSequence = cursor;
          _pingSubscription = RemoteIosPingSubscription(
            trace,
            remote,
            afterSequence: cursor,
            onSequence: (sequence) => _lastPingSequence = sequence,
          );
        }
      }
      state = const AsyncData(true);
    }
  }

  /// A server acknowledgement remains separate from visibility in Better Stack search.
  Future<TelemetryTestResult> sendTestEvent() async {
    final remote = _remote;
    if (remote == null) return const TelemetryTestResult(outcome: TelemetryTestOutcome.disabled);
    return remote.sendTestEvent();
  }

  Future<void> disableAnalytics() async {
    if (state case AsyncData()) {
      state = const AsyncLoading();
      // Keep the recovery marker until a later explicit enable completes.
      // Either durable write is sufficient to keep bootstrap fail-closed.
      Future<bool> saveBool(String key, bool value) async {
        try {
          return await _preferences.setBool(key, value);
        } on Object {
          return false;
        }
      }

      final markerSaved = await saveBool(nativeDiagnosticDisabledPrefKey, true);
      final disabledSaved = await saveBool(enableAnalyticsPrefKey, false);
      await _stopRemote(clearPending: true);
      LoggerController.instance.removePrinter("analytics");
      await Sentry.close();
      if (!markerSaved && !disabledSaved) {
        final error = StateError('analytics disable could not be persisted');
        state = AsyncError(error, StackTrace.current);
        throw error;
      }
      state = const AsyncData(false);
    }
  }
}
