import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/analytics/analytics_controller.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/gen/translations.g.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ProviderContainer> createContainer(Map<String, Object> initialValues) async {
    SharedPreferences.setMockInitialValues(initialValues);
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWith((ref) => Future.value(preferences))],
    );
    await container.read(sharedPreferencesProvider.future);
    return container;
  }

  test('analytics is disabled by default on a fresh install', () async {
    final container = await createContainer({});
    addTearDown(container.dispose);

    expect(await container.read(analyticsControllerProvider.future), isFalse);
  });

  test('an explicit analytics preference is preserved', () async {
    final container = await createContainer({enableAnalyticsPrefKey: true});
    addTearDown(container.dispose);

    expect(await container.read(analyticsControllerProvider.future), isTrue);
  });

  testWidgets('fresh install follows the system locale', (tester) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale('ru', 'RU');
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
    final container = await createContainer({});
    addTearDown(container.dispose);

    expect(container.read(localePreferencesProvider), AppLocale.ru);
  });
}
