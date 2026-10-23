import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/features/home/widget/home_page.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/data/proxy_repository.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_page.dart';
import 'package:hiddify/features/proxy/widget/proxy_tile.dart';
import 'package:hiddify/features/settings/overview/sections/general_page.dart';
import 'package:hiddify/features/settings/overview/sections/warp_options_page.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../support/connection_fixtures.dart';
import '../support/home_fixture.dart';
import '../support/profile_settings_fixtures.dart' show FixtureCore, FixtureHttp;
import '../support/surface_fixtures.dart';

Widget _applied(Widget child) => Builder(
  builder: (context) => Theme(data: BlizzardTheme.from(Theme.of(context)), child: child),
);

Future<void> _traverse(WidgetTester tester, Type page) async {
  final scroll = find.descendant(of: find.byType(page), matching: find.byType(Scrollable)).first;
  var measured = 0;
  for (var step = 0; step < 20; step++) {
    for (final e in interactiveRows().evaluate().toList()) {
      final row = find.byWidget(e.widget);
      if (row.hitTestable().evaluate().isEmpty) continue;
      expect(tester.getSize(row).shortestSide, greaterThanOrEqualTo(44));
      measured++;
    }
    final state = tester.state<ScrollableState>(scroll);
    if (state.position.extentAfter < 1) break;
    await tester.drag(scroll, const Offset(0, -300));
    await tester.pumpAndSettle();
  }
  expect(measured, greaterThan(0));
  expect(tester.state<ScrollableState>(scroll).position.extentAfter, lessThan(1));
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final spec in [(id: 'LUYP5', width: 320.0, scale: 1.0), (id: 'CATiY', width: 393.0, scale: 1.5)]) {
    testWidgets('${spec.id} Aurora General reaches full scroll at ${spec.width} and ${spec.scale} text', (
      tester,
    ) async {
      final f = await mountHomeFixture(
        tester,
        child: _applied(const GeneralPage()),
        width: spec.width,
        scale: spec.scale,
        locale: AppLocale.ru,
      );
      await _traverse(tester, GeneralPage);
      final theme = Theme.of(tester.element(find.byType(GeneralPage)));
      expect(theme.extension<BlizzardEligibility>()?.applied, isTrue);
      expect(contrastRatio(theme.colorScheme.onSurface, theme.colorScheme.surface), greaterThanOrEqualTo(4.5));
      await f.close(tester);
    });
  }
  testWidgets('mXFHW Aurora disabled WARP reaches full scroll at 150 percent text', (tester) async {
    final f = await mountHomeFixture(
      tester,
      child: _applied(const WarpOptionsPage()),
      scale: 1.5,
      locale: AppLocale.ru,
    );
    await _traverse(tester, WarpOptionsPage);
    expect(tester.widgetList<ListTile>(find.byType(ListTile)).where((w) => !w.enabled), isNotEmpty);
    await f.close(tester);
  });
  testWidgets('AbQFL ZW7Ma g90Ngr j7Us9 Aurora ten servers at 430 keep measured and timeout rows reachable', (
    tester,
  ) async {
    final group = OutboundGroup(
      tag: 'select',
      selected: 'server-1',
      items: List.generate(
        10,
        (i) => OutboundInfo(
          tag: 'server-${i + 1}',
          tagDisplay: 'Сервер ${i + 1}',
          type: 'VLESS',
          urlTestDelay: i == 2 ? 65001 : 84 + i,
        ),
      ),
    );
    final core = FixtureCore()..group = group;
    final f = await mountHomeFixture(
      tester,
      child: _applied(const ProxiesOverviewPage()),
      width: 430,
      height: 932,
      profile: connectionProfile,
      locale: AppLocale.ru,
      extraOverrides: [
        proxiesOverviewNotifierProvider.overrideWith(() => SurfaceProxies(AsyncData(group))),
        proxyRepositoryProvider.overrideWith((ref) => ProxyRepositoryImpl(singbox: core, client: FixtureHttp())),
      ],
    );
    final scroll = find.descendant(of: find.byType(GridView), matching: find.byType(Scrollable));
    for (var index = 1; index <= 10; index++) {
      final row = find.byWidgetPredicate((w) => w is ProxyTile && w.proxy.tag == 'server-$index');
      await tester.scrollUntilVisible(row, 80, scrollable: scroll);
      await Scrollable.ensureVisible(tester.element(find.text('Сервер $index')), alignment: .3);
      await tester.pumpAndSettle();
      expect(find.text('Сервер $index').hitTestable(), findsOneWidget);
      if (index == 2) expect(find.descendant(of: row, matching: find.text('85')), findsOneWidget);
      if (index == 3) expect(find.descendant(of: row, matching: find.text('×')), findsOneWidget);
    }
    final action = find.byKey(const ValueKey('servers_test_delay_button'));
    await tester.scrollUntilVisible(action, 80, scrollable: scroll);
    await tester.tap(action);
    await tester.pump();
    expect(core.delayTests, ['select']);
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });
  for (final size in [const Size(320, 568), const Size(430, 932)]) {
    final id = size.width == 320 ? 'iV7Gh' : 'nkPdP';
    testWidgets('$id Aurora Home preserves reachable primary at ${size.width}x${size.height}', (tester) async {
      final f = await mountHomeFixture(
        tester,
        child: _applied(const HomePage()),
        width: size.width,
        height: size.height,
        profile: connectionProfile,
      );
      final primary = find.byKey(const ValueKey('home_connection_button'));
      expect(primary.hitTestable(), findsOneWidget);
      expect(tester.getSize(primary).shortestSide, greaterThanOrEqualTo(44));
      expect(find.byType(HomePage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    });
  }
}
