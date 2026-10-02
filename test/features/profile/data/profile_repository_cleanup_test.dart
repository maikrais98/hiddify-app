import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/features/profile/data/profile_data_mapper.dart';
import 'package:hiddify/features/profile/data/profile_data_source.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';

const _url = 'https://example.invalid/audit-profile';
const _oldName = 'previous profile';
const _newName = 'updated profile';
const _oldConfig = 'PREVIOUS_NONSECRET_CONFIG';
const _canary = 'NEW_NONSECRET_CANARY';

void main() {
  late _Harness harness;

  setUp(() async => harness = await _Harness.create());
  tearDown(() => harness.dispose());

  group('remote add temporary ownership', () {
    test('work stays deferred until the returned task runs', () async {
      final task = harness.repository.upsertRemote(_url);

      expect(await harness.dao.getByUrl(_url), isNull);
      expect(harness.tempFiles, isEmpty);

      final result = await task.run();

      expect(result.isRight(), isTrue);
      expect((await harness.dao.getByUrl(_url))?.name, _newName);
    });

    for (final failure in [_ParserFailure.download, _ParserFailure.parse]) {
      test('removes the temporary download after ${failure.name} failure', () async {
        harness.parser.failure = failure;

        final result = await harness.repository.upsertRemote(_url).run();

        expect(result.isLeft(), isTrue);
        expect(await harness.dao.getByUrl(_url), isNull);
        expect(harness.configFiles, isEmpty);
        expect(harness.tempFiles, isEmpty);
      });
    }

    test('removes the temporary download and orphan config after validation failure', () async {
      harness.repository.validationFails = true;

      final result = await harness.repository.upsertRemote(_url).run();

      expect(result.isLeft(), isTrue);
      expect(await harness.dao.getByUrl(_url), isNull);
      expect(harness.configFiles, isEmpty);
      expect(harness.tempFiles, isEmpty);
    });

    test('removes temporary and generated files after persistence throws', () async {
      harness.source.failInsert = true;

      final result = await harness.repository.upsertRemote(_url).run();

      expect(result.isLeft(), isTrue);
      expect(await harness.dao.getByUrl(_url), isNull);
      expect(harness.configFiles, isEmpty);
      expect(harness.tempFiles, isEmpty);
    });

    test('removes temporary and generated files when cancellation wins before persistence', () async {
      final token = CancelToken();
      harness.parser.cancelBeforePersistence = true;

      final result = await harness.repository.upsertRemote(_url, cancelToken: token).run();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<ProfileCancelByUserFailure>()),
        (_) => fail('expected cancellation'),
      );
      expect(token.isCancelled, isTrue);
      expect(await harness.dao.getByUrl(_url), isNull);
      expect(harness.configFiles, isEmpty);
      expect(harness.tempFiles, isEmpty);
    });

    test('success persists one profile and leaves only its validated config', () async {
      final result = await harness.repository.upsertRemote(_url).run();

      final row = await harness.dao.getByUrl(_url);
      expect(result.isRight(), isTrue);
      expect(row?.name, _newName);
      expect(await harness.resolver.file(row!.id).readAsString(), _canary);
      expect(harness.tempFiles, isEmpty);
    });
  });

  group('remote update preserves the previous profile', () {
    setUp(() => harness.seedRemote());

    for (final failure in [_ParserFailure.download, _ParserFailure.parse]) {
      test('after ${failure.name} failure and removes the temporary download', () async {
        harness.parser.failure = failure;

        final result = await harness.repository.upsertRemote(_url).run();

        expect(result.isLeft(), isTrue);
        await harness.expectPreviousRemote();
        expect(harness.tempFiles, isEmpty);
      });
    }

    test('after validation failure and removes the temporary download', () async {
      harness.repository.validationFails = true;

      final result = await harness.repository.upsertRemote(_url).run();

      expect(result.isLeft(), isTrue);
      await harness.expectPreviousRemote();
      expect(harness.tempFiles, isEmpty);
    });

    test('after persistence throws and removes the temporary download', () async {
      harness.source.failEdit = true;

      final result = await harness.repository.upsertRemote(_url).run();

      expect(result.isLeft(), isTrue);
      await harness.expectPreviousRemote();
      expect(harness.tempFiles, isEmpty);
    });

    test('after cancellation wins before persistence and removes the temporary download', () async {
      final token = CancelToken();
      harness.parser.cancelBeforePersistence = true;

      final result = await harness.repository.upsertRemote(_url, cancelToken: token).run();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<ProfileCancelByUserFailure>()),
        (_) => fail('expected cancellation'),
      );
      expect(token.isCancelled, isTrue);
      await harness.expectPreviousRemote();
      expect(harness.tempFiles, isEmpty);
    });

    test('success replaces the stored profile and validated config', () async {
      final result = await harness.repository.upsertRemote(_url).run();

      expect(result.isRight(), isTrue);
      expect((await harness.dao.getByUrl(_url))?.name, _newName);
      expect(await harness.resolver.file(_Harness.id).readAsString(), _canary);
      expect(harness.tempFiles, isEmpty);
    });
  });

  group('offline update preserves the previous profile', () {
    late ProfileEntity previous;

    setUp(() async {
      await harness.seedLocal();
      previous = (await harness.dao.getById(_Harness.id))!.toEntity();
    });

    test('when parsing returns a failure and removes the temporary file', () async {
      harness.parser.failure = _ParserFailure.parse;

      final result = await harness.repository.offlineUpdate(previous, _canary).run();

      expect(result.isLeft(), isTrue);
      await harness.expectPreviousLocal();
      expect(harness.tempFiles, isEmpty);
    });

    test('when parser execution throws and removes the temporary file', () async {
      harness.parser.throwDuringOfflineParse = true;

      await expectLater(harness.repository.offlineUpdate(previous, _canary).run(), throwsStateError);

      await harness.expectPreviousLocal();
      expect(harness.tempFiles, isEmpty);
    });

    test('after validation failure and removes the temporary file', () async {
      harness.repository.validationFails = true;

      final result = await harness.repository.offlineUpdate(previous, _canary).run();

      expect(result.isLeft(), isTrue);
      await harness.expectPreviousLocal();
      expect(harness.tempFiles, isEmpty);
    });

    test('after persistence throws and removes the temporary file', () async {
      harness.source.failEdit = true;

      final result = await harness.repository.offlineUpdate(previous, _canary).run();

      expect(result.isLeft(), isTrue);
      await harness.expectPreviousLocal();
      expect(harness.tempFiles, isEmpty);
    });

    test('success replaces the stored profile and validated config', () async {
      final result = await harness.repository.offlineUpdate(previous, _canary).run();

      expect(result.isRight(), isTrue);
      expect((await harness.dao.getById(_Harness.id))?.name, _newName);
      expect(await harness.resolver.file(_Harness.id).readAsString(), _canary);
      expect(harness.tempFiles, isEmpty);
    });
  });

  group('local add owns temporary and final files until persistence', () {
    test('validation failure leaves no row or files', () async {
      harness.repository.validationFails = true;

      final result = await harness.repository.addLocal(_canary).run();

      expect(result.isLeft(), isTrue);
      result.fold((failure) => expect(failure, isA<ProfileInvalidConfigFailure>()), (_) => fail('expected failure'));
      expect(await harness.dao.watchProfilesCount().first, 0);
      expect(harness.configFiles, isEmpty);
      expect(harness.tempFiles, isEmpty);
    });

    test('insert throw leaves no row or files', () async {
      harness.source.failInsert = true;

      final result = await harness.repository.addLocal(_canary).run();

      expect(result.isLeft(), isTrue);
      expect(await harness.dao.watchProfilesCount().first, 0);
      expect(harness.configFiles, isEmpty);
      expect(harness.tempFiles, isEmpty);
    });

    test('cancel from onPersisting leaves no row or files', () async {
      final token = CancelToken();

      final result = await harness.repository
          .addLocal(_canary, cancelToken: token, onPersisting: () => token.cancel('synthetic cancellation'))
          .run();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<ProfileCancelByUserFailure>()),
        (_) => fail('expected cancellation'),
      );
      expect(token.isCancelled, isTrue);
      expect(await harness.dao.watchProfilesCount().first, 0);
      expect(harness.configFiles, isEmpty);
      expect(harness.tempFiles, isEmpty);
    });

    test('success persists one row and cleans its temporary file', () async {
      final result = await harness.repository.addLocal(_canary).run();

      expect(result.isRight(), isTrue);
      expect(await harness.dao.watchProfilesCount().first, 1);
      expect(harness.configFiles, hasLength(1));
      expect(harness.tempFiles, isEmpty);
    });
  });

  test('each execution of a lazy local import creates its own profile', () async {
    final task = harness.repository.addLocal(_canary);
    expect((await task.run()).isRight(), isTrue);
    expect((await task.run()).isRight(), isTrue);
    expect(await harness.dao.watchProfilesCount().first, 2);
    expect(harness.configFiles, hasLength(2));
    expect(harness.tempFiles, isEmpty);
  });

  group('temporary cleanup preserves the result channel', () {
    for (final fault in _CleanupFault.values) {
      test('${fault.name} failure after persistence returns a typed failure', () async {
        harness.resolver.fault = fault;
        final result = await harness.repository.addLocal(_canary).run();
        result.fold(
          (failure) => expect(failure, isA<ProfileUnexpectedFailure>()),
          (_) => fail('cleanup failure must use the typed failure channel'),
        );
        expect(await harness.dao.watchProfilesCount().first, 1);
        expect(await harness.configFiles.single.readAsString(), _canary);
      });

      test('${fault.name} failure preserves the primary Left', () async {
        harness.resolver.fault = fault;
        harness.parser.failure = _ParserFailure.parse;
        final result = await harness.repository.addLocal(_canary).run();
        result.fold(
          (failure) => expect(failure, const ProfileFailure.invalidConfig('synthetic parse failure')),
          (_) => fail('expected primary parser failure'),
        );
        expect(await harness.dao.watchProfilesCount().first, 0);
      });

      test('${fault.name} failure does not mask a thrown parser error', () async {
        await harness.seedLocal();
        final profile = (await harness.dao.getById(_Harness.id))!.toEntity();
        harness.resolver.fault = fault;
        harness.parser.throwDuringOfflineParse = true;
        await expectLater(
          harness.repository.offlineUpdate(profile, _canary).run(),
          throwsA(isA<StateError>().having((error) => error.message, 'message', 'synthetic parser throw')),
        );
        await harness.expectPreviousLocal();
      });
    }
  });

  group('overlapping profile transactions', () {
    for (final firstOffline in [false, true]) {
      test('${firstOffline ? 'offline' : 'remote'} failure cannot overwrite a later remote success', () async {
        await harness.seedRemote();
        final profile = (await harness.dao.getById(_Harness.id))!.toEntity();
        final entered = Completer<void>();
        final release = Completer<void>();
        var first = true;
        harness.source.beforeEdit = () async {
          if (!first) return;
          first = false;
          entered.complete();
          await release.future;
          throw StateError('first update persistence failed');
        };
        final a =
            (firstOffline
                    ? harness.repository.offlineUpdate(profile, 'FIRST_CONFIG')
                    : harness.repository.upsertRemote(_url))
                .run();
        await entered.future.timeout(const Duration(seconds: 2));
        harness.parser.remoteContent = 'SECOND_CONFIG';
        harness.parser.remoteName = 'second committed profile';
        final b = harness.repository.upsertRemote(_url).run();
        // An unprotected second operation finishes while A is held. With
        // serialization it waits, so release A after the bounded observation.
        try {
          await b.timeout(const Duration(milliseconds: 150));
        } on TimeoutException {
          // Expected when the complete transaction is serialized.
        } finally {
          release.complete();
        }
        expect((await a.timeout(const Duration(seconds: 2))).isLeft(), isTrue);
        expect((await b.timeout(const Duration(seconds: 2))).isRight(), isTrue);
        expect((await harness.dao.getById(_Harness.id))?.name, 'second committed profile');
        expect(await harness.resolver.file(_Harness.id).readAsString(), 'SECOND_CONFIG');
        expect(harness.tempFiles, isEmpty);
        expect(harness.backupFiles, isEmpty);
        // A failed transaction must also release its slot for an explicit retry.
        expect(
          (await harness.repository.upsertRemote(_url).run().timeout(const Duration(seconds: 2))).isRight(),
          isTrue,
        );
      });
    }
  });

  test('a held profile transaction does not block a different profile', () async {
    await harness.seedRemote();
    final entered = Completer<void>();
    final release = Completer<void>();
    harness.source.beforeEdit = () async {
      entered.complete();
      await release.future;
    };
    final first = harness.repository.upsertRemote(_url).run();
    await entered.future.timeout(const Duration(seconds: 2));
    try {
      const otherUrl = 'https://example.invalid/other-profile';
      final other = await harness.repository.upsertRemote(otherUrl).run().timeout(const Duration(seconds: 2));
      expect(other.isRight(), isTrue);
      final row = await harness.dao.getByUrl(otherUrl);
      expect(row, isNotNull);
      expect(await harness.resolver.file(row!.id).readAsString(), _canary);
    } finally {
      release.complete();
      await first.timeout(const Duration(seconds: 2));
    }
  });

  test('concurrent first imports of the same URL create one profile', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var first = true;
    harness.source.beforeInsert = () async {
      if (!first) return;
      first = false;
      entered.complete();
      await release.future;
    };
    final a = harness.repository.upsertRemote(_url).run();
    await entered.future.timeout(const Duration(seconds: 2));
    final b = harness.repository.upsertRemote('  $_url  ').run();
    try {
      await b.timeout(const Duration(milliseconds: 150));
    } on TimeoutException {
      // The same URL must wait even before its first database row exists.
    } finally {
      release.complete();
    }
    expect((await a.timeout(const Duration(seconds: 2))).isRight(), isTrue);
    expect((await b.timeout(const Duration(seconds: 2))).isRight(), isTrue);
    expect(await harness.dao.watchProfilesCount().first, 1);
    expect(harness.configFiles, hasLength(1));
    expect(harness.tempFiles, isEmpty);
  });

  test('temporary cleanup finishes before the next same-profile parser starts', () async {
    await harness.seedRemote();
    final entered = Completer<void>();
    final release = Completer<void>();
    var firstCleanup = true;
    var parses = 0;
    harness.parser.onRemoteRun = () => parses++;
    harness.resolver.beforeDelete = () async {
      if (!firstCleanup) return;
      firstCleanup = false;
      entered.complete();
      await release.future;
    };
    final a = harness.repository.upsertRemote(_url).run();
    await entered.future.timeout(const Duration(seconds: 2));
    final b = harness.repository.upsertRemote(_url).run();
    try {
      await b.timeout(const Duration(milliseconds: 150));
    } on TimeoutException {
      // Cleanup owns the shared temporary path until it finishes.
    } finally {
      final parsesBeforeRelease = parses;
      release.complete();
      await Future.wait([
        a.then<Object>((value) => value, onError: (Object error) => error),
        b.then<Object>((value) => value, onError: (Object error) => error),
      ]).timeout(const Duration(seconds: 2));
      expect(parsesBeforeRelease, 1);
    }
    expect(harness.tempFiles, isEmpty);
  });

  test('deletion after a failing update does not resurrect its config', () async {
    await harness.seedRemote();
    final entered = Completer<void>();
    final release = Completer<void>();
    harness.source.beforeEdit = () async {
      entered.complete();
      await release.future;
      throw StateError('pending update fails');
    };
    final update = harness.repository.upsertRemote(_url).run();
    await entered.future.timeout(const Duration(seconds: 2));
    final deletion = harness.repository.deleteById(_Harness.id, false).run();
    try {
      await deletion.timeout(const Duration(milliseconds: 150));
    } on TimeoutException {
      // Deletion must wait for the prior update's rollback and cleanup.
    } finally {
      release.complete();
    }
    expect((await update.timeout(const Duration(seconds: 2))).isLeft(), isTrue);
    expect((await deletion.timeout(const Duration(seconds: 2))).isRight(), isTrue);
    expect(await harness.dao.getById(_Harness.id), isNull);
    expect(await harness.resolver.file(_Harness.id).exists(), isFalse);
    expect(harness.backupFiles, isEmpty);
    expect(harness.tempFiles, isEmpty);
  });

  test('remote update waiting behind deletion cannot recreate the deleted profile', () async {
    await harness.seedRemote();
    final deletionEntered = Completer<void>();
    final releaseDeletion = Completer<void>();
    final lookupFinished = Completer<void>();
    harness.source.beforeDelete = () async {
      deletionEntered.complete();
      await releaseDeletion.future;
    };
    final deletion = harness.repository.deleteById(_Harness.id, false).run();
    await deletionEntered.future.timeout(const Duration(seconds: 2));
    harness.source.afterUrlLookup = () => lookupFinished.complete();
    final update = harness.repository.upsertRemote(_url).run();
    try {
      await lookupFinished.future.timeout(const Duration(seconds: 2));
    } finally {
      releaseDeletion.complete();
    }
    expect((await deletion.timeout(const Duration(seconds: 2))).isRight(), isTrue);
    final result = await update.timeout(const Duration(seconds: 2));
    result.fold(
      (failure) => expect(failure, const ProfileFailure.notFound()),
      (_) => fail('a stale update must not reinsert the deleted profile'),
    );
    expect(await harness.dao.watchProfilesCount().first, 0);
    expect(harness.configFiles, isEmpty);
    expect(harness.tempFiles, isEmpty);
  });

  test('explicit reimport after completed deletion creates a new identity', () async {
    await harness.seedRemote();
    expect((await harness.repository.deleteById(_Harness.id, false).run()).isRight(), isTrue);
    expect((await harness.repository.upsertRemote(_url).run()).isRight(), isTrue);
    final row = await harness.dao.getByUrl(_url);
    expect(row, isNotNull);
    expect(row!.id, isNot(_Harness.id));
    expect(await harness.resolver.file(row.id).readAsString(), _canary);
    expect(await harness.dao.watchProfilesCount().first, 1);
    expect(harness.tempFiles, isEmpty);
  });

  test('failed restore keeps its recoverable backup and the typed failure', () async {
    await harness.seedRemote();
    final token = CancelToken();
    final finalFile = harness.resolver.file(_Harness.id);

    final result = await harness.repository
        .upsertRemote(
          _url,
          cancelToken: token,
          onPersisting: () {
            finalFile.deleteSync();
            Directory(finalFile.path).createSync();
            token.cancel('synthetic cancellation');
          },
        )
        .run();

    expect(result.isLeft(), isTrue);
    result.fold((failure) => expect(failure, isA<ProfileCancelByUserFailure>()), (_) => fail('expected cancellation'));
    expect((await harness.dao.getByUrl(_url))?.name, _oldName);
    final backups = harness.backupFiles;
    expect(backups, hasLength(1));
    expect(await backups.single.readAsString(), _oldConfig);
  });

  test('backup preparation failure never deletes the only previous config', () async {
    final longId = List.filled(230, 'x').join();
    await harness.dao.insert(
      ProfileEntity.remote(
        id: longId,
        active: true,
        name: _oldName,
        url: _url,
        lastUpdate: DateTime.utc(2026),
        populatedHeaders: const {},
      ).toInsertEntry(),
    );
    final finalFile = harness.resolver.file(longId);
    await finalFile.writeAsString(_oldConfig);

    final result = await harness.repository.upsertRemote(_url).run();

    expect(result.isLeft(), isTrue);
    result.fold((failure) => expect(failure, isA<ProfileUnexpectedFailure>()), (_) => fail('expected failure'));
    expect((await harness.dao.getByUrl(_url))?.name, _oldName);
    expect(await finalFile.readAsString(), _oldConfig);
    expect(harness.backupFiles, isEmpty);
    expect(harness.tempFiles, isEmpty);
  });
}

enum _ParserFailure { none, download, parse }

class _Harness {
  _Harness(this.root, this.db, this.dao, this.source, this.resolver, this.parser, this.repository);

  static const id = 'existing-profile';

  final Directory root;
  final Db db;
  final ProfileDao dao;
  final _FaultingDataSource source;
  final _FaultingResolver resolver;
  final _Parser parser;
  final _Repository repository;

  static Future<_Harness> create() async {
    final root = await Directory.systemTemp.createTemp('profile-repository-cleanup-');
    final db = Db(NativeDatabase.memory());
    final dao = ProfileDao(db);
    final source = _FaultingDataSource(dao);
    final resolver = _FaultingResolver(root);
    await resolver.directory.create(recursive: true);
    final parser = _Parser();
    final repository = _Repository(
      profileDataSource: source,
      profilePathResolver: resolver,
      singbox: _CoreStub(),
      configOptionRepository: _ConfigStub(),
      profileParser: parser,
    );
    return _Harness(root, db, dao, source, resolver, parser, repository);
  }

  List<File> get tempFiles =>
      resolver.directory.listSync().whereType<File>().where((file) => file.path.endsWith('.tmp.json')).toList();

  List<File> get configFiles => resolver.directory
      .listSync()
      .whereType<File>()
      .where((file) => !file.path.endsWith('.tmp.json') && !file.path.endsWith('.backup'))
      .toList();

  List<File> get backupFiles =>
      resolver.directory.listSync().whereType<File>().where((file) => file.path.endsWith('.backup')).toList();

  Future<void> seedRemote() async {
    await dao.insert(
      ProfileEntity.remote(
        id: id,
        active: true,
        name: _oldName,
        url: _url,
        lastUpdate: DateTime.utc(2026),
        populatedHeaders: const {},
      ).toInsertEntry(),
    );
    await resolver.file(id).writeAsString(_oldConfig);
  }

  Future<void> seedLocal() async {
    await dao.insert(
      ProfileEntity.local(
        id: id,
        active: true,
        name: _oldName,
        lastUpdate: DateTime.utc(2026),
        populatedHeaders: const {},
      ).toInsertEntry(),
    );
    await resolver.file(id).writeAsString(_oldConfig);
  }

  Future<void> expectPreviousRemote() async {
    expect((await dao.getByUrl(_url))?.name, _oldName);
    expect(await resolver.file(id).readAsString(), _oldConfig);
  }

  Future<void> expectPreviousLocal() async {
    expect((await dao.getById(id))?.name, _oldName);
    expect(await resolver.file(id).readAsString(), _oldConfig);
  }

  Future<void> dispose() async {
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

class _Repository extends ProfileRepositoryImpl {
  _Repository({
    required super.profileDataSource,
    required super.profilePathResolver,
    required super.singbox,
    required super.configOptionRepository,
    required super.profileParser,
  });

  bool validationFails = false;

  @override
  TaskEither<ProfileFailure, Unit> validateConfig(String path, String tempPath, String? profileOverride, bool debug) =>
      TaskEither(() async {
        if (validationFails) return left(const ProfileFailure.invalidConfig('synthetic validation failure'));
        await File(tempPath).copy(path);
        return right(unit);
      });
}

class _Parser implements ProfileParser {
  _ParserFailure failure = _ParserFailure.none;
  bool throwDuringOfflineParse = false;
  bool cancelBeforePersistence = false;
  String remoteContent = _canary;
  String remoteName = _newName;
  void Function()? onRemoteRun;

  TaskEither<ProfileFailure, ProfileEntriesCompanion> _remote(
    String tempFilePath,
    ProfileEntriesCompanion companion,
    CancelToken? cancelToken,
  ) => TaskEither(() async {
    onRemoteRun?.call();
    await File(tempFilePath).writeAsString(remoteContent);
    if (cancelBeforePersistence) cancelToken?.cancel('synthetic cancellation');
    return switch (failure) {
      _ParserFailure.download => left(const ProfileFailure.invalidUrl('synthetic download failure')),
      _ParserFailure.parse => left(const ProfileFailure.invalidConfig('synthetic parse failure')),
      _ParserFailure.none => right(companion),
    };
  });

  @override
  TaskEither<ProfileFailure, ProfileEntriesCompanion> addRemote({
    required String id,
    required String url,
    required String tempFilePath,
    required UserOverride? userOverride,
    CancelToken? cancelToken,
    void Function()? onParsing,
  }) => _remote(
    tempFilePath,
    ProfileEntity.remote(
      id: id,
      active: true,
      name: remoteName,
      url: url,
      lastUpdate: DateTime.utc(2026, 1, 2),
      populatedHeaders: const {},
      userOverride: userOverride,
    ).toInsertEntry(),
    cancelToken,
  );

  @override
  TaskEither<ProfileFailure, ProfileEntriesCompanion> updateRemote({
    required RemoteProfileEntity rp,
    required String tempFilePath,
    CancelToken? cancelToken,
    void Function()? onParsing,
  }) => _remote(
    tempFilePath,
    rp.copyWith(name: remoteName, lastUpdate: DateTime.utc(2026, 1, 2)).toUpdateEntry(),
    cancelToken,
  );

  @override
  TaskEither<ProfileFailure, ProfileEntriesCompanion> addLocal({
    required String id,
    required String content,
    required String tempFilePath,
    required UserOverride? userOverride,
    CancelToken? cancelToken,
  }) => _remote(
    tempFilePath,
    ProfileEntity.local(
      id: id,
      active: true,
      name: remoteName,
      lastUpdate: DateTime.utc(2026, 1, 2),
      populatedHeaders: const {},
      userOverride: userOverride,
    ).toInsertEntry(),
    cancelToken,
  );

  @override
  Either<ProfileFailure, ProfileEntriesCompanion> offlineUpdate({
    required ProfileEntity profile,
    required String tempFilePath,
  }) {
    if (throwDuringOfflineParse) throw StateError('synthetic parser throw');
    if (failure == _ParserFailure.parse) return left(const ProfileFailure.invalidConfig('synthetic parse failure'));
    return right(profile.copyWith(name: remoteName, lastUpdate: DateTime.utc(2026, 1, 2)).toUpdateEntry());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FaultingDataSource implements ProfileDataSource {
  _FaultingDataSource(this.delegate);

  final ProfileDataSource delegate;
  bool failInsert = false;
  bool failEdit = false;
  Future<void> Function()? beforeEdit;
  Future<void> Function()? beforeInsert;
  Future<void> Function()? beforeDelete;
  void Function()? afterUrlLookup;

  @override
  Future<void> deleteById(String id, bool isActive) async {
    await beforeDelete?.call();
    return delegate.deleteById(id, isActive);
  }

  @override
  Future<ProfileEntry?> getById(String id) => delegate.getById(id);

  @override
  Future<ProfileEntry?> getByUrl(String url) async {
    final row = await delegate.getByUrl(url);
    afterUrlLookup?.call();
    return row;
  }

  @override
  Future<void> insert(ProfileEntriesCompanion entry) async {
    await beforeInsert?.call();
    if (failInsert) throw StateError('synthetic insert failure');
    return delegate.insert(entry);
  }

  @override
  Future<void> edit(String id, ProfileEntriesCompanion entry) async {
    await beforeEdit?.call();
    if (failEdit) throw StateError('synthetic edit failure');
    return delegate.edit(id, entry);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CoreStub implements HiddifyCoreService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ConfigStub implements ConfigOptionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

enum _CleanupFault { exists, delete }

class _FaultingResolver extends ProfilePathResolver {
  _FaultingResolver(super.directory);
  _CleanupFault? fault;
  Future<void> Function()? beforeDelete;

  @override
  File tempFile(String fileName) =>
      _CleanupFile(super.tempFile(fileName), () => fault, () async => await beforeDelete?.call());
}

// Only the filesystem boundary faults; repository, database and file contents
// remain real. The core fixture promotes using paths, bypassing this wrapper.
class _CleanupFile implements File {
  _CleanupFile(this.delegate, this.fault, this.beforeDelete);
  final Future<void> Function() beforeDelete;
  final File delegate;
  final _CleanupFault? Function() fault;
  @override
  String get path => delegate.path;
  @override
  Future<bool> exists() {
    if (fault() == _CleanupFault.exists) throw FileSystemException('synthetic cleanup exists failure', path);
    return delegate.exists();
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    await beforeDelete();
    if (fault() == _CleanupFault.delete) throw FileSystemException('synthetic cleanup delete failure', path);
    return delegate.delete(recursive: recursive);
  }

  @override
  Future<File> writeAsString(
    String contents, {
    Encoding encoding = utf8,
    FileMode mode = FileMode.write,
    bool flush = false,
  }) => delegate.writeAsString(contents, encoding: encoding, mode: mode, flush: flush);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
