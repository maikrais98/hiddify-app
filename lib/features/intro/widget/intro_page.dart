import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/analytics/analytics_controller.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/model/region.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
import 'package:hiddify/features/common/general_pref_tiles.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/widget/preference_tile.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class IntroPage extends HookConsumerWidget with PresLogger {
  const IntroPage({super.key});

  static bool locationInfoLoaded = false;

  // for focus management
  KeyEventResult _handleKeyEvent(KeyEvent event, String key) {
    if (KeyboardConst.select.contains(event.logicalKey) && event is KeyUpEvent) {
      UriUtils.tryLaunch(Uri.parse(IntroConst.url[key]!));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    final isStarting = useState(false);

    if (!locationInfoLoaded) {
      autoSelectRegion(ref).then((value) => loggy.debug("Auto Region selection finished!"));
      locationInfoLoaded = true;
    }

    // for focus management
    final focusNodes = <String, FocusNode>{
      IntroConst.termsAndConditionsKey: useFocusNode(),
      IntroConst.githubKey: useFocusNode(),
      IntroConst.licenseKey: useFocusNode(),
    };

    return Scaffold(
      body: Center(
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth > IntroConst.maxwidth
                          ? IntroConst.maxwidth
                          : constraints.maxWidth;
                      final size = width * 0.4;
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(size * 0.24),
                        child: Image.asset(
                          'design/assets/woman-in-red-app-icon-master.png',
                          width: size,
                          height: size,
                          fit: BoxFit.cover,
                          semanticLabel: t.common.appTitle,
                        ),
                      );
                    },
                  ),
                  const Gap(16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        Text(t.intro.banner, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                        const Gap(8),
                        Text(t.intro.accessPrompt, style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                  const Gap(24),
                  const LocalePrefTile(),
                  ChoicePreferenceWidget(
                    selected: ref.watch(ConfigOptions.region),
                    preferences: ref.watch(ConfigOptions.region.notifier),
                    choices: Region.values,
                    title: t.pages.settings.routing.generalOptions.region,
                    showFlag: true,
                    icon: Icons.place_rounded,
                    presentChoice: (value) => value.present(t),
                    onChanged: (val) async {
                      await ref.read(ConfigOptions.directDnsAddress.notifier).reset();
                    },
                  ),
                  const EnableAnalyticsPrefTile(),
                  const Gap(24),
                  Text.rich(
                    t.intro.termsAndPolicyCaution(
                      tap: (text) => WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: IntroInlineLink(
                          key: const ValueKey('intro_link_terms'),
                          text: text,
                          focusNode: focusNodes[IntroConst.termsAndConditionsKey]!,
                          onKeyEvent: (node, event) => _handleKeyEvent(event, IntroConst.termsAndConditionsKey),
                          onActivate: () => UriUtils.tryLaunch(Uri.parse(Constants.termsAndConditionsUrl)),
                        ),
                      ),
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                  const Gap(8),
                  Text.rich(
                    t.intro.info(
                      tap_source: (text) => WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: IntroInlineLink(
                          key: const ValueKey('intro_link_source'),
                          text: text,
                          focusNode: focusNodes[IntroConst.githubKey]!,
                          onKeyEvent: (node, event) => _handleKeyEvent(event, IntroConst.githubKey),
                          onActivate: () => UriUtils.tryLaunch(Uri.parse(Constants.githubUrl)),
                        ),
                      ),
                      tap_license: (text) => WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: IntroInlineLink(
                          key: const ValueKey('intro_link_license'),
                          text: text,
                          focusNode: focusNodes[IntroConst.licenseKey]!,
                          onKeyEvent: (node, event) => _handleKeyEvent(event, IntroConst.licenseKey),
                          onActivate: () => UriUtils.tryLaunch(Uri.parse(Constants.licenseUrl)),
                        ),
                      ),
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: isStarting.value
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator())
            : const Icon(Icons.rocket_launch),
        label: Text(t.common.start, style: theme.textTheme.titleMedium),
        onPressed: () async {
          if (isStarting.value) return;
          isStarting.value = true;
          if (!ref.read(analyticsControllerProvider).requireValue) {
            loggy.info("disabling analytics per user request");
            try {
              await ref.read(analyticsControllerProvider.notifier).disableAnalytics();
            } catch (error, stackTrace) {
              loggy.error("could not disable analytics", error, stackTrace);
            }
          }
          await ref.read(Preferences.introCompleted.notifier).update(true);
        },
      ),
    );
  }

  Future<void> autoSelectRegion(WidgetRef ref) async {
    try {
      final countryCode = RegionDetector.detect();
      final regionLocale = _getRegionLocale(countryCode);
      loggy.debug('Timezone Region: ${regionLocale.region} Locale: ${regionLocale.locale}');
      await ref.read(ConfigOptions.region.notifier).update(regionLocale.region);
      await ref.watch(ConfigOptions.directDnsAddress.notifier).reset();
      await ref.read(localePreferencesProvider.notifier).changeLocale(regionLocale.locale);
      return;
    } catch (e) {
      loggy.warning('Could not get the local country code based on timezone', e);
    }

    try {
      final DioHttpClient client = DioHttpClient(
        timeout: const Duration(seconds: 2),
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:123.0) Gecko/20100101 Firefox/123.0",
        debug: true,
      );
      final response = await client.get<Map<String, dynamic>>('https://api.ip.sb/geoip/');

      if (response.statusCode == 200) {
        final jsonData = response.data!;
        final regionLocale = _getRegionLocale(jsonData['country_code']?.toString() ?? "");

        loggy.debug('Region: ${regionLocale.region} Locale: ${regionLocale.locale}');
        await ref.read(ConfigOptions.region.notifier).update(regionLocale.region);
        await ref.read(localePreferencesProvider.notifier).changeLocale(regionLocale.locale);
      } else {
        loggy.warning('Request failed with status: ${response.statusCode}');
      }
    } catch (e) {
      loggy.warning('Could not get the local country code from ip');
    }
  }

  RegionLocale _getRegionLocale(String country) {
    switch (country.toUpperCase()) {
      case "IR":
        return RegionLocale(Region.ir, AppLocale.fa);
      case "CN":
        return RegionLocale(Region.cn, AppLocale.zhCn);
      case "RU":
        return RegionLocale(Region.ru, AppLocale.ru);
      case "AF":
        return RegionLocale(Region.af, AppLocale.fa);
      case "BR":
        return RegionLocale(Region.br, AppLocale.ptBr);
      case "TR":
        return RegionLocale(Region.tr, AppLocale.tr);
      default:
        return RegionLocale(Region.other, AppLocale.en);
    }
  }
}

class IntroInlineLink extends StatefulWidget {
  const IntroInlineLink({
    super.key,
    required this.text,
    required this.focusNode,
    required this.onActivate,
    required this.onKeyEvent,
    this.enabled = true,
  });

  final String text;
  final FocusNode focusNode;
  final Future<void> Function() onActivate;
  final KeyEventResult Function(FocusNode node, KeyEvent event) onKeyEvent;
  final bool enabled;

  @override
  State<IntroInlineLink> createState() => _IntroInlineLinkState();
}

class _IntroInlineLinkState extends State<IntroInlineLink> {
  static final _activationKeys = {LogicalKeyboardKey.enter, LogicalKeyboardKey.space, LogicalKeyboardKey.select};

  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  void _setHovered(bool value) {
    if (_hovered == value || !mounted) return;
    setState(() => _hovered = value);
  }

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  Color _foregroundColor(NovaThemeData nova) {
    if (!widget.enabled) return nova.linkDisabled;
    if (_pressed) return nova.linkPressed;
    if (_hovered) return nova.linkHover;
    if (_focused) return nova.focusRing;
    return nova.link;
  }

  Color _backgroundColor(NovaThemeData nova) {
    if (!widget.enabled) return Colors.transparent;
    if (_pressed) return nova.linkPressed.withValues(alpha: 0.18);
    if (_hovered) return nova.linkHover.withValues(alpha: 0.12);
    return Colors.transparent;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.enabled || !_activationKeys.contains(event.logicalKey)) {
      return widget.onKeyEvent(node, event);
    }
    if (event is KeyDownEvent) {
      _setPressed(true);
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      _setPressed(false);
      return widget.onKeyEvent(node, event);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nova = NovaThemeData.of(context);
    final color = _foregroundColor(nova);
    final textStyle = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      color: color,
      decoration: TextDecoration.underline,
      decorationColor: color,
      decorationThickness: _hovered || _pressed || _focused ? 2 : 1,
    );

    return Semantics(
      label: widget.text,
      link: true,
      enabled: widget.enabled,
      child: MouseRegion(
        cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: widget.enabled ? (_) => _setHovered(true) : null,
        onExit: widget.enabled ? (_) => _setHovered(false) : null,
        child: Focus(
          focusNode: widget.focusNode,
          canRequestFocus: widget.enabled,
          onFocusChange: (value) {
            if (mounted) setState(() => _focused = value);
          },
          onKeyEvent: _handleKeyEvent,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.enabled ? widget.onActivate : null,
            onTapDown: widget.enabled ? (_) => _setPressed(true) : null,
            onTapUp: widget.enabled ? (_) => _setPressed(false) : null,
            onTapCancel: widget.enabled ? () => _setPressed(false) : null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _backgroundColor(nova),
                border: Border.all(color: _focused ? nova.focusRing : Colors.transparent, width: 2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                child: Text(widget.text, style: textStyle),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RegionLocale {
  final Region region;
  final AppLocale locale;

  RegionLocale(this.region, this.locale);
}

class RegionDetector {
  /// Returns: 'IR' | 'AF' | 'CN' | 'TR' | 'RU' | 'BR' | 'US'
  static String detect() {
    final now = DateTime.now();
    final offset = now.timeZoneOffset.inMinutes;
    final tz = now.timeZoneName.toLowerCase().trim();

    if (offset == 210) return 'IR';

    if (offset == 270) {
      final (_, country) = _parseLocale();
      return country == 'IR' ? 'IR' : 'AF';
    }

    final fromName = _fromTzName(tz, offset);
    if (fromName != null) return fromName;

    final candidates = _candidatesForOffset(offset);
    if (candidates.isEmpty) return 'US';

    return _resolveByLocale(candidates);
  }

  static String? _fromTzName(String tz, int offset) {
    if (tz.contains('/')) {
      final city = tz.split('/').last.replaceAll(' ', '_');
      final r = _ianaCities[city];
      if (r != null) return r;
    }

    if (tz == 'irst' || tz == 'irdt' || tz.contains('iran')) return 'IR';

    if (tz == 'aft' || tz.contains('afghanistan')) return 'AF';

    if (tz == 'trt' || tz.contains('turkey') || tz.contains('istanbul')) {
      return 'TR';
    }

    if (tz.contains('china') || tz.contains('beijing')) return 'CN';
    if (tz == 'cst' && offset == 480) return 'CN';

    if (_matchesRussiaTz(tz)) return 'RU';

    if (_matchesBrazilTz(tz)) return 'BR';

    return null;
  }

  static bool _matchesRussiaTz(String tz) {
    if (tz.contains('russia') || tz.contains('moscow')) return true;

    const abbrs = {'msk', 'yekt', 'omst', 'krat', 'irkt', 'yakt', 'vlat', 'magt', 'pett', 'sakt', 'sret'};
    if (abbrs.contains(tz)) return true;

    const winKeys = [
      'ekaterinburg',
      'kaliningrad',
      'yakutsk',
      'vladivostok',
      'magadan',
      'sakhalin',
      'kamchatka',
      'astrakhan',
      'saratov',
      'volgograd',
      'altai',
      'tomsk',
      'transbaikal',
      'n. central asia',
      'north asia',
    ];
    return winKeys.any(tz.contains);
  }

  static bool _matchesBrazilTz(String tz) {
    if (tz == 'brt' || tz == 'brst') return true;
    if (tz.contains('brazil') || tz.contains('brasilia')) return true;

    const winKeys = ['e. south america', 'central brazilian', 'tocantins', 'bahia'];
    return winKeys.any(tz.contains);
  }

  static Set<String> _candidatesForOffset(int offset) {
    final c = <String>{};

    if (offset == 180) c.add('TR');

    if (offset == 480) c.add('CN');

    if (_ruOffsets.contains(offset)) c.add('RU');

    if (_brOffsets.contains(offset)) c.add('BR');

    return c;
  }

  static const _ruOffsets = {120, 180, 240, 300, 360, 420, 480, 540, 600, 660, 720};

  static const _brOffsets = {-120, -180, -240, -300};

  static String _resolveByLocale(Set<String> candidates) {
    final (lang, country) = _parseLocale();

    if (country != null && candidates.contains(country)) {
      return country;
    }

    final regionFromLang = _langToRegion[lang];
    if (regionFromLang != null && candidates.contains(regionFromLang)) {
      return regionFromLang;
    }

    return 'US';
  }

  static (String, String?) _parseLocale() {
    try {
      final parts = Platform.localeName.split(RegExp(r'[_\-.]'));
      final lang = parts.first.toLowerCase();

      String? country;
      for (final p in parts.skip(1)) {
        if (p.length == 2) {
          country = p.toUpperCase();
          break;
        }
      }

      return (lang, country);
    } catch (_) {
      return ('en', null);
    }
  }

  static const _langToRegion = <String, String>{'fa': 'IR', 'ps': 'AF', 'tr': 'TR', 'zh': 'CN', 'ru': 'RU', 'pt': 'BR'};

  static const _ianaCities = <String, String>{
    'tehran': 'IR',
    'kabul': 'AF',
    'istanbul': 'TR',
    'shanghai': 'CN',
    'chongqing': 'CN',
    'urumqi': 'CN',
    'harbin': 'CN',
    'moscow': 'RU',
    'kaliningrad': 'RU',
    'samara': 'RU',
    'yekaterinburg': 'RU',
    'omsk': 'RU',
    'novosibirsk': 'RU',
    'barnaul': 'RU',
    'tomsk': 'RU',
    'krasnoyarsk': 'RU',
    'irkutsk': 'RU',
    'chita': 'RU',
    'yakutsk': 'RU',
    'vladivostok': 'RU',
    'magadan': 'RU',
    'sakhalin': 'RU',
    'kamchatka': 'RU',
    'anadyr': 'RU',
    'volgograd': 'RU',
    'saratov': 'RU',
    'astrakhan': 'RU',
    'sao_paulo': 'BR',
    'fortaleza': 'BR',
    'recife': 'BR',
    'manaus': 'BR',
    'belem': 'BR',
    'cuiaba': 'BR',
    'bahia': 'BR',
    'rio_branco': 'BR',
    'noronha': 'BR',
    'porto_velho': 'BR',
    'campo_grande': 'BR',
  };
}
