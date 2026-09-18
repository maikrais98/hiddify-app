import 'dart:io';

import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/observability/observability.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/data/connection_data_providers.dart';
import 'package:hiddify/features/connection/data/connection_repository.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rxdart/rxdart.dart';

part 'connection_notifier.g.dart';

@Riverpod(keepAlive: true)
class ConnectionNotifier extends _$ConnectionNotifier with AppLogger {
  ConnectionNotifier({bool? initializeOnBuild}) : _initializeOnBuild = initializeOnBuild ?? Platform.isIOS;

  final bool _initializeOnBuild;
  bool _initializationFailed = false;
  String? _connectionOperationId;
  bool get needsInitializationRetry => _initializationFailed;

  @override
  Stream<ConnectionStatus> build() async* {
    if (_initializeOnBuild) {
      final operationId = Observability.newOperationId();
      final stopwatch = Stopwatch()..start();
      Observability.event(
        module: ObservabilityModule.vpn,
        operation: ObservabilityOperation.initialize,
        name: ObservabilityEvent.vpnInitializationStarted,
        status: ObservabilityStatus.started,
        operationId: operationId,
      );
      final result = await _connectionRepo.setup().run();
      final failure = result.getLeft().toNullable();
      _initializationFailed = failure != null;
      if (failure != null) {
        Observability.event(
          module: ObservabilityModule.vpn,
          operation: ObservabilityOperation.initialize,
          name: ObservabilityEvent.vpnInitializationFailed,
          status: ObservabilityStatus.failed,
          operationId: operationId,
          durationMs: stopwatch.elapsedMilliseconds,
          errorCode: _connectionFailureCode(failure),
          level: ObservabilityLevel.error,
        );
        // End initialization before touching clients that setup did not create.
        // Riverpod preserves this typed error in AsyncError for the UI/retry.
        throw failure;
      }
      Observability.event(
        module: ObservabilityModule.vpn,
        operation: ObservabilityOperation.initialize,
        name: ObservabilityEvent.vpnInitializationSucceeded,
        status: ObservabilityStatus.succeeded,
        operationId: operationId,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }

    listenSelf((previous, next) async {
      if (previous == next) return;
      if (previous case AsyncData(:final value) when !value.isConnected) {
        if (next case AsyncData(value: final Connected _)) {
          await ref.read(hapticServiceProvider.notifier).heavyImpact();

          if (Platform.isAndroid && !ref.read(Preferences.storeReviewedByUser)) {
            if (await InAppReview.instance.isAvailable()) {
              InAppReview.instance.requestReview();
              ref.read(Preferences.storeReviewedByUser.notifier).update(true);
            }
          }
        }
      }
    });

    ref.listen(activeProfileProvider.select((value) => value.asData?.value), (previous, next) async {
      if (previous == null) return;
      final shouldReconnect = next == null || previous.id != next.id;
      if (shouldReconnect) {
        await reconnect(next);
      }
    });
    ref.watch(coreRestartSignalProvider);

    yield* _connectionRepo.watchConnectionStatus().doOnData((event) {
      if (event case Disconnected(connectionFailure: final _?) when PlatformUtils.isDesktop) {
        Future.microtask(() => ref.read(Preferences.startedByUser.notifier).update(false));
      }
      final failure = event is Disconnected ? event.connectionFailure : null;
      final operationId = _connectionOperationId;
      Observability.event(
        module: ObservabilityModule.vpn,
        operation: ObservabilityOperation.connection,
        name: ObservabilityEvent.vpnConnectionStateChanged,
        status: _connectionStatusCode(event),
        operationId: operationId,
        errorCode: failure == null ? null : _connectionFailureCode(failure),
        level: failure == null ? ObservabilityLevel.info : ObservabilityLevel.warning,
      );
      if (event is Connected || event is Disconnected) {
        _connectionOperationId = null;
      }
    });
  }

  ConnectionRepository get _connectionRepo => ref.read(connectionRepositoryProvider);

  Future<void> mayConnect() async {
    if (_initializationFailed) return retryInitialization();
    if (state is AsyncError || state.valueOrNull is Disconnected) {
      await ref.read(Preferences.startedByUser.notifier).update(true);
      await _connect();
    }
  }

  Future<void> retryInitialization() async {
    if (!_initializationFailed) return;
    ref.invalidateSelf();
    try {
      await future;
    } on ConnectionFailure {
      // The rebuilt provider exposes the fresh typed error for another retry.
    }
  }

  Future<void> toggleConnection() async {
    if (_initializationFailed) return retryInitialization();
    final haptic = ref.read(hapticServiceProvider.notifier);
    if (state case AsyncError()) {
      await haptic.lightImpact();
      await _connect();
    } else if (state case AsyncData(:final value)) {
      switch (value) {
        case Disconnected():
          await haptic.lightImpact();
          await ref.read(Preferences.startedByUser.notifier).update(true);
          await _connect();
        case Connected():
          // default:
          await haptic.mediumImpact();
          await ref.read(Preferences.startedByUser.notifier).update(false);
          await _disconnect();
        default:
          loggy.warning("switching status, debounce");
      }
    }
  }

  Future<void> reconnect(ProfileEntity? profile) async {
    if (state case AsyncData(:final value) when value == const Connected()) {
      if (profile == null) {
        loggy.info("no active profile, disconnecting");
        return _disconnect();
      }
      loggy.info("active profile changed, reconnecting");
      final operationId = Observability.newOperationId();
      final stopwatch = Stopwatch()..start();
      _connectionOperationId = operationId;
      Observability.event(
        module: ObservabilityModule.vpn,
        operation: ObservabilityOperation.reconnect,
        name: ObservabilityEvent.vpnReconnectStarted,
        status: ObservabilityStatus.started,
        operationId: operationId,
      );
      await ref.read(Preferences.startedByUser.notifier).update(true);
      await _connectionRepo
          .reconnect(profile, ref.read(Preferences.disableMemoryLimit), operationId: operationId)
          .mapLeft((err) async {
            Observability.event(
              module: ObservabilityModule.vpn,
              operation: ObservabilityOperation.reconnect,
              name: ObservabilityEvent.vpnReconnectFailed,
              status: ObservabilityStatus.failed,
              operationId: operationId,
              durationMs: stopwatch.elapsedMilliseconds,
              errorCode: _connectionFailureCode(err),
              level: ObservabilityLevel.error,
            );
            _connectionOperationId = null;
            state = AsyncError(err, StackTrace.current);
            await ref
                .read(dialogNotifierProvider.notifier)
                .showCustomAlertFromErr(err.present(ref.read(translationsProvider).requireValue));
          })
          .map((_) {
            Observability.event(
              module: ObservabilityModule.vpn,
              operation: ObservabilityOperation.reconnect,
              name: ObservabilityEvent.vpnReconnectSucceeded,
              status: ObservabilityStatus.succeeded,
              operationId: operationId,
              durationMs: stopwatch.elapsedMilliseconds,
            );
          })
          .run();
    }
  }

  Future<void> abortConnection() async {
    if (state case AsyncData(:final value)) {
      switch (value) {
        case Connected() || Connecting():
          loggy.debug("aborting connection");
          await _disconnect();
        default:
      }
    }
  }

  final _singleStart = SingleCall();

  Future<void> _connect() async {
    await _singleStart.run(
      () async {
        await _connectThrottled();
      },
      onIgnored: () {
        loggy.debug("connect called while another connect/disconnect is still running, ignoring");
      },
    );
  }

  Future<void> _connectThrottled() async {
    final activeProfile = await ref.read(activeProfileProvider.future);
    if (activeProfile == null) {
      loggy.info("no active profile, not connecting");
      return;
    }
    final operationId = Observability.newOperationId();
    final stopwatch = Stopwatch()..start();
    _connectionOperationId = operationId;
    Observability.event(
      module: ObservabilityModule.vpn,
      operation: ObservabilityOperation.connect,
      name: ObservabilityEvent.vpnConnectionStarted,
      status: ObservabilityStatus.started,
      operationId: operationId,
    );
    await _connectionRepo
        .connect(activeProfile, ref.read(Preferences.disableMemoryLimit), operationId: operationId)
        .mapLeft((ConnectionFailure err) async {
          Observability.event(
            module: ObservabilityModule.vpn,
            operation: ObservabilityOperation.connect,
            name: ObservabilityEvent.vpnConnectionFailed,
            status: ObservabilityStatus.failed,
            operationId: operationId,
            durationMs: stopwatch.elapsedMilliseconds,
            errorCode: _connectionFailureCode(err),
            level: ObservabilityLevel.error,
          );
          _connectionOperationId = null;
          await ref
              .read(dialogNotifierProvider.notifier)
              .showCustomAlertFromErr(err.present(ref.read(translationsProvider).requireValue));
          await ref.read(Preferences.startedByUser.notifier).update(false);
          state = AsyncError(err, StackTrace.current);
        })
        .map((_) {
          Observability.event(
            module: ObservabilityModule.vpn,
            operation: ObservabilityOperation.connect,
            name: ObservabilityEvent.vpnConnected,
            status: ObservabilityStatus.succeeded,
            operationId: operationId,
            durationMs: stopwatch.elapsedMilliseconds,
          );
        })
        .run();
  }

  Future<void> _disconnect() async {
    final operationId = Observability.newOperationId();
    final stopwatch = Stopwatch()..start();
    _connectionOperationId = operationId;
    Observability.event(
      module: ObservabilityModule.vpn,
      operation: ObservabilityOperation.disconnect,
      name: ObservabilityEvent.vpnDisconnectStarted,
      status: ObservabilityStatus.started,
      operationId: operationId,
    );
    await _connectionRepo
        .disconnect()
        .mapLeft((err) {
          Observability.event(
            module: ObservabilityModule.vpn,
            operation: ObservabilityOperation.disconnect,
            name: ObservabilityEvent.vpnDisconnectFailed,
            status: ObservabilityStatus.failed,
            operationId: operationId,
            durationMs: stopwatch.elapsedMilliseconds,
            errorCode: _connectionFailureCode(err),
            level: ObservabilityLevel.error,
          );
          _connectionOperationId = null;
          ref
              .read(dialogNotifierProvider.notifier)
              .showCustomAlertFromErr(err.present(ref.read(translationsProvider).requireValue));
          state = AsyncError(err, StackTrace.current);
        })
        .map((_) {
          Observability.event(
            module: ObservabilityModule.vpn,
            operation: ObservabilityOperation.disconnect,
            name: ObservabilityEvent.vpnDisconnected,
            status: ObservabilityStatus.succeeded,
            operationId: operationId,
            durationMs: stopwatch.elapsedMilliseconds,
          );
        })
        .run();
  }
}

ObservabilityStatus _connectionStatusCode(ConnectionStatus status) => switch (status) {
  Disconnected() => ObservabilityStatus.disconnected,
  Connecting() => ObservabilityStatus.connecting,
  Connected() => ObservabilityStatus.connected,
  Disconnecting() => ObservabilityStatus.disconnecting,
};

ObservabilityErrorCode _connectionFailureCode(ConnectionFailure failure) => switch (failure) {
  MissingVpnPermission() => ObservabilityErrorCode.vpnPermissionDenied,
  MissingNotificationPermission() => ObservabilityErrorCode.notificationPermissionDenied,
  MissingPrivilege() => ObservabilityErrorCode.missingPrivilege,
  InvalidConfigOption() => ObservabilityErrorCode.invalidConfigurationOptions,
  InvalidConfig() => ObservabilityErrorCode.invalidConfiguration,
  BackgroundCoreNotAvailable() => ObservabilityErrorCode.coreUnavailable,
  MissingWarpLicense() => ObservabilityErrorCode.warpLicenseMissing,
  MissingPsiphonLicense() => ObservabilityErrorCode.psiphonLicenseMissing,
  UnexpectedConnectionFailure() => ObservabilityErrorCode.unexpectedConnectionFailure,
};

@Riverpod(keepAlive: true)
bool serviceRunning(Ref ref) {
  // ref.watch(coreRestartSignalProvider);
  return ref.watch(connectionNotifierProvider).valueOrNull?.isConnected ?? false;
}

class SingleCall {
  bool _running = false;

  Future<T> run<T>(Future<T> Function() task, {required T onIgnored}) async {
    if (_running) return onIgnored;

    _running = true;
    try {
      return await task();
    } finally {
      _running = false;
    }
  }
}
