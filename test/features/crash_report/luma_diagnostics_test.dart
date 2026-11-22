import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/features/app_update/model/remote_version_entity.dart';
import 'package:hiddify/features/crash_report/data/diagnostics_sender.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets('Luma diagnostics, Telegram and GitHub updates have no dialog routes', (tester) async {
    expect(Environment.sentryDSN, isEmpty);
    expect(DiagnosticsSender.available, isFalse);
    expect(Release.general.allowCustomUpdateChecker, isFalse);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(MaterialApp(navigatorKey: rootNavKey, home: const SizedBox()));
    final navigator = rootNavKey.currentState!;
    final dialogs = container.read(dialogNotifierProvider.notifier);
    final attempts = Future.wait([
      dialogs.showCrashReport(),
      dialogs.showReportProblem(),
      dialogs.showTelegramChannel(),
      dialogs.showNewVersion(
        currentVersion: '1.0.0',
        newVersion: RemoteVersionEntity(
          version: '2.0.0',
          buildNumber: '50',
          releaseTag: 'v2.0.0',
          preRelease: true,
          url: 'https://example.invalid',
          publishedAt: DateTime.utc(2026),
          flavor: Environment.dev,
        ),
        canIgnore: true,
      ),
    ]);
    await tester.pump();
    expect(navigator.canPop(), isFalse);
    await attempts;
  });
}
