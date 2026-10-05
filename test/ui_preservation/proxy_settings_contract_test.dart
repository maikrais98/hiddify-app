import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/dialog/widgets/proxy_info_dialog.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/data/proxy_repository.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/widget/proxy_tile.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/profile_settings_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final sort in ProxiesSort.values) {
    test('real proxy notifier/repository sorts ${sort.name} and forwards selection/delay', () async {
      SharedPreferences.setMockInitialValues({'haptic_feedback': false, 'proxies_sort_mode': sort.name});
      final prefs = await SharedPreferences.getInstance();
      final core = FixtureCore()
        ..group = OutboundGroup(
          tag: 'group',
          items: [
            OutboundInfo(tag: 'z', urlTestDelay: 100),
            OutboundInfo(tag: 'a', urlTestDelay: 200),
          ],
        );
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => Future.value(prefs)),
          serviceRunningProvider.overrideWith((ref) => true),
          proxyRepositoryProvider.overrideWith((ref) => ProxyRepositoryImpl(singbox: core, client: FixtureHttp())),
        ],
      );
      addTearDown(c.dispose);
      await c.read(sharedPreferencesProvider.future);
      final keep = c.listen(proxiesOverviewNotifierProvider, (_, _) {});
      addTearDown(keep.close);
      final group = await c.read(proxiesOverviewNotifierProvider.future);
      expect(group!.items.map((e) => e.tag), sort == ProxiesSort.name ? ['a', 'z'] : ['z', 'a']);
      await c.read(proxiesOverviewNotifierProvider.notifier).changeProxy('group', 'a');
      expect(core.selections, [('group', 'a')]);
      expect(c.read(proxiesOverviewNotifierProvider).requireValue!.selected, 'a');
      await c.read(proxiesOverviewNotifierProvider.notifier).urlTest('group');
      expect(core.delayTests, ['group']);
      await c.read(proxiesSortNotifierProvider.notifier).update(ProxiesSort.name);
      expect(prefs.getString('proxies_sort_mode'), 'name');
    });
  }
  test('theme, locale and haptic real setters preserve explicit values across fresh containers', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    Future<ProviderContainer> fresh() async {
      final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) => prefs)]);
      await c.read(sharedPreferencesProvider.future);
      return c;
    }

    var c = await fresh();
    expect(c.read(themePreferencesProvider), AppThemeMode.system);
    expect(c.read(hapticServiceProvider), true);
    for (final mode in AppThemeMode.values) {
      await c.read(themePreferencesProvider.notifier).changeThemeMode(mode);
      expect(prefs.getString('theme_mode'), mode.name);
      c.dispose();
      c = await fresh();
      expect(c.read(themePreferencesProvider), mode);
    }
    await c.read(localePreferencesProvider.notifier).changeLocale(AppLocale.ru);
    await c.read(hapticServiceProvider.notifier).updatePreference(false);
    c.dispose();
    c = await fresh();
    expect(c.read(localePreferencesProvider), AppLocale.ru);
    expect(prefs.getString('locale'), 'ru');
    expect(c.read(hapticServiceProvider), false);
    expect(prefs.getBool('haptic_feedback'), false);
    await c.read(localePreferencesProvider.notifier).changeLocale(AppLocale.en);
    await c.read(themePreferencesProvider.notifier).changeThemeMode(AppThemeMode.system);
    expect(prefs.getString('locale'), 'en');
    expect(prefs.getString('theme_mode'), 'system');
    c.dispose();
  });
  final cases = <(ProviderListenable<PreferencesNotifier<Object?, Object?>>, String, Object)>[
    (Preferences.autoCheckIp.notifier, 'auto_check_ip', true),
    (Preferences.dynamicNotification.notifier, 'dynamic_notification', true),
    (Preferences.silentStart.notifier, 'silent_start', false),
    (Preferences.disableMemoryLimit.notifier, 'disable_memory_limit', true),
    (Preferences.actionAtClose.notifier, 'action_at_close', 'ask'),
    (Preferences.perAppProxyMode.notifier, 'per_app_proxy_mode', 'off'),
    (Preferences.autoAppsSelectionRegion.notifier, 'auto_apps_selection_region', ''),
    (ConfigOptions.serviceMode.notifier, 'service-mode', 'system-proxy'),
    (ConfigOptions.balancerStrategy.notifier, 'balancer-strategy', 'round-robin'),
    (ConfigOptions.region.notifier, 'region', 'other'),
    (ConfigOptions.useXrayCoreWhenPossible.notifier, 'use-xray-core-when-possible', false),
    (ConfigOptions.blockAds.notifier, 'block-ads', false),
    (ConfigOptions.logLevel.notifier, 'log-level', 'warn'),
    (ConfigOptions.resolveDestination.notifier, 'resolve-destination', false),
    (ConfigOptions.ipv6Mode.notifier, 'ipv6-mode', 'ipv4_only'),
    (ConfigOptions.remoteDnsAddress.notifier, 'remote-dns-address', "tcp://8.8.8.8"),
    (ConfigOptions.remoteDnsDomainStrategy.notifier, 'remote-dns-domain-strategy', ''),
    (ConfigOptions.directDnsAddress.notifier, 'direct-dns-address', '1.1.1.1'),
    (ConfigOptions.directDnsDomainStrategy.notifier, 'direct-dns-domain-strategy', ''),
    (ConfigOptions.mixedPort.notifier, 'mixed-port', 12334),
    (ConfigOptions.tproxyPort.notifier, 'tproxy-port', 12335),
    (ConfigOptions.redirectPort.notifier, 'redirect-port', 12336),
    (ConfigOptions.directPort.notifier, 'direct-port', 12337),
    (ConfigOptions.tunImplementation.notifier, 'tun-implementation', 'gvisor'),
    (ConfigOptions.mtu.notifier, 'mtu', 9000),
    (ConfigOptions.strictRoute.notifier, 'strict-route', true),
    (ConfigOptions.connectionTestUrl.notifier, 'connection-test-url', "http://captive.apple.com/hotspot-detect.html"),
    (ConfigOptions.urlTestInterval.notifier, 'url-test-interval', 600),
    (ConfigOptions.enableClashApi.notifier, 'enable-clash-api', true),
    (ConfigOptions.clashApiPort.notifier, 'clash-api-port', 16756),
    (ConfigOptions.bypassLan.notifier, 'bypass-lan', false),
    (ConfigOptions.allowConnectionFromLan.notifier, 'allow-connection-from-lan', false),
    (ConfigOptions.enableFakeDns.notifier, 'enable-fake-dns', false),
    (ConfigOptions.independentDnsCache.notifier, 'independent-dns-cache', true),
    (ConfigOptions.enableTlsFragment.notifier, 'enable-tls-fragment', false),
    (ConfigOptions.fragmentPackets.notifier, 'fragment-packets', "tlshello"),
    (ConfigOptions.tlsFragmentSize.notifier, 'tls-fragment-size', '10-30'),
    (ConfigOptions.tlsFragmentSleep.notifier, 'tls-fragment-sleep', '2-8'),
    (ConfigOptions.enableTlsMixedSniCase.notifier, 'enable-tls-mixed-sni-case', false),
    (ConfigOptions.enableTlsPadding.notifier, 'enable-tls-padding', false),
    (ConfigOptions.tlsPaddingSize.notifier, 'tls-padding-size', '1-1500'),
    (ConfigOptions.enableMux.notifier, 'enable-mux', false),
    (ConfigOptions.muxPadding.notifier, 'mux-padding', false),
    (ConfigOptions.muxMaxStreams.notifier, 'mux-max-streams', 8),
    (ConfigOptions.muxProtocol.notifier, 'mux-protocol', 'h2mux'),
    (ConfigOptions.enableWarp.notifier, 'enable-warp', false),
    (ConfigOptions.warpDetourMode.notifier, 'warp-detour-mode', 'warpOverProxy'),
    (ConfigOptions.warpLicenseKey.notifier, 'warp-license-key', ""),
    (ConfigOptions.warp2LicenseKey.notifier, 'warp2s-license-key', ""),
    (ConfigOptions.warpAccountId.notifier, 'warp-account-id', ""),
    (ConfigOptions.warp2AccountId.notifier, 'warp2-account-id', ""),
    (ConfigOptions.warpAccessToken.notifier, 'warp-access-token', ""),
    (ConfigOptions.warp2AccessToken.notifier, 'warp2-access-token', ""),
    (ConfigOptions.warpCleanIp.notifier, 'warp-clean-ip', "auto"),
    (ConfigOptions.warpPort.notifier, 'warp-port', 0),
    (ConfigOptions.warpNoise.notifier, 'warp-noise', '1-3'),
    (ConfigOptions.warpNoiseMode.notifier, 'warp-noise-mode', "m4"),
    (ConfigOptions.warpNoiseDelay.notifier, 'warp-noise-delay', '10-30'),
    (ConfigOptions.warpNoiseSize.notifier, 'warp-noise-size', '10-30'),
    (ConfigOptions.warpWireguardConfig.notifier, 'warp-wireguard-config', ""),
    (ConfigOptions.warp2WireguardConfig.notifier, 'warp2-wireguard-config', ""),
  ];
  for (final (provider, key, expectedDefault) in cases) {
    test('setting $key default/raw write/fresh container/reset', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      Future<ProviderContainer> fresh() async {
        final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) => Future.value(prefs))]);
        await c.read(sharedPreferencesProvider.future);
        return c;
      }

      var c = await fresh();
      var notifier = c.read(provider);
      expect(notifier.entry.key, key);
      expect(notifier.raw(), expectedDefault);
      final alternatives = <String, Object>{
        'action_at_close': 'hide',
        'per_app_proxy_mode': 'include',
        'auto_apps_selection_region': 'cn',
        'service-mode': 'proxy',
        'balancer-strategy': 'consistent-hashing',
        'region': 'cn',
        'log-level': 'debug',
        'ipv6-mode': 'prefer_ipv6',
        'remote-dns-domain-strategy': 'prefer_ipv6',
        'direct-dns-domain-strategy': 'prefer_ipv6',
        'tun-implementation': 'system',
        'mux-protocol': 'smux',
        'warp-detour-mode': 'proxyOverWarp',
        'tls-fragment-size': '20-40',
        'tls-fragment-sleep': '3-9',
        'tls-padding-size': '2-1400',
        'warp-noise': '2-4',
        'warp-noise-size': '20-40',
        'warp-noise-delay': '20-40',
        'connection-test-url': 'https://example.invalid/test',
      };
      final Object changed =
          alternatives[key] ??
          (expectedDefault is bool
              ? !expectedDefault
              : expectedDefault is int
              ? expectedDefault + 1
              : '$expectedDefault-fixture');
      await notifier.updateRaw(changed);
      expect(prefs.get(key), changed);
      c.dispose();
      c = await fresh();
      notifier = c.read(provider);
      expect(notifier.raw(), changed);
      await notifier.reset();
      expect(prefs.containsKey(key), false);
      expect(c.read(provider).raw(), expectedDefault);
      c.dispose();
    });
  }
  test('WARP controls retain dependent enablement source contract', () {
    final source = File('lib/features/settings/overview/sections/warp_options_page.dart').readAsStringSync();
    for (final name in [
      'warpDetourMode',
      'warpLicenseKey',
      'warpCleanIp',
      'warpPort',
      'warpNoise',
      'warpNoiseMode',
      'warpNoiseSize',
      'warpNoiseDelay',
    ]) {
      expect(
        RegExp('preferences: ref.watch\\(ConfigOptions.$name.notifier\\),\\s*enabled: isWarpEnabled').hasMatch(source),
        true,
        reason: name,
      );
    }
    expect(source, contains('enabled: isWarpEnabled && !warpOptions.isLoading'));
  });
  for (final delay in [0, 150, 65001]) {
    testWidgets('actual proxy tile selected/callback/delay $delay', (tester) async {
      var taps = 0;
      final proxy = OutboundInfo(tag: 'synthetic', tagDisplay: 'Fixture proxy', type: 'vless', urlTestDelay: delay);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [translationsProvider.overrideWith((ref) => AppLocale.en.buildSync())],
          child: MaterialApp(
            navigatorKey: rootNavKey,
            home: Scaffold(body: ProxyTile(proxy, selected: true, onTap: () => taps++)),
          ),
        ),
      );
      expect(tester.widget<ListTile>(find.byType(ListTile)).selected, true);
      expect(find.text('Fixture proxy'), findsOneWidget);
      if (delay != 0) expect(find.text(delay > 65000 ? '×' : '$delay'), findsOneWidget);
      await tester.tap(find.byType(ListTile));
      expect(taps, 1);
      await tester.longPress(find.byType(ListTile));
      await tester.pumpAndSettle();
      expect(find.byType(ProxyInfoDialog), findsOneWidget);
      expect(tester.widget<ProxyInfoDialog>(find.byType(ProxyInfoDialog)).outboundInfo, same(proxy));
    });
  }
}
