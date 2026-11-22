import 'package:flutter/material.dart';

/// Aurora v2.3 semantic colors shared by the app and its design library.
abstract final class BlizzardPalette {
  static const background = Color(0xFF07121F);
  static const surface = Color(0xFF10232F);
  static const elevated = Color(0xFF1C1F23);
  static const selected = Color(0xFF262A2F);
  static const primary = Color(0xFFF2F6F5);
  static const secondary = Color(0xFFB5C4CC);
  static const muted = Color(0xFF91A5AE);
  static const disabled = Color(0xFF748A94);
  static const accent = Color(0xFF8DDED8);
  static const border = Color(0xFF567382);
  static const separator = Color.fromRGBO(242, 246, 245, 0.12);
  static const accentPressed = Color(0xFF7AC1BE);
  static const controlPressed = Color(0xFF30353B);
  static const trackOff = Color.fromRGBO(242, 246, 245, 0.16);
  static const thumb = Color(0xFFFFFFFF);
  static const selection = Color.fromRGBO(141, 222, 216, 0.24);
  static const pressOverlay = Color.fromRGBO(141, 222, 216, 0.08);
  static const error = Color(0xFFF1A6A0);
  static const warning = Color(0xFFEAC586);
  static const auroraJade = Color(0xFF8DE0B5);
  static const auroraTeal = Color(0xFF60CFC5);
  static const auroraLilac = Color(0xFFB6A2E8);
  // Text-bearing content keeps contrast even over the brightest scene pixels.
  // v2.4: text plates are neutral (no blue cast) and let the dimmed scene through.
  static const plate = Color(0x660B0B0C);
  // Cards on Home sit over the undimmed scene, so they carry most of the dimming themselves.
  static const plateOnScene = Color(0xCC0B0B0C);
  // Sheets float over arbitrary screens, so they stay opaque (and neutral).
  static const sheet = Color(0xFF111214);
  static const contentGlass = Color(0xCC10232F);
  static const glass = Color(0x1817313E);
  static const glassHighlight = Color(0x2EF2F6F5);
  static const glassEdge = Color(0xB3C8F1ED);
  static const glassShade = Color(0x2907151D);
  static const scrim = Color(0x80000000);
  static const shadow = Color(0x40000000);
  static const glow = Color(0x338DDED8);
  static const connectionGlass = Color(0x6617313E);
  static const connectionHighlight = Color(0x388DDED8);
  static const connectionHalo = Color(0x148DDED8);
  static const controlEdgeAccent = Color.fromRGBO(141, 222, 216, 0.08);
  static const controlEdgeFade = Color.fromRGBO(200, 241, 237, 0.336);
  static const lensEdgeStart = Color.fromRGBO(141, 222, 216, 0.36);
  static const lensEdgeMiddle = Color.fromRGBO(242, 246, 245, 0.13);
  static const lensEdgeClear = Color.fromRGBO(141, 222, 216, 0.07);
  static const lensEdgeEnd = Color.fromRGBO(242, 246, 245, 0.2);
  static const nativeEdgeStart = Color.fromRGBO(242, 246, 245, 0.48);
  static const nativeEdgeEnd = Color.fromRGBO(242, 246, 245, 0.18);
  static const innerEdgeStart = Color.fromRGBO(242, 246, 245, 0.34);
  static const innerEdgeClear = Color.fromRGBO(242, 246, 245, 0);
  static const innerEdgeAccent = Color.fromRGBO(141, 222, 216, 0.24);
}

/// v2.4 backdrop: the scene keeps most of its light in the title zone ([dimTop]
/// of [BlizzardPalette.background] over it) and a static gradient (the scene's own
/// drift is untouched) takes it to [dimAlpha] by [dimEnd]. Offsets are logical
/// pixels below the safe area's top edge. the contrast script (contrast_v24.py) reads these values.
abstract final class BlizzardBackdropMetrics {
  /// Dim opacity [y] logical pixels from the top for a safe area of [safeTop].
  static double dimAt(double y, double safeTop) {
    final t = ((y - safeTop - dimStart) / (dimEnd - dimStart)).clamp(0.0, 1.0);
    return dimTop + (dimAlpha - dimTop) * t * t * (3 - 2 * t);
  }

  static const dimStart = 16.0;
  static const dimEnd = 72.0;
  static const dimTop = 0.40;
  static const dimAlpha = 0.80;
}

abstract final class BlizzardRadii {
  static const control = 12.0;
  static const field = control;
  static const row = 12.0;
  static const card = 20.0;
  static const sheet = 24.0;
  static const dialog = 24.0;
  static const tab = pill;
  static const dock = pill;
  static const connection = pill;
  static const pill = 999.0;
}

abstract final class BlizzardSpacing {
  static const s4 = 4.0;
  static const s8 = 8.0;
  static const s12 = 12.0;
  static const s16 = 16.0;
  static const s20 = 20.0;
  static const s24 = 24.0;
  static const s32 = 32.0;
}

abstract final class BlizzardTypeScale {
  static const status = 28.0;
  static const statusLine = 34.0;
  static const title = 22.0;
  static const titleLine = 28.0;
  static const body = 17.0;
  static const bodyLine = 22.0;
  static const subhead = 15.0;
  static const subheadLine = 20.0;
  static const label = 13.0;
  static const labelLine = 18.0;
}

abstract final class BlizzardMetrics {
  static const minimumTarget = 44.0;
  static const toolbarButton = 48.0;
  static const rowMinHeight = 52.0;
  static const fieldMinHeight = 52.0;
  static const primaryButtonHeight = 48.0;
  static const cardMinHeight = 84.0;
  static const quickSettingsMinHeight = 526.0;
  static const profilesSheetMinHeight = 386.0;
  static const addProfileMinHeight = 568.0;
  static const screenMargin = BlizzardSpacing.s20;
  static const hairline = 1.0;
  static const switchInset = 2.0;
  static const dockInset = 6.0;
  static const dockWidth = 320.0;
  static const dockHeight = 64.0;
  static const dockTabWidth = 152.0;
  static const dockTabHeight = 52.0;
  static const connectionButton = 148.0;
  static const connectionStatusHeight = 98.0;
  static const connectionControlInset = 23.0;
  static const connectionLabelGap = 16.0;
  static const waveSize = Size(353, 260);
  static const waveDuration = Duration(seconds: 12);
  static const waveTopFromStatus = 76.0;
  static const controlTopFromStatus = 116.0;
}

/// Optical controls transmit the scene; content surfaces remain opaque.
abstract final class BlizzardGlassMetrics {
  static const blur = 1.6;
  static const connectionBlur = 3.5;
  static const lensScale = 1.055;
  static const edgeWidth = 1.0;
  static const lensEdgeWidth = 0.75;
  static const edgeInset = 0.75;
  static const innerEdgeInset = 2.2;
  static const innerEdgeWidth = 0.6;
}

/// Opaque content keeps decoration from reducing readability.
@immutable
class BlizzardMaterials {
  const BlizzardMaterials({this.highContrast = false});
  final bool highContrast;
  Color get content => highContrast ? BlizzardPalette.background : BlizzardPalette.surface;
  // v2.4 list plates and sheets; High Contrast keeps them opaque.
  Color get plate => highContrast ? BlizzardPalette.background : BlizzardPalette.plate;
  Color get plateOnScene => highContrast ? BlizzardPalette.background : BlizzardPalette.plateOnScene;
  Color get sheet => highContrast ? BlizzardPalette.background : BlizzardPalette.sheet;
  Color get control => highContrast ? BlizzardPalette.surface : BlizzardPalette.elevated;
  Color get edge => highContrast ? BlizzardPalette.secondary : BlizzardPalette.border;
  Color get opaqueFallback => BlizzardPalette.background;
}
