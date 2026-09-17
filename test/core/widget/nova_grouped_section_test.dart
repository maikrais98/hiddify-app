import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
import 'package:hiddify/core/widget/nova_grouped_section.dart';

void main() {
  testWidgets('renders one rounded group with dividers and accessible rows', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [NovaThemeData.dark]),
        home: const Scaffold(
          body: NovaGroupedSection(
            title: 'НАСТРОЙКИ',
            children: [
              ListTile(title: Text('Общие')),
              ListTile(title: Text('Расширенные настройки')),
            ],
          ),
        ),
      ),
    );

    expect(find.text('НАСТРОЙКИ'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
    expect(find.byType(Material), findsWidgets);
    expect(tester.getSize(find.text('Общие').first).height, greaterThan(0));
    expect(tester.getSize(find.byType(ListTile).first).height, greaterThanOrEqualTo(44));
  });

  testWidgets('keeps grouped content reachable at 393x852 and 2x text', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [NovaThemeData.dark]),
        home: const MediaQuery(
          data: MediaQueryData(size: Size(393, 852), textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: NovaGroupedSection(
                title: 'СЕТЬ И ЗАЩИТА',
                footer: 'Параметры применяются к текущему подключению.',
                children: [
                  ListTile(title: Text('Настройки VPN'), subtitle: Text('Входящие соединения и локальные порты')),
                  ListTile(title: Text('TLS и фрагментация')),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('TLS и фрагментация'), findsOneWidget);
  });
}
