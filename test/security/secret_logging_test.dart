import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/analytics/analytics_logger.dart';
import 'package:hiddify/core/logger/custom_logger.dart';
import 'package:hiddify/core/logger/logger_controller.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/details/profile_details_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:loggy/loggy.dart';

void main() {
  test('profile import never logs the private subscription URL', () {
    final source = File('lib/features/profile/notifier/profile_notifier.dart').readAsStringSync();

    expect(source, isNot(contains('url: [\${rs.url}]')));
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
    Loggy.initLoggy(
      logPrinter: LoggerController(records, {'app': filePrinter, 'sentry': breadcrumbs}),
    );

    final container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWith((ref) => _ProfileRepository(config))],
    );
    addTearDown(() {
      container.dispose();
      Loggy.initLoggy(logPrinter: const ConsolePrinter());
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    await container.read(profileRepositoryProvider.future);
    final state = await container.read(profileDetailsNotifierProvider('profile-id').future);
    expect(state.configContent, contains(canary));

    filePrinter.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(records.serialized, isNot(contains(canary)));
    expect(logFile.readAsStringSync(), isNot(contains(canary)));
    expect(breadcrumbs.serialized, isNot(contains(canary)));
  });

  test('Riverpod diagnostics never serialize provider values', () {
    final source = File('lib/riverpod_observer.dart').readAsStringSync();

    expect(source, isNot(contains(r': $value')));
    expect(source, isNot(contains(r': $previousValue -> $newValue')));
  });

  test('connection crash reporting never sends the raw core error', () {
    final source = File('lib/features/connection/notifier/connection_notifier.dart').readAsStringSync();
    final captureCall = RegExp(r'Sentry\.capture(?:Exception|Message)\((.*?)\);', dotAll: true).firstMatch(source);

    expect(captureCall, isNotNull);
    expect(captureCall!.group(1), isNot(contains('err.toString()')));
  });

  test('Release profile import has no bundled test subscription endpoint', () {
    final notifier = File('lib/features/profile/notifier/profile_notifier.dart').readAsStringSync();
    final modal = File('lib/features/profile/add/add_profile_modal.dart').readAsStringSync();

    expect(notifier, isNot(contains('test.configs/free_configs')));
    expect(modal, isNot(contains('FreeBtns')));
    expect(modal, isNot(contains('freeSwitchNotifierProvider')));
  });
}

class _ProfileRepository implements ProfileRepository {
  _ProfileRepository(this.config);

  final String config;

  @override
  TaskEither<ProfileFailure, ProfileEntity?> getById(String id) =>
      TaskEither.of(ProfileEntity.local(id: id, active: true, name: 'Test', lastUpdate: DateTime.utc(2026)));

  @override
  TaskEither<ProfileFailure, String> generateConfig(String id) => TaskEither.of(config);

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
  final breadcrumbs = <Map<String, dynamic>>[];

  @override
  void onLog(LogRecord record) => breadcrumbs.add(record.toBreadcrumb().toJson());

  String get serialized => breadcrumbs.join('\n');
}
