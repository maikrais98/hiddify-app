import 'dart:io';

import 'package:dartx/dartx.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_backdrop.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_presentation.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_system_symbol.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:hiddify/features/common/general_pref_tiles.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/widget/blizzard_settings_group.dart';
import 'package:hiddify/features/settings/widget/blizzard_settings_leading.dart';
import 'package:hiddify/features/settings/widget/preference_tile.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface_mobile.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:humanizer/humanizer.dart';

class GeneralPage extends HookConsumerWidget {
  const GeneralPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final isBlizzard =
        BlizzardPresentation.isActive(context) ||
        (Theme.of(context).extension<BlizzardEligibility>()?.applied ?? false);

    final appearance = <Widget>[const LocalePrefTile(), const ThemeModePrefTile()];
    final privacy = <Widget>[
      const EnableAnalyticsPrefTile(),
      SwitchListTile.adaptive(
        title: Text(t.pages.settings.general.autoIpCheck),
        value: ref.watch(Preferences.autoCheckIp),
        secondary: const BlizzardSystemSymbol(icon: Icons.flag_rounded),
        onChanged: ref.read(Preferences.autoCheckIp.notifier).update,
      ),
      if (PlatformUtils.isAndroid) ...[
        SwitchListTile.adaptive(
          title: Text(t.pages.settings.general.dynamicNotification),
          secondary: const BlizzardSystemSymbol(icon: Icons.speed_rounded),
          value: ref.watch(Preferences.dynamicNotification),
          onChanged: ref.read(Preferences.dynamicNotification.notifier).update,
        ),
        SwitchListTile.adaptive(
          title: Text(t.pages.settings.general.hapticFeedback),
          secondary: const BlizzardSystemSymbol(icon: Icons.vibration_rounded),
          value: ref.watch(hapticServiceProvider),
          onChanged: ref.read(hapticServiceProvider.notifier).updatePreference,
        ),
      ],
      if (PlatformUtils.isIOS)
        SwitchListTile.adaptive(
          title: Text(t.pages.settings.general.alwaysOnVpn),
          secondary: const BlizzardSystemSymbol(icon: Icons.vpn_lock_rounded),
          value: ref.watch(Preferences.alwaysOnVpn),
          onChanged: (value) async {
            await ref.read(Preferences.alwaysOnVpn.notifier).update(value);
            await CoreInterfaceMobile.methodChannel.invokeMethod("set_always_on", value);
          },
        ),
      if (PlatformUtils.isDesktop) ...[
        const ClosingPrefTile(),
        SwitchListTile.adaptive(
          title: Text(t.pages.settings.general.autoStart),
          secondary: const BlizzardSystemSymbol(icon: Icons.auto_mode_rounded),
          value: ref.watch(autoStartNotifierProvider).asData!.value,
          onChanged: (value) async => value
              ? await ref.read(autoStartNotifierProvider.notifier).enable()
              : await ref.read(autoStartNotifierProvider.notifier).disable(),
        ),
        SwitchListTile.adaptive(
          title: Text(t.pages.settings.general.silentStart),
          secondary: const BlizzardSystemSymbol(icon: Icons.visibility_off_rounded),
          value: ref.watch(Preferences.silentStart),
          onChanged: ref.read(Preferences.silentStart.notifier).update,
        ),
      ],
      if (PlatformUtils.isAndroid) const BatteryOptimizationWidget(),
    ];
    final memoryLimit = SwitchListTile.adaptive(
      title: Text(t.pages.settings.general.memoryLimit),
      subtitle: Text(t.pages.settings.general.memoryLimitMsg),
      secondary: const BlizzardSystemSymbol(icon: Icons.memory_rounded),
      value: !ref.watch(Preferences.disableMemoryLimit),
      onChanged: (value) async => await ref.read(Preferences.disableMemoryLimit.notifier).update(!value),
    );
    final connection = <Widget>[
      if (!PlatformUtils.isIOS) memoryLimit,
      ValuePreferenceWidget(
        value: ref.watch(ConfigOptions.connectionTestUrl),
        preferences: ref.watch(ConfigOptions.connectionTestUrl.notifier),
        title: t.pages.settings.general.connectionTestUrl,
        icon: Icons.link_rounded,
      ),
      ListTile(
        title: Text(t.pages.settings.general.urlTestInterval),
        subtitle: Text(ref.watch(ConfigOptions.urlTestInterval).toApproximateTime(isRelativeToNow: false)),
        leading: const BlizzardSystemSymbol(icon: Icons.timer_rounded),
        onTap: () async => await ref
            .read(dialogNotifierProvider.notifier)
            .showSettingSlider(
              title: t.pages.settings.general.urlTestInterval,
              initialValue: ref.watch(ConfigOptions.urlTestInterval).inMinutes.coerceIn(0, 60).toDouble(),
              onReset: ref.read(ConfigOptions.urlTestInterval.notifier).reset,
              min: 1,
              max: 60,
              divisions: 60,
              labelGen: (value) => Duration(minutes: value.toInt()).toApproximateTime(isRelativeToNow: false),
            )
            .then((value) async {
              if (value == null) return;
              await ref.read(ConfigOptions.urlTestInterval.notifier).update(Duration(minutes: value.toInt()));
            }),
      ),
      // how a speed test of the proxy list runs: download or upload, how much, how many proxies
      ListTile(
        title: Text(t.pages.settings.general.speedTest),
        subtitle: Text(
          [
            switch (ref.watch(ConfigOptions.speedTestDirection)) {
              SpeedTestDirection.download => t.pages.proxies.speedTest.download,
              SpeedTestDirection.upload => t.pages.proxies.speedTest.upload,
              SpeedTestDirection.both => t.pages.proxies.speedTest.both,
            },
            t.pages.settings.general.megabytes(n: ref.watch(ConfigOptions.uploadTestSize)),
            if (ref.watch(ConfigOptions.uploadTestLimit) case final limit when limit > 0)
              t.pages.proxies.speedTest.fastest(n: limit)
            else
              t.pages.proxies.speedTest.all,
          ].join(' · '),
        ),
        leading: const BlizzardSystemSymbol(icon: Icons.speed_rounded),
        onTap: () => ref.read(dialogNotifierProvider.notifier).showSpeedTest(start: false),
      ),
      ValuePreferenceWidget(
        value: ref.watch(ConfigOptions.clashApiPort),
        preferences: ref.watch(ConfigOptions.clashApiPort.notifier),
        title: t.pages.settings.general.clashApiPort,
        icon: Icons.api_rounded,
        validateInput: isPort,
        digitsOnly: true,
        inputToValue: int.tryParse,
      ),
      if (Platform.isMacOS || Platform.isIOS || Platform.isWindows)
        SwitchListTile.adaptive(
          title: Text(t.pages.settings.general.useSystemTlsEngine),
          subtitle: Text(t.pages.settings.general.useSystemTlsEngineMsg),
          secondary: const BlizzardSystemSymbol(icon: Icons.verified_user_rounded),
          value: ref.watch(ConfigOptions.useSystemTlsEngine),
          onChanged: ref.read(ConfigOptions.useSystemTlsEngine.notifier).update,
        ),
    ];

    return BlizzardPresentation(
      child: BlizzardBackdrop(
        child: Scaffold(
          backgroundColor: isBlizzard ? Colors.transparent : null,
          appBar: AppBar(leading: blizzardSettingsLeading(context), title: Text(t.pages.settings.general.title)),
          body: ListView(
            padding: isBlizzard ? EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.paddingOf(context).bottom) : null,
            children: isBlizzard
                ? [
                    BlizzardSettingsGroup(
                      groupKey: const ValueKey('general-settings-group-appearance'),
                      title: t.$meta.locale == AppLocale.ru ? 'Оформление' : 'Appearance',
                      children: appearance,
                    ),
                    const Gap(20),
                    BlizzardSettingsGroup(
                      groupKey: const ValueKey('general-settings-group-privacy'),
                      title: t.$meta.locale == AppLocale.ru ? 'Приватность' : 'Privacy',
                      children: privacy,
                    ),
                    const Gap(20),
                    BlizzardSettingsGroup(
                      groupKey: const ValueKey('general-settings-group-connection'),
                      title: t.$meta.locale == AppLocale.ru ? 'Подключение' : 'Connection',
                      children: connection,
                    ),
                  ]
                : [...appearance, ...privacy, ...connection],
          ),
        ),
      ),
    );
  }
}
