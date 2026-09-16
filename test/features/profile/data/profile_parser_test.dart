import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/core/http_client/http_client_provider.dart';
import 'package:hiddify/core/http_client/profile_download_policy.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

void main() {
  const validBaseUrl = "https://example.com/configurations/user1/filename.yaml";
  const validExtendedUrl = "https://example.com/configurations/user1/filename.yaml?test#b";
  const validSupportUrl = "https://example.com/support";

  group("parse", () {
    test("Should use filename in url with no headers and fragment", () {
      final profile = ProfileParser.parse(
        tempFilePath: '',
        profile: ProfileEntity.remote(
          id: const Uuid().v4(),
          active: true,
          name: '',
          url: validBaseUrl,
          lastUpdate: DateTime.now(),
        ),
      );
      expect(profile.isRight(), true);
      profile.match((l) {}, (r) {
        expect(r is RemoteProfileEntity, true);
        r.map(
          remote: (rp) {
            expect(rp.name, equals("filename"));
            expect(rp.url, equals(validBaseUrl));
            expect(rp.options, isNull);
            expect(rp.subInfo, isNull);
          },
          local: (lp) {},
        );
      });
    });

    test("Should use fragment in url with no headers", () {
      final profile = ProfileParser.parse(
        tempFilePath: '',
        profile: ProfileEntity.remote(
          id: const Uuid().v4(),
          active: true,
          name: '',
          url: validExtendedUrl,
          lastUpdate: DateTime.now(),
        ),
      );
      expect(profile.isRight(), true);
      profile.match((l) {}, (r) {
        expect(r is RemoteProfileEntity, true);
        r.map(
          remote: (rp) {
            expect(rp.name, equals("b"));
            expect(rp.url, equals(validExtendedUrl));
            expect(rp.options, isNull);
            expect(rp.subInfo, isNull);
          },
          local: (lp) {},
        );
      });
    });

    test("Should use base64 title in headers", () {
      final headers = <String, List<String>>{
        "profile-title": ["base64:ZXhhbXBsZVRpdGxl"],
        "profile-update-interval": ["1"],
        "connection-test-url": [validBaseUrl],
        "remote-dns-address": [validBaseUrl],
        "subscription-userinfo": ["upload=0;download=1024;total=10240.5;expire=1704054600.55"],
        "profile-web-page-url": [validBaseUrl],
        "support-url": [validSupportUrl],
      };
      // This fix occurs in the _downloadProfile method within ProfileParser, and the fixed headers are passed to populateHeaders
      final fixedHeaders = headers.map((key, value) {
        if (value.length == 1) return MapEntry(key, value.first);
        return MapEntry(key, value);
      });
      final allHeaders = ProfileParser.populateHeaders(content: '', remoteHeaders: fixedHeaders);
      expect(allHeaders.isRight(), true);
      allHeaders.match((l) {}, (r) {
        final profile = ProfileParser.parse(
          tempFilePath: '',
          profile: ProfileEntity.remote(
            id: const Uuid().v4(),
            active: true,
            name: '',
            url: validExtendedUrl,
            lastUpdate: DateTime.now(),
            populatedHeaders: r,
          ),
        );
        expect(profile.isRight(), true);
        profile.match((l) {}, (r) {
          expect(r is RemoteProfileEntity, true);
          r.map(
            remote: (rp) {
              expect(rp.name, equals("exampleTitle"));
              expect(rp.url, equals(validExtendedUrl));
              expect(rp.options, equals(const ProfileOptions(updateInterval: Duration(hours: 1))));
              expect(
                rp.subInfo,
                equals(
                  SubscriptionInfo(
                    upload: 0,
                    download: 1024,
                    total: 10240,
                    expire: DateTime.fromMillisecondsSinceEpoch(1704054600 * 1000),
                    webPageUrl: validBaseUrl,
                    supportUrl: validSupportUrl,
                  ),
                ),
              );
            },
            local: (lp) {},
          );
        });
      });
    });

    test("Should use infinite when given 0 for subscription properties", () {
      final headers = <String, List<String>>{
        "profile-title": ["title"],
        "profile-update-interval": ["1"],
        "subscription-userinfo": ["upload=0;download=1024;total=0;expire=0"],
        "profile-web-page-url": [validBaseUrl],
        "support-url": [validSupportUrl],
      };
      // This fix occurs in the _downloadProfile method within ProfileParser, and the fixed headers are passed to populateHeaders
      final fixedHeaders = headers.map((key, value) {
        if (value.length == 1) return MapEntry(key, value.first);
        return MapEntry(key, value);
      });
      final allHeaders = ProfileParser.populateHeaders(content: '', remoteHeaders: fixedHeaders);
      expect(allHeaders.isRight(), true);
      allHeaders.match((l) {}, (r) {
        final profile = ProfileParser.parse(
          tempFilePath: '',
          profile: RemoteProfileEntity(
            id: const Uuid().v4(),
            active: true,
            name: '',
            url: validBaseUrl,
            lastUpdate: DateTime.now(),
            populatedHeaders: r,
          ),
        );
        expect(profile.isRight(), true);
        profile.match((l) {}, (r) {
          expect(r is RemoteProfileEntity, true);
          r.map(
            remote: (rp) {
              expect(rp.subInfo, isNotNull);
              expect(rp.subInfo!.total, equals(ProfileParser.infiniteTrafficThreshold + 1));
              expect(
                rp.subInfo!.expire,
                equals(DateTime.fromMillisecondsSinceEpoch(ProfileParser.infiniteTimeThreshold * 1000)),
              );
            },
            local: (lp) {},
          );
        });
      });
    });

    const updateIntervalCases = <String, int?>{
      'invalid': null,
      '-1': 0,
      '0': 0,
      '96': 96,
      '97': 96,
      '999999999': 96,
    };
    for (final MapEntry(key: rawInterval, value: expectedHours) in updateIntervalCases.entries) {
      test('normalizes profile-update-interval "$rawInterval" without failing the profile', () {
        final result = ProfileParser.parse(
          tempFilePath: '',
          profile: ProfileEntity.remote(
            id: const Uuid().v4(),
            active: true,
            name: '',
            url: validBaseUrl,
            lastUpdate: DateTime.now(),
            populatedHeaders: {'profile-update-interval': rawInterval},
          ),
        );

        expect(result.isRight(), isTrue);
        result.match(
          (failure) => fail('profile parsing failed: $failure'),
          (profile) => profile.map(
            remote: (profile) {
              if (expectedHours == null) {
                expect(profile.options, isNull);
              } else {
                expect(profile.options?.updateInterval, Duration(hours: expectedHours));
              }
            },
            local: (_) => fail('expected a remote profile'),
          ),
        );
      });
    }

    test('normalizes an out-of-range user override before creating profile options', () {
      final result = ProfileParser.parse(
        tempFilePath: '',
        profile: ProfileEntity.remote(
          id: const Uuid().v4(),
          active: true,
          name: '',
          url: validBaseUrl,
          lastUpdate: DateTime.now(),
          userOverride: const UserOverride(updateInterval: 97),
        ),
      );

      result.match(
        (failure) => fail('profile parsing failed: $failure'),
        (profile) => profile.map(
          remote: (profile) => expect(profile.options?.updateInterval, const Duration(hours: 96)),
          local: (_) => fail('expected a remote profile'),
        ),
      );
    });

    test('keeps a normalized update interval through user override serialization', () {
      const override = UserOverride(updateInterval: 999999999);

      final restored = UserOverride.fromStr(override.toStr());

      expect(restored?.updateInterval, 96);
      expect(UserOverride.fromStr(restored?.toStr())?.updateInterval, 96);
    });
  });

  group('expandRemoteLinesInParallel', () {
    late Directory tempDir;
    late File sourceFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('profile-parser-test-');
      sourceFile = File('${tempDir.path}/profile.tmp')..writeAsStringSync('https://example.test/nested');
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('addLocal forwards cancellation to an active nested download', () async {
      final client = _WaitingDioHttpClient();
      final container = await _createContainer(client);
      addTearDown(container.dispose);
      final token = CancelToken();
      final task = container
          .read(profileParserProvider)
          .addLocal(
            id: 'local',
            content: sourceFile.readAsStringSync(),
            tempFilePath: sourceFile.path,
            userOverride: null,
            cancelToken: token,
          )
          .run();
      await client.started.future;
      expect(client.token, isNotNull);
      token.cancel();
      final result = await task;
      expect(client.cancelObserved, true);
      expect(result.fold((error) => error is ProfileCancelByUserFailure, (_) => false), true);
      _expectOnlySourceFileRemains(tempDir, sourceFile);
    });

    test('rejects too many URLs before downloading', () async {
      sourceFile.writeAsStringSync(List.filled(17, 'https://example.test/nested').join('\n'));
      final client = _FakeDioHttpClient(_DownloadOutcome.success);
      final container = await _createContainer(client);
      addTearDown(container.dispose);
      await expectLater(
        container
            .read(profileParserProvider)
            .expandRemoteLinesInParallel(
              tempFilePath: sourceFile.path,
              httpClient: client,
              cancelToken: CancelToken(),
              ref: container.read(_refProvider),
            ),
        throwsFormatException,
      );
      expect(client.downloads, 0);
    });

    for (final outcome in [_DownloadOutcome.nested, _DownloadOutcome.large]) {
      test('rejects nested depth or oversized input: $outcome', () async {
        final client = _FakeDioHttpClient(outcome);
        final container = await _createContainer(client);
        addTearDown(container.dispose);
        await expectLater(
          container
              .read(profileParserProvider)
              .expandRemoteLinesInParallel(
                tempFilePath: sourceFile.path,
                httpClient: client,
                cancelToken: CancelToken(),
                ref: container.read(_refProvider),
              ),
          throwsFormatException,
        );
        expect(sourceFile.readAsStringSync(), 'https://example.test/nested');
        _expectOnlySourceFileRemains(tempDir, sourceFile);
      });
    }

    test('bounds aggregate expansion before replacing the source', () async {
      sourceFile.writeAsStringSync(List.filled(5, 'https://example.test/nested').join('\n'));
      final original = sourceFile.readAsStringSync();
      final client = _FakeDioHttpClient(_DownloadOutcome.aggregate);
      final container = await _createContainer(client);
      addTearDown(container.dispose);
      await expectLater(
        container
            .read(profileParserProvider)
            .expandRemoteLinesInParallel(
              tempFilePath: sourceFile.path,
              httpClient: client,
              cancelToken: CancelToken(),
              ref: container.read(_refProvider),
              parallelism: 1,
            ),
        throwsFormatException,
      );
      expect(sourceFile.readAsStringSync(), original);
      expect(client.downloads, 4);
      _expectOnlySourceFileRemains(tempDir, sourceFile);
    });

    test('expansion shares deadline across URLs and aborts stalled DNS without late connect', () async {
      sourceFile.writeAsStringSync('https://first.test/config\nhttps://second.test/config');
      final client = _DeadlineDioHttpClient();
      final container = await _createContainer(client);
      addTearDown(container.dispose);
      final watch = Stopwatch()..start();
      await expectLater(
        container
            .read(profileParserProvider)
            .expandRemoteLinesInParallel(
              tempFilePath: sourceFile.path,
              httpClient: client,
              cancelToken: CancelToken(),
              ref: container.read(_refProvider),
              parallelism: 1,
              timeLimit: const Duration(milliseconds: 200),
            ),
        throwsA(
          isA<ProfileDownloadException>().having((error) => error.kind, 'kind', ProfileDownloadFailureKind.deadline),
        ),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
      expect(client.budgets, hasLength(2));
      expect(client.budgets.last, lessThan(const Duration(milliseconds: 120)));
      client.lateDns.complete([InternetAddress('8.8.8.8')]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(client.connects, 0);
      _expectOnlySourceFileRemains(tempDir, sourceFile);
    });

    for (final entry in {
      ProfileDownloadFailureKind.url: isA<ProfileInvalidUrlFailure>(),
      ProfileDownloadFailureKind.address: isA<ProfileInvalidUrlFailure>(),
      ProfileDownloadFailureKind.redirect: isA<ProfileInvalidUrlFailure>(),
      ProfileDownloadFailureKind.size: isA<ProfileInvalidConfigFailure>(),
      ProfileDownloadFailureKind.depth: isA<ProfileInvalidConfigFailure>(),
      ProfileDownloadFailureKind.deadline: isA<ProfileInvalidConfigFailure>(),
    }.entries) {
      test('maps root and nested ${entry.key} without user-cancel or unexpected', () async {
        final client = _RejectingDioHttpClient(entry.key);
        final container = await _createContainer(client);
        addTearDown(container.dispose);
        final parser = container.read(profileParserProvider);
        final local = await parser
            .addLocal(
              id: 'local',
              content: sourceFile.readAsStringSync(),
              tempFilePath: sourceFile.path,
              userOverride: null,
            )
            .run();
        final remote = await parser
            .addRemote(
              id: 'remote',
              url: 'https://example.test/config',
              tempFilePath: sourceFile.path,
              userOverride: null,
            )
            .run();
        expect(local.fold((error) => error, (_) => null), entry.value);
        expect(remote.fold((error) => error, (_) => null), entry.value);
      });
    }

    test('removes the nested temp file after success', () async {
      final client = _FakeDioHttpClient(_DownloadOutcome.success);
      final container = await _createContainer(client);
      addTearDown(container.dispose);

      await container
          .read(profileParserProvider)
          .expandRemoteLinesInParallel(
            tempFilePath: sourceFile.path,
            httpClient: client,
            cancelToken: CancelToken(),
            ref: container.read(_refProvider),
            parallelism: 1,
          );

      expect(await sourceFile.readAsString(), 'nested config');
      _expectOnlySourceFileRemains(tempDir, sourceFile);
    });

    test('removes the nested temp file after a read error', () async {
      final client = _FakeDioHttpClient(_DownloadOutcome.readError);
      final container = await _createContainer(client);
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(profileParserProvider)
            .expandRemoteLinesInParallel(
              tempFilePath: sourceFile.path,
              httpClient: client,
              cancelToken: CancelToken(),
              ref: container.read(_refProvider),
              parallelism: 1,
            ),
        throwsA(anything),
      );

      _expectOnlySourceFileRemains(tempDir, sourceFile);
    });

    test('removes a partial nested temp file after a network error', () async {
      final client = _FakeDioHttpClient(_DownloadOutcome.networkError);
      final container = await _createContainer(client);
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(profileParserProvider)
            .expandRemoteLinesInParallel(
              tempFilePath: sourceFile.path,
              httpClient: client,
              cancelToken: CancelToken(),
              ref: container.read(_refProvider),
              parallelism: 1,
            ),
        throwsA(anything),
      );

      _expectOnlySourceFileRemains(tempDir, sourceFile);
    });

    test('removes a partial nested temp file after cancellation', () async {
      final client = _FakeDioHttpClient(_DownloadOutcome.cancel);
      final container = await _createContainer(client);
      addTearDown(container.dispose);
      final cancelToken = CancelToken();

      await expectLater(
        container
            .read(profileParserProvider)
            .expandRemoteLinesInParallel(
              tempFilePath: sourceFile.path,
              httpClient: client,
              cancelToken: cancelToken,
              ref: container.read(_refProvider),
              parallelism: 1,
            ),
        throwsA(anything),
      );

      expect(await sourceFile.readAsString(), 'https://example.test/nested');
      _expectOnlySourceFileRemains(tempDir, sourceFile);
    });
  });
}

final _refProvider = Provider<Ref>((ref) => ref);

Future<ProviderContainer> _createContainer(DioHttpClient client) async {
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) => preferences),
      httpClientProvider.overrideWith((ref) => client),
    ],
  );
  await container.read(sharedPreferencesProvider.future);
  return container;
}

void _expectOnlySourceFileRemains(Directory tempDir, File sourceFile) {
  expect(tempDir.listSync().map((entry) => entry.path), [sourceFile.path]);
}

enum _DownloadOutcome { success, readError, networkError, cancel, nested, large, aggregate }

class _FakeDioHttpClient extends DioHttpClient {
  _FakeDioHttpClient(this.outcome)
    : super(timeout: const Duration(seconds: 1), userAgent: 'profile-parser-test', debug: false);

  final _DownloadOutcome outcome;
  int downloads = 0;

  @override
  Future<Response> downloadProfile(
    String url,
    String path, {
    CancelToken? cancelToken,
    String? userAgent,
    Duration timeLimit = ProfileDownloadPolicy.deadline,
  }) async {
    final requestOptions = RequestOptions(path: url);
    downloads++;
    switch (outcome) {
      case _DownloadOutcome.nested:
        await File(path).writeAsString('https://example.test/deeper');
        return Response(requestOptions: requestOptions);
      case _DownloadOutcome.aggregate:
        final file = await File(path).open(mode: FileMode.write);
        await file.truncate(8 * 1024 * 1024);
        await file.close();
        return Response(requestOptions: requestOptions);
      case _DownloadOutcome.large:
        final file = await File(path).open(mode: FileMode.write);
        await file.truncate(8 * 1024 * 1024 + 1);
        await file.close();
        return Response(requestOptions: requestOptions);
      case _DownloadOutcome.success:
        await File(path).writeAsString('nested config');
        return Response(requestOptions: requestOptions);
      case _DownloadOutcome.readError:
        await File(path).writeAsBytes([0xff]);
        return Response(requestOptions: requestOptions);
      case _DownloadOutcome.networkError:
        await File(path).writeAsString('partial config');
        throw DioException(requestOptions: requestOptions, type: DioExceptionType.connectionError);
      case _DownloadOutcome.cancel:
        await File(path).writeAsString('partial config');
        cancelToken!.cancel('profile-parser-test');
        throw DioException(requestOptions: requestOptions, type: DioExceptionType.cancel);
    }
  }
}

class _WaitingDioHttpClient extends DioHttpClient {
  _WaitingDioHttpClient() : super(timeout: const Duration(seconds: 1), userAgent: 'test', debug: false);
  final started = Completer<void>();
  CancelToken? token;
  bool cancelObserved = false;
  @override
  Future<Response> downloadProfile(
    String url,
    String path, {
    CancelToken? cancelToken,
    String? userAgent,
    Duration timeLimit = ProfileDownloadPolicy.deadline,
  }) async {
    token = cancelToken;
    started.complete();
    final error = await cancelToken!.whenCancel;
    cancelObserved = true;
    throw error;
  }
}

class _RejectingDioHttpClient extends DioHttpClient {
  _RejectingDioHttpClient(this.kind) : super(timeout: const Duration(seconds: 1), userAgent: 'test', debug: false);
  final ProfileDownloadFailureKind kind;
  @override
  Future<Response> downloadProfile(
    String url,
    String path, {
    CancelToken? cancelToken,
    String? userAgent,
    Duration timeLimit = ProfileDownloadPolicy.deadline,
  }) => Future.error(ProfileDownloadException(kind, 'Synthetic policy rejection.'));
}

class _DeadlineDioHttpClient extends DioHttpClient {
  _DeadlineDioHttpClient() : super(timeout: const Duration(seconds: 1), userAgent: 'test', debug: false);
  final budgets = <Duration>[];
  final lateDns = Completer<List<InternetAddress>>();
  int connects = 0;
  @override
  Future<Response> downloadProfile(
    String url,
    String path, {
    CancelToken? cancelToken,
    String? userAgent,
    Duration timeLimit = ProfileDownloadPolicy.deadline,
  }) async {
    budgets.add(timeLimit);
    if (budgets.length == 1) {
      await Future<void>.delayed(const Duration(milliseconds: 140));
      await File(path).writeAsString('config');
      return Response(requestOptions: RequestOptions(path: url));
    }
    return ProfileDownloadPolicy(
      timeLimit: timeLimit,
      lookup: (_) => lateDns.future,
      adapterFactory: (_) {
        connects++;
        throw StateError('No late connection allowed.');
      },
    ).download(url, path, cancelToken: cancelToken, userAgent: 'test');
  }
}
