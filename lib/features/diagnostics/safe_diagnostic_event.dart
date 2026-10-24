import 'package:hiddify/features/connection/model/connection_failure.dart';

enum DiagnosticOperation {
  setup,
  connect,
  reconnect,
  disconnect,
  tunnel,
  subscriptionImport,
  subscriptionUpdate,
  native,
}

enum DiagnosticStage { requested, accepted, failed, state, skipped }

enum DiagnosticCode {
  unknown,
  cancelled,
  partialFailure,
  storageFailure,
  overflow,
  unsupported,
  noError,
  noProfile,
  stale,
  notConnected,
  busy,
  none,
  unexpected,
  vpnPermissionDenied,
  notificationPermissionDenied,
  privilegeRequired,
  invalidConfigOption,
  invalidConfig,
  coreUnavailable,
  warpLicenseRequired,
  starting,
  started,
  stopping,
  stopped,
}

DiagnosticCode diagnosticCodeForFailure(ConnectionFailure failure) => switch (failure) {
  UnexpectedConnectionFailure() => DiagnosticCode.unexpected,
  MissingVpnPermission() => DiagnosticCode.vpnPermissionDenied,
  MissingNotificationPermission() => DiagnosticCode.notificationPermissionDenied,
  MissingPrivilege() => DiagnosticCode.privilegeRequired,
  InvalidConfigOption() => DiagnosticCode.invalidConfigOption,
  InvalidConfig() => DiagnosticCode.invalidConfig,
  BackgroundCoreNotAvailable() => DiagnosticCode.coreUnavailable,
  MissingWarpLicense() => DiagnosticCode.warpLicenseRequired,
};

enum DiagnosticPhase {
  action,
  download,
  nestedDownload,
  metadataParse,
  changeOptions,
  validateAndCommitConfig,
  dbPersist,
  reconnectDecision,
  reconnectResult,
  foregroundReady,
  optionsReady,
  backgroundStart,
  preferencesLoad,
  preferencesSave,
  preferencesReload,
  networkSettings,
  tunDescriptor,
  sleep,
  wake,
  lastDisconnectError,
}

enum DiagnosticTrigger { manual, automatic, importAction }

enum DiagnosticHttpOutcome {
  success,
  connectionTimeout,
  sendTimeout,
  receiveTimeout,
  badCertificate,
  badResponse,
  cancel,
  connectionError,
  unknown,
}

enum DiagnosticHttpMode { direct, proxy, both }

enum DiagnosticNativeStatus { invalid, disconnected, connecting, connected, reasserting, disconnecting, unknown }

enum DiagnosticErrorDomain { neVpn, neProvider, posix, url, cocoa, unknown }

final class SafeDiagnosticEvent {
  SafeDiagnosticEvent({
    required this.sequence,
    required this.operationId,
    required this.operation,
    required this.stage,
    required this.code,
    int durationMs = 0,
    this.phase,
    this.trigger,
    this.parentOperationId,
    this.httpOutcome,
    this.httpStatus,
    this.selectedMode,
    this.retryCount,
    this.nestedTotal,
    this.nestedFailed,
    this.nativeStatus,
    this.errorDomain,
    this.errorCode,
    this.stopReason,
  }) : durationMs = durationMs.clamp(0, maxDurationMs) {
    _validateOptional(toJson());
    if (sequence <= 0 || sequence > maxCounter) {
      throw RangeError.range(sequence, 1, maxCounter, 'sequence');
    }
    if (operationId < 0 || operationId > maxCounter || !_validOperationId(operationId, operation, stage)) {
      throw RangeError.range(operationId, 0, maxCounter, 'operationId');
    }
  }

  static const int maxDurationMs = 3600000;
  static const int maxCounter = 9007199254740991;
  static const Set<String> _keys = {
    'sequence',
    'operation_id',
    'operation',
    'stage',
    'code',
    'duration_ms',
    'reachability',
  };

  static const optionalKeys = <String>{
    'phase',
    'trigger',
    'parent_operation_id',
    'http_outcome',
    'http_status',
    'selected_mode',
    'retry_count',
    'nested_total',
    'nested_failed',
    'native_status',
    'error_domain',
    'error_code',
    'stop_reason',
  };

  final DiagnosticPhase? phase;
  final DiagnosticTrigger? trigger;
  final int? parentOperationId;
  final DiagnosticHttpOutcome? httpOutcome;
  final int? httpStatus;
  final DiagnosticHttpMode? selectedMode;
  final int? retryCount;
  final int? nestedTotal;
  final int? nestedFailed;
  final DiagnosticNativeStatus? nativeStatus;
  final DiagnosticErrorDomain? errorDomain;
  final int? errorCode;
  final int? stopReason;

  final int sequence;
  final int operationId;
  final DiagnosticOperation operation;
  final DiagnosticStage stage;
  final DiagnosticCode code;
  final int durationMs;

  Map<String, Object> toJson() => {
    'sequence': sequence,
    'operation_id': operationId,
    'operation': operation.name,
    'stage': stage.name,
    'code': code.name,
    'duration_ms': durationMs,
    'reachability': 'not_checked',
    if (phase != null) 'phase': phase!.name,
    if (trigger != null) 'trigger': trigger!.name,
    if (parentOperationId != null) 'parent_operation_id': parentOperationId!,
    if (httpOutcome != null) 'http_outcome': httpOutcome!.name,
    if (httpStatus != null) 'http_status': httpStatus!,
    if (selectedMode != null) 'selected_mode': selectedMode!.name,
    if (retryCount != null) 'retry_count': retryCount!,
    if (nestedTotal != null) 'nested_total': nestedTotal!,
    if (nestedFailed != null) 'nested_failed': nestedFailed!,
    if (nativeStatus != null) 'native_status': nativeStatus!.name,
    if (errorDomain != null) 'error_domain': errorDomain!.name,
    if (errorCode != null) 'error_code': errorCode!,
    if (stopReason != null) 'stop_reason': stopReason!,
  };

  factory SafeDiagnosticEvent.fromJson(Map<String, Object?> json) {
    if (!_keys.every(json.containsKey) || json.keys.any((key) => !_keys.contains(key) && !optionalKeys.contains(key))) {
      throw const FormatException('invalid diagnostic event fields');
    }
    _validateOptional(json);
    final sequence = json['sequence'];
    final operationId = json['operation_id'];
    final operation = json['operation'];
    final stage = json['stage'];
    final code = json['code'];
    final durationMs = json['duration_ms'];
    if (sequence is! int ||
        sequence <= 0 ||
        sequence > maxCounter ||
        operationId is! int ||
        operationId < 0 ||
        operationId > maxCounter ||
        operation is! String ||
        stage is! String ||
        code is! String ||
        durationMs is! int ||
        durationMs < 0 ||
        durationMs > maxDurationMs ||
        json['reachability'] != 'not_checked') {
      throw const FormatException('invalid diagnostic event value');
    }
    final parsedOperation = _enumByName(DiagnosticOperation.values, operation);
    final parsedStage = _enumByName(DiagnosticStage.values, stage);
    final parsedCode = _enumByName(DiagnosticCode.values, code);
    if (parsedOperation == null || parsedStage == null || parsedCode == null) {
      throw const FormatException('unknown diagnostic event value');
    }
    if (!_validOperationId(operationId, parsedOperation, parsedStage)) {
      throw const FormatException('invalid diagnostic operation id');
    }
    return SafeDiagnosticEvent(
      sequence: sequence,
      operationId: operationId,
      operation: parsedOperation,
      stage: parsedStage,
      code: parsedCode,
      durationMs: durationMs,
      phase: json.containsKey('phase') ? _enumByName(DiagnosticPhase.values, json['phase'] as String?) : null,
      trigger: json.containsKey('trigger') ? _enumByName(DiagnosticTrigger.values, json['trigger'] as String?) : null,
      parentOperationId: json['parent_operation_id'] as int?,
      httpOutcome: json.containsKey('http_outcome')
          ? _enumByName(DiagnosticHttpOutcome.values, json['http_outcome'] as String?)
          : null,
      httpStatus: json['http_status'] as int?,
      selectedMode: json.containsKey('selected_mode')
          ? _enumByName(DiagnosticHttpMode.values, json['selected_mode'] as String?)
          : null,
      retryCount: json['retry_count'] as int?,
      nestedTotal: json['nested_total'] as int?,
      nestedFailed: json['nested_failed'] as int?,
      nativeStatus: json.containsKey('native_status')
          ? _enumByName(DiagnosticNativeStatus.values, json['native_status'] as String?)
          : null,
      errorDomain: json.containsKey('error_domain')
          ? _enumByName(DiagnosticErrorDomain.values, json['error_domain'] as String?)
          : null,
      errorCode: json['error_code'] as int?,
      stopReason: json['stop_reason'] as int?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SafeDiagnosticEvent &&
          sequence == other.sequence &&
          operationId == other.operationId &&
          operation == other.operation &&
          stage == other.stage &&
          code == other.code &&
          durationMs == other.durationMs &&
          phase == other.phase &&
          trigger == other.trigger &&
          parentOperationId == other.parentOperationId &&
          httpOutcome == other.httpOutcome &&
          httpStatus == other.httpStatus &&
          selectedMode == other.selectedMode &&
          retryCount == other.retryCount &&
          nestedTotal == other.nestedTotal &&
          nestedFailed == other.nestedFailed &&
          nativeStatus == other.nativeStatus &&
          errorDomain == other.errorDomain &&
          errorCode == other.errorCode &&
          stopReason == other.stopReason;

  @override
  int get hashCode => Object.hashAll([
    sequence,
    operationId,
    operation,
    stage,
    code,
    durationMs,
    phase,
    trigger,
    parentOperationId,
    httpOutcome,
    httpStatus,
    selectedMode,
    retryCount,
    nestedTotal,
    nestedFailed,
    nativeStatus,
    errorDomain,
    errorCode,
    stopReason,
  ]);
}

bool _validOperationId(int operationId, DiagnosticOperation operation, DiagnosticStage stage) =>
    operationId > 0 ||
    operation == DiagnosticOperation.native ||
    operation == DiagnosticOperation.tunnel && stage == DiagnosticStage.state;

T? _enumByName<T extends Enum>(List<T> values, String? name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

void _validateOptional(Map<String, Object?> json) {
  if (json.containsKey('phase')) {
    final value = json['phase'];
    if (value is! String || _enumByName(DiagnosticPhase.values, value) == null) {
      throw const FormatException('invalid diagnostic phase');
    }
  }
  if (json.containsKey('trigger')) {
    final value = json['trigger'];
    if (value is! String || _enumByName(DiagnosticTrigger.values, value) == null) {
      throw const FormatException('invalid diagnostic trigger');
    }
  }
  if (json.containsKey('parent_operation_id')) {
    final value = json['parent_operation_id'];
    if (value is! int || value < 1 || value > SafeDiagnosticEvent.maxCounter) {
      throw const FormatException('invalid diagnostic parent_operation_id');
    }
  }
  if (json.containsKey('http_outcome')) {
    final value = json['http_outcome'];
    if (value is! String || _enumByName(DiagnosticHttpOutcome.values, value) == null) {
      throw const FormatException('invalid diagnostic http_outcome');
    }
  }
  if (json.containsKey('http_status')) {
    final value = json['http_status'];
    if (value is! int || value < 100 || value > 599) throw const FormatException('invalid diagnostic http_status');
  }
  if (json.containsKey('selected_mode')) {
    final value = json['selected_mode'];
    if (value is! String || _enumByName(DiagnosticHttpMode.values, value) == null) {
      throw const FormatException('invalid diagnostic selected_mode');
    }
  }
  if (json.containsKey('retry_count')) {
    final value = json['retry_count'];
    if (value is! int || value < 0 || value > 3) throw const FormatException('invalid diagnostic retry_count');
  }
  if (json.containsKey('nested_total')) {
    final value = json['nested_total'];
    if (value is! int || value < 0 || value > 65535) throw const FormatException('invalid diagnostic nested_total');
  }
  if (json.containsKey('nested_failed')) {
    final value = json['nested_failed'];
    if (value is! int || value < 0 || value > 65535) throw const FormatException('invalid diagnostic nested_failed');
  }
  if (json.containsKey('native_status')) {
    final value = json['native_status'];
    if (value is! String || _enumByName(DiagnosticNativeStatus.values, value) == null) {
      throw const FormatException('invalid diagnostic native_status');
    }
  }
  if (json.containsKey('error_domain')) {
    final value = json['error_domain'];
    if (value is! String || _enumByName(DiagnosticErrorDomain.values, value) == null) {
      throw const FormatException('invalid diagnostic error_domain');
    }
  }
  if (json.containsKey('error_code')) {
    final value = json['error_code'];
    if (value is! int || value < -2147483648 || value > 2147483647) {
      throw const FormatException('invalid diagnostic error_code');
    }
  }
  if (json.containsKey('stop_reason')) {
    final value = json['stop_reason'];
    if (value is! int || value < 0 || value > 255) throw const FormatException('invalid diagnostic stop_reason');
  }
  if (json.containsKey('error_code') && (!json.containsKey('error_domain') || json['error_domain'] == 'unknown')) {
    throw const FormatException('untyped native error');
  }
  final nestedTotal = json['nested_total'];
  final nestedFailed = json['nested_failed'];
  if (nestedTotal is int && nestedFailed is int && nestedFailed > nestedTotal) {
    throw const FormatException('invalid nested aggregate');
  }
}
