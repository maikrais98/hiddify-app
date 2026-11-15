import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';

void main() {
  test('Aurora presents dark content without changing the stored appearance choice', () {
    for (final mode in AppThemeMode.values) {
      final base = ThemeData.light().copyWith(extensions: [BlizzardEligibility(mode: mode)]);
      final aurora = BlizzardTheme.from(base);

      expect(aurora.brightness, Brightness.dark);
      expect(aurora.colorScheme.brightness, Brightness.dark);
      expect(aurora.iconTheme.color, BlizzardPalette.primary);
      expect(aurora.primaryIconTheme.color, BlizzardPalette.primary);
      expect(aurora.extension<BlizzardEligibility>()?.mode, mode);
      expect(aurora.extension<BlizzardEligibility>()?.applied, isTrue);
      expect(base.brightness, Brightness.light);
      expect(base.extension<BlizzardEligibility>()?.applied, isFalse);
    }
  });
}
