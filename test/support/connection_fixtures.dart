import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/data/connection_repository.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final connectionProfile = ProfileEntity.local(
  id: 'synthetic-profile',
  active: true,
  name: 'Synthetic profile',
  lastUpdate: DateTime.utc(2026),
);

class FixtureProfile extends ActiveProfile {
  FixtureProfile(this.profile);
  final ProfileEntity? profile;
  @override
  Stream<ProfileEntity?> build() => Stream.value(profile);
}

class FixtureProxy extends ActiveProxyNotifier {
  FixtureProxy(this.delay);
  final int delay;
  @override
  Stream<OutboundInfo> build() => Stream.value(OutboundInfo(urlTestDelay: delay));
}

class FixtureConfig extends ConfigOptionNotifier {
  FixtureConfig(this.reconnectRequired);
  final bool reconnectRequired;
  @override
  Future<bool> build() async => reconnectRequired;
}

// This spy is ONLY for the widget's callback binding; notifier tests use the real notifier.
class ButtonConnectionSpy extends ConnectionNotifier {
  ButtonConnectionSpy(this.initial, this.events);
  final AsyncValue<ConnectionStatus> initial;
  final List<String> events;
  ProfileEntity? reconnectedProfile;
  @override
  Stream<ConnectionStatus> build() {
    return switch (initial) {
      AsyncData(:final value) => Stream.value(value),
      AsyncError(:final error, :final stackTrace) => Stream.error(error, stackTrace),
      _ => const Stream.empty(),
    };
  }

  @override
  Future<void> toggleConnection() async {
    events.add('toggle');
  }

  @override
  Future<void> reconnect(ProfileEntity? profile) async {
    reconnectedProfile = profile;
    events.add('reconnect');
  }
}

class FixtureDialogs extends DialogNotifier {
  FixtureDialogs(this.events);
  final List<String> events;
  Completer<void>? noProfile;
  Completer<bool>? notice;
  bool noticeResult = true;
  @override
  void build() {}
  @override
  Future<void> showNoActiveProfile() async {
    events.add('no-profile');
    await noProfile?.future;
  }

  @override
  Future<bool> showExperimentalFeatureNotice() async {
    events.add('notice');
    return notice == null ? noticeResult : await notice!.future;
  }

  @override
  Future<void> showCustomAlertFromErr(({String type, String? message}) err) async {
    events.add('error-dialog');
  }
}

class FixtureSheets extends BottomSheetsNotifier {
  FixtureSheets(this.events);
  final List<String> events;
  @override
  void build() {}
  @override
  Future<void> showAddProfile({String? url}) async {
    events.add('add-profile:$url');
  }
}

class RecordingConnectionRepository implements ConnectionRepository {
  final statuses = StreamController<ConnectionStatus>.broadcast();
  final calls = <String>[];
  final args = <(ProfileEntity, bool)>[];
  Completer<void>? connectGate;
  ConnectionFailure? failure;
  @override
  SingboxConfigOption? get configOptionsSnapshot => null;
  @override
  TaskEither<ConnectionFailure, Unit> setup() => TaskEither.of(unit);
  @override
  Stream<ConnectionStatus> watchConnectionStatus() => statuses.stream;
  TaskEither<ConnectionFailure, Unit> operation(String name, [ProfileEntity? profile, bool? memory]) =>
      TaskEither(() async {
        calls.add(name);
        if (profile != null) args.add((profile, memory!));
        if (name == 'connect') await connectGate?.future;
        return failure == null ? right(unit) : left(failure!);
      });
  @override
  TaskEither<ConnectionFailure, Unit> connect(ProfileEntity profile, bool memory) =>
      operation('connect', profile, memory);
  @override
  TaskEither<ConnectionFailure, Unit> reconnect(ProfileEntity profile, bool memory) =>
      operation('reconnect', profile, memory);
  @override
  TaskEither<ConnectionFailure, Unit> disconnect() => operation('disconnect');
}
