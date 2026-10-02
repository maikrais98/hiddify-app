import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/db/db.dart';

import 'package:hiddify/core/utils/exception_handler.dart';
import 'package:hiddify/features/profile/data/profile_data_mapper.dart';
import 'package:hiddify/features/profile/data/profile_data_source.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/model/profile_sort_enum.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:uuid/uuid.dart';

abstract interface class ProfileRepository {
  TaskEither<ProfileFailure, Unit> init();
  TaskEither<ProfileFailure, ProfileEntity?> getById(String id);
  TaskEither<ProfileFailure, Unit> setAsActive(String id);
  TaskEither<ProfileFailure, Unit> deleteById(String id, bool isActive);
  Stream<Either<ProfileFailure, ProfileEntity?>> watchActiveProfile();
  Stream<Either<ProfileFailure, bool>> watchHasAnyProfile();
  Stream<Either<ProfileFailure, List<ProfileEntity>>> watchAll({
    ProfilesSort sort = ProfilesSort.lastUpdate,
    SortMode sortMode = SortMode.ascending,
  });
  TaskEither<ProfileFailure, Unit> upsertRemote(
    String url, {
    UserOverride? userOverride,
    CancelToken? cancelToken,
    void Function()? onParsing,
    void Function()? onValidating,
    void Function()? onPersisting,
  });
  TaskEither<ProfileFailure, Unit> addLocal(
    String content, {
    UserOverride? userOverride,
    CancelToken? cancelToken,
    void Function()? onValidating,
    void Function()? onPersisting,
  });
  TaskEither<ProfileFailure, Unit> offlineUpdate(ProfileEntity nProfile, String nContent);
  TaskEither<ProfileFailure, Unit> validateConfig(String path, String tempPath, String? profileOverride, bool debug);
  TaskEither<ProfileFailure, String> generateConfig(String id);
  TaskEither<ProfileFailure, String> getRawConfig(String id);
}

class ProfileRepositoryImpl with ExceptionHandler, InfraLogger implements ProfileRepository {
  ProfileRepositoryImpl({
    required ProfileDataSource profileDataSource,
    required ProfilePathResolver profilePathResolver,
    required HiddifyCoreService singbox,
    required ConfigOptionRepository configOptionRepository,
    required ProfileParser profileParser,
  }) : _profileParser = profileParser,
       _configOptionRepo = configOptionRepository,
       _singbox = singbox,
       _profilePathResolver = profilePathResolver,
       _profileDataSource = profileDataSource;

  final ProfileDataSource _profileDataSource;
  final ProfilePathResolver _profilePathResolver;
  final HiddifyCoreService _singbox;
  final ConfigOptionRepository _configOptionRepo;
  final ProfileParser _profileParser;
  final Map<String, Future<void>> _profileOperations = {};

  TaskEither<ProfileFailure, T> _withProfileOperation<T>(
    String key,
    TaskEither<ProfileFailure, T> Function() operation,
  ) => TaskEither(() async {
    final previous = _profileOperations[key];
    final completion = Completer<void>();
    _profileOperations[key] = completion.future;
    try {
      if (previous != null) await previous;
      return await operation().run();
    } finally {
      completion.complete();
      if (identical(_profileOperations[key], completion.future)) _profileOperations.remove(key);
    }
  });

  @override
  TaskEither<ProfileFailure, Unit> init() {
    return exceptionHandler(() async {
      if (!kIsWeb) {
        if (!await _profilePathResolver.directory.exists()) {
          await _profilePathResolver.directory.create(recursive: true);
        }
      }

      return right(unit);
    }, ProfileUnexpectedFailure.new);
  }

  @override
  TaskEither<ProfileFailure, ProfileEntity?> getById(String id) {
    return TaskEither.tryCatch(
      () => _profileDataSource.getById(id).then((value) => value?.toEntity()),
      ProfileUnexpectedFailure.new,
    );
  }

  @override
  TaskEither<ProfileFailure, Unit> setAsActive(String id) {
    return TaskEither.tryCatch(() async {
      await _profileDataSource.edit(id, const ProfileEntriesCompanion(active: Value(true)));
      return unit;
    }, ProfileUnexpectedFailure.new);
  }

  @override
  TaskEither<ProfileFailure, Unit> deleteById(String id, bool isActive) {
    return _withProfileOperation(
      'id:$id',
      () => TaskEither.tryCatch(() async {
        await _profileDataSource.deleteById(id, isActive);
        await _profilePathResolver.file(id).delete();
        return unit;
      }, ProfileUnexpectedFailure.new),
    );
  }

  @override
  Stream<Either<ProfileFailure, ProfileEntity?>> watchActiveProfile() {
    return _profileDataSource.watchActiveProfile().map((event) => event?.toEntity()).handleExceptions((
      error,
      stackTrace,
    ) {
      loggy.error("error watching active profile", error, stackTrace);
      return ProfileUnexpectedFailure(error, stackTrace);
    });
  }

  @override
  Stream<Either<ProfileFailure, bool>> watchHasAnyProfile() {
    return _profileDataSource
        .watchProfilesCount()
        .map((event) => event != 0)
        .handleExceptions(ProfileUnexpectedFailure.new);
  }

  @override
  Stream<Either<ProfileFailure, List<ProfileEntity>>> watchAll({
    ProfilesSort sort = ProfilesSort.lastUpdate,
    SortMode sortMode = SortMode.ascending,
  }) {
    return _profileDataSource
        .watchAll(sort: sort, sortMode: sortMode)
        .map((event) => event.map((e) => e.toEntity()).toList())
        .handleExceptions(ProfileUnexpectedFailure.new);
  }

  @override
  TaskEither<ProfileFailure, Unit> upsertRemote(
    String url, {
    UserOverride? userOverride,
    CancelToken? cancelToken,
    void Function()? onParsing,
    void Function()? onValidating,
    void Function()? onPersisting,
  }) => _upsertRemote(
    normalizeProfileUrl(url),
    userOverride: userOverride,
    cancelToken: cancelToken,
    onParsing: onParsing,
    onValidating: onValidating,
    onPersisting: onPersisting,
  );

  TaskEither<ProfileFailure, Unit> _upsertRemote(
    String url, {
    UserOverride? userOverride,
    CancelToken? cancelToken,
    void Function()? onParsing,
    void Function()? onValidating,
    void Function()? onPersisting,
  }) => _withProfileOperation(
    'url:$url',
    () =>
        TaskEither.tryCatch(
          () async => await _profileDataSource.getByUrl(url).then((profEntry) => profEntry?.toEntity()),
          ProfileFailure.unexpected,
        ).flatMap((existingProfile) {
          // if profile is null, generate id
          final id = existingProfile?.id ?? const Uuid().v4();
          return _withProfileOperation(
            'id:$id',
            () =>
                TaskEither.tryCatch(
                  () async => (await _profileDataSource.getById(id))?.toEntity(),
                  ProfileFailure.unexpected,
                ).flatMap((profEntity) {
                  if (existingProfile != null && profEntity == null) {
                    return TaskEither.left(const ProfileFailure.notFound());
                  }
                  final file = _profilePathResolver.file(id);
                  final tempFile = _profilePathResolver.tempFile(id);
                  return _withTemporaryFileCleanup(tempFile, () {
                    if (profEntity != null && profEntity is RemoteProfileEntity) {
                      // Update
                      var remoteProfile = profEntity;
                      if (userOverride != null) {
                        remoteProfile = remoteProfile.copyWith(userOverride: userOverride);
                      }
                      return _profileParser
                          .updateRemote(
                            rp: remoteProfile,
                            tempFilePath: tempFile.path,
                            cancelToken: cancelToken,
                            onParsing: onParsing,
                          )
                          .flatMap(
                            (profEntity) => _validateAndPersist(
                              file: file,
                              tempFile: tempFile,
                              profileOverride: ProfileParser.profileOverrideHelper(profile: profEntity),
                              cancelToken: cancelToken,
                              onValidating: onValidating,
                              onPersisting: onPersisting,
                              persist: () => _profileDataSource.edit(id, profEntity),
                            ),
                          );
                    } else {
                      // Add
                      return _profileParser
                          .addRemote(
                            id: id,
                            url: url,
                            tempFilePath: tempFile.path,
                            userOverride: userOverride,
                            cancelToken: cancelToken,
                            onParsing: onParsing,
                          )
                          .flatMap(
                            (profEntity) => _validateAndPersist(
                              file: file,
                              tempFile: tempFile,
                              profileOverride: ProfileParser.profileOverrideHelper(profile: profEntity),
                              cancelToken: cancelToken,
                              onValidating: onValidating,
                              onPersisting: onPersisting,
                              persist: () => _profileDataSource.insert(profEntity),
                            ),
                          );
                    }
                  });
                }),
          );
        }),
  );

  @override
  TaskEither<ProfileFailure, Unit> addLocal(
    String content, {
    UserOverride? userOverride,
    CancelToken? cancelToken,
    void Function()? onValidating,
    void Function()? onPersisting,
  }) => TaskEither(() async {
    final id = const Uuid().v4();
    final file = _profilePathResolver.file(id);
    final tempFile = _profilePathResolver.tempFile(id);
    return await _withTemporaryFileCleanup(
      tempFile,
      () => TaskEither.tryCatch(() => tempFile.writeAsString(content), _toProfileFailure).flatMap(
        (_) => _profileParser
            .addLocal(
              id: id,
              content: content,
              tempFilePath: tempFile.path,
              userOverride: userOverride,
              cancelToken: cancelToken,
            )
            .flatMap(
              (profEntity) => _validateAndPersist(
                file: file,
                tempFile: tempFile,
                profileOverride: ProfileParser.profileOverrideHelper(profile: profEntity),
                cancelToken: cancelToken,
                onValidating: onValidating,
                onPersisting: onPersisting,
                persist: () => _profileDataSource.insert(profEntity),
              ),
            ),
      ),
    ).run();
  });

  @override
  TaskEither<ProfileFailure, Unit> offlineUpdate(ProfileEntity profile, String nContent) => _withProfileOperation(
    'id:${profile.id}',
    () =>
        TaskEither.tryCatch(
          () async => await _profileDataSource.getById(profile.id).then((profEntry) => profEntry?.toEntity()),
          ProfileFailure.unexpected,
        ).flatMap((oProfile) {
          if (oProfile == null || oProfile.runtimeType != profile.runtimeType) throw const ProfileFailure.notFound();
          if (profile.userOverride == null) loggy.warning('Updaing profile content with "userOverride" == null');
          final id = oProfile.id;
          final file = _profilePathResolver.file(id);
          final tempFile = _profilePathResolver.tempFile(id);
          return _withTemporaryFileCleanup(
            tempFile,
            () => TaskEither.tryCatch(() async => await tempFile.writeAsString(nContent), _toProfileFailure).flatMap(
              (_) =>
                  TaskEither.fromEither(
                    _profileParser.offlineUpdate(
                      profile: oProfile.copyWith(userOverride: profile.userOverride),
                      tempFilePath: tempFile.path,
                    ),
                  ).flatMap(
                    (profEntity) => _validateAndPersist(
                      file: file,
                      tempFile: tempFile,
                      profileOverride: ProfileParser.profileOverrideHelper(profile: profEntity),
                      persist: () => _profileDataSource.edit(id, profEntity),
                    ),
                  ),
            ),
          );
        }),
  );

  TaskEither<ProfileFailure, T> _withTemporaryFileCleanup<T>(
    File tempFile,
    TaskEither<ProfileFailure, T> Function() operation,
  ) => TaskEither(() async {
    Either<ProfileFailure, T> result;
    try {
      result = await operation().run();
    } catch (_) {
      await _cleanupTemporaryFile(tempFile);
      rethrow;
    }
    final cleanupFailure = await _cleanupTemporaryFile(tempFile);
    if (result.isRight() && cleanupFailure != null) return left(cleanupFailure);
    return result;
  });

  Future<ProfileFailure?> _cleanupTemporaryFile(File tempFile) async {
    try {
      if (await tempFile.exists()) await tempFile.delete();
      return null;
    } catch (error, stackTrace) {
      loggy.error('failed to clean temporary profile file');
      return _toProfileFailure(error, stackTrace);
    }
  }

  TaskEither<ProfileFailure, Unit> _validateAndPersist({
    required File file,
    required File tempFile,
    required String? profileOverride,
    required Future<void> Function() persist,
    CancelToken? cancelToken,
    void Function()? onValidating,
    void Function()? onPersisting,
  }) => TaskEither(() async {
    File? backupFile;
    var rollbackNeeded = false;
    Either<ProfileFailure, Unit> fail(ProfileFailure failure) => left(failure);

    try {
      onValidating?.call();
      if (cancelToken?.isCancelled ?? false) return fail(const ProfileFailure.cancelByUser());

      if (await file.exists()) {
        final candidate = File('${file.path}.${const Uuid().v4()}.backup');
        try {
          await file.copy(candidate.path);
        } catch (error, stackTrace) {
          await _deleteBackup(candidate);
          return fail(_toProfileFailure(error, stackTrace));
        }
        backupFile = candidate;
      }

      if (cancelToken?.isCancelled ?? false) {
        await _deleteBackup(backupFile);
        return fail(const ProfileFailure.cancelByUser());
      }

      rollbackNeeded = true;
      final validation = await validateConfig(file.path, tempFile.path, profileOverride, false).run();
      if (validation case Left(value: final failure)) {
        await _rollbackConfig(file, backupFile);
        return fail(failure);
      }

      onPersisting?.call();
      if (cancelToken?.isCancelled ?? false) {
        await _rollbackConfig(file, backupFile);
        return fail(const ProfileFailure.cancelByUser());
      }

      try {
        await persist();
      } catch (error, stackTrace) {
        await _rollbackConfig(file, backupFile);
        return fail(_toProfileFailure(error, stackTrace));
      }

      await _deleteBackup(backupFile);
      return right(unit);
    } catch (error, stackTrace) {
      if (rollbackNeeded) await _rollbackConfig(file, backupFile);
      return fail(_toProfileFailure(error, stackTrace));
    }
  });

  Future<void> _rollbackConfig(File file, File? backupFile) async {
    if (backupFile != null && await backupFile.exists()) {
      try {
        await backupFile.copy(file.path);
        await backupFile.delete();
      } catch (_) {
        loggy.error('failed to restore previous profile config; backup retained');
      }
    } else {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        loggy.error('failed to remove uncommitted profile config');
      }
    }
  }

  Future<void> _deleteBackup(File? backupFile) async {
    if (backupFile == null || !await backupFile.exists()) return;
    try {
      await backupFile.delete();
    } catch (_) {
      loggy.warning('failed to remove obsolete profile config backup');
    }
  }

  ProfileFailure _toProfileFailure(Object error, StackTrace stackTrace) =>
      error is ProfileFailure ? error : ProfileFailure.unexpected(error, stackTrace);

  @override
  TaskEither<ProfileFailure, Unit> validateConfig(String path, String tempPath, String? profileOverride, bool debug) =>
      TaskEither.fromEither(_configOptionRepo.fullOptionsOverrided(profileOverride))
          .mapLeft((configOptionFailure) => ProfileFailure.invalidConfig(null, configOptionFailure))
          .flatMap(
            (overridedOptions) => _singbox
                .changeOptions(overridedOptions)
                .mapLeft(ProfileFailure.invalidConfig)
                .flatMap(
                  (_) => _singbox.validateConfigByPath(path, tempPath, debug).mapLeft(ProfileFailure.invalidConfig),
                ),
          );

  @override
  TaskEither<ProfileFailure, String> generateConfig(String id) => TaskEither.fromEither(
    Either.tryCatch(() => _profilePathResolver.file(id), ProfileFailure.unexpected),
  ).flatMap((configFile) => _singbox.generateFullConfigByPath(configFile.path).mapLeft(ProfileFailure.unexpected));

  @override
  TaskEither<ProfileFailure, String> getRawConfig(String id) {
    return TaskEither.fromEither(
      Either.tryCatch(() => _profilePathResolver.file(id), ProfileFailure.unexpected),
    ).flatMap((configFile) => TaskEither.tryCatch(() => configFile.readAsString(), ProfileFailure.unexpected));
  }
}
