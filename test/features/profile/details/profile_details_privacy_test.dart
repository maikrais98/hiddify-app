import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/analytics/analytics_filter.dart' as analytics;
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/logger/sinks/sentry_sink.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/details/profile_details_notifier.dart';
import 'package:hiddify/features/profile/details/profile_details_state.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

// Artificial markers only; the repository/core boundary never reads user files.
const _canaries = ['fixture-vless-credential', 'fixture-proxy-password', 'fixture-endpoint-private-key', '8140275963'];
const _safeDiagnostic = 'synthetic profile diagnostic probe';
final _outbounds = [
  {'type': 'vless', 'tag': 'fixture-vless', 'server': 'vpn.example.invalid', 'uuid': _canaries[0]},
  {'type': 'shadowsocks', 'tag': 'fixture-proxy', 'server': 'proxy.example.invalid', 'password': _canaries[1]},
];
final _endpoints = [
  {'type': 'wireguard', 'tag': 'fixture-endpoint', 'private_key': _canaries[2]},
];
final _configuration = jsonEncode({
  'outbounds': [
    ..._outbounds,
    {'type': 'selector', 'tag': 'fixture-selector'},
    {'type': 'direct', 'tag': 'direct'},
  ],
  'endpoints': _endpoints,
});

class _SyntheticProfiles implements ProfileRepository {
  _SyntheticProfiles({this.generationFails = false, String? content}) : content = content ?? _configuration;

  final bool generationFails;
  final String content;
  int rawReads = 0;
  final saved = <(ProfileEntity, String)>[];
  final profile = ProfileEntity.local(
    id: 'synthetic-profile',
    active: false,
    name: 'Offline diagnostic fixture',
    lastUpdate: DateTime.utc(2026, 10, 14),
  );

  @override
  TaskEither<ProfileFailure, ProfileEntity?> getById(String id) => TaskEither.right(profile);

  @override
  TaskEither<ProfileFailure, String> generateConfig(String id) => generationFails
      ? TaskEither.left(ProfileFailure.unexpected(StateError('synthetic converter unavailable')))
      : TaskEither.right(content);

  @override
  TaskEither<ProfileFailure, String> getRawConfig(String id) => TaskEither(() async {
    rawReads++;
    return right(content);
  });

  @override
  TaskEither<ProfileFailure, Unit> offlineUpdate(ProfileEntity profile, String content) => TaskEither(() async {
    saved.add((profile, content));
    return right(unit);
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SuccessNotifications extends InAppNotificationController {
  final messages = <String>[];

  @override
  void showSuccessToast(String message, {ToastAction? action}) {
    messages.add(message);
  }
}

class _MemoryTransport implements Transport {
  final payloads = <String>[];

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    for (final item in envelope.items) {
      if (item.header.type == 'event') {
        payloads.add(utf8.decode(await item.dataFactory()));
      }
    }
    return envelope.header.eventId;
  }
}

// Observe the production logging stream and use the current sink's event and
// breadcrumb converters with an offline Hub, keeping the real SDK serialization.
class _RecordingLogs {
  _RecordingLogs(this.hub) {
    previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    subscription = Logger.root.onRecord.listen(onLog);
  }

  final Hub hub;
  late final Level previousLevel;
  late final StreamSubscription<LogRecord> subscription;
  final records = <LogRecord>[];
  final pending = <Future<void>>[];

  void onLog(LogRecord record) {
    records.add(record);
    pending.add(forward(record));
  }

  Future<void> forward(LogRecord record) async {
    if (!analytics.canLogEvent(record.error)) return;
    if (record.level >= Level.SEVERE) {
      await hub.captureEvent(record.toSentryEvent(), stackTrace: record.stackTrace);
    }
    if (record.level >= Level.INFO) await hub.addBreadcrumb(record.toBreadcrumb());
  }

  Future<void> flush() async {
    while (pending.isNotEmpty) {
      final batch = List<Future<void>>.of(pending);
      pending.clear();
      await Future.wait(batch);
    }
  }

  Future<void> close() async {
    await flush();
    await subscription.cancel();
    Logger.root.level = previousLevel;
  }

  String get recordContent =>
      records.map((record) => '${record.message}\n${record.object}\n${record.error}\n${record.stackTrace}').join('\n');
}

class _OfflineDiagnostics {
  _OfflineDiagnostics() {
    options = SentryOptions(dsn: 'https://fixture-public-key@example.invalid/1')
      ..transport = transport
      ..beforeSend = analytics.sentryBeforeSend;
    hub = Hub(options);
    logs = _RecordingLogs(hub);
  }

  final transport = _MemoryTransport();
  late final SentryOptions options;
  late final Hub hub;
  late final _RecordingLogs logs;

  Future<void> captureSafeProbe() async {
    await logs.flush();
    Logger('privacy-probe').severe(_safeDiagnostic, StateError('synthetic failure'));
    await logs.flush();
  }

  Future<void> close() async {
    await logs.close();
    await hub.close();
  }
}

void _expectNoConfigurationInDiagnostics(_OfflineDiagnostics diagnostics) {
  // Read the serialized event envelope, after the real Hub and beforeSend.
  expect(diagnostics.transport.payloads, isNotEmpty);
  final serialized = diagnostics.transport.payloads.join('\n');
  expect(serialized, contains(_safeDiagnostic));
  for (final marker in _canaries) {
    expect(
      {'localLog': diagnostics.logs.recordContent.contains(marker), 'eventEnvelope': serialized.contains(marker)},
      {'localLog': false, 'eventEnvelope': false},
      reason: 'configuration must stay in the editor, outside diagnostic sinks',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _OfflineDiagnostics diagnostics;
  late ProviderContainer container;
  late _SuccessNotifications notifications;
  ProviderSubscription<AsyncValue<ProfileDetailsState>>? detailsSubscription;
  int networkAttempts = 0;

  Future<T> offline<T>(Future<T> Function() operation) => HttpOverrides.runZoned(
    operation,
    createHttpClient: (_) {
      networkAttempts++;
      throw StateError('HTTP disabled in offline privacy fixture');
    },
  );

  Future<void> open(_SyntheticProfiles repository) async {
    container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith((ref) => repository),
        translationsProvider.overrideWith((ref) => AppLocale.en.buildSync()),
        inAppNotificationControllerProvider.overrideWith((ref) => notifications),
      ],
    );
    await container.read(profileRepositoryProvider.future);
    final provider = profileDetailsNotifierProvider(repository.profile.id);
    final configReady = Completer<void>();
    detailsSubscription = container.listen(provider, (_, next) {
      if (next.valueOrNull?.config.hasValue == true && !configReady.isCompleted) configReady.complete();
    });
    final initial = await container.read(provider.future);
    expect(initial.profile, repository.profile);
    expect(initial.config.isLoading, isTrue);
    await configReady.future.timeout(const Duration(seconds: 5));
  }

  setUp(() {
    networkAttempts = 0;
    diagnostics = _OfflineDiagnostics();
    notifications = _SuccessNotifications();
  });
  tearDown(() async {
    detailsSubscription?.close();
    detailsSubscription = null;
    container.dispose();
    await diagnostics.close();
    expect(networkAttempts, 0);
  });

  for (final fallback in [false, true]) {
    test(
      '${fallback ? 'raw fallback' : 'generated'} profile credentials stay in editor and out of diagnostics',
      () async {
        await offline(() async {
          final repository = _SyntheticProfiles(generationFails: fallback);
          await open(repository);
          final details = container.read(profileDetailsNotifierProvider(repository.profile.id)).requireValue;
          expect(jsonDecode(details.config.requireValue.text), {'outbounds': _outbounds, 'endpoints': _endpoints});
          expect(details.profile, repository.profile);
          expect(details.isDetailsChanged, isFalse);
          expect(details.isLoading, isFalse);
          expect(repository.rawReads, fallback ? 1 : 0);
          if (fallback) {
            expect(
              diagnostics.logs.records.any(
                (record) => record.message.startsWith('Error generating config for profile'),
              ),
              isTrue,
            );
          }
          await diagnostics.captureSafeProbe();
          _expectNoConfigurationInDiagnostics(diagnostics);
        });
      },
    );
  }

  test('editing a loaded profile preserves the draft and marks it changed without logging credentials', () async {
    await offline(() async {
      final repository = _SyntheticProfiles();
      await open(repository);
      final draft = jsonEncode({'outbounds': _outbounds.reversed.toList(), 'endpoints': _endpoints});
      container.read(profileDetailsNotifierProvider(repository.profile.id).notifier).setContent(draft);
      final details = container.read(profileDetailsNotifierProvider(repository.profile.id)).requireValue;
      expect(details.config.requireValue.text, draft);
      expect(details.profile, repository.profile);
      expect(details.isDetailsChanged, isTrue);
      await diagnostics.captureSafeProbe();
      _expectNoConfigurationInDiagnostics(diagnostics);
    });
  });

  test('saving an edited profile forwards its exact draft once without exposing credentials', () async {
    await offline(() async {
      final repository = _SyntheticProfiles();
      await open(repository);
      final draft = jsonEncode({'outbounds': _outbounds.reversed.toList(), 'endpoints': _endpoints});
      final notifier = container.read(profileDetailsNotifierProvider(repository.profile.id).notifier);
      notifier.setContent(draft);
      expect(await notifier.save(), isTrue);
      expect(repository.saved, [(repository.profile, draft)]);
      expect(notifications.messages, hasLength(1));
      final details = container.read(profileDetailsNotifierProvider(repository.profile.id)).requireValue;
      expect(details.config.requireValue.text, draft);
      expect(details.isLoading, isFalse);
      await diagnostics.captureSafeProbe();
      _expectNoConfigurationInDiagnostics(diagnostics);
    });
  });

  test('malformed synthetic JSON stays editable as plain text', () async {
    await offline(() async {
      const malformed = '{"outbounds": [}';
      final repository = _SyntheticProfiles(content: malformed);
      await open(repository);
      final details = container.read(profileDetailsNotifierProvider(repository.profile.id)).requireValue;
      expect(details.config.requireValue.text, malformed);
      expect(repository.rawReads, 0);
      await diagnostics.captureSafeProbe();
      expect(details.config.requireValue.isJson, isFalse);
    });
  });

  for (final fallback in [false, true]) {
    final path = fallback ? 'raw fallback' : 'generated';
    for (final entry in {'uuid': _canaries[0], 'password': _canaries[1], 'private_key': _canaries[2]}.entries) {
      test('$path malformed JSON keeps ${entry.key} in the editor and out of parse diagnostics', () async {
        await offline(() async {
          final malformed = '{"${entry.key}":"${entry.value}",}';
          final repository = _SyntheticProfiles(generationFails: fallback, content: malformed);
          await open(repository);
          final details = container.read(profileDetailsNotifierProvider(repository.profile.id)).requireValue;
          expect(details.config.requireValue.text, malformed);
          expect(details.profile, repository.profile);
          expect(details.isDetailsChanged, isFalse);
          expect(details.isLoading, isFalse);
          expect(repository.rawReads, fallback ? 1 : 0);
          await diagnostics.captureSafeProbe();
          _expectNoConfigurationInDiagnostics(diagnostics);
          expect(details.config.requireValue.isJson, isFalse);
        });
      });
    }

    final invalidShapes = {
      'numeric scalar': _canaries[3],
      'null scalar': 'null',
      'endpoint object': jsonEncode({'endpoints': _endpoints.single, 'outbounds': _outbounds}),
    };
    for (final entry in invalidShapes.entries) {
      test('$path ${entry.key} preserves content without exposing the parse error receiver', () async {
        await offline(() async {
          final repository = _SyntheticProfiles(generationFails: fallback, content: entry.value);
          await open(repository);
          final details = container.read(profileDetailsNotifierProvider(repository.profile.id)).requireValue;
          expect(details.config.requireValue.text, entry.value);
          expect(details.profile, repository.profile);
          expect(details.isDetailsChanged, isFalse);
          expect(details.isLoading, isFalse);
          expect(repository.rawReads, fallback ? 1 : 0);
          await diagnostics.captureSafeProbe();
          _expectNoConfigurationInDiagnostics(diagnostics);
          expect(details.config.requireValue.isJson, isFalse);
        });
      });
    }

    test('$path plain text fallback can be corrected and saved once without diagnostic credentials', () async {
      await offline(() async {
        final malformed = '{"uuid":"${_canaries[0]}",}';
        final repository = _SyntheticProfiles(generationFails: fallback, content: malformed);
        await open(repository);
        final notifier = container.read(profileDetailsNotifierProvider(repository.profile.id).notifier);
        final draft = jsonEncode({'outbounds': _outbounds, 'endpoints': _endpoints});
        notifier.setContent(draft);
        expect(await notifier.save(), isTrue);
        expect(repository.saved, [(repository.profile, draft)]);
        expect(notifications.messages, hasLength(1));
        final details = container.read(profileDetailsNotifierProvider(repository.profile.id)).requireValue;
        expect(details.config.requireValue.text, draft);
        expect(details.profile, repository.profile);
        expect(details.isDetailsChanged, isTrue);
        expect(details.isLoading, isFalse);
        expect(repository.rawReads, fallback ? 1 : 0);
        await diagnostics.captureSafeProbe();
        _expectNoConfigurationInDiagnostics(diagnostics);
        expect(details.config.requireValue.isJson, isFalse);
      });
    });
  }
}
