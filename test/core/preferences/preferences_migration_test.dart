import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_migration.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a malformed migration key does not remove unrelated preferences', () async {
    SharedPreferences.setMockInitialValues({
      'service-mode': true,
      'intro_completed': true,
      'per_app_proxy_include_list': 'com.example.included',
      'per_app_proxy_exclude_list': 'com.example.excluded',
      'silent_start': true,
      'started_by_user': true,
      'warp-consent-given': true,
      'psiphon-consent-given': true,
    });
    final preferences = await SharedPreferences.getInstance();
    final migration = PreferencesMigration(sharedPreferences: preferences);

    await migration.migrate();

    expect(preferences.get('service-mode'), isNull);
    expect(preferences.getBool('intro_completed'), isTrue);
    expect(preferences.getString('per_app_proxy_include_list'), 'com.example.included');
    expect(preferences.getString('per_app_proxy_exclude_list'), 'com.example.excluded');
    expect(preferences.getBool('silent_start'), isTrue);
    expect(preferences.getBool('started_by_user'), isTrue);
    expect(preferences.getBool('warp-consent-given'), isTrue);
    expect(preferences.getBool('psiphon-consent-given'), isTrue);
    expect(preferences.getInt(PreferencesMigration.versionKey), 1);

    final valuesAfterFirstMigration = {for (final key in preferences.getKeys()) key: preferences.get(key)};
    await migration.migrate();
    expect({for (final key in preferences.getKeys()) key: preferences.get(key)}, valuesAfterFirstMigration);
  });

  test('a malformed migration version is recovered without removing preferences', () async {
    SharedPreferences.setMockInitialValues({PreferencesMigration.versionKey: 'invalid', 'intro_completed': true});
    final preferences = await SharedPreferences.getInstance();
    final migration = PreferencesMigration(sharedPreferences: preferences);

    await migration.migrate();

    expect(preferences.getInt(PreferencesMigration.versionKey), 1);
    expect(preferences.getBool('intro_completed'), isTrue);

    await migration.migrate();
    expect(preferences.getInt(PreferencesMigration.versionKey), 1);
    expect(preferences.getBool('intro_completed'), isTrue);
  });

  test('a negative migration version is recovered without removing preferences', () async {
    SharedPreferences.setMockInitialValues({PreferencesMigration.versionKey: -1, 'intro_completed': true});
    final preferences = await SharedPreferences.getInstance();
    final migration = PreferencesMigration(sharedPreferences: preferences);

    await migration.migrate();

    expect(preferences.getInt(PreferencesMigration.versionKey), 1);
    expect(preferences.getBool('intro_completed'), isTrue);

    await migration.migrate();
    expect(preferences.getInt(PreferencesMigration.versionKey), 1);
    expect(preferences.getBool('intro_completed'), isTrue);
  });
}
