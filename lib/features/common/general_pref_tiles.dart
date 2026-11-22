import 'package:flutter/material.dart';
import 'package:hiddify/core/analytics/analytics_controller.dart';
import 'package:hiddify/core/localization/locale_extensions.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_presentation.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_system_symbol.dart';
import 'package:hiddify/features/proxy/active/ip_widget.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class LocalePrefTile extends ConsumerWidget {
  const LocalePrefTile({super.key, this.onChanged});

  /// Called after the user picks a language (not on reset).
  final ValueChanged<AppLocale>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    final locale = ref.watch(localePreferencesProvider);
    return BlizzardPresentation(
      child: ListTile(
        title: Text(t.pages.settings.general.locale),
        subtitle: Text(locale.localeName),
        leading: const BlizzardSystemSymbol(icon: Icons.translate_rounded),
        // Persian wears the lion and sun, as Iran does in the region row below it
        trailing: BlizzardPresentation.isActive(context)
            ? const BlizzardSystemSymbol(icon: Icons.chevron_right_rounded, color: BlizzardPalette.secondary)
            : _localeFlag(locale, size: 40),
        onTap: () async {
          final selectedLocale = await ref
              .read(dialogNotifierProvider.notifier)
              .showSettingPicker<AppLocale>(
                title: t.pages.settings.general.locale,
                selected: locale,
                onReset: () => ref.read(localePreferencesProvider.notifier).changeLocale(AppLocale.en),
                options: _localeOrder,
                getTitle: (e) => e.localeName,
                getSecondary: _localeFlag,
              );
          if (selectedLocale != null) {
            await ref.read(localePreferencesProvider.notifier).changeLocale(selectedLocale);
            onChanged?.call(selectedLocale);
          }
        },
      ),
    );
  }
}

/// English first, Persian second, then the rest as declared.
final _localeOrder = [
  AppLocale.en,
  AppLocale.fa,
  ...AppLocale.values.where((e) => e != AppLocale.en && e != AppLocale.fa),
];

/// The language's flag (Persian's with the lion and sun); none for a language without one.
Widget? _localeFlag(AppLocale locale, {double size = 32}) =>
    locale.flagCountryCode.isEmpty ? null : IPCountryFlag(countryCode: locale.flagCountryCode, size: size);

class EnableAnalyticsPrefTile extends ConsumerWidget {
  const EnableAnalyticsPrefTile({super.key, this.onChanged});

  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    final enabled = ref.watch(analyticsControllerProvider).requireValue;
    final aurora = BlizzardPresentation.isActive(context);
    final toggle = SwitchListTile.adaptive(
      title: Text(t.pages.settings.general.enableAnalytics),
      subtitle: aurora
          ? null
          : Text(t.pages.settings.general.enableAnalyticsMsg, style: Theme.of(context).textTheme.bodySmall),
      secondary: const BlizzardSystemSymbol(icon: Icons.analytics_rounded),
      value: enabled,
      onChanged: (value) async {
        if (onChanged != null) {
          return onChanged!(value);
        }
        if (enabled) {
          await ref.read(analyticsControllerProvider.notifier).disableAnalytics();
        } else {
          await ref.read(analyticsControllerProvider.notifier).enableAnalytics();
        }
      },
    );
    return BlizzardPresentation(
      child: aurora
          ? MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  toggle,
                  Padding(
                    padding: const EdgeInsets.fromLTRB(BlizzardSpacing.s16, 0, BlizzardSpacing.s16, BlizzardSpacing.s8),
                    child: Text(
                      t.pages.settings.general.enableAnalyticsMsg,
                      style: BlizzardPresentation.themeOf(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: BlizzardPalette.secondary),
                    ),
                  ),
                ],
              ),
            )
          : toggle,
    );
  }
}

class ThemeModePrefTile extends ConsumerWidget {
  const ThemeModePrefTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    final themeMode = ref.watch(themePreferencesProvider);

    return BlizzardPresentation(
      child: ListTile(
        title: Text(t.pages.settings.general.themeMode),
        subtitle: Text(themeMode.present(t)),
        leading: BlizzardSystemSymbol(
          icon: switch (ref.watch(themePreferencesProvider)) {
            AppThemeMode.system => Icons.auto_awesome_rounded,
            AppThemeMode.light => Icons.light_mode_rounded,
            AppThemeMode.dark => Icons.dark_mode_rounded,
            AppThemeMode.black => Icons.contrast_rounded,
          },
        ),
        onTap: () async {
          final selectedThemeMode = await ref
              .read(dialogNotifierProvider.notifier)
              .showSettingPicker<AppThemeMode>(
                title: t.pages.settings.general.themeMode,
                selected: themeMode,
                onReset: () => ref.read(themePreferencesProvider.notifier).changeThemeMode(AppThemeMode.system),
                options: AppThemeMode.values,
                getTitle: (e) => e.present(t),
              );
          if (selectedThemeMode != null) {
            await ref.read(themePreferencesProvider.notifier).changeThemeMode(selectedThemeMode);
          }
        },
      ),
    );
  }
}

/// Solid (the sheet's material) or glass for sheets, menus and dialogs; applies at once.
class MenuStylePrefTile extends ConsumerWidget {
  const MenuStylePrefTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final style = ref.watch(Preferences.menuStyle);
    String present(BlizzardMenuStyle e) => e == BlizzardMenuStyle.glass
        ? t.pages.settings.general.menuStyleGlass
        : t.pages.settings.general.menuStyleSolid;

    return ListTile(
      title: Text(t.pages.settings.general.menuStyle),
      subtitle: Text(present(style)),
      leading: const BlizzardSystemSymbol(icon: Icons.blur_on_rounded),
      trailing: const BlizzardSystemSymbol(icon: Icons.chevron_right_rounded, color: BlizzardPalette.secondary),
      onTap: () async {
        final selected = await ref
            .read(dialogNotifierProvider.notifier)
            .showSettingPicker<BlizzardMenuStyle>(
              title: t.pages.settings.general.menuStyle,
              selected: style,
              options: const [BlizzardMenuStyle.neutral, BlizzardMenuStyle.glass],
              getTitle: present,
            );
        if (selected != null) await ref.read(Preferences.menuStyle.notifier).update(selected);
      },
    );
  }
}

class ClosingPrefTile extends ConsumerWidget {
  const ClosingPrefTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    final action = ref.watch(Preferences.actionAtClose);

    return BlizzardPresentation(
      child: ListTile(
        title: Text(t.pages.settings.general.actionAtClosing),
        subtitle: Text(action.present(t)),
        leading: const BlizzardSystemSymbol(icon: Icons.logout_rounded),
        onTap: () async {
          final selectedAction = await ref.read(dialogNotifierProvider.notifier).showActionAtClosing(selected: action);
          if (selectedAction != null) {
            await ref.read(Preferences.actionAtClose.notifier).update(selectedAction);
          }
        },
      ),
    );
  }
}
