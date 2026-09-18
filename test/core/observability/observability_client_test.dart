import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/model/app_info_entity.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/observability/observability.dart';

void main() {
  test('operation has one terminal result, correlation and bounded duration', () {
    final events = <Map<String, Object>>[];
    final client = ObservabilityClient(sink: (payload, level) => events.add(payload));
    final operation = client.startOperation(module: ObservabilityModule.vpn, operation: ObservabilityOperation.connect);
    operation.success();
    operation.failure(ObservabilityErrorCode.unexpectedConnectionFailure);
    expect(events.length, 2);
    expect(events.last['operation_id'], events.first['operation_id']);
    expect(events.last['status'], 'succeeded');
    expect(events.last['duration_ms'], isNonNegative);
    expect(events.last['schema_version'], 1);
  });
  test('failure, cancellation and manual test emit only closed fields', () {
    final events = <Map<String, Object>>[];
    final client = ObservabilityClient(sink: (payload, level) => events.add(payload));
    expect(events, isEmpty);
    client
        .startOperation(module: ObservabilityModule.vpn, operation: ObservabilityOperation.connect)
        .failure(ObservabilityErrorCode.vpnPermissionDenied);
    client.startOperation(module: ObservabilityModule.vpn, operation: ObservabilityOperation.disconnect).cancel();
    client.captureException(
      module: ObservabilityModule.app,
      operation: ObservabilityOperation.initialize,
      errorCode: ObservabilityErrorCode.unexpectedConnectionFailure,
    );
    client.sendTestEvent();
    expect(events.map((e) => e['status']), containsAll(['failed', 'cancelled']));
    expect(events.last['event'], 'test_event');
    expect(events.every((e) => !e.containsKey('exception') && !e.containsKey('stack_trace')), isTrue);
  });

  test('diagnostic snapshot bounds storage and exposes immutable newest safe events', () {
    final client = ObservabilityClient(sink: (_, _) {});
    client.configure(
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
    for (var index = 0; index < 55; index++) {
      client.event(
        module: ObservabilityModule.api,
        operation: ObservabilityOperation.request,
        name: ObservabilityEvent.apiRequestCompleted,
        status: index == 54 ? ObservabilityStatus.failed : ObservabilityStatus.succeeded,
        operationId: '12345678-1234-4234-8234-${index.toString().padLeft(12, '0')}',
        requestId: '87654321-4321-4321-8321-${index.toString().padLeft(12, '0')}',
        errorCode: index == 54 ? ObservabilityErrorCode.networkUnavailable : null,
        count: index,
      );
    }

    final snapshot = client.diagnosticSnapshot;

    expect(client.bufferedEventCount, 50);
    expect(snapshot.appVersion, '4.1.3');
    expect(snapshot.buildNumber, '40103');
    expect(snapshot.environment, 'prod');
    expect(snapshot.platform, 'ios');
    expect(snapshot.latestErrorCode, 'network_unavailable');
    expect(snapshot.recentEvents, hasLength(20));
    expect(snapshot.recentEvents.first['count'], 35);
    expect(snapshot.recentEvents.last['count'], 54);
    expect(
      snapshot.recentEvents.every(
        (event) =>
            !event.containsKey('session_id') &&
            !event.containsKey('operation_id') &&
            !event.containsKey('request_id') &&
            !event.containsKey('error_message') &&
            !event.containsKey('stack_trace'),
      ),
      isTrue,
    );
    expect(() => snapshot.recentEvents.add({}), throwsUnsupportedError);
    expect(() => snapshot.recentEvents.first['event'] = 'changed', throwsUnsupportedError);
  });

  test('normal session caps ordinary info while lifecycle and errors remain unsampled', () {
    final events = <Map<String, Object>>[];
    final client = ObservabilityClient(sink: (payload, _) => events.add(payload));

    for (var index = 0; index < 60; index++) {
      client.event(
        module: ObservabilityModule.app,
        operation: ObservabilityOperation.initialize,
        name: ObservabilityEvent.vpnConnectionStateChanged,
        status: ObservabilityStatus.observed,
      );
    }
    final operation = client.startOperation(module: ObservabilityModule.vpn, operation: ObservabilityOperation.connect);
    operation.success();
    client.captureException(
      module: ObservabilityModule.app,
      operation: ObservabilityOperation.initialize,
      errorCode: ObservabilityErrorCode.unknownSafe,
    );

    expect(events, hasLength(53));
    expect(events[50]['event'], 'operation_started');
    expect(events[51]['event'], 'operation_succeeded');
    expect(events[51]['duration_ms'], isNonNegative);
    expect(events.last['status'], 'failed');
  });
}
