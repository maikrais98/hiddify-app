import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_glass.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_surface.dart';
import 'package:hiddify/features/settings/widget/blizzard_settings_group.dart';

ThemeData _lumaTheme() => BlizzardTheme.from(
  ThemeData(extensions: const <ThemeExtension<dynamic>>[BlizzardEligibility(mode: AppThemeMode.dark)]),
);

void main() {
  test('Luma chrome is clear while readable content surfaces stay backed', () {
    final theme = _lumaTheme();

    expect(theme.appBarTheme.backgroundColor, Colors.transparent);
    expect(theme.appBarTheme.surfaceTintColor, Colors.transparent);
    expect(theme.appBarTheme.scrolledUnderElevation, 0);
    expect(theme.navigationBarTheme.backgroundColor, Colors.transparent);

    expect(theme.dialogTheme.backgroundColor, isNot(Colors.transparent));
    expect(theme.inputDecorationTheme.filled, isTrue);
    expect(theme.inputDecorationTheme.fillColor, isNot(Colors.transparent));
  });

  testWidgets('Luma surface keeps padding and delegates one panel to native glass', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      MaterialApp(
        theme: _lumaTheme(),
        home: const Center(
          child: BlizzardSurface(
            radius: 18,
            padding: EdgeInsets.all(12),
            child: SizedBox(key: ValueKey('surface-child'), width: 80, height: 40),
          ),
        ),
      ),
    );

    expect(find.byType(UiKitView), findsOneWidget);
    final native = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(native.viewType, 'app.blizzard/native-liquid-glass');
    expect(native.creationParams, {'radius': 18.0, 'lens': false, 'contentSurface': true});
    expect(native.creationParamsCodec, isA<StandardMessageCodec>());
    expect(tester.getSize(find.byType(BlizzardSurface)), const Size(104, 64));
    expect(tester.getSize(find.byKey(const ValueKey('surface-child'))), const Size(80, 40));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Luma settings group has one glass owner and clear interactive rows', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: _lumaTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: BlizzardSettingsGroup(
              groupKey: const ValueKey('settings-group'),
              title: 'Connection',
              children: [
                ListTile(key: const ValueKey('first-row'), title: const Text('First'), onTap: () => taps++),
                ListTile(key: const ValueKey('second-row'), title: const Text('Second'), onTap: () {}),
              ],
            ),
          ),
        ),
      ),
    );

    final heading = tester.widget<Text>(find.text('Connection'));
    expect(heading.style!.color, _lumaTheme().colorScheme.onSurface);

    final group = find.byKey(const ValueKey('settings-group'));
    expect(find.descendant(of: group, matching: find.byType(UiKitView)), findsOneWidget);
    expect(find.descendant(of: group, matching: find.byType(BlizzardGlass)), findsOneWidget);
    expect(
      tester
          .widgetList<Material>(find.descendant(of: group, matching: find.byType(Material)))
          .every((material) => material.color == null || material.color == Colors.transparent),
      isTrue,
      reason: 'The panel material is owned by BlizzardGlass; Flutter rows must not mask it',
    );
    final rowTheme = tester.widget<ListTileTheme>(
      find.ancestor(of: find.byKey(const ValueKey('first-row')), matching: find.byType(ListTileTheme)).first,
    );
    expect(rowTheme.data.tileColor, Colors.transparent);
    expect(rowTheme.data.selectedTileColor, Colors.transparent);
    final panelBounds = tester.getRect(group);
    final firstBounds = tester.getRect(find.byKey(const ValueKey('first-row')));
    final lastBounds = tester.getRect(find.byKey(const ValueKey('second-row')));
    expect(firstBounds.top - panelBounds.top, 4);
    expect(panelBounds.bottom - lastBounds.bottom, 4);
    expect(firstBounds.height, greaterThanOrEqualTo(52));
    expect(lastBounds.height, greaterThanOrEqualTo(52));
    expect(rowTheme.data.minVerticalPadding, 8);
    final separator = tester.getRect(find.descendant(of: group, matching: find.byType(Divider)));
    expect(separator.left - panelBounds.left, 56);
    expect(panelBounds.right - separator.right, 20);


    await tester.tap(find.byKey(const ValueKey('first-row')));
    expect(taps, 1);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('high contrast settings group keeps the opaque BlizzardGlass fallback', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      MaterialApp(
        theme: _lumaTheme(),
        home: const MediaQuery(
          data: MediaQueryData(highContrast: true),
          child: BlizzardSettingsGroup(
            groupKey: ValueKey('accessible-group'),
            title: 'Connection',
            children: [ListTile(title: Text('First'))],
          ),
        ),
      ),
    );

    final group = find.byKey(const ValueKey('accessible-group'));
    expect(find.descendant(of: group, matching: find.byType(UiKitView)), findsNothing);
    expect(find.descendant(of: group, matching: find.byType(ColoredBox)), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
