import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_system_symbol.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_system_symbol_map.dart';

const _channel = MethodChannel(BlizzardSystemSymbol.channelName);
const _symbolKey = ValueKey('system-symbol');

final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL1WQAAAABJRU5ErkJggg==',
);

Map<String, Object?> _arguments(MethodCall call) => Map<String, Object?>.from(call.arguments as Map);

void _testSymbolWidgets(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    BlizzardSystemSymbol.debugClearCache();
    try {
      await callback(tester);
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
      BlizzardSystemSymbol.debugClearCache();
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Widget _fixture({
  IconData icon = Icons.settings_rounded,
  String semanticLabel = 'Settings',
  double devicePixelRatio = 3,
  Brightness brightness = Brightness.dark,
  bool highContrast = false,
  bool blizzard = true,
  double? size,
  double? weight,
}) => MaterialApp(
  theme: ThemeData.dark().copyWith(
    iconTheme: const IconThemeData(color: Color(0xff8de8c7), size: 27, weight: 500),
    extensions: [BlizzardEligibility(mode: AppThemeMode.dark, applied: blizzard)],
  ),
  home: MediaQuery(
    data: MediaQueryData(
      devicePixelRatio: devicePixelRatio,
      platformBrightness: brightness,
      highContrast: highContrast,
    ),
    child: Center(
      child: BlizzardSystemSymbol(
        key: _symbolKey,
        icon: icon,
        semanticLabel: semanticLabel,
        size: size,
        weight: weight,
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('approved source map remains closed to the 81 reviewed entries', () {
    expect(BlizzardSystemSymbolMap.sourceToSymbol, hasLength(81));
    expect(
      BlizzardSystemSymbolMap.sourceToSymbol,
      containsPair('Material Symbols Rounded:power_settings_new', 'power'),
    );
    expect(
      BlizzardSystemSymbolMap.sourceToSymbol,
      containsPair('Material Symbols Rounded:settings_ethernet', 'cable.connector.horizontal'),
    );
    expect(BlizzardSystemSymbolMap.sourceToSymbol, containsPair('lucide:house', 'house'));
    expect(BlizzardSystemSymbolMap.sourceToSymbol, containsPair('lucide:settings', 'gearshape'));
    expect(BlizzardSystemSymbolMap.symbolFor(Icons.power_settings_new_rounded), 'power');
    expect(BlizzardSystemSymbolMap.symbolFor(Icons.home_outlined), 'house');
    expect(BlizzardSystemSymbolMap.symbolFor(Icons.settings_outlined), 'gearshape');
    expect(BlizzardSystemSymbolMap.symbolFor(Icons.warning_rounded), isNull);
  });

  _testSymbolWidgets('iOS renders and tints one cached glyph for an identical request', (tester) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return _onePixelPng;
    });

    await tester.pumpWidget(_fixture());
    await tester.pumpAndSettle();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'render');
    expect(calls.single.arguments, containsPair('symbol', 'gearshape'));
    expect(calls.single.arguments, containsPair('size', 27.0));
    expect(calls.single.arguments, containsPair('weight', 500.0));
    expect(calls.single.arguments, containsPair('brightness', 'dark'));
    expect(calls.single.arguments, containsPair('highContrast', false));
    expect(calls.single.arguments, containsPair('textDirection', 'ltr'));
    expect(calls.single.arguments, containsPair('pixelRatio', 3.0));

    final image = tester.widget<Image>(find.descendant(of: find.byKey(_symbolKey), matching: find.byType(Image)));
    expect(image.width, 27);
    expect(image.height, 27);
    expect(image.color, const Color(0xff8de8c7));
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);

    await tester.pumpWidget(_fixture());
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
  });

  _testSymbolWidgets('cache key includes size, weight, display trait, and pixel ratio', (tester) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return _onePixelPng;
    });

    await tester.pumpWidget(_fixture());
    await tester.pumpAndSettle();
    await tester.pumpWidget(_fixture(size: 28));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_fixture(size: 28, weight: 600));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_fixture(size: 28, weight: 600, brightness: Brightness.light));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_fixture(size: 28, weight: 600, brightness: Brightness.light, highContrast: true));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _fixture(size: 28, weight: 600, brightness: Brightness.light, highContrast: true, devicePixelRatio: 2),
    );
    await tester.pumpAndSettle();

    expect(calls, hasLength(6));
    expect(calls.map((call) => _arguments(call)['size']), [27.0, 28.0, 28.0, 28.0, 28.0, 28.0]);
    expect(calls.map((call) => _arguments(call)['weight']), [500.0, 500.0, 600.0, 600.0, 600.0, 600.0]);
    expect(calls.map((call) => _arguments(call)['pixelRatio']), [3.0, 3.0, 3.0, 3.0, 3.0, 2.0]);
  });

  _testSymbolWidgets('missing symbol keeps the original icon semantics and geometry', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      (_) async => null,
    );

    await tester.pumpWidget(_fixture(size: 31, semanticLabel: 'Open settings'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('Open settings'), findsOneWidget);
    expect(tester.getSize(find.byKey(_symbolKey)), const Size.square(31));
  });

  _testSymbolWidgets('unavailable bridge keeps the original icon instead of an empty slot', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      (_) => Future<Object?>.error(MissingPluginException('not registered')),
    );

    await tester.pumpWidget(_fixture(semanticLabel: 'Settings fallback'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('Settings fallback'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _testSymbolWidgets('unmapped icons never cross the native channel', (tester) async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (_) async {
      calls += 1;
      return _onePixelPng;
    });

    await tester.pumpWidget(_fixture(icon: Icons.warning_rounded, semanticLabel: 'Warning'));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.byIcon(Icons.warning_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('Warning'), findsOneWidget);
  });

  _testSymbolWidgets('non-iOS platforms keep the original Flutter icon', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (_) async {
      calls += 1;
      return _onePixelPng;
    });

    await tester.pumpWidget(_fixture());
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
  });

  _testSymbolWidgets('legacy iOS theme keeps the original Flutter icon', (tester) async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (_) async {
      calls += 1;
      return _onePixelPng;
    });

    await tester.pumpWidget(_fixture(blizzard: false));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
  });

  _testSymbolWidgets('glyph cache is bounded and evicts the oldest request', (tester) async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (_) async {
      calls += 1;
      return _onePixelPng;
    });

    const cacheLimit = 128;
    for (var index = 0; index <= cacheLimit; index += 1) {
      await tester.pumpWidget(_fixture(size: 20 + index.toDouble()));
      await tester.pumpAndSettle();
    }
    expect(calls, cacheLimit + 1);

    await tester.pumpWidget(_fixture(size: 20));
    await tester.pumpAndSettle();
    expect(calls, cacheLimit + 2);
  });
}
