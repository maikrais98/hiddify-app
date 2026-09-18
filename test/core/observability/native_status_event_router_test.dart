import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/hiddifycore/core_interface/native_status_event_router.dart';
import 'package:hiddify/hiddifycore/core_interface/native_tunnel_failure.dart';
import 'package:hiddify/singbox/model/core_status.dart';

void main() {
  test('routes only the active operation native failure exactly once', () async {
    const staleOperationId = '550e8400-e29b-41d4-a716-446655440000';
    const activeOperationId = '550e8400-e29b-41d4-a716-446655440001';
    final failures = <NativeTunnelFailure>[];

    final statuses = await routeNativeStatusEvents(
      Stream<dynamic>.fromIterable([
        {'status': 'Stopped', 'schema': 1, 'operation_id': staleOperationId, 'error_code': 'tunnel_start_failed'},
        {'status': 'Starting'},
        {'status': 'Stopped', 'schema': 1, 'operation_id': activeOperationId, 'error_code': 'network_unavailable'},
      ]),
      activeOperationId: () => activeOperationId,
      onFailure: failures.add,
    ).toList();

    expect(statuses, hasLength(2));
    expect(statuses.first, isA<CoreStarting>());
    expect(statuses.last, isA<CoreStopped>());
    expect(failures, hasLength(1));
    expect(failures.single.operationId, activeOperationId);
    expect(failures.single.code, NativeTunnelFailureCode.networkUnavailable);
  });
}
