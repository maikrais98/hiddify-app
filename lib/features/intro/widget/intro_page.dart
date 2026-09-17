import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/analytics/analytics_controller.dart';
import 'package:hiddify/core/localization/locale_extensions.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/model/region.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class IntroPage extends ConsumerWidget {
  const IntroPage({super.key, this.pendingUrl});

  final String? pendingUrl;

  Future<void> _finish(BuildContext context, WidgetRef ref, {required bool openImporter}) async {
    await ref.read(Preferences.introCompleted.notifier).update(true);
    if (!context.mounted) return;
    final importer = openImporter && pendingUrl == null ? ref.read(bottomSheetsNotifierProvider.notifier) : null;
    final home = Uri(path: '/home', queryParameters: {if (pendingUrl != null) 'url': pendingUrl}).toString();
    context.go(home);
    if (importer != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        importer.showAddProfile();
      });
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final nova = NovaThemeData.of(context);
    final locale = ref.watch(localePreferencesProvider);
    final region = ref.watch(ConfigOptions.region);
    final analytics = ref.watch(analyticsControllerProvider).valueOrNull ?? false;
    final copy = _IntroCopy.forLocale(Localizations.localeOf(context));

    return Scaffold(
      backgroundColor: nova.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 56, 20, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  Container(
                    width: 128,
                    height: 128,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: nova.accent.withValues(alpha: .32),
                          blurRadius: 32,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      'design/assets/woman-in-red-app-icon-master.png',
                      semanticLabel: Constants.appName,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    copy.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: nova.primaryText, fontSize: 29, height: 1.02, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    copy.body,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: nova.secondaryText, fontSize: 14, height: 1.35),
                  ),
                  const SizedBox(height: 22),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(NovaRadii.large),
                    child: Column(
                      children: [
                        _IntroRow(
                          icon: Icons.translate_rounded,
                          label: t.pages.settings.general.locale,
                          value: locale.localeName,
                          onTap: () async {
                            final selected = await ref
                                .read(dialogNotifierProvider.notifier)
                                .showSettingPicker<AppLocale>(
                                  title: t.pages.settings.general.locale,
                                  selected: locale,
                                  onReset: () =>
                                      ref.read(localePreferencesProvider.notifier).changeLocale(AppLocale.en),
                                  options: AppLocale.values,
                                  getTitle: (value) => value.localeName,
                                );
                            if (selected != null) {
                              await ref.read(localePreferencesProvider.notifier).changeLocale(selected);
                            }
                          },
                        ),
                        Divider(height: 1, color: nova.separator),
                        _IntroRow(
                          icon: Icons.location_on_outlined,
                          label: t.pages.settings.routing.generalOptions.region,
                          value: region.present(t),
                          onTap: () async {
                            final selected = await ref
                                .read(dialogNotifierProvider.notifier)
                                .showSettingPicker<Region>(
                                  title: t.pages.settings.routing.generalOptions.region,
                                  selected: region,
                                  options: Region.values,
                                  getTitle: (value) => value.present(t),
                                  onReset: ref.read(ConfigOptions.region.notifier).reset,
                                );
                            if (selected != null) {
                              await ref.read(ConfigOptions.region.notifier).update(selected);
                              await ref.read(ConfigOptions.directDnsAddress.notifier).reset();
                            }
                          },
                        ),
                        Divider(height: 1, color: nova.separator),
                        _IntroRow(
                          icon: Icons.analytics_outlined,
                          label: t.pages.settings.general.enableAnalytics,
                          value: analytics ? copy.enabled : copy.disabled,
                          onTap: () async {
                            if (analytics) {
                              await ref.read(analyticsControllerProvider.notifier).disableAnalytics();
                            } else {
                              await ref.read(analyticsControllerProvider.notifier).enableAnalytics();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      key: const ValueKey('intro_add_profile'),
                      onPressed: () => _finish(context, ref, openImporter: true),
                      icon: const Icon(Icons.rocket_launch_rounded, size: 20),
                      label: Text(copy.addProfile),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD7193F),
                        foregroundColor: NovaColors.primaryText,
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('intro_later'),
                    onPressed: () => _finish(context, ref, openImporter: false),
                    child: Text(copy.later),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IntroRow extends StatelessWidget {
  const _IntroRow({required this.icon, required this.label, required this.value, required this.onTap});

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nova = NovaThemeData.of(context);
    return Material(
      color: nova.surface,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(icon, color: nova.secondaryText, size: 21),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(label, style: TextStyle(color: nova.primaryText, fontSize: 15)),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: nova.secondaryText, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: nova.tertiaryText, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _IntroCopy {
  russian(
    title: 'Личная дверь в\nоткрытый интернет',
    body: 'Добавьте VPN-профиль из файла, ссылки или QR-кода. Email не требуется.',
    addProfile: 'Добавить профиль',
    later: 'Позже',
    enabled: 'Вкл.',
    disabled: 'Выкл.',
  ),
  english(
    title: 'Your private door to\nthe open internet',
    body: 'Add a VPN profile from a file, link, or QR code. No email required.',
    addProfile: 'Add profile',
    later: 'Later',
    enabled: 'On',
    disabled: 'Off',
  );

  const _IntroCopy({
    required this.title,
    required this.body,
    required this.addProfile,
    required this.later,
    required this.enabled,
    required this.disabled,
  });

  final String title;
  final String body;
  final String addProfile;
  final String later;
  final String enabled;
  final String disabled;

  static _IntroCopy forLocale(Locale locale) => locale.languageCode == 'ru' ? russian : english;
}
