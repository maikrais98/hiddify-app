import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_event.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_journal.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';

import '../../../support/profile_settings_fixtures.dart';

void main() {
  test(
    'iOS import waits for foreground readiness before settings, validation, config commit, and database insert',
    () async {
      final readiness = Completer<bool>();
      final core = _ForegroundFixtureCore(readiness: () => readiness.future);
      final journal = SafeDiagnosticJournal();
      final fixture = await ProfileFixture.create(core: core, diagnostics: journal);
      addTearDown(fixture.dispose);

      final import = fixture.repository
          .upsertRemote('https://example.invalid/foreground-delayed', diagnosticTrigger: DiagnosticTrigger.importAction)
          .run();
      await core.readinessEntered.future.timeout(const Duration(seconds: 5));

      expect(core.changeOptionsCalls, 0);
      expect(core.validationCalls, 0);
      expect(_committedConfigs(fixture), isEmpty);
      expect(await fixture.dao.watchProfilesCount().first, 0);
      expect(
        journal.events.where((event) => event.phase == DiagnosticPhase.foregroundReady).map((event) => event.stage),
        [DiagnosticStage.requested],
      );

      readiness.complete(true);
      expect((await import).isRight(), true);
      expect(core.changeOptionsCalls, 1);
      expect(core.validationCalls, 1);
      expect(_committedConfigs(fixture), hasLength(1));
      expect(await fixture.dao.watchProfilesCount().first, 1);
      expect(
        journal.events.where((event) => event.phase == DiagnosticPhase.foregroundReady).map((event) => event.stage),
        [DiagnosticStage.requested, DiagnosticStage.accepted],
      );
    },
  );

  test('failed iOS readiness is core unavailable without commit and a later import can retry', () async {
    var ready = false;
    final core = _ForegroundFixtureCore(readiness: () async => ready);
    final journal = SafeDiagnosticJournal();
    final fixture = await ProfileFixture.create(core: core, diagnostics: journal);
    addTearDown(fixture.dispose);

    final first = await fixture.repository
        .upsertRemote('https://example.invalid/foreground-retry', diagnosticTrigger: DiagnosticTrigger.importAction)
        .run();
    final failure = first.fold((failure) => failure, (_) => fail('readiness failure must reject the import'));

    expect(failure, isA<ProfileUnexpectedFailure>());
    expect((failure as ProfileUnexpectedFailure).error, isA<HiddifyCoreInitializationException>());
    expect(core.changeOptionsCalls, 0);
    expect(core.validationCalls, 0);
    expect(_committedConfigs(fixture), isEmpty);
    expect(await fixture.dao.watchProfilesCount().first, 0);
    expect(
      journal.events
          .where((event) => event.phase == DiagnosticPhase.foregroundReady)
          .map((event) => (event.stage, event.code)),
      [(DiagnosticStage.requested, DiagnosticCode.none), (DiagnosticStage.failed, DiagnosticCode.coreUnavailable)],
    );
    expect(journal.events.last.code, DiagnosticCode.coreUnavailable);

    ready = true;
    final retry = await fixture.repository
        .upsertRemote('https://example.invalid/foreground-retry', diagnosticTrigger: DiagnosticTrigger.importAction)
        .run();

    expect(retry.isRight(), true);
    expect(core.readinessCalls, 2);
    expect(core.changeOptionsCalls, 1);
    expect(core.validationCalls, 1);
    expect(await fixture.dao.watchProfilesCount().first, 1);
  });

  test('only foreground settings unavailability is classified as core unavailable', () async {
    final core = _ForegroundFixtureCore(readiness: () async => true)
      ..changeOptionsFailure = 'foreground_settings_unavailable';
    final journal = SafeDiagnosticJournal();
    final fixture = await ProfileFixture.create(core: core, diagnostics: journal);
    addTearDown(fixture.dispose);

    final unavailable = await fixture.repository
        .upsertRemote('https://example.invalid/foreground-settings', diagnosticTrigger: DiagnosticTrigger.importAction)
        .run();
    final unavailableFailure = unavailable.fold(
      (failure) => failure,
      (_) => fail('foreground settings failure must reject the import'),
    );

    expect(unavailableFailure, isA<ProfileUnexpectedFailure>());
    expect((unavailableFailure as ProfileUnexpectedFailure).error, isA<HiddifyCoreInitializationException>());
    expect(core.validationCalls, 0);
    expect(await fixture.dao.watchProfilesCount().first, 0);
    expect(journal.events.last.code, DiagnosticCode.coreUnavailable);

    core.changeOptionsFailure = 'synthetic invalid settings';
    journal.clear();
    final invalid = await fixture.repository
        .upsertRemote('https://example.invalid/invalid-settings', diagnosticTrigger: DiagnosticTrigger.importAction)
        .run();

    expect(invalid.fold((failure) => failure, (_) => null), isA<ProfileInvalidConfigFailure>());
    expect(await fixture.dao.watchProfilesCount().first, 0);
    expect(journal.events.last.code, DiagnosticCode.invalidConfig);
  });
}

List<File> _committedConfigs(ProfileFixture fixture) => Directory('${fixture.directory.path}/configs')
    .listSync()
    .whereType<File>()
    .where((file) => file.path.endsWith('.json') && !file.path.endsWith('.tmp.json'))
    .toList();

final class _SystemStatusCore extends CoreInterface {
  @override
  bool get supportsSystemStatus => true;
}

final class _ForegroundFixtureCore extends FixtureCore {
  _ForegroundFixtureCore({required this.readiness}) : super(core: _SystemStatusCore());

  final Future<bool> Function() readiness;
  final Completer<void> readinessEntered = Completer<void>();
  int readinessCalls = 0;
  int changeOptionsCalls = 0;
  int validationCalls = 0;
  String? changeOptionsFailure;

  @override
  Future<bool> ensureForegroundReady() {
    readinessCalls++;
    if (!readinessEntered.isCompleted) readinessEntered.complete();
    return readiness();
  }

  @override
  TaskEither<String, Unit> changeOptions(SingboxConfigOption options) => TaskEither(() async {
    changeOptionsCalls++;
    final failure = changeOptionsFailure;
    return failure == null ? right(unit) : left(failure);
  });

  @override
  TaskEither<String, Unit> validateConfigByPath(String path, String tempPath, bool debug) => TaskEither(() {
    validationCalls++;
    return super.validateConfigByPath(path, tempPath, debug).run();
  });
}
