import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
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

  for (final outcome in [_SaveOutcome.falseResult, _SaveOutcome.exception]) {
    testWidgets('keeps the dirty draft when persistence returns ${outcome.name}', (tester) async {
      final preferences = _TestPreferences({'woman_in_red_profile_email': 'old@example.com'}, outcome: outcome);
      final harness = await _IdentityHarness.pump(tester, preferences);

      await harness.enterEmail(tester, 'draft@example.com');
      await harness.save(tester);

      expect(find.text('Saved'), findsNothing);
      expect(find.text('Could not save the profile. Try again.'), findsOneWidget);
      expect(harness.emailField(tester).controller!.text, 'draft@example.com');
      expect(harness.container.read(identityProfileProvider).email, 'old@example.com');

      await harness.enterEmail(tester, 'retry@example.com');
      expect(find.text('Could not save the profile. Try again.'), findsNothing);
      expect(harness.emailField(tester).controller!.text, 'retry@example.com');
    });
  }
}

enum _SaveOutcome { success, falseResult, exception }

class _IdentityHarness {
  _IdentityHarness(this.container);

  final ProviderContainer container;

  static Future<_IdentityHarness> pump(WidgetTester tester, _TestPreferences preferences) async {
    final translations = await AppLocale.en.build();
    final container = ProviderContainer(
      overrides: [
        translationsProvider.overrideWith((ref) => translations),
        identityProfileProvider.overrideWith((ref) => IdentityProfileNotifier(IdentityProfileStore(preferences))),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          routes: {
            '/': (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).pushNamed('/identity'),
                child: const Text('Open profile'),
              ),
            ),
            '/identity': (context) => const IdentityProfilePage(),
          },
        ),
      ),
    );
    await tester.tap(find.text('Open profile'));
    await tester.pumpAndSettle();
    return _IdentityHarness(container);
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
