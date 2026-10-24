import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/analytics/analytics_controller.dart';
import 'package:hiddify/core/logger/logger_controller.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _frozenBoundary =
    '{"version":1,"sources":[{"source":"runner","generation":"0123456789abcdef","sequence":0},{"source":"extension","generation":"fedcba9876543210","sequence":0}]}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('OFF-to-ON persists native baseline requirement across controller restart', () async {
    final temp = await Directory.systemTemp.createTemp('native-consent-test');
    LoggerController.init('${temp.path}/app.log');
    LoggerController.instance.removePrinter('app');
    addTearDown(() => temp.delete(recursive: true));
    SharedPreferences.setMockInitialValues({enableAnalyticsPrefKey: false});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) => preferences)]);
    await container.read(analyticsControllerProvider.future);
    await container.read(analyticsControllerProvider.notifier).enableAnalytics();
    expect(preferences.getBool('native_diagnostic_baseline_pending_v1'), isTrue);
    expect(preferences.getBool(enableAnalyticsPrefKey), isTrue);
    container.dispose();
  });
  for (final invalid in [
    'not-json',
    '{"version":1,"sources":[]}',
    '{"version":1,"sources":[{"source":"runner","generation":"0123456789abcdef","sequence":0}]}',
  ]) {
    test('invalid persisted baseline stays OFF: $invalid', () async {
      SharedPreferences.setMockInitialValues({
        enableAnalyticsPrefKey: true,
        nativeDiagnosticBaselinePendingPrefKey: invalid,
      });
      final preferences = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) => preferences)]);
      expect(await container.read(analyticsControllerProvider.future), isFalse);
      container.dispose();
    });
  }
  test('exact native boundary is durable before enabling after capture', () async {
    SharedPreferences.setMockInitialValues({enableAnalyticsPrefKey: false});
    final store = _ConsentStore({'flutter.$enableAnalyticsPrefKey': false});
    SharedPreferencesStorePlatform.instance = store;
    final preferences = await SharedPreferences.getInstance();
    expect(
      await persistAnalyticsEnableBoundary(
        preferences: preferences,
        captureNativeBaseline: () async {
          expect(store.operations, isEmpty);
          expect((await store.getAll())['flutter.$enableAnalyticsPrefKey'], isFalse);
          return _frozenBoundary;
        },
      ),
      isTrue,
    );
    expect(store.operations, [
      'set:flutter.$nativeDiagnosticBaselinePendingPrefKey',
      'set:flutter.$enableAnalyticsPrefKey',
    ]);
    expect((await store.getAll())['flutter.$nativeDiagnosticBaselinePendingPrefKey'], _frozenBoundary);
  });
  test('failed frozen boundary save never writes enabled consent', () async {
    SharedPreferences.setMockInitialValues({enableAnalyticsPrefKey: false});
    final store = _ConsentStore({'flutter.$enableAnalyticsPrefKey': false})
      ..failedKey = 'flutter.$nativeDiagnosticBaselinePendingPrefKey';
    SharedPreferencesStorePlatform.instance = store;
    final preferences = await SharedPreferences.getInstance();
    expect(
      await persistAnalyticsEnableBoundary(
        preferences: preferences,
        captureNativeBaseline: () async => _frozenBoundary,
      ),
      isFalse,
    );
    expect(store.operations, ['set:flutter.$nativeDiagnosticBaselinePendingPrefKey']);
    expect((await store.getAll())['flutter.$enableAnalyticsPrefKey'], isFalse);
  });
  test('failed disable-marker removal keeps next bootstrap OFF', () async {
    SharedPreferences.setMockInitialValues({enableAnalyticsPrefKey: false, nativeDiagnosticDisabledPrefKey: true});
    final store = _ConsentStore({
      'flutter.$enableAnalyticsPrefKey': false,
      'flutter.$nativeDiagnosticDisabledPrefKey': true,
    })..failedRemove = 'flutter.$nativeDiagnosticDisabledPrefKey';
    SharedPreferencesStorePlatform.instance = store;
    final preferences = await SharedPreferences.getInstance();
    expect(
      await persistAnalyticsEnableBoundary(
        preferences: preferences,
        captureNativeBaseline: () async => _frozenBoundary,
      ),
      isFalse,
    );
    await preferences.reload();
    final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) => preferences)]);
    expect(await container.read(analyticsControllerProvider.future), isFalse);
    container.dispose();
  });

  for (final failedWrite in [enableAnalyticsPrefKey, 'native_diagnostic_disabled_v1']) {
    test('disable survives restart when $failedWrite write fails', () async {
      SharedPreferences.setMockInitialValues({enableAnalyticsPrefKey: true});
      final store = _ConsentStore({'flutter.$enableAnalyticsPrefKey': true})..failedKey = 'flutter.$failedWrite';
      SharedPreferencesStorePlatform.instance = store;
      final preferences = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) => preferences)]);
      expect(await container.read(analyticsControllerProvider.future), isTrue);
      await container.read(analyticsControllerProvider.notifier).disableAnalytics();
      container.dispose();
      await preferences.reload(); // Reload durable values, excluding the optimistic failed-write cache.
      final restarted = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) => preferences)]);
      expect(await restarted.read(analyticsControllerProvider.future), isFalse);
      expect(store.operations.first, 'set:flutter.native_diagnostic_disabled_v1');
      restarted.dispose();
    });
  }
  test('restart with disable marker refuses enabled flag before teardown completion', () async {
    SharedPreferences.setMockInitialValues({enableAnalyticsPrefKey: true, 'native_diagnostic_disabled_v1': true});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) => preferences)]);
    expect(await container.read(analyticsControllerProvider.future), isFalse);
    container.dispose();
  });
  test('complete storage failure is reported after disabling current-process delivery', () async {
    SharedPreferences.setMockInitialValues({enableAnalyticsPrefKey: true});
    final store = _ConsentStore({'flutter.$enableAnalyticsPrefKey': true})..failAll = true;
    SharedPreferencesStorePlatform.instance = store;
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) => preferences)]);
    await container.read(analyticsControllerProvider.future);
    await expectLater(container.read(analyticsControllerProvider.notifier).disableAnalytics(), throwsStateError);
    expect(container.read(analyticsControllerProvider).hasError, isTrue);
    container.dispose();
  });
}

class _ConsentStore extends InMemorySharedPreferencesStore {
  _ConsentStore(super.data) : super.withData();
  String? failedKey;
  String? failedRemove;
  bool failAll = false;
  final operations = <String>[];
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    operations.add('set:$key');
    if (failAll || key == failedKey) return false;
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    operations.add('remove:$key');
    if (failAll || key == failedRemove) return false;
    return super.remove(key);
  }
}
