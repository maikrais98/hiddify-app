import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';

// The verified visual candidate is enabled by default; explicit false preserves the legacy skin.
const blizzardVisuals = bool.fromEnvironment('BLIZZARD_VISUALS', defaultValue: true);

@immutable
class BlizzardEligibility extends ThemeExtension<BlizzardEligibility> {
  const BlizzardEligibility({required this.mode, this.applied = false});
  final AppThemeMode mode;
  final bool applied;
  bool get permitsDark => mode == AppThemeMode.dark || mode == AppThemeMode.system;

  @override
  BlizzardEligibility copyWith({AppThemeMode? mode, bool? applied}) =>
      BlizzardEligibility(mode: mode ?? this.mode, applied: applied ?? this.applied);

  @override
  BlizzardEligibility lerp(covariant BlizzardEligibility? other, double t) => other == null || t < 0.5 ? this : other;
}

/// Creates only local presentation data; never changes the global theme factory.
abstract final class BlizzardTheme {
  static TextStyle? brandStyle(ThemeData theme) => theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w400);

  static ThemeData from(ThemeData base, {bool highContrast = false}) {
    final material = BlizzardMaterials(highContrast: highContrast);
    final persian = base.textTheme.bodyLarge?.fontFamily == 'Shabnam';
    final textFont = persian ? 'Shabnam' : '.SF Pro Text';
    final displayFont = persian ? 'Shabnam' : '.SF Pro Display';
    TextStyle role(double size, double line, {FontWeight weight = FontWeight.w400, bool display = false}) => TextStyle(
      inherit: false,
      textBaseline: TextBaseline.alphabetic,
      fontFamily: display ? displayFont : textFont,
      fontSize: size,
      fontWeight: weight,
      height: line / size,
      color: BlizzardPalette.primary,
    );
    final text = base.textTheme
        .apply(fontFamily: textFont, bodyColor: BlizzardPalette.primary, displayColor: BlizzardPalette.primary)
        .copyWith(
          headlineLarge: role(
            BlizzardTypeScale.status,
            BlizzardTypeScale.statusLine,
            weight: FontWeight.w600,
            display: true,
          ),
          headlineMedium: role(
            BlizzardTypeScale.status,
            BlizzardTypeScale.statusLine,
            weight: FontWeight.w600,
            display: true,
          ),
          headlineSmall: role(
            BlizzardTypeScale.title,
            BlizzardTypeScale.titleLine,
            weight: FontWeight.w600,
            display: true,
          ),
          titleLarge: role(
            BlizzardTypeScale.title,
            BlizzardTypeScale.titleLine,
            weight: FontWeight.w600,
            display: true,
          ),
          titleMedium: role(BlizzardTypeScale.body, BlizzardTypeScale.bodyLine, weight: FontWeight.w600),
          titleSmall: role(BlizzardTypeScale.body, BlizzardTypeScale.bodyLine, weight: FontWeight.w600),
          bodyLarge: role(BlizzardTypeScale.body, BlizzardTypeScale.bodyLine),
          bodyMedium: role(BlizzardTypeScale.body, BlizzardTypeScale.bodyLine),
          bodySmall: role(BlizzardTypeScale.subhead, BlizzardTypeScale.subheadLine),
          labelLarge: role(BlizzardTypeScale.label, BlizzardTypeScale.labelLine, weight: FontWeight.w500),
          labelMedium: role(BlizzardTypeScale.label, BlizzardTypeScale.labelLine, weight: FontWeight.w500),
          labelSmall: role(BlizzardTypeScale.label, BlizzardTypeScale.labelLine, weight: FontWeight.w500),
        );
    final scheme = base.colorScheme.copyWith(
      brightness: Brightness.dark,
      primary: BlizzardPalette.accent,
      onPrimary: BlizzardPalette.background,
      primaryContainer: BlizzardPalette.selected,
      onPrimaryContainer: BlizzardPalette.primary,
      secondary: BlizzardPalette.accent,
      onSecondary: BlizzardPalette.background,
      secondaryContainer: BlizzardPalette.selected,
      onSecondaryContainer: BlizzardPalette.primary,
      tertiary: BlizzardPalette.secondary,
      onTertiary: BlizzardPalette.background,
      surface: material.content,
      onSurface: BlizzardPalette.primary,
      onSurfaceVariant: BlizzardPalette.secondary,
      surfaceContainerLowest: BlizzardPalette.background,
      surfaceContainerLow: material.content,
      surfaceContainer: material.content,
      surfaceContainerHigh: material.control,
      surfaceContainerHighest: material.control,
      surfaceTint: Colors.transparent,
      error: BlizzardPalette.error,
      onError: BlizzardPalette.background,
      errorContainer: material.control,
      onErrorContainer: BlizzardPalette.error,
      outline: material.edge,
      outlineVariant: BlizzardPalette.separator,
      inverseSurface: BlizzardPalette.primary,
      onInverseSurface: BlizzardPalette.background,
      inversePrimary: BlizzardPalette.selected,
      shadow: BlizzardPalette.shadow,
      scrim: BlizzardPalette.scrim,
    );
    RoundedRectangleBorder shape(double radius) => RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    final button = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(
        Size(BlizzardMetrics.minimumTarget, BlizzardMetrics.primaryButtonHeight),
      ),
      shape: WidgetStatePropertyAll(shape(BlizzardRadii.row)),
      textStyle: WidgetStatePropertyAll(text.titleMedium),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: BlizzardSpacing.s16, vertical: BlizzardSpacing.s12),
      ),
    );
    final primaryButton = button.copyWith(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? material.control
            : states.contains(WidgetState.pressed)
            ? BlizzardPalette.accentPressed
            : BlizzardPalette.accent,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? BlizzardPalette.disabled : BlizzardPalette.background,
      ),
    );
    return base.copyWith(
      brightness: Brightness.dark,
      cupertinoOverrideTheme: const CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: BlizzardPalette.accent,
        primaryContrastingColor: BlizzardPalette.background,
      ),
      colorScheme: scheme,
      canvasColor: material.content,
      cardColor: material.content,
      primaryColor: BlizzardPalette.accent,
      scaffoldBackgroundColor: BlizzardPalette.background,
      textTheme: text,
      primaryTextTheme: text,
      iconTheme: base.iconTheme.copyWith(color: BlizzardPalette.primary),
      primaryIconTheme: base.primaryIconTheme.copyWith(color: BlizzardPalette.primary),
      disabledColor: BlizzardPalette.disabled,
      dividerColor: BlizzardPalette.separator,
      dividerTheme: const DividerThemeData(color: BlizzardPalette.separator, thickness: BlizzardMetrics.hairline),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: BlizzardPalette.accent,
        selectionColor: BlizzardPalette.selection,
        selectionHandleColor: BlizzardPalette.accent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(BlizzardPalette.thumb),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? BlizzardPalette.accent : BlizzardPalette.trackOff,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: BlizzardPalette.accent,
        inactiveTrackColor: BlizzardPalette.trackOff,
        thumbColor: BlizzardPalette.accent,
        overlayColor: BlizzardPalette.pressOverlay,
      ),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      extensions: [
        ...base.extensions.values.where((extension) => extension is! BlizzardEligibility),
        if (base.extension<BlizzardEligibility>() case final eligibility?) eligibility.copyWith(applied: true),
      ],
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        foregroundColor: BlizzardPalette.primary,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: material.content,
        surfaceTintColor: Colors.transparent,
        shape: shape(BlizzardRadii.card),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        textColor: BlizzardPalette.primary,
        iconColor: BlizzardPalette.secondary,
        tileColor: material.content,
        selectedTileColor: BlizzardPalette.selected,
        selectedColor: BlizzardPalette.primary,
        minVerticalPadding: BlizzardSpacing.s8,
        minTileHeight: BlizzardMetrics.rowMinHeight,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall?.copyWith(color: BlizzardPalette.secondary),
        shape: shape(BlizzardRadii.row),
      ),
      filledButtonTheme: FilledButtonThemeData(style: primaryButton),
      elevatedButtonTheme: ElevatedButtonThemeData(style: primaryButton),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: button.copyWith(
          side: const WidgetStatePropertyAll(BorderSide(color: BlizzardPalette.separator)),
          foregroundColor: const WidgetStatePropertyAll(BlizzardPalette.primary),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed) ? BlizzardPalette.controlPressed : Colors.transparent,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: button.copyWith(
          minimumSize: const WidgetStatePropertyAll(Size(BlizzardMetrics.minimumTarget, BlizzardMetrics.minimumTarget)),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled) ? BlizzardPalette.disabled : BlizzardPalette.accent,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: button.copyWith(padding: const WidgetStatePropertyAll(EdgeInsets.zero)),
      ),
      searchBarTheme: base.searchBarTheme.copyWith(backgroundColor: WidgetStatePropertyAll(material.control)),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: material.content,
        labelStyle: text.labelLarge?.copyWith(color: BlizzardPalette.secondary),
        floatingLabelStyle: text.labelLarge?.copyWith(color: BlizzardPalette.accent),
        errorStyle: text.bodySmall?.copyWith(color: BlizzardPalette.error),
        hintStyle: text.bodyMedium?.copyWith(color: BlizzardPalette.muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: BlizzardSpacing.s16, vertical: BlizzardSpacing.s12),
        constraints: const BoxConstraints(minHeight: BlizzardMetrics.fieldMinHeight),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BlizzardRadii.field),
          borderSide: BorderSide(color: material.edge),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BlizzardRadii.field),
          borderSide: BorderSide(color: material.edge),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BlizzardRadii.field),
          borderSide: const BorderSide(color: BlizzardPalette.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BlizzardRadii.field),
          borderSide: const BorderSide(color: BlizzardPalette.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BlizzardRadii.field),
          borderSide: const BorderSide(color: BlizzardPalette.error, width: 2),
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: material.content,
        surfaceTintColor: Colors.transparent,
        shape: shape(BlizzardRadii.dialog),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyLarge,
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: material.content,
        modalBackgroundColor: material.content,
        surfaceTintColor: Colors.transparent,
        shape: shape(BlizzardRadii.sheet),
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: material.control,
        surfaceTintColor: Colors.transparent,
        shape: shape(BlizzardRadii.row),
        textStyle: text.bodyMedium,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(material.control),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(shape(BlizzardRadii.row)),
        ),
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        height: BlizzardMetrics.dockHeight,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: BlizzardPalette.selected,
        labelTextStyle: WidgetStatePropertyAll(text.labelSmall),
      ),
    );
  }

  /// Flutter resolves monospace to the platform system fixed-width font.
  /// On iOS this requests the system fallback rather than bundling SF Mono.
  static TextStyle codeStyle(ThemeData theme) => TextStyle(
    fontFamily: 'monospace',
    fontSize: BlizzardTypeScale.label,
    height: BlizzardTypeScale.labelLine / BlizzardTypeScale.label,
    color: theme.colorScheme.onSurface,
  );
}
