import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_event.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_journal.dart';

void main() {
  test('bounded journal overflow is explicit and survives restart', () {
    final journal = SafeDiagnosticJournal(capacity: 1);
    for (var n = 1; n <= 3; n++) {
      journal.record(
        operation: DiagnosticOperation.connect,
        stage: DiagnosticStage.requested,
        code: DiagnosticCode.none,
        operationId: n,
      );
    }
    expect(journal.droppedCount, 2);
    final restored = SafeDiagnosticJournal(restored: journal.exportJson());
    expect(restored.droppedCount, 2);
    expect(restored.events.length, 1);
  });

  test('no-profile skip has a closed code', () {
    final raw = SafeDiagnosticEvent(sequence: 1, operationId: 1, operation: DiagnosticOperation.connect, stage: DiagnosticStage.skipped, code: DiagnosticCode.none).toJson();
    expect(SafeDiagnosticEvent.fromJson({...raw, 'code': 'noProfile'}).toJson()['code'], 'noProfile');
  });

  test('foreground readiness has a separate closed phase', () {
    final raw = SafeDiagnosticEvent(
      sequence: 1,
      operationId: 1,
      operation: DiagnosticOperation.connect,
      stage: DiagnosticStage.accepted,
      code: DiagnosticCode.none,
    ).toJson();
    expect(SafeDiagnosticEvent.fromJson({...raw, 'phase': 'foregroundReady'}).toJson()['phase'], 'foregroundReady');
  });
  test('optional typed subscription attributes survive journal restore', () {
    final journal = SafeDiagnosticJournal();
    journal.record(
      operation: DiagnosticOperation.subscriptionUpdate,
      stage: DiagnosticStage.accepted,
      code: DiagnosticCode.none,
      operationId: 1,
      phase: DiagnosticPhase.download,
      trigger: DiagnosticTrigger.manual,
      httpOutcome: DiagnosticHttpOutcome.success,
      httpStatus: 200,
      selectedMode: DiagnosticHttpMode.both,
      retryCount: 2,
      nestedTotal: 3,
      nestedFailed: 1,
      parentOperationId: 2,
    );
    final restored = SafeDiagnosticJournal(restored: journal.exportJson());
    expect(restored.events, journal.events);
    expect(restored.events.single.httpStatus, 200);
    expect(restored.events.single.selectedMode, DiagnosticHttpMode.both);
  });

  test('native autonomous observations retain typed status/error only', () {
    final event = SafeDiagnosticEvent(
      sequence: 1,
      operationId: 0,
      operation: DiagnosticOperation.native,
      stage: DiagnosticStage.state,
      code: DiagnosticCode.none,
      nativeStatus: DiagnosticNativeStatus.reasserting,
      errorDomain: DiagnosticErrorDomain.posix,
      errorCode: 54,
      stopReason: 1,
    );
    expect(SafeDiagnosticEvent.fromJson(event.toJson()), event);
    for (final patch in <Map<String, Object?>>[
      {'error_domain': 'private.example.invalid'},
      {'error_domain': 'unknown'},
      {'error_code': 2147483648},
      {'http_status': 99},
      {'retry_count': 4},
      {'parent_operation_id': 0},
      {'phase': 'secret-token'},
      {'stop_reason': -1},
      {'nested_total': 1, 'nested_failed': 2},
      {'url': 'vless://secret'},
      {'http_status': null},
    ]) {
      expect(() => SafeDiagnosticEvent.fromJson({...event.toJson(), ...patch}), throwsFormatException);
    }
  });
}
