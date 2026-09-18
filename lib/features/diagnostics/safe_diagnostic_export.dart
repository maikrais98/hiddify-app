import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:hiddify/core/observability/observability.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_summary.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

enum DiagnosticExportResult { shared, dismissed, unavailable, failed }

/// Exceptions and share-platform responses may contain paths or private data.
/// Never log, retain, or display them; expose only closed result codes.
final class SafeDiagnosticExport {
  SafeDiagnosticExport({Future<Directory> Function()? temporaryDirectory, ObservabilityClient? observabilityClient})
    : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
      _observabilityClient = observabilityClient ?? Observability.client;

  static const fileName = 'safe-diagnostics.json';
  final Future<Directory> Function() _temporaryDirectory;
  final ObservabilityClient _observabilityClient;
  Directory? _directory;
  File? _file;
  Future<void>? _pending;

  bool get hasFile => _file != null;

  // Queue ownership changes before any await. A discard waits for earlier
  // creates/shares, so no in-flight operation can publish an orphan afterwards.
  Future<T> _exclusive<T>(Future<T> Function() action) async {
    final previous = _pending;
    final complete = Completer<void>();
    _pending = complete.future;
    if (previous != null) await previous;
    try {
      return await action();
    } finally {
      complete.complete();
    }
  }

  Future<bool> create(SafeDiagnosticSummary summary) => _exclusive(() => _create(summary));

  Future<bool> _create(SafeDiagnosticSummary summary) async {
    if (_file != null) return true;
    try {
      final root = await _temporaryDirectory();
      _directory = await root.createTemp('safe-diagnostics-');
      final file = File('${_directory!.path}/$fileName');
      await file.writeAsString(summary.json, flush: true);
      _file = file;
      _observe(ObservabilityEvent.diagnosticFileCreated, ObservabilityStatus.succeeded);
      return true;
    } catch (_) {
      await _discard(emitEvent: false);
      _observe(ObservabilityEvent.diagnosticFileCreated, ObservabilityStatus.failed, ObservabilityErrorCode.ioFailure);
      return false;
    }
  }

  Future<DiagnosticExportResult> share(Rect origin) => _exclusive(() => _share(origin));

  Future<DiagnosticExportResult> _share(Rect origin) async {
    final file = _file;
    if (file == null) {
      _observe(
        ObservabilityEvent.diagnosticFileShareCompleted,
        ObservabilityStatus.failed,
        ObservabilityErrorCode.unknownSafe,
      );
      return DiagnosticExportResult.unavailable;
    }
    try {
      final result = await Share.shareXFiles([
        XFile(file.path, mimeType: 'application/json'),
      ], sharePositionOrigin: origin);
      final exportResult = switch (result.status) {
        ShareResultStatus.success => DiagnosticExportResult.shared,
        ShareResultStatus.dismissed => DiagnosticExportResult.dismissed,
        ShareResultStatus.unavailable => DiagnosticExportResult.unavailable,
      };
      _observe(
        ObservabilityEvent.diagnosticFileShareCompleted,
        switch (exportResult) {
          DiagnosticExportResult.shared => ObservabilityStatus.succeeded,
          DiagnosticExportResult.dismissed => ObservabilityStatus.cancelled,
          DiagnosticExportResult.unavailable || DiagnosticExportResult.failed => ObservabilityStatus.failed,
        },
        exportResult == DiagnosticExportResult.unavailable ? ObservabilityErrorCode.unknownSafe : null,
      );
      return exportResult;
    } catch (_) {
      _observe(
        ObservabilityEvent.diagnosticFileShareCompleted,
        ObservabilityStatus.failed,
        ObservabilityErrorCode.unknownSafe,
      );
      return DiagnosticExportResult.failed;
    }
  }

  Future<void> discard() => _exclusive(() => _discard(emitEvent: true));

  Future<void> _discard({required bool emitEvent}) async {
    final directory = _directory;
    final hadOwnedCopy = directory != null || _file != null;
    _file = null;
    _directory = null;
    var failed = false;
    try {
      if (directory != null && await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {
      failed = true;
      // The OS temporary-directory lifecycle is the fallback. No path logging.
    }
    if (emitEvent && hadOwnedCopy) {
      _observe(
        ObservabilityEvent.diagnosticFileDiscarded,
        failed ? ObservabilityStatus.failed : ObservabilityStatus.succeeded,
        failed ? ObservabilityErrorCode.ioFailure : null,
      );
    }
  }

  void _observe(ObservabilityEvent event, ObservabilityStatus status, [ObservabilityErrorCode? errorCode]) {
    _observabilityClient.event(
      module: ObservabilityModule.app,
      operation: ObservabilityOperation.diagnosticExport,
      name: event,
      status: status,
      errorCode: errorCode,
      level: status == ObservabilityStatus.failed ? ObservabilityLevel.warning : ObservabilityLevel.info,
    );
  }
}
