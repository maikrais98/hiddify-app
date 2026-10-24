import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_event.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_journal.dart';

import '../../support/profile_settings_fixtures.dart';

void main() {
  test('remote import is lazy, ordered, and allocates a fresh operation for each run', () async {
    final journal = SafeDiagnosticJournal();
    final fixture = await ProfileFixture.create(diagnostics: journal);
    addTearDown(fixture.dispose);
    final task = fixture.repository.upsertRemote(
      'https://example.invalid/diagnostic-import',
      diagnosticTrigger: DiagnosticTrigger.importAction,
    );

    expect(journal.events, isEmpty);

    expect((await task.run()).isRight(), true);
    final first = List<SafeDiagnosticEvent>.of(journal.events);
    expect(first, isNotEmpty);
    expect(first.map((event) => event.operation).toSet(), {DiagnosticOperation.subscriptionImport});
    expect(first.map((event) => event.operationId).toSet(), hasLength(1));
    expect(first.map((event) => (event.phase, event.stage)), [
      (DiagnosticPhase.action, DiagnosticStage.requested),
      (DiagnosticPhase.download, DiagnosticStage.requested),
      (DiagnosticPhase.download, DiagnosticStage.accepted),
      (DiagnosticPhase.nestedDownload, DiagnosticStage.requested),
      (DiagnosticPhase.nestedDownload, DiagnosticStage.accepted),
      (DiagnosticPhase.metadataParse, DiagnosticStage.requested),
      (DiagnosticPhase.metadataParse, DiagnosticStage.accepted),
      (DiagnosticPhase.changeOptions, DiagnosticStage.requested),
      (DiagnosticPhase.changeOptions, DiagnosticStage.accepted),
      (DiagnosticPhase.validateAndCommitConfig, DiagnosticStage.requested),
      (DiagnosticPhase.validateAndCommitConfig, DiagnosticStage.accepted),
      (DiagnosticPhase.dbPersist, DiagnosticStage.requested),
      (DiagnosticPhase.dbPersist, DiagnosticStage.accepted),
      (DiagnosticPhase.action, DiagnosticStage.accepted),
    ]);

    expect((await task.run()).isRight(), true);
    final operationIds = journal.events.map((event) => event.operationId).toSet();
    expect(operationIds, hasLength(2));
  });

  test('a disposed observer cannot change the business result', () async {
    final journal = SafeDiagnosticJournal()..dispose();
    final fixture = await ProfileFixture.create(diagnostics: journal);
    addTearDown(fixture.dispose);

    final result = await fixture.repository
        .upsertRemote('https://example.invalid/observer-failure', diagnosticTrigger: DiagnosticTrigger.importAction)
        .run();

    expect(result.isRight(), true);
  });

  test('nested remote failures are aggregated once and remain partial success', () async {
    final journal = SafeDiagnosticJournal();
    final fixture = await ProfileFixture.create(diagnostics: journal);
    addTearDown(fixture.dispose);
    fixture.http.content = '''
https://nested-success.invalid/a
https://nested-failure.invalid/b
vless://fixture@example.invalid:443#Fixture
''';
    fixture.http.failingUrls.add('https://nested-failure.invalid/b');

    final result = await fixture.repository
        .upsertRemote('https://example.invalid/nested', diagnosticTrigger: DiagnosticTrigger.importAction)
        .run();

    expect(result.isRight(), true);
    final nested = journal.events.where((event) => event.phase == DiagnosticPhase.nestedDownload).toList();
    expect(nested.map((event) => event.stage), [DiagnosticStage.requested, DiagnosticStage.accepted]);
    expect(nested.last.code, DiagnosticCode.partialFailure);
    expect(nested.last.nestedTotal, 2);
    expect(nested.last.nestedFailed, 1);
  });
}
