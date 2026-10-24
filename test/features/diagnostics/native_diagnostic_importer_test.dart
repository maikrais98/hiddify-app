import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/observability/better_stack_log_printer.dart';
import 'package:hiddify/core/observability/telemetry_budget.dart';
import 'package:hiddify/features/diagnostics/native_diagnostic_importer.dart';
import 'package:hiddify/features/diagnostics/remote_diagnostic_subscription.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_event.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_journal.dart';

Map<String, Object> snapshot(int last, {bool corrupt = false}) => {
  'version': 1,
  'sources': [
    {
      'source': 'extension',
      'generation': '0123456789abcdef',
      'first_sequence': 1,
      'last_sequence': last,
      'dropped_count': 0,
      'storage_failed': false,
      'records': [
        for (var n = 1; n <= last; n++)
          {
            'source_sequence': n,
            'event': {
              ...SafeDiagnosticEvent(
                sequence: n,
                operationId: 0,
                operation: DiagnosticOperation.native,
                stage: DiagnosticStage.state,
                code: DiagnosticCode.none,
                nativeStatus: DiagnosticNativeStatus.connected,
              ).toJson(),
              if (corrupt) 'url': 'vless://secret-token',
            },
          },
      ],
    },
  ],
};
void main() {
  test('capture rejects an incomplete two-source consent boundary', () async {
    final journal = SafeDiagnosticJournal();
    final importer = NativeDiagnosticImporter(journal: journal, read: () async => snapshot(1));
    await expectLater(importer.captureBaseline(), throwsStateError);
    importer.dispose();
    journal.dispose();
  });

  for (final crashAfterFirstSource in [true, false]) {
    for (final rotate in [false, true]) {
      test('restart resumes frozen boundary partial=$crashAfterFirstSource rotate=$rotate', () async {
        String? stored;
        String? frozen;
        var writes = 0;
        var crash = true;
        var raw = snapshot(2);
        final runner = Map<String, Object>.from((raw['sources']! as List).single as Map)..['source'] = 'runner';
        (raw['sources']! as List).insert(0, runner);
        BetterStackLogPrinter remote() => BetterStackLogPrinter(
          endpoint: Uri.parse('https://s1.betterstackdata.com'),
          sessionId: '123e4567-e89b-42d3-a456-426614174000',
          token: 'test',
          budget: TelemetryBudget(read: () => null, write: (_) async => true),
          autoFlush: false,
          readOutbox: () => stored,
          writeOutbox: (value) async {
            writes++;
            if (crash && crashAfterFirstSource && writes > 1) return false;
            stored = value;
            return true;
          },
        );
        final firstRemote = remote();
        final firstJournal = SafeDiagnosticJournal();
        final first = NativeDiagnosticImporter(journal: firstJournal, read: () async => raw);
        await first.attachRemote(
          firstRemote,
          baseline: true,
          persistBaseline: (value) async {
            expect(writes, 0);
            frozen = value;
            return true;
          },
          onBaselinePersisted: () => Future<void>.error(StateError('crash before pending removal')),
        );
        expect(frozen, isNotNull);
        first.dispose();
        // Simulate process loss without graceful disposal writing any newer state.
        final diskAtCrash = stored;
        await firstRemote.dispose();
        stored = diskAtCrash;
        firstJournal.dispose();
        crash = false;
        raw = snapshot(3);
        final nextRunner = Map<String, Object>.from((raw['sources']! as List).single as Map)..['source'] = 'runner';
        (raw['sources']! as List).insert(0, nextRunner);
        if (rotate) {
          for (final source in raw['sources']! as List) {
            (source as Map)['generation'] = 'fedcba9876543210';
          }
        }
        final secondRemote = remote();
        final secondJournal = SafeDiagnosticJournal();
        final second = NativeDiagnosticImporter(journal: secondJournal, read: () async => raw);
        var completed = false;
        await second.attachRemote(
          secondRemote,
          baseline: true,
          persistedBaseline: frozen,
          persistBaseline: (_) async => throw StateError('must reuse durable boundary'),
          onBaselinePersisted: () async {
            completed = true;
          },
        );
        expect(completed, isTrue);
        expect(second.baselinePending, isFalse);
        expect((jsonDecode(stored!) as Map)['events'], hasLength(rotate ? 6 : 2));
        second.dispose();
        await secondRemote.dispose();
        secondJournal.dispose();
      });
    }
  }

  test('source rotation and retained suffix gaps are explicit without rejecting surviving events', () async {
    final journal = SafeDiagnosticJournal();
    var raw = snapshot(1);
    final importer = NativeDiagnosticImporter(journal: journal, read: () async => raw);
    await importer.refresh();
    expect(importer.historyGap, isFalse);
    raw = snapshot(5);
    final source = (raw['sources']! as List).single as Map;
    source['first_sequence'] = 4;
    source['records'] = (source['records'] as List).sublist(3);
    await importer.refresh();
    expect(importer.historyGap, isTrue);
    expect(journal.events.length, 3);
    importer.dispose();
    journal.dispose();

    final rotatedJournal = SafeDiagnosticJournal();
    raw = snapshot(1);
    final rotated = NativeDiagnosticImporter(journal: rotatedJournal, read: () async => raw);
    await rotated.refresh();
    ((raw['sources']! as List).single as Map)['generation'] = 'fedcba9876543210';
    await rotated.refresh();
    expect(rotated.historyGap, isTrue);
    expect(rotatedJournal.events.length, 2);
    rotated.dispose();
    rotatedJournal.dispose();
  });

  test('restored remote cursor exposes source rotation after importer restart', () async {
    String? stored;
    BetterStackLogPrinter remote() => BetterStackLogPrinter(
      endpoint: Uri.parse('https://s1.betterstackdata.com'),
      sessionId: '123e4567-e89b-42d3-a456-426614174000',
      token: 'test',
      budget: TelemetryBudget(read: () => null, write: (_) async => true),
      autoFlush: false,
      readOutbox: () => stored,
      writeOutbox: (value) async {
        stored = value;
        return true;
      },
    );
    final raw = snapshot(1);
    final firstRemote = remote();
    final firstJournal = SafeDiagnosticJournal();
    final first = NativeDiagnosticImporter(journal: firstJournal, read: () async => raw);
    await first.attachRemote(firstRemote);
    first.dispose();
    await firstRemote.dispose();
    firstJournal.dispose();
    ((raw['sources']! as List).single as Map)['generation'] = 'fedcba9876543210';
    final secondRemote = remote();
    final secondJournal = SafeDiagnosticJournal();
    final second = NativeDiagnosticImporter(journal: secondJournal, read: () async => raw);
    await second.attachRemote(secondRemote);
    expect(second.historyGap, isTrue);
    expect(secondJournal.events.length, 1);
    second.dispose();
    await secondRemote.dispose();
    secondJournal.dispose();
  });

  test('failed handoff retry keeps its assigned local journal sequence', () async {
    String? stored;
    var writable = false;
    final journal = SafeDiagnosticJournal();
    journal.record(
      operation: DiagnosticOperation.connect,
      stage: DiagnosticStage.requested,
      code: DiagnosticCode.none,
      operationId: journal.nextOperationId(),
    );
    final remote = BetterStackLogPrinter(
      endpoint: Uri.parse('https://s1.betterstackdata.com'),
      sessionId: '123e4567-e89b-42d3-a456-426614174000',
      token: 'test',
      budget: TelemetryBudget(read: () => null, write: (_) async => true),
      autoFlush: false,
      writeOutbox: (value) async {
        if (writable) stored = value;
        return writable;
      },
    );
    final importer = NativeDiagnosticImporter(journal: journal, read: () async => snapshot(1));
    await importer.attachRemote(remote);
    final localSequence = journal.events.last.sequence;
    expect(localSequence, 2);
    expect(stored, isNull);
    writable = true;
    await importer.refresh();
    final saved = jsonDecode(stored!) as Map<String, dynamic>;
    expect(((saved['events'] as List).single as Map)['sequence'], localSequence);
    expect(journal.events.length, 2);
    importer.dispose();
    await remote.dispose();
    journal.dispose();
  });

  test('local import while OFF deduplicates and rejects whole malformed snapshot', () async {
    final journal = SafeDiagnosticJournal();
    var raw = snapshot(2);
    final importer = NativeDiagnosticImporter(journal: journal, read: () async => raw);
    await importer.refresh();
    await importer.refresh();
    expect(journal.events.length, 2);
    raw = snapshot(3, corrupt: true);
    await importer.refresh();
    expect(journal.events.length, 2);
    expect(importer.readFailed, isTrue);
  });
  test('storage-failed source cannot establish an OFF baseline', () async {
    final journal = SafeDiagnosticJournal();
    final raw = snapshot(2);
    ((raw['sources']! as List).single as Map)['storage_failed'] = true;
    var writes = 0;
    final remote = BetterStackLogPrinter(
      endpoint: Uri.parse('https://s1.betterstackdata.com'),
      sessionId: '123e4567-e89b-42d3-a456-426614174000',
      token: 'test',
      budget: TelemetryBudget(read: () => null, write: (_) async => true),
      autoFlush: false,
      writeOutbox: (_) async {
        writes++;
        return true;
      },
    );
    final importer = NativeDiagnosticImporter(journal: journal, read: () async => raw);
    await importer.attachRemote(remote, baseline: true);
    expect(importer.baselinePending, isTrue);
    expect(writes, 0);
    importer.detachRemote();
    await remote.dispose();
  });

  test('existing delivery acknowledgement resumes a capacity-blocked native backlog', () async {
    final journal = SafeDiagnosticJournal();
    final raw = snapshot(101);
    String? stored;
    final remote = BetterStackLogPrinter(
      endpoint: Uri.parse('https://s1.betterstackdata.com'),
      sessionId: '123e4567-e89b-42d3-a456-426614174000',
      token: 'test',
      budget: TelemetryBudget(read: () => null, write: (_) async => true),
      autoFlush: false,
      post: (_, _, _) async => 202,
      writeOutbox: (s) async {
        stored = s;
        return true;
      },
    );
    final importer = NativeDiagnosticImporter(journal: journal, read: () async => raw);
    await importer.attachRemote(remote);
    expect(importer.deliveryFailed, isTrue);
    await remote.flush();
    // Let the existing accepted delivery notification finish its import pass.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect((((jsonDecode(stored!) as Map)['source_cursors'] as List).single as Map)['sequence'], 101);
    expect(importer.deliveryFailed, isFalse);
    importer.detachRemote();
    await remote.dispose();
  });

  test('failed baseline is frozen and blocks backlog; imported events bypass normal forwarding', () async {
    final journal = SafeDiagnosticJournal();
    var raw = _withEmptyRunner(snapshot(2));
    final importer = NativeDiagnosticImporter(journal: journal, read: () async => raw);
    await importer.refresh();
    var success = false;
    String? stored;
    final remote = BetterStackLogPrinter(
      endpoint: Uri.parse('https://s1.betterstackdata.com'),
      sessionId: '123e4567-e89b-42d3-a456-426614174000',
      token: 'test',
      budget: TelemetryBudget(read: () => null, write: (_) async => true),
      autoFlush: false,
      writeOutbox: (s) async {
        if (success) stored = s;
        return success;
      },
    );
    final subscription = RemoteDiagnosticSubscription(journal, remote);
    await importer.attachRemote(remote, baseline: true);
    expect(importer.baselinePending, isTrue);
    success = true;
    raw = _withEmptyRunner(snapshot(3));
    await importer.refresh();
    expect(importer.baselinePending, isFalse);
    final persisted = jsonDecode(stored!) as Map;
    expect((persisted['events'] as List).length, 1);
    expect(
      (persisted['source_cursors'] as List).cast<Map>().firstWhere(
        (cursor) => cursor['source'] == 'extension',
      )['sequence'],
      3,
    );
    subscription.dispose();
    importer.detachRemote();
    await remote.dispose();
  });
}

Map<String, Object> _withEmptyRunner(Map<String, Object> value) {
  (value['sources']! as List).insert(0, {
    'source': 'runner',
    'generation': 'fedcba9876543210',
    'first_sequence': 0,
    'last_sequence': 0,
    'dropped_count': 0,
    'storage_failed': false,
    'records': <Object>[],
  });
  return value;
}
