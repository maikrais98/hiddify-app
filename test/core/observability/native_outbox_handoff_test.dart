import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/observability/better_stack_log_printer.dart';
import 'package:hiddify/core/observability/telemetry_budget.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_event.dart';

const generation = '0123456789abcdef';
SafeDiagnosticEvent event(int sequence) => SafeDiagnosticEvent(
  sequence: sequence,
  operationId: 0,
  operation: DiagnosticOperation.native,
  stage: DiagnosticStage.state,
  code: DiagnosticCode.none,
  nativeStatus: DiagnosticNativeStatus.connected,
);
void main() {
  String? stored;
  var sends = 0;
  BetterStackLogPrinter printer({RemoteOutboxWrite? write, String token = 'test'}) => BetterStackLogPrinter(
    endpoint: Uri.parse('https://s1.betterstackdata.com'),
    sessionId: '123e4567-e89b-42d3-a456-426614174000',
    token: token,
    budget: TelemetryBudget(read: () => null, write: (_) async => true),
    autoFlush: false,
    readOutbox: () => stored,
    writeOutbox: write,
    post: (_, _, _) async {
      sends++;
      return 202;
    },
  );
  Future<DiagnosticEnqueueResult> add(BetterStackLogPrinter p, int n) =>
      p.addImportedDiagnostic(event(n), source: 'extension', generation: generation, sourceSequence: n);
  setUp(() {
    stored = null;
    sends = 0;
  });
  test('failed write never advances cursor; retry and restart after dequeue deduplicate', () async {
    var success = false;
    final p = printer(
      write: (s) async {
        if (success) stored = s;
        return success;
      },
    );
    expect(await add(p, 1), DiagnosticEnqueueResult.storageFailed);
    expect(stored, isNull);
    success = true;
    expect(await add(p, 1), DiagnosticEnqueueResult.persisted);
    final document = jsonDecode(stored!) as Map;
    expect(((document['source_cursors'] as List).single as Map)['sequence'], 1);
    expect((document['events'] as List).length, 1);
    await p.flush();
    expect(sends, 1);
    await p.dispose();
    final restored = printer(
      write: (s) async {
        stored = s;
        return true;
      },
    );
    expect(await add(restored, 1), DiagnosticEnqueueResult.alreadyPersisted);
    await restored.flush();
    expect(sends, 1);
    await restored.dispose();
  });
  test('no writer cannot acknowledge durable handoff; disabled does not write', () async {
    final p = printer();
    expect(await add(p, 1), DiagnosticEnqueueResult.storageFailed);
    await p.flush();
    expect(sends, 0);
    await p.dispose();
    var writes = 0;
    final off = printer(
      token: '',
      write: (_) async {
        writes++;
        return true;
      },
    );
    expect(await add(off, 1), DiagnosticEnqueueResult.disabled);
    expect(writes, 0);
    await off.dispose();
  });
  test('pending persistence cannot send staged event and disable prevents sending', () async {
    final gate = Completer<bool>();
    final p = printer(
      write: (s) async {
        if (!gate.isCompleted) await gate.future;
        stored = s;
        return true;
      },
    );
    final pending = add(p, 1);
    await Future<void>.delayed(Duration.zero);
    final flush = p.flush();
    expect(sends, 0);
    final disposed = p.dispose(clearPending: true);
    gate.complete(true);
    await pending;
    await flush;
    await disposed;
    expect(sends, 0);
  });
  test('OFF-to-ON baseline persists cursor without event and blocks on failure', () async {
    var success = false;
    final p = printer(
      write: (s) async {
        if (success) stored = s;
        return success;
      },
    );
    expect(
      await p.baselineImportedSource(source: 'extension', generation: generation, sourceSequence: 4),
      DiagnosticEnqueueResult.storageFailed,
    );
    success = true;
    expect(
      await p.baselineImportedSource(source: 'extension', generation: generation, sourceSequence: 4),
      DiagnosticEnqueueResult.persisted,
    );
    expect((jsonDecode(stored!) as Map)['events'], isEmpty);
    expect(await add(p, 4), DiagnosticEnqueueResult.alreadyPersisted);
    expect(await add(p, 5), DiagnosticEnqueueResult.persisted);
    await p.dispose();
  });
  test('full queue rejection leaves source cursor available for retry', () async {
    final p = printer(
      write: (s) async {
        stored = s;
        return true;
      },
    );
    for (var n = 1; n <= BetterStackLogPrinter.maxQueueLength; n++) {
      p.addDiagnostic(
        SafeDiagnosticEvent(
          sequence: n,
          operationId: n,
          operation: DiagnosticOperation.connect,
          stage: DiagnosticStage.accepted,
          code: DiagnosticCode.none,
        ),
      );
    }
    expect(await add(p, 1), DiagnosticEnqueueResult.rejected);
    expect((jsonDecode(stored!) as Map).containsKey('source_cursors'), isFalse);
    await p.flush();
    expect(await add(p, 1), DiagnosticEnqueueResult.persisted);
    await p.dispose();
  });
  test('restart before send restores source identity and rejects duplicate import', () async {
    final first = printer(
      write: (s) async {
        stored = s;
        return true;
      },
    );
    expect(await add(first, 1), DiagnosticEnqueueResult.persisted);
    final firstId = (((jsonDecode(stored!) as Map)['events'] as List).single as Map)['event_id'];
    await first.dispose();
    final second = printer(
      write: (s) async {
        stored = s;
        return true;
      },
    );
    expect(await add(second, 1), DiagnosticEnqueueResult.alreadyPersisted);
    expect((((jsonDecode(stored!) as Map)['events'] as List).single as Map)['event_id'], firstId);
    await second.flush();
    expect(sends, 1);
    await second.dispose();
  });
  test('native source identity is independent of local event sequence', () async {
    final p = printer(
      write: (s) async {
        stored = s;
        return true;
      },
    );
    expect(
      await p.addImportedDiagnostic(event(50), source: 'runner', generation: generation, sourceSequence: 1),
      DiagnosticEnqueueResult.persisted,
    );
    expect(
      await p.addImportedDiagnostic(event(51), source: 'runner', generation: generation, sourceSequence: 1),
      DiagnosticEnqueueResult.alreadyPersisted,
    );
    expect((jsonDecode(stored!) as Map)['events'], hasLength(1));
    await p.dispose();
  });

  test('optional schema survives old and new outbox restore', () async {
    final p = printer(
      write: (s) async {
        stored = s;
        return true;
      },
    );
    p.addDiagnostic(
      SafeDiagnosticEvent(
        sequence: 1,
        operationId: 1,
        operation: DiagnosticOperation.subscriptionUpdate,
        stage: DiagnosticStage.accepted,
        code: DiagnosticCode.none,
        phase: DiagnosticPhase.download,
        httpStatus: 200,
      ),
    );
    await p.dispose();
    final restored = printer(
      write: (s) async {
        stored = s;
        return true;
      },
    );
    await restored.flush();
    expect(sends, 1);
    await restored.dispose();
  });
}
