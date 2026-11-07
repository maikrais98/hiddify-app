import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_migration.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoRules extends RulesNotifier {
  @override
  List<Rule> build() => [];
}

Map<String, dynamic> section(Map<String, dynamic> json, String key) => json[key] as Map<String, dynamic>;

Map<String, dynamic> warp(Map<String, dynamic> json, String hop) => section(section(json, hop), 'warp');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> migrate(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues({'preferences_version': 1, ...values});
    final prefs = await SharedPreferences.getInstance();
    await PreferencesMigration(sharedPreferences: prefs).migrate();
    return prefs;
  }

  Future<Map<String, dynamic>> emitted(SharedPreferences prefs) async {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => prefs),
        rulesNotifierProvider.overrideWith(_NoRules.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);
    return container.read(ConfigOptions.singboxConfigOptions).toJson();
  }

  for (final detour in [null, 'warpOverProxy', 'proxyOverWarp']) {
    test('legacy enabled WARP $detour reaches the official chain', () async {
      final prefs = await migrate({
        'enable-warp': true,
        if (detour != null) 'warp-detour-mode': detour,
        'warp-license-key': 'synthetic-license',
        'warp-clean-ip': '192.0.2.1',
        'warp-port': 2408,
        'warp-noise': '2-4',
        'warp-noise-mode': 'm4',
        'warp-noise-size': '20-40',
        'warp-noise-delay': '5-10',
      });
      final json = await emitted(prefs);
      final unblocker = detour == 'proxyOverWarp';
      final hop = unblocker ? 'unblocker' : 'extra-security';
      expect(json['chain-status'], unblocker ? 'unblocker' : 'extra_security');
      expect(section(json, hop)['mode'], 'warp_auto');
      expect(warp(json, hop)['license-key'], 'synthetic-license');
      if (unblocker) {
        expect(warp(json, hop), containsPair('endpoint', 'custom'));
        expect(warp(json, hop), containsPair('clean-ip', '192.0.2.1'));
        expect(warp(json, hop), containsPair('clean-port', 2408));
        for (final field in ['noise', 'noise-mode', 'noise-size', 'noise-delay']) {
          expect(warp(json, hop)[field], prefs.getString('warp-$field'));
        }
      }
      final saved = {for (final key in prefs.getKeys()) key: prefs.get(key)};
      await PreferencesMigration(sharedPreferences: prefs).migrate();
      expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, saved);
      await prefs.setInt('preferences_version', 4);
      await PreferencesMigration(sharedPreferences: prefs).migrate();
      expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, saved);
      expect(await emitted(prefs), json);
      expect(prefs.getInt('preferences_version'), 5);
    });
  }

  for (final enabled in [null, false]) {
    test('absent or disabled legacy WARP ($enabled) remains off', () async {
      final prefs = await migrate({if (enabled != null) 'enable-warp': enabled});
      expect((await emitted(prefs))['chain-status'], 'off');
      expect(prefs.containsKey('chain-status'), false);
    });
  }

  for (final status in ['off', 'extraSecurity', 'unblocker']) {
    test('existing modern chain $status wins', () async {
      final prefs = await migrate({
        'enable-warp': true,
        'chain-status': status,
        'extra-security-mode': 'psiphon',
        'extra-security-warp-license-key': '',
      });
      final json = await emitted(prefs);
      expect(json['chain-status'], status == 'extraSecurity' ? 'extra_security' : status);
      expect(section(json, 'extra-security')['mode'], 'psiphon');
      expect(warp(json, 'extra-security')['license-key'], '');
    });
  }

  test('modern endpoint and clean IP win over legacy endpoint', () async {
    final prefs = await migrate({
      'enable-warp': true,
      'warp-detour-mode': 'proxyOverWarp',
      'warp-clean-ip': '192.0.2.1',
      'unblocker-warp-endpoint': 'profile',
      'unblocker-warp-clean-ip': '192.0.2.2',
    });
    final json = await emitted(prefs);
    expect(warp(json, 'unblocker')['endpoint'], 'profile');
    expect(warp(json, 'unblocker')['clean-ip'], '192.0.2.2');
  });

  test('modern selected-hop fields win and automatic endpoint is translated', () async {
    final prefs = await migrate({
      'enable-warp': true,
      'warp-detour-mode': 'proxyOverWarp',
      'warp-license-key': 'synthetic-old',
      'warp-clean-ip': 'auto',
      'warp-port': 2408,
      'unblocker-mode': 'psiphon',
      'unblocker-warp-license-key': '',
      'unblocker-warp-port': 500,
    });
    final json = await emitted(prefs);
    expect(section(json, 'unblocker')['mode'], 'psiphon');
    expect(warp(json, 'unblocker')['license-key'], '');
    expect(warp(json, 'unblocker')['clean-port'], 500);
    expect(warp(json, 'unblocker')['endpoint'], 'scan');
    expect(warp(json, 'unblocker')['clean-ip'], '');
  });
}
