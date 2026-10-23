import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/router/adaptive_layout/blizzard_dock.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_route_action.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_native_tab_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
  });

  testWidgets('iOS dock delegates its complete interactive surface to UIKit', (tester) async {
    final viewId = await _pumpNativeDock(tester);

    expect(find.byType(BlizzardNativeTabBar), findsOneWidget);
    expect(find.byType(UiKitView), findsOneWidget);
    expect(find.byType(InkWell), findsNothing);
    final platformSemantics = find.descendant(of: find.byType(BlizzardNativeTabBar), matching: find.byType(Semantics));
    expect(platformSemantics, findsOneWidget);
    final semantics = tester.widget<Semantics>(platformSemantics).properties;
    expect(semantics.label, isNull);
    expect(semantics.button, isNull);
    expect(semantics.selected, isNull);
    expect(semantics.onTap, isNull);
    expect(find.text('Home'), findsNothing);
    expect(find.text('Settings'), findsNothing);
    expect(find.byKey(const ValueKey('blizzard_bottom_dock_tab_0')), findsNothing);
    expect(find.byKey(const ValueKey('blizzard_bottom_dock_tab_1')), findsNothing);
    expect(find.byKey(const ValueKey('blizzard_bottom_dock')), findsOneWidget);

    final view = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(view.viewType, 'app.blizzard/native-tab-bar');
    expect(view.creationParamsCodec, isA<StandardMessageCodec>());
    expect(view.creationParams, {
      'titles': ['Home', 'Settings'],
      'selectedIndex': 0,
      'tint': BlizzardPalette.accent.toARGB32(),
      'dark': false,
    });
    expect(tester.getSize(find.byType(UiKitView)), const Size(320, 88));
    expect(tester.getSize(find.byType(BlizzardDock)), const Size(800, 100));
    expect(viewId, isNonNegative);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS dock does not add the device bottom inset to its 12 point external padding', (tester) async {
    await _pumpNativeDock(tester, bottomPadding: 34);

    expect(tester.getSize(find.byType(UiKitView)), const Size(320, 88));
    expect(tester.getSize(find.byType(BlizzardDock)).height, 100);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('non-iOS fallback retains its device-aware safe-area geometry', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await _pumpNativeDock(tester);
    expect(tester.getSize(find.byType(BlizzardDock)).height, 64 + 12);
    expect(find.byType(UiKitView), findsNothing);

    await _pumpNativeDock(tester, bottomPadding: 34);
    expect(tester.getSize(find.byType(BlizzardDock)).height, 64 + 34);
    expect(find.byType(UiKitView), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('native select delivers selection and re-selection while ignoring invalid payloads', (tester) async {
    final selected = <int>[];
    final viewId = await _pumpNativeDock(tester, onSelected: selected.add);
    final channel = MethodChannel('app.blizzard/native-tab-bar/$viewId');

    await _sendNativeCall(tester, channel, const MethodCall('select', {'index': 1}));
    await _sendNativeCall(tester, channel, const MethodCall('select', {'index': 0}));
    await _sendNativeCall(tester, channel, const MethodCall('select', {'index': 0}));
    await _sendNativeCall(tester, channel, const MethodCall('select', {'index': -1}));
    await _sendNativeCall(tester, channel, const MethodCall('select', {'index': 2}));
    await _sendNativeCall(tester, channel, const MethodCall('select', {'index': '1'}));
    await _sendNativeCall(tester, channel, const MethodCall('select'));
    await _sendNativeCall(tester, channel, const MethodCall('unknown', {'index': 1}));

    expect(selected, [1, 0, 0]);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('native view receives one atomic full-state update after each meaningful change', (tester) async {
    final updates = <Map<Object?, Object?>>[];
    final selectedIndex = ValueNotifier(0);
    final titles = ValueNotifier(['Home', 'Settings']);
    final dark = ValueNotifier(false);
    addTearDown(selectedIndex.dispose);
    addTearDown(titles.dispose);
    addTearDown(dark.dispose);

    final viewId = await _pumpNativeDock(
      tester,
      selectedIndex: selectedIndex,
      titles: titles,
      dark: dark,
      onUpdate: (arguments) => updates.add(Map<Object?, Object?>.from(arguments! as Map)),
    );
    expect(updates, [
      {
        'titles': ['Home', 'Settings'],
        'selectedIndex': 0,
        'tint': BlizzardPalette.accent.toARGB32(),
        'dark': false,
      },
    ]);

    selectedIndex.value = 1;
    await tester.pump();
    titles.value = ['Главная', 'Настройки'];
    await tester.pump();
    dark.value = true;
    await tester.pumpAndSettle();

    expect(updates, hasLength(4));
    expect(updates[1], {
      'titles': ['Home', 'Settings'],
      'selectedIndex': 1,
      'tint': BlizzardPalette.accent.toARGB32(),
      'dark': false,
    });
    expect(updates[2], {
      'titles': ['Главная', 'Настройки'],
      'selectedIndex': 1,
      'tint': BlizzardPalette.accent.toARGB32(),
      'dark': false,
    });
    expect(updates[3], {
      'titles': ['Главная', 'Настройки'],
      'selectedIndex': 1,
      'tint': BlizzardPalette.accent.toARGB32(),
      'dark': true,
    });

    // The channel identity is part of the protocol and remains stable for the view.
    expect(viewId, isNonNegative);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('disposed native dock clears its callback channel', (tester) async {
    final selected = <int>[];
    final viewId = await _pumpNativeDock(tester, onSelected: selected.add);
    final channel = MethodChannel('app.blizzard/native-tab-bar/$viewId');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _sendNativeCall(tester, channel, const MethodCall('select', {'index': 1}));

    expect(selected, isEmpty);
    debugDefaultTargetPlatformOverride = null;
  });
}

Future<int> _pumpNativeDock(
  WidgetTester tester, {
  ValueChanged<int>? onSelected,
  ValueNotifier<int>? selectedIndex,
  ValueNotifier<List<String>>? titles,
  ValueNotifier<bool>? dark,
  ValueChanged<Object?>? onUpdate,
  double bottomPadding = 0,
}) async {
  final created = Completer<int>();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
    if (call.method == 'create') {
      final arguments = call.arguments! as Map<Object?, Object?>;
      final id = arguments['id']! as int;
      if (onUpdate != null) {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          MethodChannel('app.blizzard/native-tab-bar/$id'),
          (call) async {
            if (call.method == 'update') onUpdate(call.arguments);
            return null;
          },
        );
      }
      if (!created.isCompleted) created.complete(id);
    }
    return null;
  });

  Widget buildDock(BuildContext context) {
    final currentTitles = titles?.value ?? ['Home', 'Settings'];
    return BlizzardDock(
      actions: [
        ShellRouteAction(Icons.home_rounded, currentTitles[0]),
        ShellRouteAction(Icons.settings_rounded, currentTitles[1]),
      ],
      selectedIndex: selectedIndex?.value ?? 0,
      onDestinationSelected: onSelected ?? (_) {},
    );
  }

  Widget app() {
    return AnimatedBuilder(
      animation: Listenable.merge([
        if (selectedIndex != null) selectedIndex,
        if (titles != null) titles,
        if (dark != null) dark,
      ]),
      builder: (context, _) => MaterialApp(
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: dark?.value == true ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: EdgeInsets.only(bottom: bottomPadding),
            viewPadding: EdgeInsets.only(bottom: bottomPadding),
          ),
          child: child!,
        ),
        home: Scaffold(bottomNavigationBar: Builder(builder: buildDock)),
      ),
    );
  }

  await tester.pumpWidget(app());
  await tester.pump();
  if (find.byType(UiKitView).evaluate().isEmpty) return -1;
  final viewId = await created.future;
  return viewId;
}

Future<void> _sendNativeCall(WidgetTester tester, MethodChannel channel, MethodCall call) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    channel.name,
    channel.codec.encodeMethodCall(call),
    (_) {},
  );
  await tester.pump();
}
