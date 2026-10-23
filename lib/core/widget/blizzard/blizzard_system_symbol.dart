import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_system_symbol_map.dart';

/// Renders a reviewed SF Symbol on iOS and preserves the supplied [Icon] as a
/// layout- and semantics-compatible fallback everywhere else.
class BlizzardSystemSymbol extends StatelessWidget {
  const BlizzardSystemSymbol({
    super.key,
    required this.icon,
    this.size,
    this.fill,
    this.weight,
    this.grade,
    this.opticalSize,
    this.color,
    this.shadows,
    this.semanticLabel,
    this.textDirection,
    this.applyTextScaling,
    this.blendMode,
    this.fontWeight,
  });

  static const channelName = 'app.blizzard/system-symbols';
  static const _channel = MethodChannel(channelName);
  static const _cacheLimit = 128;
  static final LinkedHashMap<_GlyphKey, Future<Uint8List?>> _glyphCache = LinkedHashMap();

  final IconData icon;
  final double? size;
  final double? fill;
  final double? weight;
  final double? grade;
  final double? opticalSize;
  final Color? color;
  final List<Shadow>? shadows;
  final String? semanticLabel;
  final TextDirection? textDirection;
  final bool? applyTextScaling;
  final BlendMode? blendMode;
  final FontWeight? fontWeight;

  @visibleForTesting
  static void debugClearCache() => _glyphCache.clear();

  @override
  Widget build(BuildContext context) {
    assert(textDirection != null || debugCheckHasDirectionality(context));
    final fallback = Icon(
      icon,
      size: size,
      fill: fill,
      weight: weight,
      grade: grade,
      opticalSize: opticalSize,
      color: color,
      shadows: shadows,
      semanticLabel: semanticLabel,
      textDirection: textDirection,
      applyTextScaling: applyTextScaling,
      blendMode: blendMode,
      fontWeight: fontWeight,
    );
    final blizzard = Theme.of(context).extension<BlizzardEligibility>()?.applied ?? false;
    if (!blizzard || kIsWeb || defaultTargetPlatform != TargetPlatform.iOS || shadows != null) return fallback;

    final symbol = BlizzardSystemSymbolMap.symbolFor(icon);
    if (symbol == null) return fallback;

    final iconTheme = IconTheme.of(context);
    final shouldScale = applyTextScaling ?? iconTheme.applyTextScaling ?? false;
    final tentativeSize = size ?? iconTheme.size ?? 24;
    final resolvedSize = shouldScale ? MediaQuery.textScalerOf(context).scale(tentativeSize) : tentativeSize;
    final resolvedWeight = weight ?? iconTheme.weight ?? 400;
    final direction = textDirection ?? Directionality.of(context);
    final media = MediaQuery.of(context);
    final key = _GlyphKey(
      symbol: symbol,
      size: resolvedSize,
      weight: resolvedWeight,
      brightness: media.platformBrightness,
      highContrast: media.highContrast,
      textDirection: direction,
      pixelRatio: media.devicePixelRatio,
    );
    final glyph = _glyphFor(key);

    final opacity = iconTheme.opacity ?? 1;
    final baseColor = color ?? iconTheme.color!;
    final resolvedColor = opacity == 1 ? baseColor : baseColor.withValues(alpha: baseColor.a * opacity);

    return FutureBuilder<Uint8List?>(
      future: glyph,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) return fallback;

        Widget image = Image.memory(
          bytes,
          width: resolvedSize,
          height: resolvedSize,
          color: resolvedColor,
          colorBlendMode: blendMode ?? BlendMode.srcIn,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
          excludeFromSemantics: true,
        );
        if (icon.matchTextDirection && direction == TextDirection.rtl) {
          image = Transform(
            transform: Matrix4.identity()..scaleByDouble(-1, 1, 1, 1),
            alignment: Alignment.center,
            transformHitTests: false,
            child: image,
          );
        }
        return Semantics(
          label: semanticLabel,
          child: ExcludeSemantics(
            child: SizedBox.square(
              dimension: resolvedSize,
              child: Center(child: image),
            ),
          ),
        );
      },
    );
  }

  static Future<Uint8List?> _glyphFor(_GlyphKey key) {
    final cached = _glyphCache.remove(key);
    if (cached != null) {
      _glyphCache[key] = cached;
      return cached;
    }
    final glyph = _loadGlyph(key);
    _glyphCache[key] = glyph;
    if (_glyphCache.length > _cacheLimit) _glyphCache.remove(_glyphCache.keys.first);
    return glyph;
  }

  static Future<Uint8List?> _loadGlyph(_GlyphKey key) async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('render', key.toArguments());
      return bytes == null || bytes.isEmpty ? null : bytes;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

@immutable
class _GlyphKey {
  const _GlyphKey({
    required this.symbol,
    required this.size,
    required this.weight,
    required this.brightness,
    required this.highContrast,
    required this.textDirection,
    required this.pixelRatio,
  });

  final String symbol;
  final double size;
  final double weight;
  final Brightness brightness;
  final bool highContrast;
  final TextDirection textDirection;
  final double pixelRatio;

  Map<String, Object> toArguments() => {
    'symbol': symbol,
    'size': size,
    'weight': weight,
    'brightness': brightness.name,
    'highContrast': highContrast,
    'textDirection': textDirection.name,
    'pixelRatio': pixelRatio,
  };

  @override
  bool operator ==(Object other) =>
      other is _GlyphKey &&
      other.symbol == symbol &&
      other.size == size &&
      other.weight == weight &&
      other.brightness == brightness &&
      other.highContrast == highContrast &&
      other.textDirection == textDirection &&
      other.pixelRatio == pixelRatio;

  @override
  int get hashCode => Object.hash(symbol, size, weight, brightness, highContrast, textDirection, pixelRatio);
}
