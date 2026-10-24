import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_event.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_journal.dart';

/// Carries one existing command attempt through its asynchronous implementation.
/// A zone keeps concurrent commands separate without changing repository APIs.
final class ConnectionDiagnosticScope {
  ConnectionDiagnosticScope(this.journal, this.operation, this.operationId, this.parentOperationId);

  static final _key = Object();
  final SafeDiagnosticJournal journal;
  final DiagnosticOperation operation;
  final int operationId;
  final int? parentOperationId;

  Future<T> run<T>(Future<T> Function() action) => runZoned(action, zoneValues: {_key: this});

  static void record(DiagnosticPhase phase, DiagnosticStage stage, DiagnosticCode code, {int durationMs = 0}) {
    try {
      final scope = Zone.current[_key] as ConnectionDiagnosticScope?;
      if (scope == null) return;
      scope.journal.record(
        operation: scope.operation,
        operationId: scope.operationId,
        parentOperationId: scope.parentOperationId,
        phase: phase,
        stage: stage,
        code: code,
        durationMs: durationMs,
      );
    } on Object {
      // Observation must never change the command or its original failure.
    }
  }

  static TaskEither<L, R> observe<L, R>(
    TaskEither<L, R> task, {
    required DiagnosticPhase phase,
    required DiagnosticCode Function(L failure) failureCode,
  }) => TaskEither(() async {
    record(phase, DiagnosticStage.requested, DiagnosticCode.none);
    final watch = Stopwatch()..start();
    try {
      final result = await task.run();
      try {
        result.match(
          (failure) =>
              record(phase, DiagnosticStage.failed, failureCode(failure), durationMs: watch.elapsedMilliseconds),
          (_) => record(phase, DiagnosticStage.accepted, DiagnosticCode.none, durationMs: watch.elapsedMilliseconds),
        );
      } on Object {
        // A classifier is observation too; preserve the result even if it fails.
      }
      return result;
    } on Object {
      record(phase, DiagnosticStage.failed, DiagnosticCode.unexpected, durationMs: watch.elapsedMilliseconds);
      rethrow;
    }
  });
}
