import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/features/profile/data/profile_data_mapper.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';

import '../../../drift/db/generated/schema_v5.dart' as v5;

Map<String, dynamic> overrideFor(Map<String, dynamic> headers, {UserOverride? userOverride}) =>
    jsonDecode(ProfileParser.profileOverride(populatedHeaders: headers, userOverride: userOverride))
        as Map<String, dynamic>;

void main() {
  group('official subscription policy', () {
    test('modern subscription values win over legacy flags', () {
      expect(
        overrideFor({
          'enable-warp': 'true',
          'enable-fragment': 'true',
          'extra-security': 'psiphon',
          'fragment': '10-20,1-2,tlshello',
        }),
        {
          'chain-status': 'extra_security',
          'extra-security': {'mode': 'psiphon'},
          'tls-tricks': {'enable-fragment': true, 'fragment-size': '10-20', 'fragment-sleep': '1-2'},
        },
      );
    });

    test('invalid modern values keep their official rejection semantics', () {
      expect(
        overrideFor({
          'enable-warp': 'true',
          'enable-fragment': 'true',
          'extra-security': 'profile',
          'fragment': 'invalid',
        }),
        isEmpty,
      );
    });

    test('user choices keep precedence over subscription values', () {
      expect(
        overrideFor({
          'enable-warp': 'true',
          'enable-fragment': 'true',
          'extra-security': 'warp',
          'fragment': '10-20,1-2,tlshello',
        }, userOverride: const UserOverride(extraSecurity: 'psiphon', enableFragment: true)),
        {
          'chain-status': 'extra_security',
          'extra-security': {'mode': 'psiphon'},
          'tls-tricks': {'enable-fragment': true},
        },
      );
    });

    test('false and malformed legacy flags do not enable features', () {
      for (final flag in ['false', '1', 'TRUE', '', null]) {
        expect(overrideFor({'enable-warp': flag, 'enable-fragment': flag}), isEmpty);
      }
    });
  });

  for (final missingLegacyColumn in [false, true]) {
    test('v5 profiles reconstruct options after migration and reopen '
        '(missing cached column: $missingLegacyColumn)', () async {
      final directory = Directory.systemTemp.createTempSync('legacy-profile-migration-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/profiles.sqlite');
      final savedAt = DateTime.utc(2026);
      final headers = {
        'enable-warp': 'true',
        'enable-fragment': 'true',
        'connection-test-url': 'https://example.com/check',
        'direct-dns-address': 'localhost',
        'remote-dns-address': 'https://example.com/dns-query',
      };
      // This is the non-empty cache QA45 writes from these subscription flags.
      // The cache is deliberately absent in v7: only surviving inputs may be used.
      final cachedOverride = {
        'connection-test-url': headers['connection-test-url'],
        'direct-dns-address': headers['direct-dns-address'],
        'remote-dns-address': headers['remote-dns-address'],
        'warp': {'enable': true, 'mode': 'warp_over_proxy'},
        'warp2': {'enable': true, 'mode': 'warp_over_proxy'},
        'tls-tricks': {'enable-fragment': true},
      };
      final oldDb = v5.DatabaseAtV5(NativeDatabase(file));
      await oldDb
          .into(oldDb.profileEntries)
          .insert(
            v5.ProfileEntriesCompanion.insert(
              id: 'legacy-subscription',
              type: 'remote',
              active: true,
              name: 'Saved subscription',
              url: const Value('https://example.com/subscription'),
              lastUpdate: savedAt,
              updateInterval: const Value(21600),
              upload: const Value(10),
              download: const Value(20),
              total: const Value(1000),
              expire: Value(DateTime.utc(2030)),
              webPageUrl: const Value('https://example.com/account'),
              supportUrl: const Value('https://example.com/support'),
              populatedHeaders: Value(jsonEncode(headers)),
              profileOverride: Value(jsonEncode(cachedOverride)),
            ),
          );
      final oldUserChoices = jsonEncode({
        'version': 1,
        'name': 'My local profile',
        'isAutoUpdateDisable': true,
        'updateInterval': 12,
        'enableWarp': true,
        'enableFragment': true,
      });
      await oldDb
          .into(oldDb.profileEntries)
          .insert(
            v5.ProfileEntriesCompanion.insert(
              id: 'legacy-user-choices',
              type: 'local',
              active: false,
              name: 'My local profile',
              lastUpdate: savedAt,
              populatedHeaders: const Value('{}'),
              profileOverride: Value(jsonEncode(cachedOverride)),
              userOverride: Value(oldUserChoices),
            ),
          );
      final modernHeaders = {
        'enable-warp': 'true',
        'enable-fragment': 'true',
        'extra-security': 'psiphon',
        'fragment': 'invalid',
        'tls-tricks': {'enable-fragment': false},
      };
      await oldDb
          .into(oldDb.profileEntries)
          .insert(
            v5.ProfileEntriesCompanion.insert(
              id: 'already-modern',
              type: 'local',
              active: false,
              name: 'Modern fields',
              lastUpdate: savedAt,
              populatedHeaders: Value(jsonEncode(modernHeaders)),
              profileOverride: Value(jsonEncode(cachedOverride)),
            ),
          );
      expect(
        (await oldDb.select(oldDb.profileEntries).get()).every(
          (row) => (jsonDecode(row.profileOverride!) as Map).isNotEmpty,
        ),
        isTrue,
      );
      if (missingLegacyColumn) {
        await oldDb.customStatement('ALTER TABLE profile_entries DROP COLUMN profile_override');
      }
      await oldDb.close();

      Future<void> checkProfiles(Db db) async {
        final rows = await db.select(db.profileEntries).get();
        expect(rows, hasLength(3));
        final remote = rows.firstWhere((row) => row.id == 'legacy-subscription').toEntity() as RemoteProfileEntity;
        expect(remote.active, isTrue);
        expect(remote.name, 'Saved subscription');
        expect(remote.url, 'https://example.com/subscription');
        expect(remote.lastUpdate, savedAt);
        expect(remote.options?.updateInterval, const Duration(hours: 6));
        expect(remote.subInfo?.consumption, 30);
        expect(remote.subInfo?.total, 1000);
        expect(remote.webPageUrl, 'https://example.com/account');
        expect(remote.supportUrl, 'https://example.com/support');
        expect(remote.populatedHeaders, {
          ...headers,
          'extra-security': 'warp',
          'tls-tricks': {'enable-fragment': true},
        });
        final modern = rows.firstWhere((row) => row.id == 'already-modern').toEntity();
        expect(modern.populatedHeaders, modernHeaders);
        expect(jsonDecode(modern.profileOverride()), {
          'chain-status': 'extra_security',
          'extra-security': {'mode': 'psiphon'},
          'tls-tricks': {'enable-fragment': false},
        });
        final remoteOptions = jsonDecode(remote.profileOverride()) as Map;
        for (final key in ['connection-test-url', 'direct-dns-address', 'remote-dns-address']) {
          expect(remoteOptions[key], cachedOverride[key]);
        }
        expect(remote.pinned, isFalse);
        final local = rows.firstWhere((row) => row.id == 'legacy-user-choices').toEntity();
        expect(local, isA<LocalProfileEntity>());
        expect(local.active, isFalse);
        expect(local.userOverride?.name, 'My local profile');
        expect(local.userOverride?.isAutoUpdateDisable, isTrue);
        expect(local.userOverride?.updateInterval, 12);
        expect(local.userOverride?.extraSecurity, 'warp');
        expect(local.userOverride?.enableFragment, isTrue);
        for (final profile in [remote, local]) {
          final reconstructed = jsonDecode(profile.profileOverride()) as Map;
          expect(reconstructed['tls-tricks'], cachedOverride['tls-tricks']);
          // The official core replaces the old warp + warp2 options with one chain mode.
          expect(reconstructed['chain-status'], 'extra_security');
          expect(reconstructed['extra-security'], {'mode': 'warp_auto'});
          expect(reconstructed.containsKey('warp'), isFalse);
          expect(reconstructed.containsKey('warp2'), isFalse);
        }
        final columns = await db.customSelect('PRAGMA table_info(profile_entries)').get();
        expect(columns.any((row) => row.data['name'] == 'profile_override'), isFalse);
        expect(
          await db.customSelect('PRAGMA user_version').getSingle().then((row) => row.read<int>('user_version')),
          7,
        );
      }

      final migratedDb = Db(NativeDatabase(file));
      try {
        await checkProfiles(migratedDb);
      } finally {
        await migratedDb.close();
      }
      final reopenedDb = Db(NativeDatabase(file));
      try {
        await checkProfiles(reopenedDb);
        // A later download deliberately follows 5.5.5's subscription policy:
        // deprecated boolean headers no longer enable features. Only persisted
        // pre-upgrade settings are bridged; user choices continue to apply.
        final refreshedHeaders = ProfileParser.populateHeaders(
          content: '',
          remoteHeaders: headers,
        ).getOrElse((failure) => throw StateError('$failure'));
        expect(refreshedHeaders, isEmpty);
        await (reopenedDb.update(reopenedDb.profileEntries)..where((row) => row.id.equals('legacy-subscription')))
            .write(ProfileEntriesCompanion(populatedHeaders: Value(jsonEncode(refreshedHeaders))));
        final refreshed = (await (reopenedDb.select(
          reopenedDb.profileEntries,
        )..where((row) => row.id.equals('legacy-subscription'))).getSingle()).toEntity();
        expect(jsonDecode(refreshed.profileOverride()), isEmpty);
      } finally {
        await reopenedDb.close();
      }
    });
  }
}
