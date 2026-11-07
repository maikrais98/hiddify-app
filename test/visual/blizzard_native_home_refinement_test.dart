import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/features/home/widget/home_page.dart';
import 'package:hiddify/features/proxy/active/active_proxy_delay_indicator.dart';

import '../support/blizzard_visual_acceptance_fixture.dart';
import '../support/home_fixture.dart';

Widget _applied(Widget child) => Builder(
  builder: (context) => Theme(data: BlizzardTheme.from(Theme.of(context)), child: child),
);

void main() {
  testWidgets('v3 Home latency uses the muted 15pt reference and keeps a 44pt refresh target', (tester) async {
    final fixture = await mountHomeFixture(tester, locale: AppLocale.ru, child: _applied(const HomePage()));
    final label = find.text('Задержка 84 мс');
    expect(find.textContaining('luma', findRichText: true), findsOneWidget);
    expect(label, findsOneWidget);
    final style = tester.widget<Text>(label).style!;
    expect(style.fontSize, 15);
    expect(style.fontWeight, FontWeight.w400);
    expect(style.color, BlizzardPalette.muted);
    for (final symbol in [Icons.tune_rounded, Icons.add_rounded]) {
      expect(tester.widget<Icon>(find.byIcon(symbol)).color, BlizzardPalette.primary);
    }
    await fixture.close(tester);
  });

  testWidgets('v3 latency refresh remains at least 44pt outside the hero constraints', (tester) async {
    final fixture = await mountHomeFixture(
      tester,
      locale: AppLocale.ru,
      child: _applied(const Center(child: ActiveProxyDelayIndicator())),
    );
    final label = find.text('Задержка 84 мс');
    expect(label, findsOneWidget);
    expect(
      tester.getSize(find.ancestor(of: label, matching: find.byType(InkWell)).first).height,
      greaterThanOrEqualTo(44),
    );
    await fixture.close(tester);
  });

  testWidgets('native SF status keeps the reference latency gap and refresh target', (tester) async {
    final fixture = await mountHomeFixture(
      tester,
      locale: AppLocale.ru,
      extraOverrides: blizzardVisualAcceptanceOverrides,
    );
    final label = find.text('Задержка 84 мс');
    expect(label, findsOneWidget);
    expect(
      tester.getSize(find.ancestor(of: label, matching: find.byType(InkWell)).first).height,
      greaterThanOrEqualTo(44),
    );
    final status = tester.getRect(find.text('VPN подключён'));
    final latency = tester.getRect(label);
    expect(latency.top - status.bottom, closeTo(8, 1));
    await fixture.close(tester);
  }, skip: !Platform.isIOS);
}
