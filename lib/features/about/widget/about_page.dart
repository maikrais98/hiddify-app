import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/adaptive_icon.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_backdrop.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_presentation.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_system_symbol.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_toolbar.dart';
import 'package:hiddify/features/settings/widget/blizzard_settings_group.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AboutPage extends HookConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final appInfo = ref.watch(appInfoProvider).requireValue;
    final luma =
        BlizzardPresentation.isActive(context) ||
        (Theme.of(context).extension<BlizzardEligibility>()?.applied ?? false);

    final conditionalTiles = [
      if (PlatformUtils.isDesktop)
        ListTile(
          title: Text(t.pages.about.openWorkingDir),
          trailing: const Icon(FluentIcons.open_folder_24_regular),
          onTap: () async {
            final path = ref.watch(appDirectoriesProvider).requireValue.workingDir.uri;
            await UriUtils.tryLaunch(path);
          },
        ),
    ];
    final aboutTiles = <Widget>[
      ...conditionalTiles,
      if (conditionalTiles.isNotEmpty) const Divider(),
      ListTile(
        title: Text(t.pages.about.sourceCode),
        leading: luma ? const BlizzardSystemSymbol(icon: Icons.link_rounded) : null,
        trailing: _linkIndicator(luma),
        onTap: () async {
          await UriUtils.tryLaunch(Uri.parse(Constants.githubUrl));
        },
      ),
      ListTile(
        title: Text(t.pages.about.termsAndConditions),
        leading: luma ? const BlizzardSystemSymbol(icon: Icons.description_outlined) : null,
        trailing: _linkIndicator(luma),
        onTap: () async {
          await UriUtils.tryLaunch(Uri.parse(Constants.termsAndConditionsUrl));
        },
      ),
      ListTile(
        title: Text(t.pages.about.privacyPolicy),
        leading: luma ? const BlizzardSystemSymbol(icon: Icons.shield_outlined) : null,
        trailing: _linkIndicator(luma),
        onTap: () async {
          await UriUtils.tryLaunch(Uri.parse(Constants.privacyPolicyUrl));
        },
      ),
    ];

    return BlizzardPresentation(
      child: BlizzardBackdrop(
        child: Scaffold(
          backgroundColor: luma ? Colors.transparent : null,
          appBar: AppBar(
            title: Text(t.pages.about.title),
            leading: blizzardToolbarLeading(context),
            actions: [
              ...blizzardToolbarActions(context, [
                PopupMenuButton(
                  icon: Icon(AdaptiveIcon(context).more),
                  itemBuilder: (context) {
                    return [
                      PopupMenuItem(
                        child: Text(t.common.addToClipboard),
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: appInfo.format()));
                        },
                      ),
                    ];
                  },
                ),
              ]),
              const Gap(8),
            ],
          ),
          body: CustomScrollView(
            slivers: [
              if (luma)
                SliverPadding(
                  padding: const EdgeInsets.all(BlizzardMetrics.screenMargin),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.common.appTitle, style: BlizzardTheme.brandStyle(BlizzardPresentation.themeOf(context))),
                        const Gap(BlizzardSpacing.s24),
                        Text(
                          '${t.common.version} ${appInfo.presentVersion}',
                          style: BlizzardPresentation.themeOf(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: BlizzardPalette.secondary),
                        ),
                        const Gap(BlizzardSpacing.s16),
                        BlizzardSettingsGroup(
                          groupKey: const ValueKey('about-links-panel'),
                          title: t.$meta.locale == AppLocale.ru ? 'Приложение' : 'Application',
                          children: aboutTiles,
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Assets.images.logo.svg(width: 64, height: 64),
                        const Gap(16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.common.appTitle, style: BlizzardPresentation.themeOf(context).textTheme.titleLarge),
                            const Gap(4),
                            Text("${t.common.version} ${appInfo.presentVersion}"),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: BlizzardSettingsPanel(key: const ValueKey('about-links-panel'), children: aboutTiles),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _linkIndicator(bool luma) => luma
      ? const BlizzardSystemSymbol(icon: Icons.chevron_right_rounded, color: BlizzardPalette.secondary)
      : const Icon(FluentIcons.open_24_regular);
}
