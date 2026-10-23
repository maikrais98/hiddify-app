import 'package:flutter/material.dart';

/// Approved Blizzard Aurora 0.3 semantic colors. RGBA source tokens use ARGB here.
abstract final class BlizzardPalette {
  static const background = Color(0xFF07151D);
  static const surface = Color(0xFF10232F);
  static const elevated = Color(0xFF17313E);
  static const selected = Color(0xFF17313E);
  static const primary = Color(0xFFF2F6F5);
  static const secondary = Color(0xFFB5C4CC);
  static const muted = Color(0xFF91A5AE);
  static const disabled = Color(0xFF748A94);
  static const accent = Color(0xFF8DDED8);
  static const border = Color(0xFF38525F);
  static const separator = Color(0xFF29424E);
  static const error = Color(0xFFF1A6A0);
  static const warning = Color(0xFFEAC586);
  static const auroraJade = Color(0xFF8DE0B5);
  static const auroraTeal = Color(0xFF60CFC5);
  static const auroraLilac = Color(0xFFB6A2E8);
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
}

abstract final class BlizzardRadii {
  static const field = 8.0;
  static const row = 12.0;
  static const card = 20.0;
  static const sheet = 24.0;
  static const dialog = 24.0;
  static const tab = 26.0;
  static const dock = 32.0;
  static const connection = 44.0;
  static const pill = 999.0;
}

abstract final class BlizzardMetrics {
  static const minimumTarget = 44.0;
  static const dockWidth = 320.0;
  static const dockHeight = 64.0;
  static const dockTabWidth = 152.0;
  static const dockTabHeight = 52.0;
  static const connectionButton = 148.0;
  static const connectionStatusHeight = 98.0;
  static const connectionControlGroupHeight = 210.0;
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
  static const edgeWidth = 1.2;
}

/// Opaque content keeps decoration from reducing readability.
@immutable
class BlizzardMaterials {
  const BlizzardMaterials({this.highContrast = false});
  final bool highContrast;
  Color get content => highContrast ? BlizzardPalette.background : BlizzardPalette.surface;
  Color get control => highContrast ? BlizzardPalette.surface : BlizzardPalette.elevated;
  Color get edge => highContrast ? BlizzardPalette.secondary : BlizzardPalette.border;
  Color get opaqueFallback => BlizzardPalette.background;
}
