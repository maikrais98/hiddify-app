import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_glass.dart';
import 'package:hiddify/features/about/widget/about_page.dart';
import 'package:hiddify/features/app_update/notifier/app_update_notifier.dart';
import 'package:hiddify/features/diagnostics/diagnostic_providers.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_journal.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostics_page.dart';
import 'package:hiddify/features/profile/details/profile_details_notifier.dart';
import 'package:hiddify/features/profile/details/profile_details_page.dart';
import 'package:hiddify/features/profile/details/profile_details_state.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../support/connection_fixtures.dart';
import '../support/home_fixture.dart';
import '../support/surface_fixtures.dart';

Widget _openPage(Widget page, {bool active = true, bool fullscreenDialog = false}) => Builder(
  builder: (context) => TextButton(
    onPressed: () => Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: fullscreenDialog,
        builder: (context) => active ? Theme(data: BlizzardTheme.from(Theme.of(context)), child: page) : page,
      ),
    ),
    child: const Text('Open page'),
  ),
);

void main() {
  for (final screen in ['about', 'diagnostics', 'profile']) {
    testWidgets('$screen uses shared glass navigation and one action group', (tester) async {
      final journal = SafeDiagnosticJournal();
      addTearDown(journal.dispose);
      final page = switch (screen) {
        'about' => const AboutPage(),
        'diagnostics' => const SafeDiagnosticsPage(),
        _ => ProfileDetailsPage(id: connectionProfile.id),
      };
      final fixture = await mountHomeFixture(
        tester,
        child: _openPage(page),
        extraOverrides: [
          appUpdateNotifierProvider.overrideWith(SurfaceAppUpdate.new),
          safeDiagnosticJournalProvider.overrideWithValue(journal),
          profileDetailsNotifierProvider(connectionProfile.id).overrideWith(
            () => SurfaceDetails(ProfileDetailsState(
              loadingState: const AsyncData(null),
              profile: connectionProfile,
              configContent: 'outbound = synthetic',
              isDetailsChanged: false,
            )),
          ),
        ],
      );
      await tester.tap(find.text('Open page'));
      await tester.pumpAndSettle();
      final toolbar = find.byType(AppBar);
      expect(find.descendant(of: toolbar, matching: find.byType(BlizzardGlass)), findsNWidgets(2));
      final back = find.byType(BackButton);
      expect(back, findsOneWidget);
      expect(tester.getSize(back).shortestSide, greaterThanOrEqualTo(44));
      for (final control in find.descendant(
        of: toolbar,
        matching: find.byWidgetPredicate((widget) => widget is IconButton || widget is TextButton),
      ).evaluate()) {
        expect(find.ancestor(of: find.byWidget(control.widget), matching: find.byType(BlizzardGlass)), findsOneWidget);
      }
      if (screen == 'profile') {
        expect(tester.widget<TextButton>(find.byWidgetPredicate((widget) => widget is TextButton).last).onPressed, isNull);
      }
      expect(tester.takeException(), isNull);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.text('Open page'), findsOneWidget);
      await fixture.close(tester);
    });
  }

  testWidgets('fullscreen navigation retains the standard close action', (tester) async {
    final fixture = await mountHomeFixture(
      tester,
      child: _openPage(const AboutPage(), fullscreenDialog: true),
      extraOverrides: [appUpdateNotifierProvider.overrideWith(SurfaceAppUpdate.new)],
    );
    await tester.tap(find.text('Open page'));
    await tester.pumpAndSettle();
    final close = find.byType(CloseButton);
    expect(close, findsOneWidget);
    expect(find.ancestor(of: close, matching: find.byType(BlizzardGlass)), findsOneWidget);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.text('Open page'), findsOneWidget);
    await fixture.close(tester);
  });

  for (final loading in [true, false]) {
    testWidgets('profile ${loading ? 'loading' : 'error'} keeps glass navigation', (tester) async {
      final fixture = await mountHomeFixture(
        tester,
        child: _openPage(ProfileDetailsPage(id: connectionProfile.id)),
        extraOverrides: [
          profileDetailsNotifierProvider(connectionProfile.id).overrideWith(
            () => loading ? _LoadingDetails() : _ErrorDetails(),
          ),
        ],
      );
      await tester.tap(find.text('Open page'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.descendant(of: find.byType(AppBar), matching: find.byType(BlizzardGlass)), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Open page'), findsOneWidget);
      await fixture.close(tester);
    });
  }

  testWidgets('legacy navigation retains its original controls without glass', (tester) async {
    final fixture = await mountHomeFixture(
      tester,
      mode: AppThemeMode.light,
      child: _openPage(const AboutPage(), active: false),
      extraOverrides: [appUpdateNotifierProvider.overrideWith(SurfaceAppUpdate.new)],
    );
    await tester.tap(find.text('Open page'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(AppBar), matching: find.byType(BlizzardGlass)), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Open page'), findsOneWidget);
    await fixture.close(tester);
  });
}

class _LoadingDetails extends ProfileDetailsNotifier {
  @override
  Future<ProfileDetailsState> build(String id) => Completer<ProfileDetailsState>().future;
}

class _ErrorDetails extends ProfileDetailsNotifier {
  @override
  Future<ProfileDetailsState> build(String id) async => throw StateError('Synthetic profile error');
}
