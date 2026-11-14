import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';

void main() {
  test('Aurora presents dark content without changing the stored appearance choice', () {
    for (final mode in AppThemeMode.values) {
      final base = ThemeData.light().copyWith(extensions: [BlizzardEligibility(mode: mode)]);
      final aurora = BlizzardTheme.from(base);

      expect(aurora.brightness, Brightness.dark);
      expect(aurora.colorScheme.brightness, Brightness.dark);
      expect(aurora.extension<BlizzardEligibility>()?.mode, mode);
      expect(aurora.extension<BlizzardEligibility>()?.applied, isTrue);
      expect(base.brightness, Brightness.light);
      expect(base.extension<BlizzardEligibility>()?.applied, isFalse);
    }
  });
}
