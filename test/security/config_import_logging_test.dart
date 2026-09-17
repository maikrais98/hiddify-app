import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/analytics/analytics_logger.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/logger/custom_logger.dart';
import 'package:hiddify/core/logger/logger_controller.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/per_app_proxy/data/app_proxy_data_source.dart';
import 'package:hiddify/features/per_app_proxy/data/selected_data_provider.dart';
import 'package:hiddify/features/per_app_proxy/model/per_app_proxy_backup.dart';
import 'package:hiddify/features/per_app_proxy/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/per_app_proxy/overview/per_app_proxy_notifier.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:loggy/loggy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

const _canary = 'AUDIT_SYNTHETIC_CONFIG_MARKER';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('config options imports', () {
    for (final source in _ImportSource.values) {
      test('${source.name} parse failure only emits an allowlisted code', () async {
        final result = await _runConfigOptionsImport(source, '{"secret":"$_canary",broken}');

        _expectRedacted(result, 'config_options_${source.name}_parse', succeeded: false);
      });

      test('${source.name} update failure only emits an allowlisted code', () async {
        final result = await _runConfigOptionsImport(source, jsonEncode({'region': _canary}));

        _expectRedacted(result, 'config_options_${source.name}_update', succeeded: true);
      });
    }
  });

  group('per-app proxy imports', () {
    for (final source in _ImportSource.values) {
      test('${source.name} parse failure only emits an allowlisted code', () async {
        final result = await _runPerAppProxyImport(source, '{"secret":"$_canary",broken}', updateFailure: false);

        _expectRedacted(result, 'per_app_proxy_${source.name}_parse', succeeded: false);
      });

      test('${source.name} update failure only emits an allowlisted code', () async {
        final config = jsonEncode({
          'include': {
            'selected': [_canary],
          },
        });
        // Preserve the existing file-handler normalization: U9 only changes
        // what reaches log sinks when the production update path fails.
        final result = await _runPerAppProxyImport(
          source,
          source == _ImportSource.file ? jsonEncode(config) : config,
          updateFailure: true,
        );

        _expectRedacted(result, 'per_app_proxy_${source.name}_update', succeeded: false);
      });
    }
  });
}

void _expectRedacted(_ImportResult result, String failureCode, {required bool succeeded}) {
  expect(result.succeeded, succeeded);
  expect(result.records, contains(failureCode));
  expect(result.fileLog, contains(failureCode));
  expect(result.breadcrumbs, contains(failureCode));
  expect(result.records, isNot(contains(_canary)));
  expect(result.fileLog, isNot(contains(_canary)));
  expect(result.breadcrumbs, isNot(contains(_canary)));
}

Future<_ImportResult> _runConfigOptionsImport(_ImportSource source, String input) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final translations = await AppLocale.en.build();
  final notifications = _RecordingNotifications();
  final container = ProviderContainer(
    overrides: [
      translationsProvider.overrideWith((ref) => translations),
      sharedPreferencesProvider.overrideWith((ref) => preferences),
      inAppNotificationControllerProvider.overrideWithValue(notifications),
      configOptionNotifierProvider.overrideWith(_TestConfigOptions.new),
    ],
  );
  final harness = await _ImportHarness.create(input);
  try {
    final notifier = container.read(configOptionNotifierProvider.notifier);
    final succeeded = switch (source) {
      _ImportSource.clipboard => await notifier.importFromClipboard(),
      _ImportSource.file => await notifier.importFromJsonFile(),
    };
    return await harness.finish(succeeded);
  } finally {
    container.dispose();
    await harness.dispose();
  }
}

Future<_ImportResult> _runPerAppProxyImport(_ImportSource source, String input, {required bool updateFailure}) async {
  final translations = await AppLocale.en.build();
  final notifications = _RecordingNotifications();
  final dataSource = _AppProxyDataSource(updateFailure: updateFailure);
  final provider = perAppProxyProvider(AppProxyMode.include);
  final container = ProviderContainer(
    overrides: [
      translationsProvider.overrideWith((ref) => translations),
      inAppNotificationControllerProvider.overrideWithValue(notifications),
      appProxyDataSourceProvider.overrideWithValue(dataSource),
      provider.overrideWith(_TestPerAppProxy.new),
    ],
  );
  final subscription = container.listen(provider, (_, _) {}, fireImmediately: true);
  final harness = await _ImportHarness.create(input);
  try {
    final notifier = container.read(provider.notifier);
    final succeeded = switch (source) {
      _ImportSource.clipboard => await notifier.importClipboard(),
      _ImportSource.file => await notifier.importFile(),
    };
    return await harness.finish(succeeded);
  } finally {
    subscription.close();
    container.dispose();
    await harness.dispose();
  }
}

enum _ImportSource { clipboard, file }

final class _ImportHarness {
  _ImportHarness._(this._tempDir, this._logFile, this._filePrinter, this._records, this._breadcrumbs);

  final Directory _tempDir;
  final File _logFile;
  final FileLogPrinter _filePrinter;
  final _RecordPrinter _records;
  final _BreadcrumbPrinter _breadcrumbs;
  bool _finished = false;

  static Future<_ImportHarness> create(String input) async {
    final tempDir = Directory.systemTemp.createTempSync('config-import-logging-');
    final inputFile = File('${tempDir.path}/input.json')..writeAsStringSync(input);
    final logFile = File('${tempDir.path}/app.log');
    final records = _RecordPrinter();
    final breadcrumbs = _BreadcrumbPrinter();
    final filePrinter = FileLogPrinter(logFile.path);
    Loggy.initLoggy(logPrinter: LoggerController(records, {'app': filePrinter, 'sentry': breadcrumbs}));
    FilePicker.platform = _TestFilePicker(inputFile);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') return {'text': input};
        return null;
      },
    );
    return _ImportHarness._(tempDir, logFile, filePrinter, records, breadcrumbs);
  }

  Future<_ImportResult> finish(bool succeeded) async {
    final fileLog = await _closeAndReadLog(_filePrinter, _logFile, 'config-import-log-complete');
    _finished = true;
    return _ImportResult(succeeded, _records.serialized, fileLog, _breadcrumbs.serialized);
  }

  Future<void> dispose() async {
    if (!_finished) _filePrinter.dispose();
    FilePickerIO.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
    Loggy.initLoggy(logPrinter: const ConsolePrinter());
    if (_tempDir.existsSync()) _tempDir.deleteSync(recursive: true);
  }
}

final class _ImportResult {
  const _ImportResult(this.succeeded, this.records, this.fileLog, this.breadcrumbs);

  final bool succeeded;
  final String records;
  final String fileLog;
  final String breadcrumbs;
}

Future<String> _closeAndReadLog(FileLogPrinter printer, File logFile, String completionMarker) async {
  Loggy('config-import-logging-test').info(completionMarker);
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

final class _TestFilePicker extends FilePicker {
  _TestFilePicker(this.file);

  final File file;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult([PlatformFile(name: 'input.json', size: await file.length(), path: file.path)]);
}

final class _TestConfigOptions extends ConfigOptionNotifier {
  @override
  Future<bool> build() async => false;
}

final class _TestPerAppProxy extends PerAppProxy {
  @override
  Stream<Map<String, int>> build(AppProxyMode? mode) => Stream.value({});
}

final class _AppProxyDataSource implements AppProxyDataSource {
  _AppProxyDataSource({required this.updateFailure});

  final bool updateFailure;

  @override
  Future<void> importPkgs({required PerAppProxyBackup backup}) async {
    if (updateFailure) throw StateError(_canary);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RecordingNotifications extends InAppNotificationController {
  @override
  ToastificationItem? showErrorToast(String message) => null;

  @override
  ToastificationItem? showSuccessToast(String message) => null;
}

final class _RecordPrinter extends LoggyPrinter {
  final records = <LogRecord>[];

  @override
  void onLog(LogRecord record) => records.add(record);

  String get serialized =>
      records.map((record) => [record.message, record.object, record.error, record.stackTrace].join('\n')).join('\n');
}

final class _BreadcrumbPrinter extends LoggyPrinter {
  final records = <LogRecord>[];

  @override
  void onLog(LogRecord record) => records.add(record);

  String get serialized =>
      records.map((record) => [record.toBreadcrumb().toJson(), record.toEvent().toJson()].join('\n')).join('\n');
}
