import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';

void main() {
  final theme = AppTheme(AppThemeMode.system, 'Shabnam').darkTheme(null);

  double contrastRatio(Color foreground, Color background) {
    final foregroundLuminance = foreground.computeLuminance();
    final backgroundLuminance = background.computeLuminance();
    final lighter = foregroundLuminance > backgroundLuminance ? foregroundLuminance : backgroundLuminance;
    final darker = foregroundLuminance > backgroundLuminance ? backgroundLuminance : foregroundLuminance;
    return (lighter + 0.05) / (darker + 0.05);
  }

  test('does not install future light semantics at runtime', () {
    final lightTheme = AppTheme(AppThemeMode.system, 'Shabnam').lightTheme(null);

    expect(lightTheme.extension<NovaThemeData>(), isNull);
  });

  test('builds a dark Woman in Red color scheme independent of dynamic color', () {
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, NovaColors.brandFill);
    expect(theme.colorScheme.secondary, NovaColors.brandFill);
    expect(theme.colorScheme.onPrimary, NovaColors.onAccent);
    expect(theme.colorScheme.surface, NovaColors.surface);
    expect(theme.scaffoldBackgroundColor, NovaColors.voidBackground);
    expect(theme.extension<NovaThemeData>(), NovaThemeData.dark);
  });

  test('themes navigation, grouped content, controls, and overlays', () {
    expect(theme.appBarTheme.backgroundColor, NovaColors.voidBackground);
    expect(theme.cardTheme.color, NovaColors.surface);
    expect(theme.listTileTheme.selectedColor, NovaColors.ritualRed);
    expect(theme.listTileTheme.selectedTileColor, NovaThemeData.dark.accentFill);
    expect(theme.bottomSheetTheme.backgroundColor, NovaColors.elevatedSurface);
    expect(theme.dialogTheme.backgroundColor, NovaColors.elevatedSurface);
    expect(theme.inputDecorationTheme.fillColor, NovaColors.surface);
    expect(theme.progressIndicatorTheme.color, NovaColors.ritualRed);
  });

  testWidgets('filled, tonal, and text actions preserve roles and contrast in every interaction state', (tester) async {
    const primaryKey = ValueKey('primary_action');
    const tonalKey = ValueKey('tonal_action');

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          backgroundColor: NovaColors.elevatedSurface,
          body: Column(
            children: [
              FilledButton(key: primaryKey, onPressed: () {}, child: const Text('Primary')),
              FilledButton.tonal(key: tonalKey, onPressed: () {}, child: const Text('Tonal')),
              TextButton(onPressed: () {}, child: const Text('Text')),
            ],
          ),
        ),
      ),
    );

    final filledOverlay = theme.filledButtonTheme.style!.overlayColor!;
    final textStyle = theme.textButtonTheme.style!;
    const enabledStates = <Set<WidgetState>>[
      {},
      {WidgetState.hovered},
      {WidgetState.focused},
      {WidgetState.pressed},
    ];

    for (final states in enabledStates) {
      final overlay = filledOverlay.resolve(states)!;
      final effectiveFilledBackground = Color.alphaBlend(overlay, theme.colorScheme.primary);
      final effectiveTonalBackground = Color.alphaBlend(overlay, theme.colorScheme.secondaryContainer);
      final textForeground = textStyle.foregroundColor!.resolve(states)!;
      final textOverlay = textStyle.overlayColor!.resolve(states)!;
      final effectiveTextBackground = Color.alphaBlend(textOverlay, NovaColors.elevatedSurface);

      expect(
        contrastRatio(theme.colorScheme.onPrimary, effectiveFilledBackground),
        greaterThanOrEqualTo(4.5),
        reason: 'filled action label must remain readable for $states',
      );
      expect(
        contrastRatio(theme.colorScheme.onSecondaryContainer, effectiveTonalBackground),
        greaterThanOrEqualTo(4.5),
        reason: 'tonal action label must remain readable for $states',
      );
      expect(
        contrastRatio(textForeground, effectiveTextBackground),
        greaterThanOrEqualTo(4.5),
        reason: 'dialog text action must remain readable for $states',
      );
    }

    expect(theme.colorScheme.primary, NovaColors.brandFill);
    expect(theme.colorScheme.onPrimary, NovaColors.onAccent);
    expect(theme.colorScheme.secondaryContainer, isNot(theme.colorScheme.primary));
    final primaryMaterial = tester.widget<Material>(
      find.descendant(of: find.byKey(primaryKey), matching: find.byType(Material)),
    );
    final tonalMaterial = tester.widget<Material>(
      find.descendant(of: find.byKey(tonalKey), matching: find.byType(Material)),
    );
    expect(primaryMaterial.color, NovaColors.brandFill);
    expect(tonalMaterial.color, theme.colorScheme.secondaryContainer);
    expect(DefaultTextStyle.of(tester.element(find.text('Primary'))).style.color, NovaColors.onAccent);
    expect(DefaultTextStyle.of(tester.element(find.text('Tonal'))).style.color, theme.colorScheme.onSecondaryContainer);
    expect(textStyle.foregroundColor!.resolve({}), NovaColors.textAction);
    expect(textStyle.foregroundColor!.resolve({WidgetState.disabled}), isNot(NovaColors.textAction));
  });
}
