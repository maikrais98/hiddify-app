import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/hiddifycore/core_interface/native_tunnel_failure.dart';

void main() {
  test('parses only closed native fields and preserves operation id', () {
    const canary = 'PRIVATE_CANARY_7d91';
    final failure = NativeTunnelFailure.fromEvent({
      'status': 'Stopped',
      'schema': 1,
      'operation_id': '550e8400-e29b-41d4-a716-446655440000',
      'error_code': 'invalid_configuration',
      'message': 'config=$canary url=https://user:$canary@example.invalid',
    });

    expect(failure, isNotNull);
    expect(failure!.operationId, '550e8400-e29b-41d4-a716-446655440000');
    expect(failure.code, NativeTunnelFailureCode.invalidConfiguration);
    expect(failure.failure, isA<InvalidConfig>());
    expect((failure.failure as InvalidConfig).message, isNot(contains(canary)));
    expect((failure.failure as InvalidConfig).message, isNot(contains('https://')));
  });

  test('maps every allowlisted native code to a typed safe failure', () {
    final expected = <String, Matcher>{
      'invalid_configuration': isA<InvalidConfig>(),
      'tunnel_start_failed': isA<BackgroundCoreNotAvailable>(),
      'permission_denied': isA<MissingVpnPermission>(),
      'network_unavailable': isA<BackgroundCoreNotAvailable>(),
      'connection_timeout': isA<BackgroundCoreNotAvailable>(),
      'unknown_safe': isA<BackgroundCoreNotAvailable>(),
    };

    for (final entry in expected.entries) {
      final failure = NativeTunnelFailure.fromEvent({
        'status': 'Stopped',
        'schema': 1,
        'operation_id': '550e8400-e29b-41d4-a716-446655440000',
        'error_code': entry.key,
      });
      expect(failure, isNotNull, reason: entry.key);
      expect(failure!.failure, entry.value, reason: entry.key);
    }
  });

  test('rejects malformed payloads without reading raw values', () {
    expect(
      NativeTunnelFailure.fromEvent({
        'status': 'Stopped',
        'schema': 99,
        'operation_id': '550e8400-e29b-41d4-a716-446655440000',
        'error_code': 'invalid_configuration',
      }),
      isNull,
    );
    expect(
      NativeTunnelFailure.fromEvent({
        'status': 'Stopped',
        'schema': 1,
        'operation_id': '550e8400-e29b-11d4-a716-446655440000',
        'error_code': 'not-allowlisted',
      }),
      isNull,
    );
    expect(
      NativeTunnelFailure.fromEvent({
        'status': 'Stopped',
        'schema': 1,
        'operation_id': 'https://private.invalid',
        'error_code': 'invalid_configuration',
      }),
      isNull,
    );
  });

  test('accepts a native failure only for the active connection operation', () {
    final failure = NativeTunnelFailure.fromEvent({
      'status': 'Stopped',
      'schema': 1,
      'operation_id': '550e8400-e29b-41d4-a716-446655440000',
      'error_code': 'tunnel_start_failed',
    });

    expect(failure, isNotNull);
    expect(failure!.belongsTo('550e8400-e29b-41d4-a716-446655440000'), isTrue);
    expect(failure.belongsTo('550e8400-e29b-41d4-a716-446655440001'), isFalse);
    expect(failure.belongsTo(null), isFalse);
  });
}
