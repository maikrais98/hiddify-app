import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_backdrop.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_presentation.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_surface.dart';

// v2.4 backdrop: dimmed scene below the title zone, neutral translucent plates.

Widget _host({bool highContrast = false, required Widget child}) => MaterialApp(
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(highContrast: highContrast, padding: const EdgeInsets.only(top: 62)),
      child: Theme(
        data: BlizzardTheme.from(
          ThemeData(extensions: const <ThemeExtension<dynamic>>[BlizzardEligibility(mode: AppThemeMode.dark)]),
          highContrast: highContrast,
        ),
        child: child,
      ),
    ),
  ),
);

Color _plateColor(WidgetTester tester) {
  final box = tester
      .widgetList<DecoratedBox>(find.descendant(of: find.byType(BlizzardSurface), matching: find.byType(DecoratedBox)))
      .first;
  return (box.decoration as BoxDecoration).color!;
}

bool _neutral(Color c) {
  final r = (c.r * 255).round();
  final g = (c.g * 255).round();
  final b = (c.b * 255).round();
  return (b - r).abs() <= 4 && (g - r).abs() <= 4;
}

void main() {
  setUp(() => BlizzardPresentation.debugAssumeIOS = true);
  tearDown(() => BlizzardPresentation.debugAssumeIOS = false);

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  test('plate and sheet tokens carry no blue cast; the plate is translucent, the sheet opaque', () {
    expect(_neutral(BlizzardPalette.plate), isTrue);
    expect(_neutral(BlizzardPalette.sheet), isTrue);
    expect(BlizzardPalette.plate.a, inInclusiveRange(0.35, 0.5));
    expect(BlizzardPalette.sheet.a, 1);
  });

  test('dim gradient is bright in the title zone and reaches ~80% below it', () {
    const safe = 62.0;
    expect(BlizzardBackdropMetrics.dimAt(0, safe), BlizzardBackdropMetrics.dimTop);
    expect(
      BlizzardBackdropMetrics.dimAt(safe + BlizzardBackdropMetrics.dimStart, safe),
      BlizzardBackdropMetrics.dimTop,
    );
    expect(
      BlizzardBackdropMetrics.dimAt(safe + BlizzardBackdropMetrics.dimEnd, safe),
      BlizzardBackdropMetrics.dimAlpha,
    );
    expect(BlizzardBackdropMetrics.dimAt(900, safe), closeTo(0.8, 1e-9));
    var previous = 0.0;
    for (var y = 0.0; y < 400; y += 4) {
      final dim = BlizzardBackdropMetrics.dimAt(y, safe);
      expect(dim, greaterThanOrEqualTo(previous));
      previous = dim;
    }
  });

  testWidgets('backdrop paints the dim gradient instead of the flat scrim', (tester) async {
    phone(tester);
    await tester.pumpWidget(_host(child: const BlizzardBackdrop(child: SizedBox.expand())));
    final gradients = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => (box.decoration as BoxDecoration).gradient)
        .whereType<LinearGradient>()
        .toList();
    expect(gradients, hasLength(1));
    final colors = gradients.single.colors;
    expect(colors.first.a, closeTo(BlizzardBackdropMetrics.dimTop, 0.01));
    expect(colors.last.a, closeTo(BlizzardBackdropMetrics.dimAlpha, 0.01));
    expect(colors.first.toARGB32() & 0xFFFFFF, BlizzardPalette.background.toARGB32() & 0xFFFFFF);
    expect(find.byWidgetPredicate((w) => w is ColoredBox && w.color == BlizzardPalette.scrim), findsNothing);
  });

  testWidgets('plates are translucent neutral, sheets opaque neutral', (tester) async {
    phone(tester);
    await tester.pumpWidget(_host(child: const BlizzardSurface(child: SizedBox(width: 80, height: 40))));
    expect(_plateColor(tester), BlizzardPalette.plate);
    await tester.pumpWidget(
      _host(
        child: const BlizzardSurface(kind: BlizzardSurfaceKind.sheet, child: SizedBox(width: 80, height: 40)),
      ),
    );
    expect(_plateColor(tester), BlizzardPalette.sheet);
  });

  testWidgets('Increase Contrast gives opaque surfaces and keeps the flat scrim', (tester) async {
    phone(tester);
    for (final kind in BlizzardSurfaceKind.values) {
      await tester.pumpWidget(
        _host(
          highContrast: true,
          child: BlizzardSurface(kind: kind, child: const SizedBox(width: 80, height: 40)),
        ),
      );
      final color = _plateColor(tester);
      expect(color.a, 1, reason: '$kind must be opaque under Increase Contrast');
      expect(color, BlizzardPalette.background);
    }
    await tester.pumpWidget(_host(highContrast: true, child: const BlizzardBackdrop(child: SizedBox.expand())));
    expect(find.byWidgetPredicate((w) => w is ColoredBox && w.color == BlizzardPalette.scrim), findsOneWidget);
  });
}
