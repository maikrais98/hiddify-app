import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/logger/custom_logger.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/features/profile/add/add_profile_modal.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:loggy/loggy.dart';

class _RecordingDialogs extends DialogNotifier {
  String? message;
  String? positiveButtonText;

  @override
  void build() {}

  @override
  Future<bool> showConfirmation({
    required String title,
    required String message,
    IconData? icon,
    String? positiveBtnTxt,
  }) async {
    this.message = message;
    positiveButtonText = positiveBtnTxt;
    return false;
  }
}

class _RecordingLogPrinter extends LoggyPrinter {
  final records = <LogRecord>[];

  @override
  void onLog(LogRecord record) => records.add(record);

  String get serialized => records.map((record) => record.toString()).join('\n');
}

void main() {
  Future<ProviderContainer> createContainer(_RecordingDialogs dialogs) async {
    final translations = await AppLocale.en.build();
    final container = ProviderContainer(
      overrides: [
        translationsProvider.overrideWith((ref) => translations),
        dialogNotifierProvider.overrideWith(() => dialogs),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('deep-link confirmation shows the nested source hostname and explicit import action', () async {
    final dialogs = _RecordingDialogs();
    final container = await createContainer(dialogs);

    await container
        .read(bottomSheetsNotifierProvider.notifier)
        .showAddProfile(
          url: 'hiddify://import?url=https%3A%2F%2Faccess.example.com%2Fsubscription%3Fclient%3Dalice',
          triggeredByDeepLink: true,
        );

    expect(dialogs.message, contains('access.example.com'));
    expect(dialogs.message, isNot(contains('/subscription')));
    expect(dialogs.message, isNot(contains('client=alice')));
    expect(dialogs.positiveButtonText, 'Import');
  });

  test('malformed nested source is represented without exposing its contents', () async {
    const malformed = 'not a valid source secret-canary';
    final dialogs = _RecordingDialogs();
    final container = await createContainer(dialogs);

    await container
        .read(bottomSheetsNotifierProvider.notifier)
        .showAddProfile(url: 'hiddify://import?url=${Uri.encodeQueryComponent(malformed)}', triggeredByDeepLink: true);

    expect(dialogs.message, contains('Unknown'));
    expect(dialogs.message, isNot(contains(malformed)));
    expect(dialogs.message, isNot(contains('secret-canary')));
  });

  test('secret query data is absent from confirmation text and logs', () async {
    const canary = 'vpn-import-secret-7f1d2b';
    final logs = _RecordingLogPrinter();
    Loggy.initLoggy(logPrinter: logs);
    addTearDown(() => Loggy.initLoggy(logPrinter: const ConsolePrinter()));
    final dialogs = _RecordingDialogs();
    final container = await createContainer(dialogs);

    await container
        .read(bottomSheetsNotifierProvider.notifier)
        .showAddProfile(
          url: 'hiddify://import?url=https%3A%2F%2Fsecure.example.com%2Fsub%3Ftoken%3D$canary%26user%3Dalice',
          triggeredByDeepLink: true,
        );

    expect(dialogs.message, contains('secure.example.com'));
    expect(dialogs.message, isNot(contains(canary)));
    expect(dialogs.message, isNot(contains('token=')));
    expect(logs.serialized, isNot(contains(canary)));
  });

  testWidgets('canceling deep-link confirmation does not open profile import', (tester) async {
    final dialogs = _RecordingDialogs();
    final container = await createContainer(dialogs);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: rootNavKey,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );

    await container
        .read(bottomSheetsNotifierProvider.notifier)
        .showAddProfile(
          url: 'hiddify://import?url=https%3A%2F%2Faccess.example.com%2Fsubscription',
          triggeredByDeepLink: true,
        );
    await tester.pump();

    expect(find.byType(AddProfileModal), findsNothing);
  });
}
