import 'package:hiddify/core/logger/log_sanitizer.dart';
import 'package:hiddify/core/observability/observability.dart';
import 'package:hiddify/utils/sentry_utils.dart';
import 'package:loggy/loggy.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

// modified version of https://github.com/getsentry/sentry-dart/tree/main/logging
class SentryLoggyIntegration extends LoggyPrinter implements Integration<SentryOptions> {
  SentryLoggyIntegration({LogLevel minBreadcrumbLevel = LogLevel.info, LogLevel minEventLevel = LogLevel.error})
    : _minBreadcrumbLevel = minBreadcrumbLevel,
      _minEventLevel = minEventLevel;

  final LogLevel _minBreadcrumbLevel;
  final LogLevel _minEventLevel;

  late Hub _hub;

  @override
  void call(Hub hub, SentryOptions options) {
    _hub = hub;
    options.sdk.addIntegration('LoggyIntegration');
  }

  @override
  Future<void> close() async {}

  bool _shouldLog(LogLevel logLevel, LogLevel minLevel) {
    if (logLevel == LogLevel.off) {
      return false;
    }
    return logLevel.priority >= minLevel.priority;
  }

  @override
  Future<void> onLog(LogRecord record) async {
    if (!canLogEvent(record.error)) return;

    final payload = record.loggerName == 'observability' ? safeObservabilityPayload(record.message) : null;
    final isDurationTerminal =
        payload != null &&
        payload['duration_ms'] is int &&
        const {'succeeded', 'failed', 'cancelled'}.contains(payload['status']);
    if (_shouldLog(record.level, _minEventLevel) || (_shouldLog(record.level, LogLevel.info) && isDurationTerminal)) {
      await _hub.captureEvent(record.toEvent());
    }

    if (_shouldLog(record.level, _minBreadcrumbLevel)) {
      await _hub.addBreadcrumb(record.toBreadcrumb());
    }
  }
}

extension LogRecordX on LogRecord {
  Breadcrumb toBreadcrumb() {
    return Breadcrumb(
      category: 'log',
      type: 'debug',
      timestamp: time.toUtc(),
      level: level.toSentryLevel(),
      message: sanitizeLogText(message),
      data: <String, Object>{
        if (error != null) 'error_type': error.runtimeType.toString(),
        'LogRecord.loggerName': loggerName,
        'LogRecord.sequenceNumber': sequenceNumber,
      },
    );
  }

  SentryEvent toEvent() {
    return SentryEvent(
      timestamp: time.toUtc(),
      logger: loggerName,
      level: level.toSentryLevel(),
      message: SentryMessage(sanitizeLogText(message)),
      // ignore: deprecated_member_use
      extra: <String, Object>{
        if (error != null) 'error_type': error.runtimeType.toString(),
        'LogRecord.sequenceNumber': sequenceNumber,
      },
    );
  }
}

extension LogLevelX on LogLevel {
  SentryLevel? toSentryLevel() => switch (this) {
    LogLevel.all || LogLevel.debug => SentryLevel.debug,
    LogLevel.info => SentryLevel.info,
    LogLevel.warning => SentryLevel.warning,
    LogLevel.error => SentryLevel.error,
    _ => null,
  };
}
