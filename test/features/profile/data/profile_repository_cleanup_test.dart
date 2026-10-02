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
  final ProfilePathResolver resolver;
  final _Parser parser;
  final _Repository repository;

  static Future<_Harness> create() async {
    final root = await Directory.systemTemp.createTemp('profile-repository-cleanup-');
    final db = Db(NativeDatabase.memory());
    final dao = ProfileDao(db);
    final source = _FaultingDataSource(dao);
    final resolver = ProfilePathResolver(root);
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

  TaskEither<ProfileFailure, ProfileEntriesCompanion> _remote(
    String tempFilePath,
    ProfileEntriesCompanion companion,
    CancelToken? cancelToken,
  ) => TaskEither(() async {
    await File(tempFilePath).writeAsString(_canary);
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
      name: _newName,
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
    rp.copyWith(name: _newName, lastUpdate: DateTime.utc(2026, 1, 2)).toUpdateEntry(),
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
      name: _newName,
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
    return right(profile.copyWith(name: _newName, lastUpdate: DateTime.utc(2026, 1, 2)).toUpdateEntry());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FaultingDataSource implements ProfileDataSource {
  _FaultingDataSource(this.delegate);

  final ProfileDataSource delegate;
  bool failInsert = false;
  bool failEdit = false;

  @override
  Future<ProfileEntry?> getById(String id) => delegate.getById(id);

  @override
  Future<ProfileEntry?> getByUrl(String url) => delegate.getByUrl(url);

  @override
  Future<void> insert(ProfileEntriesCompanion entry) {
    if (failInsert) throw StateError('synthetic insert failure');
    return delegate.insert(entry);
  }

  @override
  Future<void> edit(String id, ProfileEntriesCompanion entry) {
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
