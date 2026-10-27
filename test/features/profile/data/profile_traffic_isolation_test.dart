import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_event.dart';
import 'package:hiddify/features/profile/data/profile_data_mapper.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../support/profile_settings_fixtures.dart';

void main() {
  group('profile URL identity', () {
    const cases = <({String label, String storedUrl, String requestedUrl})>[
      (
        label: 'underscore is literal',
        storedUrl: 'https://example.invalid/sub/tokenA1B',
        requestedUrl: 'https://example.invalid/sub/tokenA_B',
      ),
      (
        label: 'encoded percent is literal',
        storedUrl: 'https://example.invalid/sub/tokenAxyz25B',
        requestedUrl: 'https://example.invalid/sub/tokenA%25B',
      ),
      (
        label: 'substring is not identity',
        storedUrl: 'https://example.invalid/sub/target/suffix',
        requestedUrl: 'https://example.invalid/sub/target',
      ),
      (
        label: 'path and query token remain case-sensitive',
        storedUrl: 'https://example.invalid/Sub?token=ABC',
        requestedUrl: 'https://example.invalid/sub?token=abc',
      ),
    ];

    for (final testCase in cases) {
      test(testCase.label, () async {
        final fixture = await ProfileFixture.create();
        addTearDown(fixture.dispose);
        await _insertProfile(
          fixture,
          id: 'stored',
          name: 'Akonit',
          url: testCase.storedUrl,
          subInfo: _subscription(upload: 1, download: 2, total: 100),
        );

        expect(await fixture.dao.getByUrl(testCase.requestedUrl), isNull);

        await _insertProfile(
          fixture,
          id: 'requested',
          name: 'My',
          url: testCase.requestedUrl,
          subInfo: _subscription(upload: 4, download: 5, total: 200),
        );
        expect((await fixture.dao.getByUrl(testCase.requestedUrl))?.id, 'requested');
      });
    }

    test('unrelated URL remains isolated', () async {
      final fixture = await ProfileFixture.create();
      addTearDown(fixture.dispose);
      await _insertProfile(
        fixture,
        id: 'akonit',
        name: 'Akonit',
        url: 'https://example.invalid/sub/akonit-token',
        subInfo: _subscription(upload: 1, download: 2, total: 100),
      );

      expect(await fixture.dao.getByUrl('https://example.invalid/sub/my-token'), isNull);
    });
  });

  test('updating My requests its exact URL and leaves Akonit traffic unchanged', () async {
    const akonitUrl = 'https://example.invalid/sub/tokenA1B';
    const myUrl = 'https://example.invalid/sub/tokenA_B';
    final fixture = await ProfileFixture.create();
    addTearDown(fixture.dispose);
    await _insertProfile(
      fixture,
      id: 'akonit',
      name: 'Akonit',
      url: akonitUrl,
      subInfo: _subscription(upload: 10, download: 20, total: 1000),
    );
    await _insertProfile(
      fixture,
      id: 'my',
      name: 'My',
      url: myUrl,
      subInfo: _subscription(upload: 40, download: 50, total: 2000),
    );
    final http = _PerUrlHttp(
      subscriptionHeaders: {
        akonitUrl: 'upload=11;download=22;total=111;expire=4102444800',
        myUrl: 'upload=44;download=55;total=222;expire=4102444800',
      },
    );
    final repository = _repository(fixture, http);

    final result = await repository.upsertRemote(myUrl).run();

    expect(result.isRight(), isTrue);
    expect(http.requestedUrls, [myUrl]);
    expect(await fixture.dao.watchProfilesCount().first, 2);
    final akonit = (await fixture.dao.getById('akonit'))!.toEntity() as RemoteProfileEntity;
    final my = (await fixture.dao.getById('my'))!.toEntity() as RemoteProfileEntity;
    expect((akonit.subInfo!.upload, akonit.subInfo!.download, akonit.subInfo!.total), (10, 20, 1000));
    expect((my.subInfo!.upload, my.subInfo!.download, my.subInfo!.total), (44, 55, 222));
  });

  test('active switching exposes traffic from the selected exact row', () async {
    final fixture = await ProfileFixture.create();
    addTearDown(fixture.dispose);
    await _insertProfile(
      fixture,
      id: 'akonit',
      name: 'Akonit',
      url: 'https://example.invalid/sub/akonit',
      subInfo: _subscription(upload: 1, download: 2, total: 100),
    );
    await _insertProfile(
      fixture,
      id: 'my',
      name: 'My',
      url: 'https://example.invalid/sub/my',
      subInfo: _subscription(upload: 4, download: 5, total: 200),
    );

    await fixture.repository.setAsActive('akonit').run();
    final akonit = (await fixture.dao.watchActiveProfile().first)!.toEntity() as RemoteProfileEntity;
    expect((akonit.id, akonit.subInfo!.total), ('akonit', 100));

    await fixture.repository.setAsActive('my').run();
    final my = (await fixture.dao.watchActiveProfile().first)!.toEntity() as RemoteProfileEntity;
    expect((my.id, my.subInfo!.total), ('my', 200));

    await fixture.repository.setAsActive('akonit').run();
    final akonitAgain = (await fixture.dao.watchActiveProfile().first)!.toEntity() as RemoteProfileEntity;
    expect((akonitAgain.id, akonitAgain.subInfo!.total), ('akonit', 100));
  });

  test('missing My metadata clears only My traffic', () async {
    const akonitUrl = 'https://example.invalid/sub/akonit';
    const myUrl = 'https://example.invalid/sub/my';
    final fixture = await ProfileFixture.create();
    addTearDown(fixture.dispose);
    await _insertProfile(
      fixture,
      id: 'akonit',
      name: 'Akonit',
      url: akonitUrl,
      subInfo: _subscription(upload: 10, download: 20, total: 1000),
    );
    await _insertProfile(
      fixture,
      id: 'my',
      name: 'My',
      url: myUrl,
      subInfo: _subscription(upload: 40, download: 50, total: 2000),
    );
    final http = _PerUrlHttp(subscriptionHeaders: {akonitUrl: null, myUrl: null});
    final repository = _repository(fixture, http);

    final result = await repository.upsertRemote(myUrl).run();

    expect(result.isRight(), isTrue);
    expect(http.requestedUrls, [myUrl]);
    final akonit = (await fixture.dao.getById('akonit'))!.toEntity() as RemoteProfileEntity;
    final my = (await fixture.dao.getById('my'))!.toEntity() as RemoteProfileEntity;
    expect(
      (akonit.subInfo!.upload, akonit.subInfo!.download, akonit.subInfo!.total),
      (10, 20, 1000),
    );
    expect(my.subInfo, isNull);
  });
}

Future<void> _insertProfile(
  ProfileFixture fixture, {
  required String id,
  required String name,
  required String url,
  required SubscriptionInfo subInfo,
}) => fixture.dao.insert(
  ProfileEntity.remote(
    id: id,
    active: false,
    name: name,
    url: url,
    lastUpdate: DateTime.utc(2026),
    subInfo: subInfo,
    populatedHeaders: const {},
    userOverride: UserOverride(name: name),
  ).toInsertEntry(),
);

SubscriptionInfo _subscription({required int upload, required int download, required int total}) =>
    SubscriptionInfo(upload: upload, download: download, total: total, expire: DateTime.utc(2100));

ProfileRepositoryImpl _repository(ProfileFixture fixture, DioHttpClient http) {
  final parserProvider = Provider((ref) => ProfileParser(ref: ref, httpClient: http));
  return ProfileRepositoryImpl(
    profileDataSource: fixture.dao,
    profilePathResolver: ProfilePathResolver(fixture.directory),
    singbox: fixture.core,
    configOptionRepository: ConfigOptionRepository(
      preferences: fixture.preferences,
      getConfigOptions: () => fixture.container.read(ConfigOptions.singboxConfigOptions),
    ),
    profileParser: fixture.container.read(parserProvider),
  );
}

class _PerUrlHttp extends DioHttpClient {
  _PerUrlHttp({required this.subscriptionHeaders})
    : super(timeout: const Duration(seconds: 1), userAgent: 'traffic-isolation-fixture', debug: false);

  final Map<String, String?> subscriptionHeaders;
  final List<String> requestedUrls = [];

  @override
  Future<Response> download(
    String url,
    String path, {
    CancelToken? cancelToken,
    String? userAgent,
    ({String username, String password})? credentials,
    bool proxyOnly = false,
    void Function(DiagnosticHttpResult result)? onDiagnostic,
  }) async {
    requestedUrls.add(url);
    await File(path).writeAsString('vless://fixture@example.invalid:443#Fixture');
    final subscriptionHeader = subscriptionHeaders[url];
    final response = Response(
      requestOptions: RequestOptions(path: url),
      statusCode: 200,
      headers: Headers.fromMap({
        if (subscriptionHeader != null) 'subscription-userinfo': [subscriptionHeader],
      }),
    );
    onDiagnostic?.call(
      const DiagnosticHttpResult(
        outcome: DiagnosticHttpOutcome.success,
        selectedMode: DiagnosticHttpMode.direct,
        httpStatus: 200,
      ),
    );
    return response;
  }
}
