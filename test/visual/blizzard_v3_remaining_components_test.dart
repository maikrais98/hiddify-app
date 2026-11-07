import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/bottom_sheets/widgets/quick_settings_modal.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_glass.dart';
import 'package:hiddify/features/profile/add/add_profile_modal.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_modal.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart';
import 'package:hiddify/features/proxy/active/active_proxy_card.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/proxy/widget/proxy_tile.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';

import '../support/home_fixture.dart';

Widget _applied(Widget child) => Builder(
  builder: (context) => Theme(data: BlizzardTheme.from(Theme.of(context)), child: child),
);

void main() {
  testWidgets('v3 Home profile keeps update action in the light 76pt card', (tester) async {
    final profile = ProfileEntity.remote(
      id: 'v3-profile',
      active: true,
      name: 'Akonit Premium',
      url: 'https://example.invalid/sub',
      lastUpdate: DateTime.utc(2026),
      subInfo: SubscriptionInfo(upload: 0, download: 0, total: 12 * 1099511627776, expire: DateTime.utc(2099)),
    );
    final update = TileUpdateSpy();
    final fixture = await mountHomeFixture(
      tester,
      locale: AppLocale.ru,
      child: Center(
        child: SizedBox(width: 353, child: _applied(ProfileTile(profile: profile, isMain: true))),
      ),
      extraOverrides: [updateProfileNotifierProvider('v3-profile').overrideWith(() => update)],
    );

    final cardFinder = find.descendant(of: find.byType(ProfileTile), matching: find.byType(Card));
    final card = tester.widget<Card>(cardFinder);
    expect(tester.getSize(cardFinder).height, 76);
    expect((card.shape! as RoundedRectangleBorder).side, BorderSide.none);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.sync_rounded), findsOneWidget);
    expect(
      find.textContaining(AppLocale.ru.buildSync().components.subscriptionInfo.remainingUnlimited),
      findsOneWidget,
    );
    await tester.tap(find.byIcon(Icons.sync_rounded));
    await tester.pump();
    expect(update.calls, ['update:v3-profile']);
    expect(fixture.container.read(updateProfileNotifierProvider('v3-profile')).isLoading, isTrue);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('updating')), findsOneWidget);
    expect(
      tester
          .widgetList<InkWell>(
            find.descendant(of: find.byKey(const ValueKey('updating')), matching: find.byType(InkWell)),
          )
          .where((button) => button.onTap != null),
      isEmpty,
      reason: 'the official updating state exposes progress without another update callback',
    );
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('v3 server row uses 74pt geometry and an explicit selected check', (tester) async {
    final proxy = OutboundInfo(tag: 'fi', tagDisplay: 'Финляндия', type: 'VLESS', urlTestDelay: 84);
    final fixture = await mountHomeFixture(
      tester,
      locale: AppLocale.ru,
      child: Center(
        child: SizedBox(width: 353, child: _applied(ProxyTile(proxy, selected: true, onTap: () {}))),
      ),
    );

    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tester.getSize(find.byType(ListTile)), const Size(353, 74));
    expect(tile.contentPadding, const EdgeInsets.symmetric(horizontal: 14));
    expect(tile.horizontalTitleGap, 8);
    expect(tile.selectedTileColor, BlizzardPalette.accent.withValues(alpha: 0.07));
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('v3 active server card is the unshadowed 84pt content surface', (tester) async {
    final fixture = await mountHomeFixture(
      tester,
      child: Center(child: SizedBox(width: 353, child: _applied(const ActiveProxyFooter()))),
    );
    expect(fixture.container.read(activeProxyCardProvider)?.server.tag, 'fi');
    expect(tester.getSize(find.byType(ActiveProxyFooter)), const Size(353, 84));
    final glass = tester.widget<BlizzardGlass>(
      find.descendant(of: find.byType(ActiveProxyFooter), matching: find.byType(BlizzardGlass)),
    );
    expect(glass.radius, 20);
    expect(glass.active, isTrue);
    expect(find.descendant(of: find.byType(ActiveProxyFooter), matching: find.byType(Card)), findsNothing);
    expect(
      tester
          .widgetList<Material>(find.descendant(of: find.byType(ActiveProxyFooter), matching: find.byType(Material)))
          .every((material) => material.elevation == 0),
      isTrue,
      reason: 'the selected-server content must not add an elevated surface over its glass',
    );
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('v3 active server card keeps 84pt minimum and grows at 2x text scale', (tester) async {
    final fixture = await mountHomeFixture(
      tester,
      scale: 2,
      child: Center(child: SizedBox(width: 353, child: _applied(const ActiveProxyFooter()))),
    );
    expect(fixture.container.read(activeProxyCardProvider)?.server.tag, 'fi');
    expect(tester.getSize(find.byType(ActiveProxyFooter)).height, greaterThan(84));
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('v3 Settings uses outlined 20pt symbols and hairline separators', (tester) async {
    final fixture = await mountHomeFixture(tester, locale: AppLocale.ru, child: _applied(const BlizzardSettingsMenu()));
    final general = tester.widget<Icon>(find.byIcon(Icons.tune_outlined));
    expect(general.size, 20);
    expect(general.color, BlizzardPalette.secondary);
    expect(find.byIcon(Icons.layers_rounded), findsNothing);
    final generalTile = tester.widget<ListTile>(find.ancestor(of: find.text('Общие'), matching: find.byType(ListTile)));
    expect(generalTile.contentPadding, const EdgeInsets.symmetric(horizontal: 16));
    expect(generalTile.minLeadingWidth, 24);
    expect(generalTile.horizontalTitleGap, 12);
    final dividers = tester.widgetList<Divider>(find.byType(Divider)).toList();
    expect(dividers, hasLength(5));
    expect(dividers.every((divider) => divider.color == BlizzardPalette.secondary.withValues(alpha: 0.12)), isTrue);
    final applicationGroup = find.byKey(const ValueKey('settings-group-application'));
    final firstDivider = find.descendant(of: applicationGroup, matching: find.byType(Divider)).first;
    expect(tester.getRect(firstDivider).left - tester.getRect(applicationGroup).left, closeTo(56, 0.01));
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('v3 Profiles sheet starts at the 223pt reference and keeps both toolbar actions', (tester) async {
    final profiles = TileProfilesSpy()
      ..profiles = [
        ProfileEntity.local(id: 'sheet-profile', active: true, name: 'Akonit Premium', lastUpdate: DateTime.utc(2026)),
      ];
    final fixture = await mountHomeFixture(
      tester,
      locale: AppLocale.ru,
      child: _applied(const ProfilesModal()),
      extraOverrides: [profilesNotifierProvider.overrideWith(() => profiles)],
    );
    final sheet = tester.widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet));
    expect(sheet.initialChildSize, closeTo(223 / 852, .001));
    expect(find.text('Профили'), findsOneWidget);
    expect(find.byIcon(Icons.sort_rounded), findsOneWidget);
    expect(find.byIcon(Icons.update_rounded), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('v3 Quick Settings keeps the 44pt selector and official chain actions', (tester) async {
    final fixture = await mountHomeFixture(tester, locale: AppLocale.ru, child: _applied(const QuickSettingsModal()));
    expect(find.text('Быстрые настройки'), findsOneWidget);
    final segmented = find.byWidgetPredicate((widget) => widget is SegmentedButton);
    expect(tester.getSize(segmented), const Size(361, 44));
    final t = AppLocale.ru.buildSync();
    final rows = find.byType(ListTile);
    expect(tester.getSize(find.byKey(const ValueKey('quick-settings-chain-glass'))).width, 361);
    expect(rows, findsNWidgets(3));
    for (final row in rows.evaluate()) {
      final size = tester.getSize(find.byWidget(row.widget));
      expect(size.width, 353, reason: 'the grouped panel retains its 4pt content inset on each side');
      expect(size.height, greaterThanOrEqualTo(44));
    }
    expect(find.byType(Switch), findsOneWidget, reason: 'LAN sharing retains its own switch');
    final extraSecurity = find.text(t.pages.settings.chain.quick.extraSecurity.title);
    final unblocker = find.text(t.pages.settings.chain.quick.unblocker.title);
    expect(extraSecurity, findsOneWidget);
    expect(unblocker, findsOneWidget);
    await tester.tap(extraSecurity);
    await tester.pump();
    expect(fixture.container.read(ConfigOptions.chainStatus), ChainStatus.extraSecurity);
    await tester.tap(unblocker);
    await tester.pump();
    expect(fixture.container.read(ConfigOptions.chainStatus), ChainStatus.unblocker);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('v3 Add Profile options starts at the 245pt reference height', (tester) async {
    final fixture = await mountHomeFixture(tester, child: _applied(const AddProfileOptions()));
    expect(tester.getSize(find.byType(AddProfileOptions)).height, closeTo(245, .01));
    expect(find.byKey(const ValueKey('add_from_clipboard_button')), findsOneWidget);
    expect(find.byKey(const ValueKey('add_manually_button')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });
}
