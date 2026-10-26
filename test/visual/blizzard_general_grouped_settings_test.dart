import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_backdrop.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_surface.dart';
import 'package:hiddify/features/settings/overview/sections/general_page.dart';

import '../support/home_fixture.dart';

Widget _underAurora(Widget child) => Builder(
  builder: (context) => Theme(data: BlizzardTheme.from(Theme.of(context)), child: child),
);

void main() {
  testWidgets('Aurora General backdrop owns the full scaffold', (tester) async {
    final fixture = await mountHomeFixture(tester, child: _underAurora(const GeneralPage()));

    expect(find.ancestor(of: find.byType(Scaffold).last, matching: find.byType(BlizzardBackdrop)), findsOneWidget);
    expect(find.byType(BlizzardBackdrop), findsOneWidget);
    expect(tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor, Colors.transparent);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('Aurora General groups the preserved iOS preferences into dense sections', (tester) async {
    final fixture = await mountHomeFixture(
      tester,
      height: 1800,
      locale: AppLocale.ru,
      child: _underAurora(const GeneralPage()),
    );

    const groups = <String, List<String>>{
      'general-settings-group-appearance': ['Язык', 'Тема оформления'],
      'general-settings-group-privacy': ['Включить аналитику', 'Автоматически проверять IP-адрес'],
      'general-settings-group-connection': [
        'Ограничение памяти',
        'Режим отладки',
        'Уровень логирования',
        'URL для теста соединения',
        'Интервал теста URL',
        'Порт Clash API',
        'Использовать xray-core, если возможно',
      ],
    };

    for (final entry in groups.entries) {
      final group = find.byKey(ValueKey(entry.key));
      expect(group, findsOneWidget);
      expect(tester.widget<BlizzardSurface>(group).radius, 18);
      for (final title in entry.value) {
        expect(
          find.descendant(of: group, matching: find.text(title)),
          findsOneWidget,
          reason: entry.key,
        );
      }
      final dividers = find.descendant(of: group, matching: find.byType(Divider)).evaluate().length;
      expect(dividers, greaterThanOrEqualTo(entry.value.length - 1));
    }

    for (final heading in ['Оформление', 'Приватность', 'Подключение']) {
      expect(find.text(heading), findsOneWidget);
    }
    expect(find.text('Диагностика'), findsNothing);
    final titles = groups.values.expand((titles) => titles).toList();
    for (var i = 1; i < titles.length; i++) {
      expect(tester.getTopLeft(find.text(titles[i])).dy, greaterThan(tester.getTopLeft(find.text(titles[i - 1])).dy));
    }
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('Aurora General final controls scroll above the shell bottom inset', (tester) async {
    const bottomInset = 100.0;
    final fixture = await mountHomeFixture(
      tester,
      height: 568,
      locale: AppLocale.ru,
      child: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(padding: const EdgeInsets.only(bottom: bottomInset)),
          child: _underAurora(const GeneralPage()),
        ),
      ),
    );

    final list = find.descendant(of: find.byType(GeneralPage), matching: find.byType(ListView));
    final scrollable = find.descendant(of: list, matching: find.byType(Scrollable)).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    // The lazy list refines its extent when the taller final group is laid out.
    for (var attempt = 0; attempt < 3; attempt++) {
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
    }

    final lastGroup = find.byKey(const ValueKey('general-settings-group-connection'));
    expect(tester.getRect(lastGroup).bottom, lessThanOrEqualTo(tester.getRect(list).bottom - bottomInset));
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });
}
