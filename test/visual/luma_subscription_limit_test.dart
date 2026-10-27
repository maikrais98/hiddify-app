import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../support/home_fixture.dart';

const _gibibyte = 1073741824;
const _unlimitedTrafficSentinel = 920233720369;

Widget _applied(Widget child) => Builder(
  builder: (context) => Theme(data: BlizzardTheme.from(Theme.of(context)), child: child),
);

RemoteProfileEntity _profile({
  required String id,
  required String name,
  required int consumed,
  required int total,
  int remainingDays = 145,
}) => ProfileEntity.remote(
  id: id,
  active: true,
  name: name,
  url: 'https://example.invalid/$id',
  lastUpdate: DateTime.utc(2026, 10, 27),
  subInfo: SubscriptionInfo(
    upload: consumed,
    download: 0,
    total: total,
    expire: DateTime.now().add(Duration(days: remainingDays)),
  ),
) as RemoteProfileEntity;

void main() {
  testWidgets('sentinel cards keep own usage without showing the synthetic 857 GiB limit', (tester) async {
    final myUsage = (217.14 * _gibibyte).round();
    final fixture = await mountHomeFixture(
      tester,
      child: _applied(
        Column(
          children: [
            ProfileTile(
              profile: _profile(
                id: 'my',
                name: 'My',
                consumed: myUsage,
                total: _unlimitedTrafficSentinel,
                remainingDays: 1000,
              ),
              isMain: true,
            ),
            ProfileTile(
              profile: _profile(
                id: 'akonit',
                name: 'Akonit',
                consumed: 0,
                total: _unlimitedTrafficSentinel,
              ),
              isMain: true,
            ),
          ],
        ),
      ),
    );
    final t = fixture.container.read(translationsProvider).requireValue;

    final myTrafficFinder = find.textContaining('217.14GiB / —');
    final akonitTrafficFinder = find.textContaining('0GiB / —');
    expect(myTrafficFinder, findsOneWidget);
    expect(akonitTrafficFinder, findsOneWidget);
    final myTraffic = tester.widget<Text>(myTrafficFinder);
    final akonitTraffic = tester.widget<Text>(akonitTrafficFinder);
    expect(myTraffic.semanticsLabel, contains(t.common.notSet));
    expect(akonitTraffic.semanticsLabel, contains(t.common.notSet));
    expect(find.textContaining('857.03GiB'), findsNothing);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('sentinel is not treated as an exhausted finite quota', (tester) async {
    final fixture = await mountHomeFixture(
      tester,
      child: _applied(
        ProfileTile(
          profile: _profile(
            id: 'sentinel',
            name: 'Sentinel',
            consumed: _unlimitedTrafficSentinel + 1,
            total: _unlimitedTrafficSentinel,
          ),
        ),
      ),
    );
    final t = fixture.container.read(translationsProvider).requireValue;

    expect(find.byType(RemainingTrafficIndicator), findsNothing);
    expect(find.text(t.components.subscriptionInfo.noTraffic), findsNothing);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('finite totals remain numeric and distinct above and below 10 TiB', (tester) async {
    final fixture = await mountHomeFixture(
      tester,
      child: _applied(
        Column(
          children: [
            ProfileTile(
              profile: _profile(id: 'finite-100', name: 'Finite 100', consumed: _gibibyte, total: 100 * _gibibyte),
              isMain: true,
            ),
            ProfileTile(
              profile: _profile(id: 'finite-200', name: 'Finite 200', consumed: _gibibyte, total: 200 * _gibibyte),
              isMain: true,
            ),
            ProfileTile(
              profile: _profile(
                id: 'finite-12tib',
                name: 'Finite 12 TiB',
                consumed: _gibibyte,
                total: 12 * 1024 * _gibibyte,
              ),
              isMain: true,
            ),
          ],
        ),
      ),
    );

    expect(find.textContaining('1GiB / 100GiB'), findsOneWidget);
    expect(find.textContaining('1GiB / 200GiB'), findsOneWidget);
    expect(find.textContaining('1GiB / 12288GiB'), findsOneWidget);
    expect(find.textContaining('∞ GiB'), findsNothing);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  for (final subscriptionHeader in [
    'upload=1;download=2;total=0;expire=4102444800',
    'upload=1;download=2;total=invalid;expire=4102444800',
  ]) {
    test('zero or invalid total maps to the stable sentinel', () {
      final headers = ProfileParser.populateHeaders(
        content: '',
        remoteHeaders: {'subscription-userinfo': subscriptionHeader},
      ).getOrElse((failure) => throw failure);
      final profile = ProfileParser.parse(
        tempFilePath: '',
        profile: ProfileEntity.remote(
          id: 'parser',
          active: true,
          name: '',
          url: 'https://example.invalid/parser',
          lastUpdate: DateTime.utc(2026, 10, 27),
          populatedHeaders: headers,
          userOverride: const UserOverride(name: 'Parser'),
        ),
      ).getOrElse((failure) => throw failure) as RemoteProfileEntity;

      expect(profile.subInfo?.total, _unlimitedTrafficSentinel);
    });
  }

  test('missing total does not invent subscription info', () {
    final headers = ProfileParser.populateHeaders(
      content: '',
      remoteHeaders: {'subscription-userinfo': 'upload=1;download=2;expire=4102444800'},
    ).getOrElse((failure) => throw failure);
    final profile = ProfileParser.parse(
      tempFilePath: '',
      profile: ProfileEntity.remote(
        id: 'parser-missing',
        active: true,
        name: '',
        url: 'https://example.invalid/parser-missing',
        lastUpdate: DateTime.utc(2026, 10, 27),
        populatedHeaders: headers,
        userOverride: const UserOverride(name: 'Parser missing'),
      ),
    ).getOrElse((failure) => throw failure) as RemoteProfileEntity;

    expect(profile.subInfo, isNull);
  });
}
