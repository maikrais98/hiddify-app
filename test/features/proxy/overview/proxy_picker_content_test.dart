import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
import 'package:hiddify/features/proxy/overview/proxy_picker_content.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

void main() {
  OutboundInfo proxy(String tag, {String type = 'vmess', String countryCode = '', String organization = ''}) {
    return OutboundInfo(
      tag: tag,
      type: type,
      ipinfo: IpInfo(countryCode: countryCode, org: organization),
    );
  }

  Widget buildPicker({
    required OutboundGroup group,
    List<String> recentTags = const [],
    ValueChanged<OutboundInfo>? onSelect,
  }) {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [NovaThemeData.dark]),
      home: Scaffold(
        body: ProxyPickerContent(
          group: group,
          recentTags: recentTags,
          searchHint: 'Search servers',
          clearLabel: 'Clear search',
          selectedLabel: 'Selected server',
          recentLabel: 'Recent servers',
          noResultsTitle: 'No matching servers',
          noResultsBody: 'Try another name, country, city, or server tag.',
          onSelect: onSelect ?? (_) {},
        ),
      ),
    );
  }

  test('search matches node name, type, country, and organization without changing source order', () {
    final items = [
      proxy('Stockholm', countryCode: 'SE', organization: 'Bahnhof'),
      proxy('Tokyo edge', type: 'trojan', countryCode: 'JP', organization: 'Example Cloud'),
      proxy('Vienna'),
    ];

    expect(filterProxies(items, '  TOKYO '), [items[1]]);
    expect(filterProxies(items, 'trojan'), [items[1]]);
    expect(filterProxies(items, 'jp'), [items[1]]);
    expect(filterProxies(items, 'cloud'), [items[1]]);
    expect(filterProxies(items, ''), items);
  });

  test('large-list search reduces one hundred candidates to one exact result', () {
    final items = List.generate(100, (index) => proxy('Node ${index.toString().padLeft(3, '0')}'));

    expect(filterProxies(items, 'Node 099'), [items.last]);
  });

  testWidgets('keeps the selected node visible while search filters the catalog', (tester) async {
    final group = OutboundGroup(
      tag: 'select',
      selected: 'Vienna',
      items: [proxy('Stockholm'), proxy('Tokyo edge'), proxy('Vienna')],
    );
    await tester.pumpWidget(buildPicker(group: group));

    expect(find.byKey(const ValueKey('proxy_picker_selected')), findsOneWidget);
    expect(find.text('Vienna'), findsNWidgets(2));

    await tester.enterText(find.byKey(const ValueKey('proxy_picker_search')), 'tokyo');
    await tester.pump();

    expect(find.text('Tokyo edge'), findsOneWidget);
    expect(find.text('Stockholm'), findsNothing);
    expect(find.byKey(const ValueKey('proxy_picker_selected')), findsOneWidget);
    expect(find.text('Vienna'), findsOneWidget);
  });

  testWidgets('search empty state clears back to the full list', (tester) async {
    final group = OutboundGroup(tag: 'select', selected: 'Vienna', items: [proxy('Stockholm'), proxy('Vienna')]);
    await tester.pumpWidget(buildPicker(group: group));

    await tester.enterText(find.byKey(const ValueKey('proxy_picker_search')), 'does-not-exist');
    await tester.pump();

    expect(find.text('No matching servers'), findsOneWidget);
    expect(find.text('Try another name, country, city, or server tag.'), findsOneWidget);
    expect(find.byKey(const ValueKey('proxy_picker_clear')), findsOneWidget);
    expect(find.byKey(const ValueKey('proxy_picker_selected')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('proxy_picker_clear')));
    await tester.pump();

    expect(find.text('No matching servers'), findsNothing);
    expect(find.text('Stockholm'), findsOneWidget);
    expect(find.text('Vienna'), findsNWidgets(2));
  });

  testWidgets('recent node is a one-tap repeat choice and stale tags stay hidden', (tester) async {
    final selected = <String>[];
    final group = OutboundGroup(
      tag: 'select',
      selected: 'Tokyo edge',
      items: [proxy('Stockholm'), proxy('Tokyo edge'), proxy('Vienna')],
    );
    await tester.pumpWidget(
      buildPicker(
        group: group,
        recentTags: const ['Tokyo edge', 'Vienna', 'Removed node', 'Stockholm'],
        onSelect: (proxy) => selected.add(proxy.tag),
      ),
    );

    expect(find.text('Recent servers'), findsOneWidget);
    expect(find.byKey(const ValueKey('proxy_picker_recent_Vienna')), findsOneWidget);
    expect(find.byKey(const ValueKey('proxy_picker_recent_Stockholm')), findsOneWidget);
    expect(find.text('Removed node'), findsNothing);
    expect(find.byKey(const ValueKey('proxy_picker_recent_Tokyo edge')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('proxy_picker_recent_Vienna')));
    expect(selected, ['Vienna']);
  });

  testWidgets('reopening resets search and keeps selected and recent shortcuts honest', (tester) async {
    final group = OutboundGroup(
      tag: 'select',
      selected: 'Tokyo edge',
      items: [proxy('Stockholm'), proxy('Tokyo edge'), proxy('Vienna')],
    );
    await tester.pumpWidget(buildPicker(group: group, recentTags: const ['Vienna']));
    await tester.enterText(find.byKey(const ValueKey('proxy_picker_search')), 'stock');
    await tester.pump();
    expect(find.byKey(const ValueKey('proxy_picker_recent_Vienna')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(buildPicker(group: group, recentTags: const ['Vienna']));
    await tester.pump();

    expect(tester.widget<TextField>(find.byKey(const ValueKey('proxy_picker_search'))).controller!.text, isEmpty);
    expect(find.text('Stockholm'), findsOneWidget);
    expect(find.byKey(const ValueKey('proxy_picker_selected')), findsOneWidget);
    expect(find.byKey(const ValueKey('proxy_picker_recent_Vienna')), findsOneWidget);
  });
}
