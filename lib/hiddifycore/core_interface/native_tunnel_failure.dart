import 'package:hiddify/features/connection/model/connection_failure.dart';

enum NativeTunnelFailureCode {
  invalidConfiguration('invalid_configuration'),
  tunnelStartFailed('tunnel_start_failed'),
  permissionDenied('permission_denied'),
  networkUnavailable('network_unavailable'),
  connectionTimeout('connection_timeout'),
  unknownSafe('unknown_safe');

  const NativeTunnelFailureCode(this.value);

  final String value;

  static NativeTunnelFailureCode? fromValue(String value) => switch (value) {
    'invalid_configuration' => invalidConfiguration,
    'tunnel_start_failed' => tunnelStartFailed,
    'permission_denied' => permissionDenied,
    'network_unavailable' => networkUnavailable,
    'connection_timeout' => connectionTimeout,
    'unknown_safe' => unknownSafe,
    _ => null,
  };
}

/// Closed native failure data. The parser intentionally ignores all fields
/// except the schema, operation ID and allowlisted error code.
final class NativeTunnelFailure {
  NativeTunnelFailure({required this.operationId, required this.code});

  static final _safeOperationId = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  final String operationId;
  final NativeTunnelFailureCode code;

  String get safeMessage => switch (code) {
    NativeTunnelFailureCode.invalidConfiguration => 'VPN configuration is invalid.',
    NativeTunnelFailureCode.tunnelStartFailed => 'Packet tunnel failed to start.',
    NativeTunnelFailureCode.permissionDenied => 'VPN permission is required.',
    NativeTunnelFailureCode.networkUnavailable => 'Packet tunnel network failed.',
    NativeTunnelFailureCode.connectionTimeout => 'Packet tunnel start timed out.',
    NativeTunnelFailureCode.unknownSafe => 'Packet tunnel failed.',
  };

  static NativeTunnelFailure? fromEvent(Object? value) {
    if (value is! Map || value['status'] != 'Stopped' || value['schema'] != 1) return null;

    final operationId = value['operation_id'];
    final errorCode = value['error_code'];
    if (operationId is! String || !_safeOperationId.hasMatch(operationId)) return null;
    if (errorCode is! String || errorCode.isEmpty) return null;
    final code = NativeTunnelFailureCode.fromValue(errorCode);
    if (code == null) return null;

    return NativeTunnelFailure(operationId: operationId, code: code);
  }

  ConnectionFailure get failure => switch (code) {
    NativeTunnelFailureCode.invalidConfiguration => const ConnectionFailure.invalidConfig(
      'VPN configuration is invalid.',
    ),
    NativeTunnelFailureCode.tunnelStartFailed => const ConnectionFailure.backgroundCoreNotAvailable(
      'Packet tunnel failed to start.',
    ),
    NativeTunnelFailureCode.permissionDenied => const ConnectionFailure.missingVpnPermission(),
    NativeTunnelFailureCode.networkUnavailable => const ConnectionFailure.backgroundCoreNotAvailable(
      'Packet tunnel network failed.',
    ),
    NativeTunnelFailureCode.connectionTimeout => const ConnectionFailure.backgroundCoreNotAvailable(
      'Packet tunnel start timed out.',
    ),
    NativeTunnelFailureCode.unknownSafe => const ConnectionFailure.backgroundCoreNotAvailable('Packet tunnel failed.'),
  };
}
