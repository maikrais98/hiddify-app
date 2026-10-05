import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/profile/data/profile_data_source.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Only the external HTTP/core boundary is substituted. Parser, repository,
// config repository, preferences and SQLite DAO remain production classes.
class FixtureHttp extends DioHttpClient {
  FixtureHttp() : super(timeout: const Duration(seconds: 1), userAgent: 'fixture', debug: false);
  String content = '# profile-title: Synthetic remote\nvless://fixture@example.invalid:443#Fixture';
  Completer<void>? pending;
  Completer<void>? entered;
  bool cancel = false;
  @override
  Future<Response> download(
    String url,
    String path, {
    CancelToken? cancelToken,
    String? userAgent,
    ({String username, String password})? credentials,
    bool proxyOnly = false,
  }) async {
    if (entered != null && !entered!.isCompleted) entered!.complete();
    await pending?.future;
    if (cancel || (cancelToken?.isCancelled ?? false)) {
      throw DioException(
        requestOptions: RequestOptions(path: url),
        type: DioExceptionType.cancel,
      );
    }
    await File(path).writeAsString(content);
    return Response(
      requestOptions: RequestOptions(path: url),
      headers: Headers(),
    );
  }
}

class FixtureCore implements HiddifyCoreService {
  bool reject = false;
  OutboundGroup? group;
  final selections = <(String, String)>[];
  final delayTests = <String>[];
  @override
  Stream<OutboundGroup> watchGroup() => Stream.value(group!);
  @override
  TaskEither<String, Unit> selectOutbound(String groupTag, String outboundTag) {
    selections.add((groupTag, outboundTag));
    return TaskEither.right(unit);
  }

  @override
  TaskEither<String, Unit> urlTest(String groupTag) {
    delayTests.add(groupTag);
    return TaskEither.right(unit);
  }

  @override
  TaskEither<String, Unit> changeOptions(SingboxConfigOption options) => TaskEither.right(unit);
  @override
  TaskEither<String, Unit> validateConfigByPath(String path, String tempPath, bool debug) => TaskEither(() async {
    if (reject) return left('synthetic invalid config');
    await File(tempPath).copy(path);
    return right(unit);
  });
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ProfileFixture {
  final Directory directory;
  final SharedPreferences preferences;
  late Db db;
  late ProfileDao dao;
  late ProviderContainer container;
  late ProfileRepositoryImpl repository;
  final http = FixtureHttp();
  final core = FixtureCore();
  ProfileFixture._(this.directory, this.preferences);
  static Future<ProfileFixture> create() async {
    SharedPreferences.setMockInitialValues({});
    final f = ProfileFixture._(
      await Directory.systemTemp.createTemp('profile-contract-'),
      await SharedPreferences.getInstance(),
    );
    await f.open();
    return f;
  }

  Future<void> open() async {
    db = Db(NativeDatabase(File('${directory.path}/profiles.sqlite')));
    dao = ProfileDao(db);
    container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWith((ref) => Future.value(preferences))],
    );
    await container.read(sharedPreferencesProvider.future);
    final parserProvider = Provider((ref) => ProfileParser(ref: ref, httpClient: http));
    repository = ProfileRepositoryImpl(
      profileDataSource: dao,
      profilePathResolver: ProfilePathResolver(directory),
      singbox: core,
      configOptionRepository: ConfigOptionRepository(
        preferences: preferences,
        getConfigOptions: () => container.read(ConfigOptions.singboxConfigOptions),
      ),
      profileParser: container.read(parserProvider),
    );
    await repository.init().run();
  }

  Future<void> reopen() async {
    container.dispose();
    await db.close();
    await open();
  }

  Future<void> dispose() async {
    container.dispose();
    await db.close();
    await directory.delete(recursive: true);
  }
}
