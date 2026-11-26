import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';

void main() {
  Map<String, dynamic> subscriptionOverrides({
    String content = 'dmxlc3M6Ly90ZXN0',
    Map<String, dynamic>? headers,
  }) {
    final populated = ProfileParser.populateHeaders(content: content, remoteHeaders: headers);
    return populated.fold(
      (failure) => throw StateError('profile parsing failed: $failure'),
      (headers) => jsonDecode(
        ProfileParser.profileOverride(populatedHeaders: headers, userOverride: null),
      ) as Map<String, dynamic>,
    );
  }

  group('subscription routing region', () {
    test('legacy subscriptions retain the existing options', () {
      expect(subscriptionOverrides(), isEmpty);
      expect(subscriptionOverrides(headers: {'profile-title': 'Legacy'}), isEmpty);
    });

    test('a provider can request RU routing without replacing custom rules', () {
      final overrides = subscriptionOverrides(headers: {'profile-routing-region': 'ru'});
      expect(overrides, {'region': 'ru'});

      final localRules = {
        'rules': [
          {'name': 'My exception', 'outbound': 'proxy', 'domain': ['example.org']},
        ],
      };
      final options = ProfileParser.applyProfileOverride({
        'region': 'other',
        'route-rule': localRules,
        'remote-dns-address': 'tcp://8.8.8.8',
      }, jsonEncode(overrides));

      expect(options['region'], 'ru');
      expect(options['route-rule'], same(localRules));
      expect(options['remote-dns-address'], 'tcp://8.8.8.8');
    });

    test('the routing header survives profile metadata serialization', () {
      final populated = ProfileParser.populateHeaders(
        content: '',
        remoteHeaders: {'profile-routing-region': 'ru'},
      ).getOrElse((failure) => throw StateError('$failure'));
      final storedHeaders = jsonDecode(jsonEncode(populated)) as Map<String, dynamic>;
      final profile = ProfileEntity.remote(
        id: 'routing-test',
        active: true,
        name: 'Test',
        url: 'https://example.org/subscription',
        lastUpdate: DateTime.utc(2026, 1, 1),
        populatedHeaders: storedHeaders,
      );

      expect(jsonDecode(profile.profileOverride()), {'region': 'ru'});
    });

    test('metadata comments support plain and base64 server lists', () {
      const content = '# profile-routing-region: ru\nvless://synthetic-server';
      expect(subscriptionOverrides(content: content), {'region': 'ru'});
      expect(subscriptionOverrides(content: base64Encode(utf8.encode(content))), {'region': 'ru'});
    });

    test('HTTP metadata takes precedence over embedded metadata', () {
      expect(
        subscriptionOverrides(
          content: '# profile-routing-region: ru\nvless://synthetic-server',
          headers: {'profile-routing-region': 'unsupported'},
        ),
        isEmpty,
      );
    });

    test('unknown or malformed values do not break the subscription', () {
      for (final value in <dynamic>['other', 'cn', '', true, 1, ['ru'], {'region': 'ru'}]) {
        expect(subscriptionOverrides(headers: {'profile-routing-region': value}), isEmpty);
      }
      expect(subscriptionOverrides(headers: {'profile-routing-region': ' RU '}), {'region': 'ru'});
    });

    test('unrecognized raw settings cannot bypass the metadata allowlist', () {
      expect(
        subscriptionOverrides(headers: {
          'profile-routing-region': 'ru',
          'region': 'cn',
          'execute-config-as-is': true,
          'route-rule': {'rules': []},
        }),
        {'region': 'ru'},
      );
    });

    test('removing the header restores local region on the next update', () {
      final globalOptions = {'region': 'other', 'remote-dns-address': 'tcp://8.8.8.8'};
      final withPolicy = ProfileParser.applyProfileOverride(
        Map<String, dynamic>.from(globalOptions),
        jsonEncode(subscriptionOverrides(headers: {'profile-routing-region': 'ru'})),
      );
      final withoutPolicy = ProfileParser.applyProfileOverride(
        Map<String, dynamic>.from(globalOptions),
        jsonEncode(subscriptionOverrides()),
      );

      expect(withPolicy['region'], 'ru');
      expect(withoutPolicy['region'], 'other');
      expect(globalOptions['region'], 'other');
    });
  });
}
