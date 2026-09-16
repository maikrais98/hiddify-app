import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/adaptive_layout/my_adaptive_layout.dart';
import 'package:hiddify/core/router/unsaved_changes_guard.dart';
import 'package:hiddify/features/identity/data/identity_data_providers.dart';
import 'package:hiddify/features/identity/data/identity_profile_store.dart';
import 'package:hiddify/features/identity/overview/identity_profile_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('save then edit clears Saved and guards the dirty draft on exit', (tester) async {
    final harness = await _IdentityHarness.pump(
      tester,
      _TestPreferences({'woman_in_red_profile_email': 'old@example.com'}),
    );

    await harness.enterEmail(tester, 'saved@example.com');
    await harness.save(tester);
    expect(find.text('Saved'), findsOneWidget);

    await harness.enterEmail(tester, 'draft@example.com');
    expect(find.text('Saved'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Save changes?'), findsOneWidget);
    expect(find.byType(IdentityProfilePage), findsOneWidget);

    await tester.tap(find.text('Continue editing'));
    await tester.pumpAndSettle();
    expect(find.byType(IdentityProfilePage), findsOneWidget);
    expect(harness.emailField(tester).controller!.text, 'draft@example.com');

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(IdentityProfilePage), findsNothing);
  });

  testWidgets('an edit during save is not overwritten or marked Saved by stale success', (tester) async {
    final pendingSave = Completer<bool>();
    final preferences = _TestPreferences({'woman_in_red_profile_email': 'old@example.com'}, pendingSave: pendingSave);
    final harness = await _IdentityHarness.pump(tester, preferences);

    await harness.enterEmail(tester, 'saving@example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await harness.enterEmail(tester, 'new-draft@example.com');
    pendingSave.complete(true);
    await tester.pumpAndSettle();

    expect(harness.emailField(tester).controller!.text, 'new-draft@example.com');
    expect(find.text('Saved'), findsNothing);
    expect(harness.container.read(identityProfileProvider).email, 'saving@example.com');
  });

  testWidgets('discard exit waits for an in-flight save before disposing the form', (tester) async {
    final pendingSave = Completer<bool>();
    final preferences = _TestPreferences({'woman_in_red_profile_email': 'old@example.com'}, pendingSave: pendingSave);
    final harness = await _IdentityHarness.pump(tester, preferences);

    await harness.enterEmail(tester, 'saving@example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    harness.router.go('/deeplink');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Discard'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(IdentityProfilePage), findsOneWidget);
    pendingSave.complete(true);
    await tester.pumpAndSettle();

    expect(find.text('Deeplink destination'), findsOneWidget);
    expect(preferences.getString('woman_in_red_profile_email'), 'saving@example.com');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an edit that normalizes to the saved email is still treated as a draft', (tester) async {
    final harness = await _IdentityHarness.pump(
      tester,
      _TestPreferences({'woman_in_red_profile_email': 'saved@example.com'}),
    );

    await harness.enterEmail(tester, 'saved@example.com');
    await harness.save(tester);
    expect(find.text('Saved'), findsOneWidget);

    await harness.enterEmail(tester, 'saved@example.com ');
    expect(find.text('Saved'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Save changes?'), findsOneWidget);
  });

  testWidgets('guards a dirty draft when tab navigation replaces the route', (tester) async {
    final harness = await _IdentityHarness.pump(
      tester,
      _TestPreferences({'woman_in_red_profile_email': 'old@example.com'}),
    );

    await harness.enterEmail(tester, 'draft@example.com');
    await harness.selectSettingsTab(tester);
    await tester.pumpAndSettle();

    expect(find.text('Save changes?'), findsOneWidget);
    expect(find.byType(IdentityProfilePage), findsOneWidget);
    expect(find.text('Settings destination'), findsNothing);

    await tester.tap(find.text('Continue editing'));
    await tester.pumpAndSettle();
    expect(harness.router.state.uri.path, '/home/profile');
  });

  testWidgets('guards a dirty draft when a deeplink replaces the route', (tester) async {
    final harness = await _IdentityHarness.pump(
      tester,
      _TestPreferences({'woman_in_red_profile_email': 'old@example.com'}),
    );

    await harness.enterEmail(tester, 'draft@example.com');
    harness.router.go('/deeplink');
    await tester.pumpAndSettle();

    expect(find.text('Save changes?'), findsOneWidget);
    expect(find.byType(IdentityProfilePage), findsOneWidget);
    expect(find.text('Deeplink destination'), findsNothing);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Deeplink destination'), findsOneWidget);
    expect(harness.preferences.getString('woman_in_red_profile_email'), 'old@example.com');
  });

  testWidgets('saves a dirty draft before changing tabs', (tester) async {
    final harness = await _IdentityHarness.pump(
      tester,
      _TestPreferences({'woman_in_red_profile_email': 'old@example.com'}),
    );

    await harness.enterEmail(tester, 'saved@example.com');
    await harness.selectSettingsTab(tester);
    await tester.pumpAndSettle();
    expect(find.text('Save changes?'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Save')));
    await tester.pumpAndSettle();

    expect(find.text('Settings destination'), findsOneWidget);
    expect(harness.preferences.getString('woman_in_red_profile_email'), 'saved@example.com');
  });

  testWidgets('keeps the route and dirty draft when exit save fails, then allows retry', (tester) async {
    final harness = await _IdentityHarness.pump(
      tester,
      _TestPreferences({'woman_in_red_profile_email': 'old@example.com'}, outcome: _SaveOutcome.falseResult),
    );

    await harness.enterEmail(tester, 'draft@example.com');
    harness.router.go('/deeplink');
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Save')));
    await tester.pumpAndSettle();

    expect(find.byType(IdentityProfilePage), findsOneWidget);
    expect(find.text('Could not save personal data. Try again.'), findsOneWidget);
    expect(harness.emailField(tester).controller!.text, 'draft@example.com');

    harness.router.go('/deeplink');
    await tester.pumpAndSettle();
    expect(find.text('Save changes?'), findsOneWidget);
    await tester.tap(find.text('Continue editing'));
    await tester.pumpAndSettle();
    expect(find.byType(IdentityProfilePage), findsOneWidget);
  });

  testWidgets('coalesces repeated tab actions into one leave dialog', (tester) async {
    final harness = await _IdentityHarness.pump(
      tester,
      _TestPreferences({'woman_in_red_profile_email': 'old@example.com'}),
    );

    await harness.enterEmail(tester, 'draft@example.com');
    await harness.selectSettingsTab(tester, settle: false);
    await harness.selectSettingsTab(tester, settle: false);
    await tester.pumpAndSettle();

    expect(find.text('Save changes?'), findsOneWidget);
    await tester.tap(find.text('Continue editing'));
    await tester.pumpAndSettle();
    expect(harness.router.state.uri.path, '/home/profile');
  });

  testWidgets('does not interrupt external navigation for a clean form', (tester) async {
    final harness = await _IdentityHarness.pump(
      tester,
      _TestPreferences({'woman_in_red_profile_email': 'old@example.com'}),
    );

    harness.router.go('/deeplink');
    await tester.pumpAndSettle();

    expect(find.text('Save changes?'), findsNothing);
    expect(find.byType(IdentityProfilePage), findsNothing);
    expect(find.text('Deeplink destination'), findsOneWidget);
  });

  testWidgets('does not interrupt tab navigation for a clean form', (tester) async {
    final harness = await _IdentityHarness.pump(
      tester,
      _TestPreferences({'woman_in_red_profile_email': 'old@example.com'}),
    );

    await harness.selectSettingsTab(tester);
    await tester.pumpAndSettle();

    expect(find.text('Save changes?'), findsNothing);
    expect(find.text('Settings destination'), findsOneWidget);
  });

  for (final outcome in [_SaveOutcome.falseResult, _SaveOutcome.exception]) {
    testWidgets('keeps the dirty draft when persistence returns ${outcome.name}', (tester) async {
      final preferences = _TestPreferences({'woman_in_red_profile_email': 'old@example.com'}, outcome: outcome);
      final harness = await _IdentityHarness.pump(tester, preferences);

      await harness.enterEmail(tester, 'draft@example.com');
      await harness.save(tester);

      expect(find.text('Saved'), findsNothing);
      expect(find.text('Could not save personal data. Try again.'), findsOneWidget);
      expect(harness.emailField(tester).controller!.text, 'draft@example.com');
      expect(harness.container.read(identityProfileProvider).email, 'old@example.com');

      await harness.enterEmail(tester, 'retry@example.com');
      expect(find.text('Could not save personal data. Try again.'), findsNothing);
      expect(harness.emailField(tester).controller!.text, 'retry@example.com');
    });
  }
}

enum _SaveOutcome { success, falseResult, exception }

class _IdentityHarness {
  _IdentityHarness(this.container, this.router, this.preferences);

  final ProviderContainer container;
  final GoRouter router;
  final _TestPreferences preferences;

  static Future<_IdentityHarness> pump(WidgetTester tester, _TestPreferences preferences) async {
    final translations = await AppLocale.en.build();
    final container = ProviderContainer(
      overrides: [
        translationsProvider.overrideWith((ref) => translations),
        identityProfileProvider.overrideWith((ref) => IdentityProfileNotifier(IdentityProfileStore(preferences))),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              MyAdaptiveLayout(navigationShell: navigationShell, isMobileBreakpoint: false, showProfilesAction: false),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  name: 'home',
                  path: '/home',
                  builder: (context, state) => Scaffold(
                    body: TextButton(onPressed: () => context.push('/home/profile'), child: const Text('Open profile')),
                  ),
                  routes: [
                    GoRoute(
                      path: 'profile',
                      builder: (context, state) => const IdentityProfilePage(),
                      onExit: (context, state) => container.read(unsavedChangesGuardProvider).canLeave(),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  name: 'settings',
                  path: '/settings',
                  builder: (context, state) => const Text('Settings destination'),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(name: 'logs', path: '/logs', builder: (context, state) => const Text('Logs destination')),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(name: 'about', path: '/about', builder: (context, state) => const Text('About destination')),
              ],
            ),
          ],
        ),
        GoRoute(path: '/deeplink', builder: (context, state) => const Text('Deeplink destination')),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('Open profile'));
    await tester.pumpAndSettle();
    return _IdentityHarness(container, router, preferences);
  }

  TextField emailField(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField));

  Future<void> enterEmail(WidgetTester tester, String email) async {
    await tester.enterText(find.byType(TextField), email);
    await tester.pump();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
  }

  Future<void> selectSettingsTab(WidgetTester tester, {bool settle = true}) async {
    tester.widget<NavigationRail>(find.byType(NavigationRail)).onDestinationSelected!(1);
    if (settle) await tester.pump();
  }
}

class _TestPreferences implements SharedPreferences {
  _TestPreferences(this.values, {this.outcome = _SaveOutcome.success, this.pendingSave});

  final Map<String, Object> values;
  final _SaveOutcome outcome;
  final Completer<bool>? pendingSave;

  @override
  String? getString(String key) => values[key] as String?;

  @override
  Future<bool> setString(String key, String value) async {
    final persisted = pendingSave == null ? await _persist() : await pendingSave!.future;
    if (persisted) values[key] = value;
    return persisted;
  }

  Future<bool> _persist() async => switch (outcome) {
    _SaveOutcome.success => true,
    _SaveOutcome.falseResult => false,
    _SaveOutcome.exception => throw StateError('persistence failed'),
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
