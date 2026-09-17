import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/analytics/analytics_logger.dart';
import 'package:hiddify/core/localization/locale_extensions.dart';
import 'package:hiddify/core/logger/custom_logger.dart';
import 'package:hiddify/core/logger/logger_controller.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_export.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_summary.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostics_page.dart';
import 'package:hiddify/gen/translations.g.dart';
import 'package:loggy/loggy.dart';

const _canary = 'diagnostic-secret-canary-73e129';
const _hostile = 'https://private.test/$_canary\nuser+$_canary@example.test\n{"password":"$_canary"}';
const _shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('overlapping creates share one owned directory and discard removes every file', () async {
    final root = Directory.systemTemp.createTempSync('diagnostics-overlap-');
    final entered = Completer<void>();
    final release = Completer<Directory>();
    var directoryRequests = 0;
    final exporter = SafeDiagnosticExport(
      temporaryDirectory: () {
        directoryRequests++;
        if (!entered.isCompleted) entered.complete();
        return release.future;
      },
    );
    addTearDown(() async {
      await exporter.discard();
      root.deleteSync(recursive: true);
    });
    final summary = SafeDiagnosticSummary.capture(null, TargetPlatform.iOS);
    final first = exporter.create(summary);
    final second = exporter.create(summary);
    await entered.future;
    release.complete(root);
    expect(await Future.wait([first, second]), [true, true]);
    expect(directoryRequests, 1);
    expect(root.listSync().whereType<Directory>(), hasLength(1));
    final files = root.listSync(recursive: true).whereType<File>().toList();
    expect(files, hasLength(1));
    expect(files.single.readAsStringSync(), summary.json);
    await exporter.discard();
    expect(exporter.hasFile, isFalse);
    expect(root.listSync(recursive: true), isEmpty);
  });

  test('discard during pending creates waits for cleanup and cannot publish an orphan', () async {
    final root = Directory.systemTemp.createTempSync('diagnostics-discard-race-');
    final entered = Completer<void>();
    final release = Completer<Directory>();
    final exporter = SafeDiagnosticExport(
      temporaryDirectory: () {
        if (!entered.isCompleted) entered.complete();
        return release.future;
      },
    );
    addTearDown(() async {
      await exporter.discard();
      root.deleteSync(recursive: true);
    });
    final summary = SafeDiagnosticSummary.capture(null, TargetPlatform.iOS);
    final first = exporter.create(summary);
    final second = exporter.create(summary);
    await entered.future;
    final discarded = exporter.discard();
    release.complete(root);
    await discarded;
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(exporter.hasFile, isFalse);
    expect(root.listSync(recursive: true), isEmpty);
    expect(await exporter.share(const Rect.fromLTWH(0, 0, 20, 20)), DiagnosticExportResult.unavailable);
  });

  test('every failure drops hostile payload and emits only a closed category/code', () {
    final cases = <(ConnectionFailure, DiagnosticCategory, DiagnosticCode)>[
      (
        const ConnectionFailure.missingVpnPermission(_hostile),
        DiagnosticCategory.permission,
        DiagnosticCode.vpnPermission,
      ),
      (
        const ConnectionFailure.missingNotificationPermission(_hostile),
        DiagnosticCategory.permission,
        DiagnosticCode.notificationPermission,
      ),
      (const ConnectionFailure.missingPrivilege(), DiagnosticCategory.permission, DiagnosticCode.privilege),
      (
        const ConnectionFailure.invalidConfigOption(_hostile),
        DiagnosticCategory.configuration,
        DiagnosticCode.configurationOptions,
      ),
      (const ConnectionFailure.invalidConfig(_hostile), DiagnosticCategory.configuration, DiagnosticCode.configuration),
      (
        const ConnectionFailure.backgroundCoreNotAvailable(_hostile),
        DiagnosticCategory.core,
        DiagnosticCode.coreUnavailable,
      ),
      (const ConnectionFailure.missiingWarpLicense(), DiagnosticCategory.access, DiagnosticCode.warpLicense),
      (const ConnectionFailure.missingPsiphonLicense(), DiagnosticCategory.access, DiagnosticCode.psiphonLicense),
      (
        ConnectionFailure.unexpected(_Poison(), StackTrace.fromString(_hostile)),
        DiagnosticCategory.unknown,
        DiagnosticCode.unexpected,
      ),
    ];
    for (final (failure, category, code) in cases) {
      final summary = SafeDiagnosticSummary.capture(ConnectionStatus.disconnected(failure), TargetPlatform.iOS);
      expect(summary.category, category);
      expect(summary.code, code);
      expect(summary.stage, DiagnosticStage.idle);
      expect(summary.json, isNot(contains(_canary)));
      expect(
        (jsonDecode(summary.json) as Map<String, dynamic>).keys,
        unorderedEquals(['schema', 'category', 'stage', 'code', 'platform', 'reachability']),
      );
    }
  });

  test('connection stage never implies internet reachability', () {
    final cases = <(ConnectionStatus?, DiagnosticStage)>[
      (null, DiagnosticStage.unavailable),
      (const ConnectionStatus.disconnected(), DiagnosticStage.idle),
      (const ConnectionStatus.connecting(), DiagnosticStage.connecting),
      (const ConnectionStatus.connected(), DiagnosticStage.connected),
      (const ConnectionStatus.disconnecting(), DiagnosticStage.disconnecting),
    ];
    for (final (status, stage) in cases) {
      final summary = SafeDiagnosticSummary.capture(status, TargetPlatform.android);
      expect(summary.stage, stage);
      expect((jsonDecode(summary.json) as Map<String, dynamic>)['reachability'], 'not_checked');
    }
  });

  test('safe diagnostics has no dependency on raw log features', () {
    final sources = Directory(
      'lib/features/diagnostics',
    ).listSync(recursive: true).whereType<File>().where((file) => file.path.endsWith('.dart'));
    for (final source in sources) {
      final contents = source.readAsStringSync();
      expect(contents, isNot(matches(RegExp("import ['\"][^'\"]*(features/log|core/logger)/"))), reason: source.path);
      expect(contents, isNot(contains("fontFamily: 'Inter'")), reason: source.path);
    }
  });

  test('Russian and English use the runtime system font instead of bundled Inter', () {
    expect(AppLocale.ru.preferredFontFamily, isEmpty);
    expect(AppLocale.en.preferredFontFamily, isEmpty);
  });

  testWidgets('safe screen shows only the structured report and inherits the runtime font', (tester) async {
    final summary = SafeDiagnosticSummary.capture(
      const ConnectionStatus.disconnected(ConnectionFailure.invalidConfig(_hostile)),
      TargetPlatform.iOS,
    );
    final theme = AppTheme(AppThemeMode.dark, '').darkTheme(null);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('ru')],
        home: SafeDiagnosticsPage(summary: summary),
      ),
    );

    expect(find.byKey(const Key('diagnostic-summary-card')), findsOneWidget);
    expect(find.byKey(const Key('diagnostic-preview-card')), findsOneWidget);
    expect(find.textContaining('This report contains only the fields shown below.'), findsOneWidget);
    expect(find.textContaining('does not include raw logs'), findsOneWidget);
    expect(find.textContaining('Internet reachability has not been checked.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(DropdownButton<dynamic>), findsNothing);
    expect(find.text('Filter'), findsNothing);
    expect(find.text('INFO'), findsNothing);
    expect(find.textContaining('service started'), findsNothing);
    expect(find.textContaining(_canary), findsNothing);

    final titleParagraph = tester.renderObject<RenderParagraph>(find.text('Safe diagnostics'));
    expect(titleParagraph.text.style?.fontFamily, isNot('Inter'));
    expect(titleParagraph.text.style?.fontFamily, isNotNull);
    expect(theme.textTheme.bodyMedium?.fontFamily, isNot('Inter'));
  });

  testWidgets('temporary-copy wording does not promise guaranteed deletion', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: SafeDiagnosticsPage(summary: SafeDiagnosticSummary.capture(null, TargetPlatform.iOS)),
      ),
    );

    expect(find.textContaining('attempts to delete it when this screen closes'), findsOneWidget);
    expect(find.textContaining('Copies you save or share are not deleted by the app.'), findsOneWidget);
    expect(find.textContaining('is deleted when this screen closes'), findsNothing);
  });

  testWidgets('canary absent from logs, breadcrumbs, state, preview, file and native export payload', (tester) async {
    final directory = Directory.systemTemp.createTempSync('diagnostics-test-');
    final records = _Records();
    final breadcrumbs = _Breadcrumbs();
    final logFile = File('${directory.path}/app.log');
    final filePrinter = FileLogPrinter(logFile.path);
    await tester.runAsync(() async {
      Loggy.initLoggy(logPrinter: LoggerController(records, {'file': filePrinter, 'sentry': breadcrumbs}));
      await Future<void>.value();
    });
    final exporter = SafeDiagnosticExport(temporaryDirectory: () async => directory);
    final summary = SafeDiagnosticSummary.capture(
      const ConnectionStatus.disconnected(ConnectionFailure.invalidConfig(_hostile)),
      TargetPlatform.iOS,
    );
    final exports = <String>[];
    final exportArguments = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_shareChannel, (
      call,
    ) async {
      expect(call.method, 'shareFiles');
      final args = call.arguments as Map;
      expect(args['mimeTypes'], ['application/json']);
      expect(args['originWidth'], greaterThan(0));
      expect(args['originHeight'], greaterThan(0));
      exportArguments.add(args.toString());
      for (final path in args['paths'] as List) {
        exports.add(await File(path as String).readAsString());
      }
      // A plugin result can itself contain sensitive platform data.
      return _hostile;
    });
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_shareChannel, null);
      Loggy.initLoggy(logPrinter: const ConsolePrinter());
      await exporter.discard();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SafeDiagnosticsPage(summary: summary, exporter: exporter),
      ),
    );
    expect(find.text('Connection configuration · Disconnected'), findsOneWidget);
    final preview = tester.widget<SelectableText>(find.byKey(const Key('diagnostic-preview'))).data!;
    expect(preview, summary.json);
    expect(exporter.hasFile, isFalse);
    expect(exports, isEmpty);
    expect(find.text('Share file'), findsNothing);

    await tester.runAsync(() async {
      await tester.tap(find.text('Create file'));
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (!exporter.hasFile && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(exporter.hasFile, isTrue);
    expect(find.text('File created: safe-diagnostics.json'), findsOneWidget);
    expect(exports, isEmpty, reason: 'Creating a file must not share it');
    final reportFile = directory
        .listSync(recursive: true)
        .whereType<File>()
        .singleWhere((file) => file.path.endsWith(SafeDiagnosticExport.fileName));
    final saved = reportFile.readAsStringSync();
    expect(saved, preview);

    final shareButton = find.byKey(const Key('diagnostic-share-button'));
    await tester.scrollUntilVisible(shareButton, 200, scrollable: find.byType(Scrollable).first);
    await tester.runAsync(() async {
      await tester.tap(shareButton);
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (exports.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(exports, [preview]);
    expect(find.text('File handed to the selected app.'), findsOneWidget);

    // Positive control proves the real LoggerController fanout is connected.
    final diskLog = await tester.runAsync(() async {
      Loggy('safe-diagnostic-test').info('safe-diagnostic-test-complete');
      filePrinter.dispose();
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (DateTime.now().isBefore(deadline)) {
        if (logFile.existsSync()) {
          final contents = await logFile.readAsString();
          if (contents.contains('safe-diagnostic-test-complete')) return contents;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      throw StateError('Log file did not flush');
    });
    expect(records.text, contains('safe-diagnostic-test-complete'));
    expect(breadcrumbs.text, contains('safe-diagnostic-test-complete'));
    final sinks = {
      'logs': '${records.text}\n$diskLog',
      'breadcrumbs': breadcrumbs.text,
      'in-memory state': summary.toString(),
      'preview': preview,
      'file': saved,
      'export': '${exports.join()}${exportArguments.join()}',
    };
    for (final sink in sinks.entries) {
      expect(sink.value, isNot(contains(_canary)), reason: sink.key);
      expect(sink.value, isNot(contains('private.test')), reason: sink.key);
    }
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox());
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (reportFile.existsSync() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(reportFile.existsSync(), isFalse);
  });

  test('IO and share failures discard raw errors, cancellation is not success', () async {
    final records = _Records();
    final breadcrumbs = _Breadcrumbs();
    Loggy.initLoggy(logPrinter: LoggerController(records, {'sentry': breadcrumbs}));
    addTearDown(() => Loggy.initLoggy(logPrinter: const ConsolePrinter()));
    final summary = SafeDiagnosticSummary.capture(null, TargetPlatform.iOS);
    final failing = SafeDiagnosticExport(temporaryDirectory: () async => throw _Poison());
    expect(await failing.create(summary), isFalse);
    expect(failing.hasFile, isFalse);
    expect(await failing.share(const Rect.fromLTWH(0, 0, 20, 20)), DiagnosticExportResult.unavailable);
    final directory = Directory.systemTemp.createTempSync('diagnostics-errors-');
    final exporter = SafeDiagnosticExport(temporaryDirectory: () async => directory);
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_shareChannel, null);
      await exporter.discard();
      directory.deleteSync(recursive: true);
    });
    expect(await exporter.create(summary), isTrue);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _shareChannel,
      (_) async => '',
    );
    expect(await exporter.share(const Rect.fromLTWH(0, 0, 20, 20)), DiagnosticExportResult.dismissed);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _shareChannel,
      (_) async => throw PlatformException(code: _canary, message: _hostile, details: _hostile),
    );
    expect(await exporter.share(const Rect.fromLTWH(0, 0, 20, 20)), DiagnosticExportResult.failed);
    expect(records.text, isNot(contains(_canary)));
    expect(breadcrumbs.text, isNot(contains(_canary)));
  });
}

class _Poison {
  @override
  String toString() => throw StateError('Sensitive error must never be serialized');
}

class _Records extends LoggyPrinter {
  final records = <LogRecord>[];
  @override
  void onLog(LogRecord record) => records.add(record);
  String get text => records.map((r) => [r.message, r.object, r.error, r.stackTrace].join('\n')).join('\n');
}

class _Breadcrumbs extends _Records {
  @override
  String get text => records.map((r) => [r.toBreadcrumb().toJson(), r.toEvent().toJson()].join('\n')).join('\n');
}
