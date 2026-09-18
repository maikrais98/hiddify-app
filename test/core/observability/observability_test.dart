import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/model/app_info_entity.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/observability/observability.dart';
import 'package:loggy/loggy.dart';

void main() {
  test('emits structured build and operation context without error text', () {
    final printer = _RecordPrinter();
    Loggy.initLoggy(logPrinter: printer);
    addTearDown(() => Loggy.initLoggy());
    Observability.configure(
      const AppInfoEntity(
        name: 'Woman in Red',
        version: '4.1.3',
        buildNumber: '40103',
        release: Release.general,
        operatingSystem: 'ios',
        operatingSystemVersion: '27.0',
        environment: Environment.prod,
      ),
    );

    Observability.event(
      module: ObservabilityModule.vpn,
      operation: ObservabilityOperation.connect,
      name: ObservabilityEvent.vpnConnectionFailed,
      status: ObservabilityStatus.failed,
      operationId: '12345678-1234-4234-8234-123456789abc',
      durationMs: 1200,
      errorCode: ObservabilityErrorCode.vpnPermissionDenied,
      level: ObservabilityLevel.error,
    );

    final payload = jsonDecode(printer.lastMessage) as Map<String, dynamic>;
    expect(payload['schema_version'], 1);
    expect(payload['environment'], 'prod');
    expect(payload['app_version'], '4.1.3');
    expect(payload['build_number'], '40103');
    expect(payload['platform'], 'ios');
    expect(payload['event'], 'vpn_connection_failed');
    expect(payload['operation_id'], '12345678-1234-4234-8234-123456789abc');
    expect(payload['duration_ms'], 1200);
    expect(payload['error_code'], 'vpn_permission_denied');
    expect(payload, isNot(contains('error_message')));
    expect(payload, isNot(contains('stack_trace')));
  });
}

final class _RecordPrinter extends LoggyPrinter {
  String lastMessage = '';

  @override
  void onLog(LogRecord record) => lastMessage = record.message;
}
