import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/db/db.dart';

import 'package:hiddify/core/utils/exception_handler.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_event.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_journal.dart';
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
    int? diagnosticOperationId,
    DiagnosticTrigger? diagnosticTrigger,
  });
  TaskEither<ProfileFailure, Unit> addLocal(String content, {UserOverride? userOverride});
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
    SafeDiagnosticJournal? diagnostics,
  }) : _profileParser = profileParser,
       _configOptionRepo = configOptionRepository,
       _singbox = singbox,
       _profilePathResolver = profilePathResolver,
       _profileDataSource = profileDataSource,
       _diagnostics = diagnostics;

  final ProfileDataSource _profileDataSource;
  final ProfilePathResolver _profilePathResolver;
  final HiddifyCoreService _singbox;
  final ConfigOptionRepository _configOptionRepo;
  final ProfileParser _profileParser;
  final SafeDiagnosticJournal? _diagnostics;

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
    return TaskEither.tryCatch(() async {
      await _profileDataSource.deleteById(id, isActive);
      await _profilePathResolver.file(id).delete();
      return unit;
    }, ProfileUnexpectedFailure.new);
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
    int? diagnosticOperationId,
    DiagnosticTrigger? diagnosticTrigger,
  }) => TaskEither(() async {
    final operationId = diagnosticOperationId ?? _nextDiagnosticOperationId();
    final trigger = diagnosticTrigger ?? DiagnosticTrigger.manual;
    final operation = trigger == DiagnosticTrigger.importAction
        ? DiagnosticOperation.subscriptionImport
        : DiagnosticOperation.subscriptionUpdate;
    _recordDiagnostic(
      operationId,
      operation: operation,
      trigger: trigger,
      phase: DiagnosticPhase.action,
      stage: DiagnosticStage.requested,
    );
    final result = await _upsertRemote(
      url,
      userOverride: userOverride,
      cancelToken: cancelToken,
      diagnosticOperationId: operationId,
      diagnosticTrigger: trigger,
    ).run();
    _recordDiagnostic(
      operationId,
      operation: operation,
      trigger: trigger,
      phase: DiagnosticPhase.action,
      stage: result.isRight() ? DiagnosticStage.accepted : DiagnosticStage.failed,
      code: result.match(_diagnosticCodeForFailure, (_) => DiagnosticCode.none),
    );
    return result;
  });

  TaskEither<ProfileFailure, Unit> _upsertRemote(
    String url, {
    UserOverride? userOverride,
    CancelToken? cancelToken,
    int? diagnosticOperationId,
    required DiagnosticTrigger diagnosticTrigger,
  }) =>
      TaskEither.tryCatch(
        () async => await _profileDataSource.getByUrl(url).then((profEntry) => profEntry?.toEntity()),
        ProfileFailure.unexpected,
      ).flatMap((profEntity) {
        // if profile is null, generate id
        final id = profEntity?.id ?? const Uuid().v4();
        final file = _profilePathResolver.file(id);
        final tempFile = _profilePathResolver.tempFile(id);
        try {
          if (profEntity != null && profEntity is RemoteProfileEntity) {
            // Update
            if (userOverride != null) {
              profEntity = profEntity.copyWith(userOverride: userOverride);
            }
            return _profileParser
                .updateRemote(
                  rp: profEntity,
                  tempFilePath: tempFile.path,
                  cancelToken: cancelToken,
                  diagnosticOperationId: diagnosticOperationId,
                  diagnosticTrigger: diagnosticTrigger,
                )
                .flatMap(
                  (profEntity) =>
                      validateConfig(
                        file.path,
                        tempFile.path,
                        profEntity.profileOverride.value,
                        false,
                        diagnosticOperationId: diagnosticOperationId,
                        diagnosticTrigger: diagnosticTrigger,
                      ).flatMap(
                        (unit) => _observePhase(
                          () => TaskEither.tryCatch(() async {
                            await _profileDataSource.edit(id, profEntity);
                            return unit;
                          }, ProfileFailure.unexpected),
                          operationId: diagnosticOperationId,
                          trigger: diagnosticTrigger,
                          phase: DiagnosticPhase.dbPersist,
                        ),
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
                  diagnosticOperationId: diagnosticOperationId,
                  diagnosticTrigger: diagnosticTrigger,
                )
                .flatMap(
                  (profEntity) =>
                      validateConfig(
                        file.path,
                        tempFile.path,
                        profEntity.profileOverride.value,
                        false,
                        diagnosticOperationId: diagnosticOperationId,
                        diagnosticTrigger: diagnosticTrigger,
                      ).flatMap(
                        (unit) => _observePhase(
                          () => TaskEither.tryCatch(() async {
                            await _profileDataSource.insert(profEntity);
                            return unit;
                          }, ProfileFailure.unexpected),
                          operationId: diagnosticOperationId,
                          trigger: diagnosticTrigger,
                          phase: DiagnosticPhase.dbPersist,
                        ),
                      ),
                );
          }
        } finally {
          if (tempFile.existsSync()) tempFile.deleteSync();
        }
      });

  @override
  TaskEither<ProfileFailure, Unit> addLocal(String content, {UserOverride? userOverride}) =>
      TaskEither.tryCatch(() async {
        final id = const Uuid().v4();
        final file = _profilePathResolver.file(id);
        final tempFile = _profilePathResolver.tempFile(id);
        try {
          await tempFile.writeAsString(content);
          final task = _profileParser
              .addLocal(id: id, content: content, tempFilePath: tempFile.path, userOverride: userOverride)
              .flatMap(
                (profEntity) =>
                    validateConfig(file.path, tempFile.path, profEntity.profileOverride.value, false).flatMap(
                      (unit) => TaskEither.tryCatch(() async {
                        await _profileDataSource.insert(profEntity);
                        return unit;
                      }, ProfileFailure.unexpected),
                    ),
              );
          return (await task.run()).getOrElse((l) => throw l);
        } finally {
          if (tempFile.existsSync()) tempFile.deleteSync();
        }
      }, ProfileFailure.unexpected);

  @override
  TaskEither<ProfileFailure, Unit> offlineUpdate(ProfileEntity profile, String nContent) =>
      TaskEither.tryCatch(
        () async => await _profileDataSource.getById(profile.id).then((profEntry) => profEntry?.toEntity()),
        ProfileFailure.unexpected,
      ).flatMap((oProfile) {
        if (oProfile == null || oProfile.runtimeType != profile.runtimeType) throw const ProfileFailure.notFound();
        if (profile.userOverride == null) loggy.warning('Updaing profile content with "userOverride" == null');
        final id = oProfile.id;
        final file = _profilePathResolver.file(id);
        final tempFile = _profilePathResolver.tempFile(id);
        try {
          return TaskEither.tryCatch(
            () async => await tempFile.writeAsString(nContent),
            ProfileFailure.unexpected,
          ).flatMap(
            (_) =>
                TaskEither.fromEither(
                  _profileParser.offlineUpdate(
                    profile: oProfile.copyWith(userOverride: profile.userOverride),
                    tempFilePath: tempFile.path,
                  ),
                ).flatMap(
                  (profEntity) =>
                      validateConfig(file.path, tempFile.path, profEntity.profileOverride.value, false).flatMap(
                        (unit) => TaskEither.tryCatch(() async {
                          await _profileDataSource.edit(id, profEntity);
                          return unit;
                        }, ProfileFailure.unexpected),
                      ),
                ),
          );
        } finally {
          if (tempFile.existsSync()) tempFile.deleteSync();
        }
      });

  @override
  TaskEither<ProfileFailure, Unit> validateConfig(
    String path,
    String tempPath,
    String? profileOverride,
    bool debug, {
    int? diagnosticOperationId,
    DiagnosticTrigger? diagnosticTrigger,
  }) => _ensureForegroundReady(operationId: diagnosticOperationId, trigger: diagnosticTrigger).flatMap(
    (_) => TaskEither.fromEither(_configOptionRepo.fullOptionsOverrided(profileOverride))
        .mapLeft((configOptionFailure) => ProfileFailure.invalidConfig(null, configOptionFailure))
        .flatMap(
          (overridedOptions) =>
              _observePhase(
                () => _singbox
                    .changeOptions(overridedOptions)
                    .mapLeft(
                      (failure) => failure == 'foreground_settings_unavailable'
                          ? const ProfileFailure.unexpected(HiddifyCoreInitializationException())
                          : ProfileFailure.invalidConfig(failure),
                    ),
                operationId: diagnosticOperationId,
                trigger: diagnosticTrigger,
                phase: DiagnosticPhase.changeOptions,
              ).flatMap(
                (_) => _observePhase(
                  () => _singbox.validateConfigByPath(path, tempPath, debug).mapLeft(ProfileFailure.invalidConfig),
                  operationId: diagnosticOperationId,
                  trigger: diagnosticTrigger,
                  phase: DiagnosticPhase.validateAndCommitConfig,
                ),
              ),
        ),
  );

  TaskEither<ProfileFailure, Unit> _ensureForegroundReady({
    required int? operationId,
    required DiagnosticTrigger? trigger,
  }) {
    if (!_singbox.core.supportsSystemStatus) return TaskEither.right(unit);
    return _observePhase(
      () => TaskEither(() async {
        final ready = await _singbox.ensureForegroundReady();
        return ready ? right(unit) : left(const ProfileFailure.unexpected(HiddifyCoreInitializationException()));
      }),
      operationId: operationId,
      trigger: trigger,
      phase: DiagnosticPhase.foregroundReady,
    );
  }

  TaskEither<ProfileFailure, T> _observePhase<T>(
    TaskEither<ProfileFailure, T> Function() task, {
    required int? operationId,
    required DiagnosticTrigger? trigger,
    required DiagnosticPhase phase,
  }) => TaskEither(() async {
    final operation = trigger == DiagnosticTrigger.importAction
        ? DiagnosticOperation.subscriptionImport
        : DiagnosticOperation.subscriptionUpdate;
    _recordDiagnostic(
      operationId,
      operation: operation,
      trigger: trigger,
      phase: phase,
      stage: DiagnosticStage.requested,
    );
    final result = await task().run();
    _recordDiagnostic(
      operationId,
      operation: operation,
      trigger: trigger,
      phase: phase,
      stage: result.isRight() ? DiagnosticStage.accepted : DiagnosticStage.failed,
      code: result.match(_diagnosticCodeForFailure, (_) => DiagnosticCode.none),
    );
    return result;
  });

  int? _nextDiagnosticOperationId() {
    try {
      return _diagnostics?.nextOperationId();
    } on Object {
      return null;
    }
  }

  void _recordDiagnostic(
    int? operationId, {
    required DiagnosticOperation operation,
    required DiagnosticTrigger? trigger,
    required DiagnosticPhase phase,
    required DiagnosticStage stage,
    DiagnosticCode code = DiagnosticCode.none,
  }) {
    if (operationId == null) return;
    try {
      _diagnostics?.record(
        operation: operation,
        stage: stage,
        code: code,
        operationId: operationId,
        phase: phase,
        trigger: trigger,
      );
    } on Object {
      // Diagnostics must not change the profile operation being observed.
    }
  }

  DiagnosticCode _diagnosticCodeForFailure(ProfileFailure failure) => switch (failure) {
    ProfileCancelByUserFailure() => DiagnosticCode.cancelled,
    ProfileUnexpectedFailure(error: HiddifyCoreInitializationException()) => DiagnosticCode.coreUnavailable,
    ProfileInvalidConfigFailure() => DiagnosticCode.invalidConfig,
    _ => DiagnosticCode.unknown,
  };

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
