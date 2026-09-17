import 'dart:async';
import 'dart:ui' show SemanticsAction;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/add/add_profile_modal.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Repo implements ProfileRepository {
  int calls = 0;
  ProfileFailure? failure;
  Completer<void>? pending;
  Completer<void>? pendingParsing;
  CancelToken? token;
  @override
  TaskEither<ProfileFailure, Unit> upsertRemote(
    String url, {
    UserOverride? userOverride,
    CancelToken? cancelToken,
    void Function()? onParsing,
  }) => TaskEither(() async {
    calls++;
    token = cancelToken;
    await pending?.future;
    onParsing?.call();
    await pendingParsing?.future;
    return failure == null ? right(unit) : left(failure!);
  });
  @override
  TaskEither<ProfileFailure, Unit> addLocal(String content, {UserOverride? userOverride, CancelToken? cancelToken}) =>
      TaskEither.left(const ProfileFailure.invalidConfig());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<ProviderContainer> setup(_Repo repo) async {
    final c = ProviderContainer(overrides: [profileRepositoryProvider.overrideWith((ref) => Future.value(repo))]);
    addTearDown(c.dispose);
    c.listen(addProfileNotifierProvider, (_, _) {});
    c.listen(importPhaseProvider, (_, _) {});
    await c.read(profileRepositoryProvider.future);
    return c;
  }

  test('manual HTTPS transitions through validation fetch parse success without notification dependencies', () async {
    final c = await setup(_Repo());
    final phases = <ImportPhase>[];
    c.listen(importPhaseProvider, (_, next) => phases.add(next));
    await c
        .read(addProfileNotifierProvider.notifier)
        .addManual(
          url: 'https://example.com/sub',
          userOverride: const UserOverride(name: 'Test'),
        );
    expect(phases, [ImportPhase.validating, ImportPhase.fetching, ImportPhase.parsing, ImportPhase.success]);
  });
  test('invalid and unsafe input recover to idle without a request', () async {
    final repo = _Repo();
    final c = await setup(repo);
    final n = c.read(addProfileNotifierProvider.notifier);
    await n.addClipboard('');
    expect(c.read(importPhaseProvider), ImportPhase.invalid);
    n.reset();
    expect(c.read(importPhaseProvider), ImportPhase.idle);
    await n.addClipboard('http://example.com/sub');
    expect(c.read(importPhaseProvider), ImportPhase.unsafe);
    expect(repo.calls, 0);
  });
  test('network failure can retry successfully', () async {
    final repo = _Repo()
      ..failure = ProfileFailure.unexpected(
        DioException(requestOptions: RequestOptions(), type: DioExceptionType.connectionTimeout),
      );
    final c = await setup(repo);
    final n = c.read(addProfileNotifierProvider.notifier);
    await n.addClipboard('https://example.com/sub');
    expect(c.read(importPhaseProvider), ImportPhase.network);
    repo.failure = null;
    await n.retry();
    expect(c.read(importPhaseProvider), ImportPhase.success);
    expect(repo.calls, 2);
  });
  test('cancel cancels request and rejects late completion; duplicate submission ignored', () async {
    final repo = _Repo()..pending = Completer<void>();
    final c = await setup(repo);
    final n = c.read(addProfileNotifierProvider.notifier);
    final first = n.addClipboard('https://example.com/sub');
    await n.addClipboard('https://example.com/sub');
    expect(repo.calls, 1);
    n.cancel();
    expect(repo.token!.isCancelled, true);
    repo.pending!.complete();
    await first;
    expect(c.read(importPhaseProvider), ImportPhase.cancel);
    n.reset();
    expect(c.read(importPhaseProvider), ImportPhase.idle);
  });
  test('cancel after parsing begins does not suppress successful completion', () async {
    final repo = _Repo()..pendingParsing = Completer<void>();
    final c = await setup(repo);
    final notifier = c.read(addProfileNotifierProvider.notifier);
    final operation = notifier.addClipboard('https://example.com/sub');
    await Future<void>.delayed(Duration.zero);
    expect(c.read(importPhaseProvider), ImportPhase.parsing);
    notifier.cancel();
    expect(c.read(importPhaseProvider), ImportPhase.parsing);
    expect(repo.token!.isCancelled, false);
    repo.pendingParsing!.complete();
    await operation;
    expect(c.read(importPhaseProvider), ImportPhase.success);
    notifier.cancel();
    expect(c.read(importPhaseProvider), ImportPhase.success);
  });

  testWidgets('parsing does not offer cancellation after commit begins', (tester) async {
    final t = await AppLocale.en.build();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [translationsProvider.overrideWith((ref) => t)],
        child: const MaterialApp(
          home: Scaffold(body: ImportOutcome(phase: ImportPhase.parsing)),
        ),
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('modal keeps import alive across frames without an external provider listener', (tester) async {
    final repo = _Repo()..pending = Completer<void>();
    final t = await AppLocale.en.build();
    final c = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith((ref) => Future.value(repo)),
        translationsProvider.overrideWith((ref) => t),
      ],
    );
    addTearDown(c.dispose);
    await c.read(profileRepositoryProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          home: Scaffold(body: AddProfileModal(url: 'https://example.com/sub')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(repo.token!.isCancelled, false);
    expect(find.byKey(const ValueKey('import_fetching')), findsOneWidget);
    repo.pending!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('Connect'), findsOneWidget);
  });
  testWidgets('invalid configuration keeps its error type without technical details', (tester) async {
    final repo = _Repo()..failure = const ProfileFailure.invalidConfig('private config content');
    final t = await AppLocale.en.build();
    final c = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith((ref) => Future.value(repo)),
        translationsProvider.overrideWith((ref) => t),
      ],
    );
    addTearDown(c.dispose);
    await c.read(profileRepositoryProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          home: Scaffold(body: AddProfileModal(url: 'https://example.com/sub')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(c.read(importPhaseProvider), ImportPhase.invalid);
    expect(find.text(t.errors.profiles.invalidConfig), findsOneWidget);
    expect(find.text(t.errors.profiles.invalidUrl), findsNothing);
    expect(find.textContaining('private config content'), findsNothing);
  });

  testWidgets('dismissing during parsing does not cancel storage commit', (tester) async {
    final repo = _Repo()..pendingParsing = Completer<void>();
    final t = await AppLocale.en.build();
    final c = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith((ref) => Future.value(repo)),
        translationsProvider.overrideWith((ref) => t),
      ],
    );
    addTearDown(c.dispose);
    await c.read(profileRepositoryProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          home: Scaffold(body: AddProfileModal(url: 'https://example.com/sub')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(c.read(importPhaseProvider), ImportPhase.parsing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(repo.token!.isCancelled, false);
    repo.pendingParsing!.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Connect invokes the connection seam once', (tester) async {
    final t = await AppLocale.en.build();
    final connection = _ConnectRecorder();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: "/",
          builder: (_, _) => const Scaffold(body: ImportOutcome(phase: ImportPhase.success)),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWith((ref) => t),
          connectionNotifierProvider.overrideWith(() => connection),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(connection.calls, 1);
  });

  testWidgets('each result stays inline with its next action', (tester) async {
    final t = await AppLocale.en.build();
    for (final phase in [
      ImportPhase.success,
      ImportPhase.invalid,
      ImportPhase.network,
      ImportPhase.unsafe,
      ImportPhase.cancel,
    ]) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [translationsProvider.overrideWith((ref) => t)],
          child: MaterialApp(
            home: Scaffold(body: ImportOutcome(phase: phase)),
          ),
        ),
      );
      expect(find.byKey(ValueKey('import_${phase.name}')), findsOneWidget);
      expect(find.text(phase == ImportPhase.success ? 'Connect' : 'Import'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    }
  });

  testWidgets('manual import back control has a localized accessible name and returns to options', (tester) async {
    for (final testCase in [
      (locale: AppLocale.en, label: 'Back: Add access'),
      (locale: AppLocale.ru, label: 'Назад: Добавить доступ'),
    ]) {
      final repo = _Repo();
      final t = await tester.runAsync(testCase.locale.build);
      final container = ProviderContainer(
        overrides: [
          profileRepositoryProvider.overrideWith((ref) => Future.value(repo)),
          translationsProvider.overrideWith((ref) => t!),
        ],
      );
      addTearDown(container.dispose);
      await container.read(profileRepositoryProvider.future);
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: testCase.locale.flutterLocale,
            supportedLocales: const [Locale('en'), Locale('ru')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const Scaffold(body: AddProfileModal()),
          ),
        ),
      );
      container.read(addProfilePageNotifierProvider.notifier).goManual();
      await tester.pump();

      final backToOptions = find.semantics.byPredicate(
        (node) => node.tooltip == testCase.label && node.getSemanticsData().hasAction(SemanticsAction.tap),
      );
      expect(backToOptions, findsOneWidget);
      tester.semantics.tap(backToOptions);
      await tester.pump();

      expect(container.read(addProfilePageNotifierProvider), AddProfilePages.options);
      expect(find.byKey(const ValueKey('add_manually_button')), findsOneWidget);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  Future<void> openManualImportRoute(
    WidgetTester tester,
    _Repo repo, {
    required Size size,
    required double textScale,
    double keyboardInset = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final t = await AppLocale.en.build();
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith((ref) => Future.value(repo)),
        translationsProvider.overrideWith((ref) => t),
      ],
    );
    addTearDown(container.dispose);
    await container.read(profileRepositoryProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              viewInsets: EdgeInsets.only(bottom: keyboardInset),
            ),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => Navigator.of(context).push<void>(
                  ModalBottomSheetRoute<void>(
                    constraints: BottomSheetConst.boxConstraints,
                    isScrollControlled: true,
                    builder: (context) => const ThemedBottomSheetSurface(child: SafeArea(child: AddProfileManual())),
                  ),
                ),
                child: const Text('Open manual import'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open manual import'));
    await tester.pumpAndSettle();
  }

  testWidgets('manual import stays actionable at 200 percent text scale', (tester) async {
    final repo = _Repo();
    await openManualImportRoute(tester, repo, size: const Size(320, 568), textScale: 2);

    expect(tester.takeException(), isNull);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Test access');
    await tester.enterText(fields.at(1), 'https://example.com/sub');
    final submit = find.widgetWithText(FilledButton, 'Add');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(repo.calls, 1);
  });

  testWidgets('manual import stays actionable above the landscape keyboard', (tester) async {
    final repo = _Repo();
    await openManualImportRoute(tester, repo, size: const Size(568, 320), textScale: 1, keyboardInset: 180);

    expect(tester.takeException(), isNull);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Test access');
    await tester.enterText(fields.at(1), 'https://example.com/sub');
    final submit = find.widgetWithText(FilledButton, 'Add');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(repo.calls, 1);
  });

  testWidgets('manual import preserves the baseline route and action', (tester) async {
    final repo = _Repo();
    await openManualImportRoute(tester, repo, size: const Size(320, 568), textScale: 1);

    expect(tester.takeException(), isNull);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Test access');
    await tester.enterText(fields.at(1), 'https://example.com/sub');
    final submit = find.widgetWithText(FilledButton, 'Add');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(repo.calls, 1);
  });
}

class _ConnectRecorder extends ConnectionNotifier {
  int calls = 0;
  @override
  Stream<ConnectionStatus> build() => Stream.value(const Disconnected());
  @override
  Future<void> mayConnect() {
    calls++;
    return Future.value();
  }
}
