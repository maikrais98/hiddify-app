import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/utils/exception_handler.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/diagnostics/connection_diagnostic_scope.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_event.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/notifier/warp_option/warp_option_notifier.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:meta/meta.dart';

abstract interface class ConnectionRepository {
  SingboxConfigOption? get configOptionsSnapshot;

  TaskEither<ConnectionFailure, Unit> setup();
  Stream<ConnectionStatus> watchConnectionStatus();
  TaskEither<ConnectionFailure, Unit> connect(ProfileEntity activeProfile, bool disableMemoryLimit);
  TaskEither<ConnectionFailure, Unit> disconnect();
  TaskEither<ConnectionFailure, Unit> reconnect(ProfileEntity activeProfile, bool disableMemoryLimit);
}

class ConnectionRepositoryImpl with ExceptionHandler, InfraLogger implements ConnectionRepository {
  ConnectionRepositoryImpl({
    required this.ref,
    required this.directories,
    required this.singbox,
    required this.configOptionRepository,
    required this.profilePathResolver,
  });

  final Ref ref;

  final Directories directories;
  final HiddifyCoreService singbox;

  final ConfigOptionRepository configOptionRepository;
  final ProfilePathResolver profilePathResolver;

  SingboxConfigOption? _configOptionsSnapshot;
  @override
  SingboxConfigOption? get configOptionsSnapshot => _configOptionsSnapshot;

  bool _initialized = false;

  @override
  TaskEither<ConnectionFailure, Unit> setup() {
    if (_initialized) return TaskEither.of(unit);
    return exceptionHandler(() {
      loggy.debug("setting up singbox");

      return singbox
          .setup()
          .map((r) {
            _initialized = true;
            return r;
          })
          .mapLeft(UnexpectedConnectionFailure.new)
          .run();
    }, UnexpectedConnectionFailure.new);
  }

  @override
  Stream<ConnectionStatus> watchConnectionStatus() {
    return singbox.watchStatus().map(
      (event) => switch (event) {
        CoreStopped() => Disconnected(event.getCoreAlert()),
        CoreStarting() => const Connecting(),
        CoreStarted() => const Connected(),
        CoreStopping() => const Disconnecting(),
      },
    );
  }

  @override
  TaskEither<ConnectionFailure, Unit> connect(ProfileEntity activeProfile, bool disableMemoryLimit) =>
      (singbox.core.supportsSystemStatus ? _ensureForegroundReady() : setup()).flatMap(
        (_) => applyConfigOption(activeProfile).flatMap(
          (_) => ConnectionDiagnosticScope.observe(
            singbox.start(profilePathResolver.file(activeProfile.id).path, activeProfile.name, disableMemoryLimit),
            phase: DiagnosticPhase.backgroundStart,
            failureCode: diagnosticCodeForFailure,
          ),
          // .mapLeft(UnexpectedConnectionFailure.new),
        ),
      );

  @override
  TaskEither<ConnectionFailure, Unit> disconnect() => singbox.stop().mapLeft(UnexpectedConnectionFailure.new);

  @override
  TaskEither<ConnectionFailure, Unit> reconnect(ProfileEntity activeProfile, bool disableMemoryLimit) =>
      _ensureForegroundReady().flatMap(
        (_) => applyConfigOption(activeProfile).flatMap(
          (_) => ConnectionDiagnosticScope.observe(
            singbox
                .restart(profilePathResolver.file(activeProfile.id).path, activeProfile.name, disableMemoryLimit)
                .mapLeft(UnexpectedConnectionFailure.new),
            phase: DiagnosticPhase.backgroundStart,
            failureCode: diagnosticCodeForFailure,
          ),
        ),
      );

  TaskEither<ConnectionFailure, Unit> _ensureForegroundReady() {
    if (!singbox.core.supportsSystemStatus) return TaskEither.right(unit);
    return ConnectionDiagnosticScope.observe<ConnectionFailure, Unit>(
      TaskEither(() async {
        final ready = await singbox.ensureForegroundReady();
        return ready ? right(unit) : left(const ConnectionFailure.backgroundCoreNotAvailable());
      }),
      phase: DiagnosticPhase.foregroundReady,
      failureCode: diagnosticCodeForFailure,
    );
  }

  @visibleForTesting
  TaskEither<ConnectionFailure, Unit> applyConfigOption(ProfileEntity prof) =>
      TaskEither.fromEither(configOptionRepository.fullOptionsOverrided(prof.profileOverride))
          .mapLeft((l) {
            ConnectionDiagnosticScope.record(
              DiagnosticPhase.optionsReady,
              DiagnosticStage.failed,
              DiagnosticCode.invalidConfigOption,
            );
            return ConnectionFailure.invalidConfigOption(null, l);
          })
          .flatMap((overridedOptions) {
            ConnectionDiagnosticScope.record(
              DiagnosticPhase.optionsReady,
              DiagnosticStage.accepted,
              DiagnosticCode.none,
            );
            return TaskEither.tryCatch(() async {
              final isWarpLicenseAgreed = ref.read(warpLicenseNotifierProvider);
              final isWarpEnabled = overridedOptions.warp.enable || overridedOptions.warp2.enable;
              if (!isWarpLicenseAgreed && isWarpEnabled) {
                final isAgreed = await ref.read(dialogNotifierProvider.notifier).showWarpLicense();
                if (isAgreed == true) {
                  await ref.read(warpLicenseNotifierProvider.notifier).agree();
                  // return (await applyConfigOption(prof).run()).match((l) => throw l, (_) => unit);
                } else {
                  throw const MissingWarpLicense();
                }
              }
              return (await ConnectionDiagnosticScope.observe(
                singbox.changeOptions(overridedOptions),
                phase: DiagnosticPhase.changeOptions,
                failureCode: (failure) => failure == 'foreground_settings_unavailable'
                    ? DiagnosticCode.coreUnavailable
                    : DiagnosticCode.invalidConfigOption,
              ).run()).match(
                (failure) => throw failure == 'foreground_settings_unavailable'
                    ? ConnectionFailure.backgroundCoreNotAvailable(failure)
                    : ConnectionFailure.invalidConfigOption(failure),
                (_) {
                  _configOptionsSnapshot = overridedOptions;
                  return unit;
                },
              );
            }, (err, st) => err is ConnectionFailure ? err : ConnectionFailure.unexpected(err, st));
          });
}
