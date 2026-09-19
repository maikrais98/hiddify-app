import 'dart:collection';
import 'dart:convert';
import 'package:hiddify/core/model/app_info_entity.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:loggy/loggy.dart';
import 'package:uuid/uuid.dart';

enum ObservabilityLevel { debug, info, warning, error }

enum ObservabilityModule { vpn, app, native, access, api }

enum ApiEndpointClass { other, profileDownload }

enum ApiStatusClass { http2xx, http4xx, http5xx, timeout, cancelled, tls, networkUnavailable, unknownSafe }

enum ObservabilityOperation {
  initialize,
  build,
  parse,
  start,
  connect,
  reconnect,
  disconnect,
  connection,
  coreLog,
  test,
  nativeBridge,
  accessImport,
  accessUpdate,
  statusStream,
  request,
  diagnosticExport,
}

enum ObservabilityStatus {
  started,
  succeeded,
  failed,
  cancelled,
  observed,
  connected,
  connecting,
  disconnected,
  disconnecting,
}

enum ObservabilityEvent {
  operationStarted,
  operationSucceeded,
  operationFailed,
  operationCancelled,
  vpnInitializationStarted,
  vpnInitializationFailed,
  vpnInitializationSucceeded,
  vpnConnectionStateChanged,
  vpnReconnectStarted,
  vpnReconnectFailed,
  vpnReconnectSucceeded,
  vpnConnectionStarted,
  vpnConnectionFailed,
  vpnConnected,
  vpnDisconnectStarted,
  vpnDisconnectFailed,
  vpnDisconnected,
  vpnCoreWarningReceived,
  nativeDiagnosticReceived,
  testEvent,
  exceptionCaptured,
  accessValidating,
  accessFetching,
  accessParsing,
  accessPersisting,
  statusStreamRetrying,
  statusStreamExhausted,
  apiRequestStarted,
  apiRequestCompleted,
  diagnosticFileCreated,
  diagnosticFileShareCompleted,
  diagnosticFileDiscarded,
}

enum ObservabilityErrorCode {
  statusStreamUnavailable,
  vpnPermissionDenied,
  notificationPermissionDenied,
  missingPrivilege,
  invalidConfigurationOptions,
  invalidConfiguration,
  coreUnavailable,
  warpLicenseMissing,
  psiphonLicenseMissing,
  unexpectedConnectionFailure,
  coreWarning,
  coreError,
  coreFatal,
  corePanic,
  nativeFailure,
  authenticationFailure,
  configurationFailure,
  dnsFailure,
  networkFailure,
  permissionFailure,
  timeout,
  ioFailure,
  invalidUrl,
  accessNotFound,
  accessUnexpected,
  permissionDenied,
  coreInitializationFailed,
  tunnelStartFailed,
  connectionTimeout,
  networkUnavailable,
  unexpectedState,
  unknownSafe,
}

String _wire(Enum value) => switch (value) {
  ApiStatusClass.http2xx => 'http_2xx',
  ApiStatusClass.http4xx => 'http_4xx',
  ApiStatusClass.http5xx => 'http_5xx',
  ApiStatusClass.timeout => 'network_timeout',
  ApiStatusClass.tls => 'tls_failure',
  ApiStatusClass.unknownSafe => 'unexpected_network_failure',
  _ => value.name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}'),
};
final _uuidPattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
String _metadata(String value) => RegExp(r'^[a-zA-Z0-9.+_-]{1,64}$').hasMatch(value) ? value : 'unknown';
typedef ObservabilitySink = void Function(Map<String, Object> payload, ObservabilityLevel level);

/// Privacy-safe, immutable data that may be embedded in a user-created
/// diagnostic report. Correlation identifiers and arbitrary text are omitted.
final class ObservabilityDiagnosticSnapshot {
  const ObservabilityDiagnosticSnapshot({
    required this.appVersion,
    required this.buildNumber,
    required this.environment,
    required this.platform,
    required this.latestErrorCode,
    required this.recentEvents,
  });

  final String appVersion;
  final String buildNumber;
  final String environment;
  final String platform;
  final String? latestErrorCode;
  final List<Map<String, Object>> recentEvents;
}

final class ObservabilityClient {
  ObservabilityClient({required ObservabilitySink sink}) : _sink = sink;
  final ObservabilitySink _sink;
  final String sessionId = const Uuid().v4();
  String _environment = 'unknown';
  String _appVersion = 'unknown';
  String _buildNumber = 'unknown';
  String _platform = 'unknown';
  int _informationalEmissions = 0;
  final ListQueue<Map<String, Object>> _diagnosticEvents = ListQueue<Map<String, Object>>(50);

  int get bufferedEventCount => _diagnosticEvents.length;

  ObservabilityDiagnosticSnapshot get diagnosticSnapshot {
    final firstRecent = _diagnosticEvents.length > 20 ? _diagnosticEvents.length - 20 : 0;
    final recent = _diagnosticEvents.skip(firstRecent).toList(growable: false);
    String? latestErrorCode;
    for (final event in _diagnosticEvents.toList().reversed) {
      final code = event['error_code'];
      if (code is String) {
        latestErrorCode = code;
        break;
      }
    }
    return ObservabilityDiagnosticSnapshot(
      appVersion: _appVersion,
      buildNumber: _buildNumber,
      environment: _environment,
      platform: _platform,
      latestErrorCode: latestErrorCode,
      recentEvents: List.unmodifiable(recent.map((event) => Map<String, Object>.unmodifiable(event))),
    );
  }

  void configure(AppInfoEntity info) {
    _environment = info.environment == Environment.dev ? 'dev' : const TelemetryPolicy().environment;
    _appVersion = _metadata(info.version);
    _buildNumber = _metadata(info.buildNumber);
    _platform = _metadata(info.operatingSystem);
  }

  OperationHandle startOperation({required ObservabilityModule module, required ObservabilityOperation operation}) {
    final handle = OperationHandle._(this, module, operation);
    event(
      module: module,
      operation: operation,
      name: ObservabilityEvent.operationStarted,
      status: ObservabilityStatus.started,
      operationId: handle.id,
    );
    return handle;
  }

  void captureException({
    required ObservabilityModule module,
    required ObservabilityOperation operation,
    required ObservabilityErrorCode errorCode,
    String? operationId,
  }) {
    event(
      module: module,
      operation: operation,
      name: ObservabilityEvent.exceptionCaptured,
      status: ObservabilityStatus.failed,
      errorCode: errorCode,
      operationId: operationId,
      level: ObservabilityLevel.error,
    );
  }

  /// Explicit diagnostic action; never called during startup.
  void sendTestEvent() => event(
    module: ObservabilityModule.app,
    operation: ObservabilityOperation.test,
    name: ObservabilityEvent.testEvent,
    status: ObservabilityStatus.observed,
    level: ObservabilityLevel.error,
  );
  void event({
    required ObservabilityModule module,
    required ObservabilityOperation operation,
    required ObservabilityEvent name,
    required ObservabilityStatus status,
    String? operationId,
    ObservabilityErrorCode? errorCode,
    int? durationMs,
    int? count,
    String? requestId,
    ApiEndpointClass? endpointClass,
    ApiStatusClass? statusClass,
    int? retryCount,
    ObservabilityLevel level = ObservabilityLevel.info,
  }) {
    final payload = <String, Object>{
      'schema_version': 1,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'environment': _environment,
      'app_version': _appVersion,
      'build_number': _buildNumber,
      'platform': _platform,
      'session_id': sessionId,
      if (operationId != null && _uuidPattern.hasMatch(operationId)) 'operation_id': operationId,
      'module': _wire(module),
      'operation': _wire(operation),
      'event': _wire(name),
      'status': _wire(status),
      if (durationMs != null) 'duration_ms': durationMs.clamp(0, 86400000),
      if (count != null) 'count': count.clamp(0, 1000000),
      if (errorCode != null) 'error_code': _wire(errorCode),
      if (requestId != null && _uuidPattern.hasMatch(requestId)) 'request_id': requestId,
      if (endpointClass != null) 'endpoint_class': _wire(endpointClass),
      if (statusClass != null) 'status_class': _wire(statusClass),
      if (retryCount != null) 'retry_count': retryCount.clamp(0, 1000),
    };
    _recordDiagnosticEvent(payload);
    final isOperationLifecycle = switch (name) {
      ObservabilityEvent.operationStarted ||
      ObservabilityEvent.operationSucceeded ||
      ObservabilityEvent.operationFailed ||
      ObservabilityEvent.operationCancelled ||
      ObservabilityEvent.apiRequestStarted ||
      ObservabilityEvent.apiRequestCompleted => true,
      _ => false,
    };
    if (!isOperationLifecycle && (level == ObservabilityLevel.debug || level == ObservabilityLevel.info)) {
      if (_informationalEmissions >= 50) return;
      _informationalEmissions++;
    }
    try {
      _sink(Map.unmodifiable(payload), level);
    } catch (_) {
      /* Diagnostics cannot break app operations. */
    }
  }

  void _recordDiagnosticEvent(Map<String, Object> payload) {
    final event = <String, Object>{};
    for (final key in const [
      'timestamp',
      'module',
      'operation',
      'event',
      'status',
      'duration_ms',
      'count',
      'error_code',
      'endpoint_class',
      'status_class',
      'retry_count',
    ]) {
      final value = payload[key];
      if (value != null) event[key] = value;
    }
    if (_diagnosticEvents.length == 50) _diagnosticEvents.removeFirst();
    _diagnosticEvents.addLast(Map.unmodifiable(event));
  }
}

final class OperationHandle {
  OperationHandle._(this._client, this.module, this.operation);
  final ObservabilityClient _client;
  final ObservabilityModule module;
  final ObservabilityOperation operation;
  final String id = const Uuid().v4();
  final Stopwatch _stopwatch = Stopwatch()..start();
  bool _completed = false;
  void success() => _finish(ObservabilityStatus.succeeded, ObservabilityEvent.operationSucceeded);
  void failure(ObservabilityErrorCode code) =>
      _finish(ObservabilityStatus.failed, ObservabilityEvent.operationFailed, code);
  void cancel() => _finish(ObservabilityStatus.cancelled, ObservabilityEvent.operationCancelled);
  void _finish(ObservabilityStatus status, ObservabilityEvent name, [ObservabilityErrorCode? code]) {
    if (_completed) return;
    _completed = true;
    _stopwatch.stop();
    _client.event(
      module: module,
      operation: operation,
      name: name,
      status: status,
      operationId: id,
      errorCode: code,
      durationMs: _stopwatch.elapsedMilliseconds,
      level: status == ObservabilityStatus.failed ? ObservabilityLevel.error : ObservabilityLevel.info,
    );
  }
}

final class Observability {
  Observability._();
  static final Loggy _logger = Loggy('observability');
  static final client = ObservabilityClient(
    sink: (payload, level) {
      final message = jsonEncode(payload);
      switch (level) {
        case ObservabilityLevel.debug:
          _logger.debug(message);
        case ObservabilityLevel.info:
          _logger.info(message);
        case ObservabilityLevel.warning:
          _logger.warning(message);
        case ObservabilityLevel.error:
          _logger.error(message);
      }
    },
  );
  static String get sessionId => client.sessionId;
  static void configure(AppInfoEntity info) => client.configure(info);
  static String newOperationId() => const Uuid().v4();
  static void event({
    required ObservabilityModule module,
    required ObservabilityOperation operation,
    required ObservabilityEvent name,
    required ObservabilityStatus status,
    String? operationId,
    ObservabilityErrorCode? errorCode,
    int? durationMs,
    int? count,
    ObservabilityLevel level = ObservabilityLevel.info,
  }) => client.event(
    module: module,
    operation: operation,
    name: name,
    status: status,
    operationId: operationId,
    errorCode: errorCode,
    durationMs: durationMs,
    count: count,
    level: level,
  );
}

/// Revalidates an encoded event at the remote sink; arbitrary JSON is rejected.
Map<String, Object>? safeObservabilityPayload(String? message) {
  if (message == null || message.length > 4096) return null;
  try {
    final decoded = jsonDecode(message);
    if (decoded is! Map<String, dynamic> || decoded['schema_version'] != 1) return null;
    bool member(String key, List<Enum> values) => values.any((v) => _wire(v) == decoded[key]);
    if (!member('module', ObservabilityModule.values) ||
        !member('operation', ObservabilityOperation.values) ||
        !member('event', ObservabilityEvent.values) ||
        !member('status', ObservabilityStatus.values)) {
      return null;
    }
    final result = <String, Object>{'schema_version': 1};
    for (final key in ['module', 'operation', 'event', 'status']) {
      result[key] = decoded[key] as String;
    }
    for (final key in ['session_id', 'operation_id', 'request_id']) {
      final value = decoded[key];
      if (value is String && _uuidPattern.hasMatch(value)) result[key] = value;
    }
    for (final key in ['environment', 'app_version', 'build_number', 'platform']) {
      final value = decoded[key];
      if (value is String) result[key] = _metadata(value);
    }
    if (member('error_code', ObservabilityErrorCode.values)) result['error_code'] = decoded['error_code'] as String;
    if (member('endpoint_class', ApiEndpointClass.values)) {
      result['endpoint_class'] = decoded['endpoint_class'] as String;
    }
    if (member('status_class', ApiStatusClass.values)) result['status_class'] = decoded['status_class'] as String;
    if (decoded['retry_count'] is int) result['retry_count'] = (decoded['retry_count'] as int).clamp(0, 1000);
    for (final key in ['duration_ms', 'count']) {
      final value = decoded[key];
      if (value is int) result[key] = value.clamp(0, key == 'count' ? 1000000 : 86400000);
    }
    return result;
  } catch (_) {
    return null;
  }
}
