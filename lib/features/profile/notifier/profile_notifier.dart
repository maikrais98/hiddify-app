import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
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

final importPhaseProvider = StateProvider.autoDispose<ImportPhase>((ref) => ImportPhase.idle);

@riverpod
class AddProfileNotifier extends _$AddProfileNotifier {
  @override
  AsyncValue<Unit?> build() {
    ref.onDispose(() {
      _generation++;
      if (_currentPhase == ImportPhase.validating || _currentPhase == ImportPhase.fetching) {
        _cancelToken?.cancel();
      }
    });
    return const AsyncData(null);
  }

  CancelToken? _cancelToken;
  int _generation = 0;
  Future<void> Function()? _retry;

  ImportPhase _currentPhase = ImportPhase.idle;

  ImportPhase get _phase => ref.read(importPhaseProvider);

  set _phase(ImportPhase phase) {
    _currentPhase = phase;
    ref.read(importPhaseProvider.notifier).state = phase;
  }

  void reset() {
    _generation++;
    _cancelToken?.cancel();
    _retry = null;
    state = const AsyncData(null);
    _phase = ImportPhase.idle;
  }

  void cancel() {
    if (_phase != ImportPhase.validating && _phase != ImportPhase.fetching) return;
    _generation++;
    _cancelToken?.cancel();
    state = const AsyncData(null);
    _phase = ImportPhase.cancel;
  }

  Future<void> retry() async => _retry?.call();

  Future<void> addClipboard(String rawInput) => _run(rawInput);

  Future<void> addManual({required String url, required UserOverride userOverride}) =>
      _run(url, userOverride: userOverride, manual: true);

  Future<void> _run(String input, {UserOverride? userOverride, bool manual = false}) async {
    if (state.isLoading) return;
    final generation = ++_generation;
    _retry = () => _run(input, userOverride: userOverride, manual: manual);
    _cancelToken = CancelToken();
    state = const AsyncLoading();
    _phase = ImportPhase.validating;
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
        task = repo.upsertRemote(
          link.url,
          userOverride: userOverride ?? (link.name.isNotEmpty ? UserOverride(name: link.name) : null),
          cancelToken: _cancelToken,
          onParsing: () {
            if (generation == _generation) _phase = ImportPhase.parsing;
          },
        );
      } else {
        _phase = ImportPhase.parsing;
        task = repo.addLocal(safeDecodeBase64(input), cancelToken: _cancelToken);
      }
      return await task.match((error) => throw error, (_) => unit).run();
    });
    if (generation != _generation) return;
    state = result;
    if (result.hasValue) {
      _retry = null;
      _phase = ImportPhase.success;
    } else if (_phase != ImportPhase.unsafe) {
      final error = result.error;
      _phase = switch (error) {
        ProfileCancelByUserFailure() => ImportPhase.cancel,
        ProfileUnexpectedFailure(error: DioException()) => ImportPhase.network,
        _ => ImportPhase.invalid,
      };
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
    state = const AsyncLoading();
    await ref.read(hapticServiceProvider.notifier).lightImpact();
    state = await AsyncValue.guard(() async {
      return await _profilesRepo
          .upsertRemote(profile.url)
          .match(
            (err) {
              loggy.warning("failed to update profile", err);
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
