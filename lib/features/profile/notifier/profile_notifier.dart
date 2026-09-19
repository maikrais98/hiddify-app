import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/observability/observability.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/utils/riverpod_utils.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'profile_notifier.g.dart';

enum ImportPhase { idle, validating, fetching, parsing, success, invalid, network, unsafe, cancel }

ImportPhase importPhaseForFailure(Object? error) => switch (error) {
  ProfileCancelByUserFailure() => ImportPhase.cancel,
  ProfileUnexpectedFailure(error: final cause) => importPhaseForFailure(cause),
  DioException() || SocketException() || TimeoutException() || HandshakeException() => ImportPhase.network,
  ProfileInvalidConfigFailure(message: 'Profile download deadline exceeded.') => ImportPhase.network,
  _ => ImportPhase.invalid,
};

ObservabilityErrorCode _profileFailureCode(Object? error) => switch (error) {
  ProfileInvalidUrlFailure() => ObservabilityErrorCode.invalidUrl,
  ProfileInvalidConfigFailure() => ObservabilityErrorCode.invalidConfiguration,
  ProfileNotFoundFailure() => ObservabilityErrorCode.accessNotFound,
  ProfileUnexpectedFailure(error: final cause) when cause is ProfileFailure => _profileFailureCode(cause),
  _ => ObservabilityErrorCode.accessUnexpected,
};

void _emitAccessStage(OperationHandle operation, ObservabilityOperation kind, ObservabilityEvent event) {
  Observability.event(
    module: ObservabilityModule.access,
    operation: kind,
    name: event,
    status: ObservabilityStatus.observed,
    operationId: operation.id,
  );
}

final importPhaseProvider = StateProvider.autoDispose<ImportPhase>((ref) => ImportPhase.idle);

@riverpod
class AddProfileNotifier extends _$AddProfileNotifier {
  @override
  AsyncValue<Unit?> build() {
    ref.onDispose(() {
      _generation++;
      if (_currentPhase == ImportPhase.validating || _currentPhase == ImportPhase.fetching) {
        _cancelToken?.cancel();
        _cancelActiveOperation();
      }
    });
    return const AsyncData(null);
  }

  CancelToken? _cancelToken;
  int _generation = 0;
  Future<void> Function()? _retry;
  OperationHandle? _activeOperation;

  ImportPhase _currentPhase = ImportPhase.idle;

  ImportPhase get _phase => ref.read(importPhaseProvider);

  set _phase(ImportPhase phase) {
    _currentPhase = phase;
    ref.read(importPhaseProvider.notifier).state = phase;
  }

  void reset() {
    _generation++;
    _cancelToken?.cancel();
    _cancelActiveOperation();
    _retry = null;
    state = const AsyncData(null);
    _phase = ImportPhase.idle;
  }

  void cancel() {
    if (_phase != ImportPhase.validating && _phase != ImportPhase.fetching) return;
    _generation++;
    _cancelToken?.cancel();
    _cancelActiveOperation();
    state = const AsyncData(null);
    _phase = ImportPhase.cancel;
  }

  Future<void> retry() async => _retry?.call();

  Future<void> addClipboard(String rawInput) => _run(rawInput);

  Future<void> addManual({required String url, required UserOverride userOverride}) =>
      _run(url, userOverride: userOverride, manual: true);

  void _stage(OperationHandle operation, ObservabilityEvent event) {
    _emitAccessStage(operation, ObservabilityOperation.accessImport, event);
  }

  void _cancelActiveOperation() {
    _activeOperation?.cancel();
    _activeOperation = null;
  }

  Future<void> _run(String input, {UserOverride? userOverride, bool manual = false}) async {
    if (state.isLoading) return;
    final operation = Observability.client.startOperation(
      module: ObservabilityModule.access,
      operation: ObservabilityOperation.accessImport,
    );
    _activeOperation = operation;
    final generation = ++_generation;
    _retry = () => _run(input, userOverride: userOverride, manual: manual);
    _cancelToken = CancelToken();
    state = const AsyncLoading();
    _phase = ImportPhase.validating;
    _stage(operation, ObservabilityEvent.accessValidating);
    final result = await AsyncValue.guard(() async {
      if (input.trim().isEmpty) throw const ProfileFailure.invalidUrl();
      final link = LinkParser.parse(input);
      if (manual && link == null) throw const ProfileFailure.invalidUrl();
      final repo = ref.read(profileRepositoryProvider).requireValue;
      final TaskEither<ProfileFailure, Unit> task;
      if (link != null) {
        final uri = Uri.tryParse(link.url);
        if (uri == null || uri.host.isEmpty) throw const ProfileFailure.invalidUrl();
        if (uri.scheme != 'https') {
          if (generation == _generation) _phase = ImportPhase.unsafe;
          throw const ProfileFailure.invalidUrl();
        }
        _phase = ImportPhase.fetching;
        _stage(operation, ObservabilityEvent.accessFetching);
        task = repo.upsertRemote(
          link.url,
          userOverride: userOverride ?? (link.name.isNotEmpty ? UserOverride(name: link.name) : null),
          cancelToken: _cancelToken,
          onParsing: () {
            if (generation == _generation) {
              _phase = ImportPhase.parsing;
              _stage(operation, ObservabilityEvent.accessParsing);
            }
          },
          onValidating: () => _stage(operation, ObservabilityEvent.accessValidating),
          onPersisting: () => _stage(operation, ObservabilityEvent.accessPersisting),
        );
      } else {
        _phase = ImportPhase.parsing;
        _stage(operation, ObservabilityEvent.accessParsing);
        task = repo.addLocal(
          safeDecodeBase64(input),
          cancelToken: _cancelToken,
          onValidating: () => _stage(operation, ObservabilityEvent.accessValidating),
          onPersisting: () => _stage(operation, ObservabilityEvent.accessPersisting),
        );
      }
      return await task.match((error) => throw error, (_) => unit).run();
    });
    if (result.hasValue) {
      operation.success();
    } else if (result.error is ProfileCancelByUserFailure) {
      operation.cancel();
    } else {
      operation.failure(_profileFailureCode(result.error));
    }
    if (identical(_activeOperation, operation)) _activeOperation = null;
    if (generation != _generation) return;
    state = result;
    if (result.hasValue) {
      _retry = null;
      _phase = ImportPhase.success;
    } else if (_phase != ImportPhase.unsafe) {
      _phase = importPhaseForFailure(result.error);
    }
  }
}

@riverpod
class UpdateProfileNotifier extends _$UpdateProfileNotifier with AppLogger {
  @override
  AsyncValue<Unit?> build(String id) {
    ref.disposeDelay(const Duration(minutes: 1));
    listenSelf((previous, next) {
      final t = ref.read(translationsProvider).requireValue;
      final notification = ref.read(inAppNotificationControllerProvider);
      switch (next) {
        case AsyncData(value: final _?):
          notification.showSuccessToast(t.pages.profiles.msg.update.success);
        case AsyncError(:final error):
          ref
              .read(dialogNotifierProvider.notifier)
              .showCustomAlertFromErr(t.presentError(error, action: t.pages.profiles.msg.update.failure));
      }
    });
    return const AsyncData(null);
  }

  ProfileRepository get _profilesRepo => ref.read(profileRepositoryProvider).requireValue;

  Future<void> updateProfile(RemoteProfileEntity profile) async {
    if (state.isLoading) return;
    final operation = Observability.client.startOperation(
      module: ObservabilityModule.access,
      operation: ObservabilityOperation.accessUpdate,
    );
    state = const AsyncLoading();
    try {
      await ref.read(hapticServiceProvider.notifier).lightImpact();
      state = await AsyncValue.guard(() async {
        _emitAccessStage(operation, ObservabilityOperation.accessUpdate, ObservabilityEvent.accessFetching);
        return await _profilesRepo
            .upsertRemote(
              profile.url,
              onParsing: () =>
                  _emitAccessStage(operation, ObservabilityOperation.accessUpdate, ObservabilityEvent.accessParsing),
              onValidating: () =>
                  _emitAccessStage(operation, ObservabilityOperation.accessUpdate, ObservabilityEvent.accessValidating),
              onPersisting: () =>
                  _emitAccessStage(operation, ObservabilityOperation.accessUpdate, ObservabilityEvent.accessPersisting),
            )
            .match(
              (err) {
                loggy.warning("failed to update profile");
                throw err;
              },
              (_) async {
                loggy.info('successfully updated profile');

                await ref.read(activeProfileProvider.future).then((active) async {
                  if (active != null && active.id == profile.id) {
                    await ref.read(connectionNotifierProvider.notifier).reconnect(profile);
                  }
                });
                return unit;
              },
            )
            .run();
      });
      if (state.hasValue) {
        operation.success();
      } else {
        operation.failure(_profileFailureCode(state.error));
      }
    } catch (error) {
      operation.failure(_profileFailureCode(error));
      rethrow;
    }
  }
}

@riverpod
class AddProfilePageNotifier extends _$AddProfilePageNotifier {
  @override
  AddProfilePages build() => AddProfilePages.options;

  void goOptions() => state = AddProfilePages.options;
  void goManual() => state = AddProfilePages.manual;
}

enum AddProfilePages { options, manual }
