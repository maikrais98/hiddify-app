import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/analytics/analytics_logger.dart';
import 'package:hiddify/core/logger/custom_logger.dart';
import 'package:hiddify/core/logger/logger_controller.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/details/profile_details_notifier.dart';
import 'package:hiddify/features/profile/details/profile_details_state.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/model/profile_sort_enum.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:loggy/loggy.dart';

void main() {
  test('profile import never logs the private subscription URL', () {
    final source = File('lib/features/profile/notifier/profile_notifier.dart').readAsStringSync();

    expect(source, isNot(contains('url: [\${rs.url}]')));
  });

  test('failed profile deletion never logs a secret-bearing profile name', () async {
    const canary = 'vpn-delete-secret-name-91ea7c';
    const failure = ProfileFailure.unexpected('delete failed');
    final records = _RecordPrinter();
    Loggy.initLoggy(logPrinter: records);
    final container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWith((ref) => _ProfileRepository('', deleteFailure: failure))],
    );
    addTearDown(() {
      container.dispose();
      Loggy.initLoggy(logPrinter: const ConsolePrinter());
    });
    await container.read(profileRepositoryProvider.future);
    final profile = ProfileEntity.local(
      id: 'profile-id',
      active: false,
      name: canary,
      lastUpdate: DateTime.utc(2026, 9, 16),
    );

    await expectLater(container.read(profilesNotifierProvider.notifier).deleteProfile(profile), throwsA(failure));

    expect(records.serialized, contains('failed to delete profile'));
    expect(records.serialized, isNot(contains(canary)));
  });

  test('failed profile export rethrows without writing failure secrets to log sinks', () async {
    const canary = 'vpn-export-failure-secret-4b62d9';
    final failure = ProfileFailure.unexpected(
      StateError(canary),
      StackTrace.fromString('export failure stack $canary'),
    );
    final tempDir = Directory.systemTemp.createTempSync('export-failure-logging-test-');
    final logFile = File('${tempDir.path}/app.log');
    final records = _RecordPrinter();
    final breadcrumbs = _BreadcrumbPrinter();
    final filePrinter = FileLogPrinter(logFile.path);
    Loggy.initLoggy(logPrinter: LoggerController(records, {'app': filePrinter, 'sentry': breadcrumbs}));
    final container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWith((ref) => _ProfileRepository('', generateFailure: failure))],
    );
    addTearDown(() {
      container.dispose();
      Loggy.initLoggy(logPrinter: const ConsolePrinter());
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });
    await container.read(profileRepositoryProvider.future);
    final profile = ProfileEntity.local(
      id: 'profile-id',
      active: false,
      name: 'Profile',
      lastUpdate: DateTime.utc(2026, 9, 16),
    );

    late final String logContents;
    try {
      await expectLater(
        container.read(profilesNotifierProvider.notifier).exportConfigToClipboard(profile),
        throwsA(same(failure)),
      );
    } finally {
      logContents = await _closeAndReadLog(filePrinter, logFile, 'export-failure-log-complete');
    }

    expect(records.serialized, contains('failed to generate profile config for export'));
    expect(records.serialized, isNot(contains(canary)));
    expect(logContents, isNot(contains(canary)));
    expect(breadcrumbs.serialized, isNot(contains(canary)));
  });

  test('profile details never writes generated config to log sinks', () async {
    const canary = 'vpn-canary-secret-7d9f3c';
    const config =
        '''
{
  "outbounds": [
    {"type": "trojan", "tag": "proxy", "server": "example.test", "password": "$canary"}
  ],
  "endpoints": []
}
''';
    final tempDir = Directory.systemTemp.createTempSync('secret-logging-test-');
    final logFile = File('${tempDir.path}/app.log');
    final records = _RecordPrinter();
    final breadcrumbs = _BreadcrumbPrinter();
    final filePrinter = FileLogPrinter(logFile.path);
    Loggy.initLoggy(logPrinter: LoggerController(records, {'app': filePrinter, 'sentry': breadcrumbs}));

    final container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWith((ref) => _ProfileRepository(config))],
    );
    addTearDown(() {
      container.dispose();
      Loggy.initLoggy(logPrinter: const ConsolePrinter());
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    late final ProfileDetailsState state;
    late final String logContents;
    try {
      await container.read(profileRepositoryProvider.future);
      state = await container.read(profileDetailsNotifierProvider('profile-id').future);
    } finally {
      logContents = await _closeAndReadLog(filePrinter, logFile, 'valid-config-log-complete');
    }
    expect(state.configContent, contains(canary));

    expect(records.serialized, isNot(contains(canary)));
    expect(logContents, isNot(contains(canary)));
    expect(breadcrumbs.serialized, isNot(contains(canary)));
  });

  test('profile details never logs secrets from config failures', () async {
    const canary = 'vpn-canary-secret-malformed-3a8d1e';
    const malformedConfig = '{"outbounds":[{"password":"$canary"}],"endpoints":[}';
    final tempDir = Directory.systemTemp.createTempSync('secret-logging-error-test-');
    final logFile = File('${tempDir.path}/app.log');
    final records = _RecordPrinter();
    final sentry = _BreadcrumbPrinter();
    final filePrinter = FileLogPrinter(logFile.path);
    Loggy.initLoggy(logPrinter: LoggerController(records, {'app': filePrinter, 'sentry': sentry}));

    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith(
          (ref) => _ProfileRepository(
            '',
            generateFailure: const ProfileFailure.invalidConfig(canary),
            rawConfig: malformedConfig,
          ),
        ),
      ],
    );
    addTearDown(() {
      container.dispose();
      Loggy.initLoggy(logPrinter: const ConsolePrinter());
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    late final ProfileDetailsState state;
    late final String logContents;
    try {
      await container.read(profileRepositoryProvider.future);
      state = await container.read(profileDetailsNotifierProvider('profile-id').future);
    } finally {
      logContents = await _closeAndReadLog(filePrinter, logFile, 'failure-config-log-complete');
    }
    expect(state.configContent, contains(canary));

    expect(records.serialized, isNot(contains(canary)));
    expect(logContents, isNot(contains(canary)));
    expect(sentry.serialized, isNot(contains(canary)));
  });

  test('Riverpod diagnostics never serialize provider values', () {
    final source = File('lib/riverpod_observer.dart').readAsStringSync();

    expect(source, isNot(contains(r': $value')));
    expect(source, isNot(contains(r': $previousValue -> $newValue')));
  });

  test('connection errors use typed observability instead of direct Sentry calls', () {
    final source = File('lib/features/connection/notifier/connection_notifier.dart').readAsStringSync();

    expect(source, isNot(contains('Sentry.capture')));
    expect(source, contains('ObservabilityEvent.vpnConnectionFailed'));
    expect(source, isNot(contains('err.toString()')));
  });

  test('raw core messages never fan out to Loggy or Sentry', () {
    final source = File('lib/hiddifycore/hiddify_core_service.dart').readAsStringSync();

    expect(source, isNot(contains('loggy.log(getLogLevel(event.level), line)')));
    expect(source, contains('ObservabilityEvent.vpnCoreWarningReceived'));
    expect(source, isNot(contains('message: event.message')));
  });

  test('Sentry breadcrumbs exclude raw error objects and stack text', () {
    final source = File('lib/core/analytics/analytics_logger.dart').readAsStringSync();

    expect(source, isNot(contains("'LogRecord.error': error")));
    expect(source, isNot(contains("'LogRecord.stackTrace': stackTrace")));
    expect(source, contains('sanitizeLogText(message)'));
  });

  test('Release profile import has no bundled test subscription endpoint', () {
    final notifier = File('lib/features/profile/notifier/profile_notifier.dart').readAsStringSync();
    final modal = File('lib/features/profile/add/add_profile_modal.dart').readAsStringSync();

    expect(notifier, isNot(contains('test.configs/free_configs')));
    expect(modal, isNot(contains('FreeBtns')));
    expect(modal, isNot(contains('freeSwitchNotifierProvider')));
  });
}

Future<String> _closeAndReadLog(FileLogPrinter printer, File logFile, String completionMarker) async {
  Loggy('secret-logging-test').info(completionMarker);
  printer.dispose();

  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (logFile.existsSync()) {
      final contents = await logFile.readAsString();
      if (contents.contains(completionMarker)) return contents;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('File log did not flush the completion marker');
}

class _ProfileRepository implements ProfileRepository {
  _ProfileRepository(this.config, {this.generateFailure, this.rawConfig, this.deleteFailure});

  final String config;
  final ProfileFailure? generateFailure;
  final String? rawConfig;
  final ProfileFailure? deleteFailure;

  @override
  TaskEither<ProfileFailure, ProfileEntity?> getById(String id) =>
      TaskEither.of(ProfileEntity.local(id: id, active: true, name: 'Test', lastUpdate: DateTime.utc(2026)));

  @override
  TaskEither<ProfileFailure, String> generateConfig(String id) =>
      generateFailure == null ? TaskEither.of(config) : TaskEither.fromEither(Left(generateFailure!));

  @override
  TaskEither<ProfileFailure, String> getRawConfig(String id) => TaskEither.of(rawConfig ?? config);

  @override
  TaskEither<ProfileFailure, Unit> deleteById(String id, bool isActive) =>
      deleteFailure == null ? TaskEither.of(unit) : TaskEither.fromEither(Left(deleteFailure!));

  @override
  Stream<Either<ProfileFailure, List<ProfileEntity>>> watchAll({
    ProfilesSort sort = ProfilesSort.lastUpdate,
    SortMode sortMode = SortMode.ascending,
  }) => Stream.value(const Right([]));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordPrinter extends LoggyPrinter {
  final records = <LogRecord>[];

  @override
  void onLog(LogRecord record) => records.add(record);

  String get serialized =>
      records.map((record) => [record.message, record.object, record.error, record.stackTrace].join('\n')).join('\n');
}

class _BreadcrumbPrinter extends LoggyPrinter {
  final records = <LogRecord>[];

  @override
  void onLog(LogRecord record) => records.add(record);

  String get serialized =>
      records.map((record) => [record.toBreadcrumb().toJson(), record.toEvent().toJson()].join('\n')).join('\n');
}
