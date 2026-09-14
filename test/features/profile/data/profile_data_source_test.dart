import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/features/profile/data/profile_data_source.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';

void main() {
  late Db db;
  late ProfileDao dao;

  setUp(() {
    db = Db(NativeDatabase.memory());
    dao = ProfileDao(db);
  });

  tearDown(() => db.close());

  Future<void> insertRemote(String id, String url) => dao.insert(
    ProfileEntriesCompanion.insert(
      id: id,
      type: ProfileType.remote,
      active: false,
      name: id,
      url: Value(url),
      lastUpdate: DateTime.utc(2026),
    ),
  );

  group('ProfileDao.getByUrl', () {
    test('matches only the complete URL among prefix and substring candidates', () async {
      const requested = 'https://example.test/subscriptions/team';
      await insertRemote('prefix', '$requested/primary');
      await insertRemote('substring', 'https://mirror.test/next=$requested');
      await insertRemote('exact', requested);

      final result = await dao.getByUrl(requested);

      expect(result?.id, 'exact');
    });

    test('treats percent and underscore as literal URL characters', () async {
      await insertRemote('percent-candidate', 'https://example.test/sub/aXXb');
      await insertRemote('underscore-candidate', 'https://example.test/sub/aXb');

      expect(await dao.getByUrl('https://example.test/sub/a%b'), isNull);
      expect(await dao.getByUrl('https://example.test/sub/a_b'), isNull);
    });

    test('keeps query tokens distinct', () async {
      await insertRemote('long-token', 'https://example.test/sub?token=secret-extra');
      await insertRemote('other-token', 'https://example.test/sub?token=other');

      expect(await dao.getByUrl('https://example.test/sub?token=secret'), isNull);
    });

    test('normalizes surrounding whitespace before exact comparison', () async {
      const stored = 'https://example.test/sub?token=secret';
      await insertRemote('exact', stored);

      final result = await dao.getByUrl('  $stored\n');

      expect(result?.id, 'exact');
    });

    test('rejects ambiguous exact duplicates instead of choosing one', () async {
      const duplicate = 'https://example.test/sub?token=duplicate';
      await insertRemote('first', duplicate);
      await insertRemote('second', duplicate);

      expect(() => dao.getByUrl(duplicate), throwsStateError);
    });
  });
}
