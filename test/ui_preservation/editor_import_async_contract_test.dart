import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/router/go_router/routing_config_notifier.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/add/add_profile_modal.dart';
import 'package:hiddify/features/profile/add/widgets/loading.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/details/json_editor.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:toastification/toastification.dart';

import '../support/connection_fixtures.dart';
import '../support/profile_settings_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProfileFixture fixture;
  setUp(() async => fixture = await ProfileFixture.create());
  tearDown(() => fixture.dispose());
  testWidgets('real JSON editor preserves draft controller selection and focus across appearance rebuild', (
    tester,
  ) async {
    final changes = <dynamic>[];
    Widget app(Brightness brightness) => MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: JsonEditor(
          key: const ValueKey('editor'),
          json: '{"name":"initial"}',
          editors: const [Editors.text],
          onChanged: changes.add,
        ),
      ),
    );
    await tester.pumpWidget(app(Brightness.light));
    final field = find.byType(TextField).last;
    await tester.tap(field);
    await tester.enterText(field, '{"name":"draft"}');
    final editable = tester.widget<EditableText>(find.byType(EditableText).last);
    final controller = editable.controller;
    final focus = editable.focusNode;
    controller.selection = const TextSelection.collapsed(offset: 8);
    await tester.pumpWidget(app(Brightness.dark));
    final after = tester.widget<EditableText>(find.byType(EditableText).last);
    expect(identical(after.controller, controller), true);
    expect(identical(after.focusNode, focus), true);
    expect(after.focusNode.hasFocus, true);
    expect(after.controller.text, '{"name":"draft"}');
    expect(after.controller.selection.baseOffset, 8);
    await tester.pump(const Duration(milliseconds: 600));
    expect(changes.single, {'name': 'draft'});
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'malformed nonempty manual URL never starts download; closing pending manual import does not cancel baseline',
    (tester) async {
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => fixture.preferences),
          translationsProvider.overrideWith((ref) => AppLocale.en.buildSync()),
          profileRepositoryProvider.overrideWith((ref) => fixture.repository),
        ],
      );
      await c.read(profileRepositoryProvider.future);
      await c.read(translationsProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const ToastificationWrapper(
            child: MaterialApp(
              home: Scaffold(body: SingleChildScrollView(child: AddProfileManual())),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextFormField).at(0), 'Manual');
      await tester.enterText(find.byType(TextFormField).at(1), 'this is not a URL');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(find.text(AppLocale.en.buildSync().pages.profileDetails.form.invalidUrl), findsOneWidget);
      expect(c.read(addProfileNotifierProvider).isLoading, false);
      expect(await tester.runAsync(() => fixture.dao.watchProfilesCount().first), 0);
      await tester.enterText(find.byType(TextFormField).at(1), 'https://example.invalid/pending');
      late Future<void> operation;
      await tester.runAsync(() async {
        fixture.http.pending = Completer<void>();
        fixture.http.entered = Completer<void>();
        operation = c
            .read(addProfileNotifierProvider.notifier)
            .addManual(
              url: 'https://example.invalid/pending',
              userOverride: const UserOverride(name: 'Manual'),
            );
        await fixture.http.entered!.future.timeout(const Duration(seconds: 3));
      });
      expect(c.read(addProfileNotifierProvider).isLoading, true);
      await tester.tap(find.byIcon(Icons.close));
      expect(c.read(addProfilePageNotifierProvider), AddProfilePages.options);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const ToastificationWrapper(child: MaterialApp(home: Scaffold())),
        ),
      );
      await tester.runAsync(() async {
        fixture.http.pending!.complete();
        await operation.timeout(const Duration(seconds: 3));
        expect(await fixture.dao.watchProfilesCount().first, 1);
      });
      expect(c.read(addProfileNotifierProvider).hasError, false);
      toastification.dismissAll();
      c.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets('real manual loading Cancel resets provider but baseline download still commits', (tester) async {
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => fixture.preferences),
        translationsProvider.overrideWith((ref) => AppLocale.en.buildSync()),
        profileRepositoryProvider.overrideWith((ref) => fixture.repository),
      ],
    );
    await c.read(profileRepositoryProvider.future);
    await c.read(translationsProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const ToastificationWrapper(
          child: MaterialApp(home: Scaffold(body: ProfileLoading())),
        ),
      ),
    );
    late Future<Object?> outcome;
    await tester.runAsync(() async {
      fixture.http.pending = Completer<void>();
      fixture.http.entered = Completer<void>();
      outcome = c
          .read(addProfileNotifierProvider.notifier)
          .addManual(
            url: 'https://example.invalid/cancel',
            userOverride: const UserOverride(name: 'Cancel fixture'),
          )
          .then<Object?>((_) => null, onError: (Object e) => e);
      await fixture.http.entered!.future;
    });
    expect(c.read(addProfileNotifierProvider).isLoading, true);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(c.read(addProfileNotifierProvider).isLoading, false);
    await tester.runAsync(() async {
      fixture.http.pending!.complete();
      final result = await outcome;
      // Baseline addManual does not supply the notifier cancellation token.
      // Preserve the actual observed database side effect; do not repair it here.
      expect(await fixture.dao.watchProfilesCount().first, 1);
      expect(result, isNull);
    });
    toastification.dismissAll();
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('real import redirect forwards URL once to sheet boundary and returns home', (tester) async {
    await fixture.preferences.setBool('intro_completed', true);
    final events = <String>[];
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => fixture.preferences),
        isMobileBreakpointProvider.overrideWith((ref) => true),
        bottomSheetsNotifierProvider.overrideWith(() => FixtureSheets(events)),
      ],
    );
    await c.read(sharedPreferencesProvider.future);
    final redirect = c.read(routingConfigNotifierProvider).redirect;
    const url = 'https://example.invalid/import#Profile';
    final router = GoRouter(
      initialLocation: '/home?url=${Uri.encodeComponent(url)}',
      redirect: redirect,
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/intro',
          builder: (_, _) => const Scaffold(body: Text('intro')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(events, ['add-profile:$url']);
    expect(router.routeInformationProvider.value.uri.toString(), '/home');
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    c.dispose();
  });

  for (final active in [true, false]) {
    testWidgets('real UpdateProfileNotifier waits for download and reconnects only matching active profile ($active)', (
      tester,
    ) async {
      await tester.runAsync(() => fixture.repository.upsertRemote('https://example.invalid/update').run());
      final profile =
          (await tester.runAsync(() => fixture.repository.watchActiveProfile().first))!.getOrElse((e) => throw e)!
              as RemoteProfileEntity;
      final events = <String>[];
      final spy = ButtonConnectionSpy(const AsyncData(Connected()), events);
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => fixture.preferences),
          translationsProvider.overrideWith((ref) => AppLocale.en.buildSync()),
          profileRepositoryProvider.overrideWith((ref) => fixture.repository),
          activeProfileProvider.overrideWith(() => FixtureProfile(active ? profile : null)),
          connectionNotifierProvider.overrideWith(() => spy),
        ],
      );
      await c.read(profileRepositoryProvider.future);
      await c.read(translationsProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const ToastificationWrapper(child: MaterialApp(home: Scaffold())),
        ),
      );
      late Future<void> update;
      await tester.runAsync(() async {
        fixture.http.pending = Completer<void>();
        fixture.http.entered = Completer<void>();
        update = c.read(updateProfileNotifierProvider(profile.id).notifier).updateProfile(profile);
        await fixture.http.entered!.future.timeout(const Duration(seconds: 3));
      });
      expect(c.read(updateProfileNotifierProvider(profile.id)).isLoading, true);
      expect(events, isEmpty);
      await tester.runAsync(() async {
        fixture.http.pending!.complete();
        await update;
      });
      expect(c.read(updateProfileNotifierProvider(profile.id)).hasError, false);
      expect(events, active ? ['reconnect'] : isEmpty);
      if (active) expect(spy.reconnectedProfile!.id, profile.id);
      toastification.dismissAll();
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    });
  }
}
