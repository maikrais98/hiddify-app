import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/analytics/analytics_controller.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('telemetry initialization fails open when the SDK rejects its configuration', () async {
    var recovered = false;

    final initialized = await initializeTelemetrySafely(
      initialize: () async => throw const FormatException('malformed DSN'),
      recover: () async => recovered = true,
    );

    expect(initialized, isFalse);
    expect(recovered, isTrue);
  });

  test('telemetry initialization still fails open when SDK cleanup also fails', () async {
    final initialized = await initializeTelemetrySafely(
      initialize: () async => throw const FormatException('malformed DSN'),
      recover: () async => throw StateError('partial SDK cleanup failed'),
    );

    expect(initialized, isFalse);
  });

  test('analytics is opt-in for a fresh installation', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) => preferences)]);
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);

    expect(await container.read(analyticsControllerProvider.future), isFalse);
  });

  test('preserves an explicit analytics opt-in', () async {
    SharedPreferences.setMockInitialValues({enableAnalyticsPrefKey: true});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) => preferences)]);
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);

    expect(await container.read(analyticsControllerProvider.future), isTrue);
  });
}
