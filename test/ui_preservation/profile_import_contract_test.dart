import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/profile/add/add_profile_modal.dart';
import 'package:hiddify/features/profile/add/widgets/fix_btns.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:toastification/toastification.dart';

import '../support/profile_settings_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProfileFixture f;
  setUp(() async => f = await ProfileFixture.create());
  tearDown(() => f.dispose());

  test('remote import/update/edit/share/selection persist across real SQLite close/open', () async {
    expect((await f.repository.upsertRemote('https://example.invalid/a').run()).isRight(), true);
    final a = (await f.repository.watchActiveProfile().first).getOrElse((e) => throw e)!;
    expect(a.name, 'Synthetic remote');
    expect((await f.repository.addLocal('vless://fixture@example.invalid:443#Local').run()).isRight(), true);
    final b = (await f.repository.watchActiveProfile().first).getOrElse((e) => throw e)!;
    expect(b.id, isNot(a.id));
    await f.repository.setAsActive(a.id).run();
    f.http.content = '# profile-title: Updated\nvless://fixture@example.invalid:443#Changed';
    expect((await f.repository.upsertRemote('https://example.invalid/a').run()).isRight(), true);
    expect((await f.dao.getById(a.id))!.name, 'Updated');
    expect(
      (await f.repository
              .offlineUpdate(
                b.copyWith(userOverride: const UserOverride(name: 'Edited')),
                'vless://fixture@example.invalid:443#Edited',
              )
              .run())
          .isRight(),
      true,
    );
    expect((await f.repository.getRawConfig(b.id).run()).getOrElse((e) => throw e), contains('#Edited'));
    await f.reopen();
    expect((await f.dao.watchActiveProfile().first)!.id, a.id);
    expect((await f.dao.getById(b.id))!.name, 'Edited');
    expect((await f.repository.deleteById(a.id, true).run()).isRight(), true);
    expect(await f.dao.getById(a.id), isNull);
    expect((await f.dao.watchActiveProfile().first)!.id, b.id);
    await f.repository.deleteById(b.id, true).run();
    expect(await f.dao.watchActiveProfile().first, isNull);
  });

  test('invalid core validation and cancelled remote download do not insert a profile', () async {
    f.core.reject = true;
    expect((await f.repository.addLocal('not a configuration').run()).isLeft(), true);
    expect(await f.dao.watchProfilesCount().first, 0);
    f.http.cancel = true;
    final result = await f.repository.upsertRemote('https://example.invalid/cancel').run();
    expect(result.fold((e) => e, (_) => null), isA<ProfileCancelByUserFailure>());
    expect(await f.dao.watchProfilesCount().first, 0);
  });

  test('late remote update after deletion does not recreate deleted database row', () async {
    await f.repository.upsertRemote('https://example.invalid/late').run();
    final profile = (await f.dao.watchActiveProfile().first)!;
    f.http.pending = Completer<void>();
    f.http.entered = Completer<void>();
    final late = f.repository.upsertRemote('https://example.invalid/late').run();
    await f.http.entered!.future;
    await f.repository.deleteById(profile.id, true).run();
    f.http.pending!.complete();
    await late;
    expect(await f.dao.getById(profile.id), isNull);
    expect(await f.dao.watchProfilesCount().first, 0);
  });

  testWidgets('manual form rejects invalid input, saves real repository, and close returns options', (tester) async {
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => f.preferences),
        profileRepositoryProvider.overrideWith((ref) => f.repository),
        translationsProvider.overrideWith((ref) => AppLocale.en.buildSync()),
      ],
    );
    addTearDown(c.dispose);
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
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(await tester.runAsync(() => f.dao.watchProfilesCount().first), 0);
    await tester.enterText(find.byType(TextFormField).at(0), 'Manual fixture');
    await tester.enterText(find.byType(TextFormField).at(1), 'https://example.invalid/manual');
    await tester.runAsync(() async {
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed!();
      for (var attempts = 0; c.read(addProfileNotifierProvider).isLoading && attempts < 500; attempts++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(c.read(addProfileNotifierProvider).hasError, false);
    expect((await tester.runAsync(() => f.dao.watchActiveProfile().first))!.name, 'Manual fixture');
    c.read(addProfilePageNotifierProvider.notifier).goManual();
    await tester.tap(find.byIcon(Icons.close));
    expect(c.read(addProfilePageNotifierProvider), AddProfilePages.options);
    await tester.pumpWidget(const SizedBox.shrink());
    toastification.dismissAll();
    // Teardown must also drain the package removal-animation timers.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('clipboard button forwards platform text through real add notifier and repository', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': 'vless://fixture@example.invalid:443#Clipboard'} : null,
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => f.preferences),
        profileRepositoryProvider.overrideWith((ref) => f.repository),
        translationsProvider.overrideWith((ref) => AppLocale.en.buildSync()),
      ],
    );
    addTearDown(c.dispose);
    await c.read(profileRepositoryProvider.future);
    await c.read(translationsProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const ToastificationWrapper(
          child: MaterialApp(home: Scaffold(body: FixBtns(height: 100))),
        ),
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('add_from_clipboard_button')));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      for (var attempts = 0; c.read(addProfileNotifierProvider).isLoading && attempts < 500; attempts++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(c.read(addProfileNotifierProvider).hasError, false);
    expect((await tester.runAsync(() => f.dao.watchActiveProfile().first))!.name, 'Clipboard');
    f.core.reject = true;
    await tester.runAsync(() => c.read(addProfileNotifierProvider.notifier).addClipboard('invalid fixture'));
    expect(c.read(addProfileNotifierProvider).hasError, true);
    expect(await tester.runAsync(() => f.dao.watchProfilesCount().first), 1);
    f.core.reject = false;
    f.http.cancel = true;
    await tester.runAsync(
      () => c.read(addProfileNotifierProvider.notifier).addClipboard('https://example.invalid/cancelled'),
    );
    expect(c.read(addProfileNotifierProvider).error, isA<ProfileCancelByUserFailure>());
    expect(await tester.runAsync(() => f.dao.watchProfilesCount().first), 1);

    await tester.pumpWidget(const SizedBox.shrink());
    toastification.dismissAll();
    // Teardown must also drain the package removal-animation timers.
    await tester.pump(const Duration(seconds: 1));
  });

  test('QR source cancellation and successful forwarding remain bound to addClipboard', () {
    final source = File('lib/features/profile/add/widgets/fix_btns.dart').readAsStringSync();
    expect(source, contains('if (!isDesktop)'));
    expect(source, contains('final cr = await ref.read(dialogNotifierProvider.notifier).showQrScanner();'));
    expect(source, contains('if (cr == null) return;'));
    expect(source, contains('ref.read(addProfileNotifierProvider.notifier).addClipboard(cr);'));
  });

  test('real parser preserves title precedence and excludes unknown headers', () {
    final headers = ProfileParser.populateHeaders(
      content: '# profile-title: Content\n# unknown: excluded',
      remoteHeaders: {'profile-title': 'Remote'},
    ).getOrElse((e) => throw e);
    expect(headers, {'profile-title': 'Remote'});
    final profile = ProfileEntity.remote(
      id: 'synthetic',
      active: true,
      name: '',
      url: 'https://example.invalid/a#URL',
      lastUpdate: DateTime(2026),
      populatedHeaders: headers,
      userOverride: const UserOverride(name: 'Manual'),
    );
    expect(ProfileParser.parse(tempFilePath: 'unused', profile: profile).getOrElse((e) => throw e).name, 'Manual');
  });
}
