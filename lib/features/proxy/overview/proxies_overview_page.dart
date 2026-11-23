import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/adaptive_icon.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_backdrop.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_glass.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_presentation.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/keep_top/keep_top_widgets.dart';
import 'package:hiddify/features/proxy/model/proxy_entity.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/widget/proxy_tile.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProxiesOverviewPage extends HookConsumerWidget with PresLogger {
  const ProxiesOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    final proxies = ref.watch(proxiesOverviewNotifierProvider);
    final sortBy = ref.watch(proxiesSortNotifierProvider);
    final activeProfileName = ref.watch(activeProfileProvider).valueOrNull?.name;
    final showResting = ref.watch(Preferences.showSleepingProxies);
    final presentationTheme = BlizzardPresentation.themeOf(context);
    final blizzard =
        BlizzardPresentation.isActive(context) ||
        (presentationTheme.extension<BlizzardEligibility>()?.applied ?? false);
    final delayTestAction = blizzard
        ? TextButton(
            key: const ValueKey('servers_test_delay_button'),
            onPressed: () async => await ref.read(proxiesOverviewNotifierProvider.notifier).urlTest('select'),
            style: TextButton.styleFrom(
              foregroundColor: BlizzardPalette.primary,
              backgroundColor: BlizzardPalette.elevated,
              minimumSize: const Size(BlizzardMetrics.minimumTarget, BlizzardMetrics.primaryButtonHeight),
              padding: const EdgeInsets.symmetric(horizontal: BlizzardSpacing.s16, vertical: BlizzardSpacing.s12),
              textStyle: presentationTheme.textTheme.titleMedium,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BlizzardRadii.control)),
            ),
            child: Text(t.pages.proxies.testDelay, textAlign: TextAlign.center),
          )
        : FloatingActionButton.extended(
            onPressed: () async => await ref.read(proxiesOverviewNotifierProvider.notifier).urlTest('select'),
            tooltip: t.pages.proxies.testDelay,
            isExtended: false,
            icon: const Icon(FluentIcons.flash_24_filled),
            label: const SizedBox.shrink(),
          );

    // final selectActiveProxyMutation = useMutation(
    //   initialOnFailure: (error) => CustomToast.error(t.presentShortError(error)).show(context),
    // );

    final page = Scaffold(
      backgroundColor: blizzard ? Colors.transparent : null,
      appBar: AppBar(
        forceMaterialTransparency: blizzard,
        leadingWidth: blizzard ? 68 : null,
        leading: blizzard
            ? const Padding(
                padding: EdgeInsetsDirectional.only(start: 12, top: 4, bottom: 4),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: BlizzardGlass(
                    active: true,
                    radius: BlizzardRadii.sheet,
                    child: SizedBox.square(dimension: 48, child: BackButton(key: ValueKey('servers_back_button'))),
                  ),
                ),
              )
            : null,
        title: Text(blizzard ? _serversTitle(t.$meta.locale) : t.pages.proxies.title),
        actions: [
          BlizzardGlass(
            active: blizzard,
            radius: BlizzardRadii.sheet,
            child: PopupMenuButton<ProxiesSort>(
              popUpAnimationStyle: BlizzardPopupTransition.styleOf(context),
              initialValue: sortBy,
              onSelected: ref.read(proxiesSortNotifierProvider.notifier).update,
              icon: const Icon(FluentIcons.arrow_sort_24_regular),
              tooltip: t.pages.proxies.sort,
              itemBuilder: (context) {
                return [...ProxiesSort.values.map((e) => PopupMenuItem(value: e, child: Text(e.present(t))))];
              },
            ),
          ),
          // "Signal style" (off by default) shows pings as the signal instead of numbers
          PopupMenuButton<bool>(
            popUpAnimationStyle: BlizzardPopupTransition.styleOf(context),
            onSelected: (_) => ref.read(proxyPingStyleNotifierProvider.notifier).toggle(),
            icon: Icon(AdaptiveIcon(context).more),
            tooltip: MaterialLocalizations.of(context).showMenuTooltip,
            itemBuilder: (context) => [
              // a null value would close the menu as cancelled
              PopupMenuItem(
                value: true,
                child: Row(
                  children: [
                    Checkbox(
                      value: ref.read(proxyPingStyleNotifierProvider) == ProxyPingStyle.signal,
                      // a tap on the box itself does what a tap on the item does
                      onChanged: (_) => Navigator.pop(context, true),
                    ),
                    const Gap(8),
                    Text(t.pages.proxies.signalStyle),
                  ],
                ),
              ),
            ],
          ),
          const Gap(8),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // the speed of the proxies listed: what it tests and the data it takes show first, and
          // it starts from there
          if (proxies.valueOrNull case final group?)
            FloatingActionButton.small(
              heroTag: 'upload-test',
              onPressed: () async {
                final count = group.items.where((e) => !e.isGroup && !e.resting).length;
                if (await ref.read(dialogNotifierProvider.notifier).showSpeedTest(count: count)) {
                  await ref.read(proxiesOverviewNotifierProvider.notifier).speedTestAll();
                }
              },
              tooltip: t.pages.proxies.speedTest.title,
              child: const Icon(Icons.speed_rounded, size: 26),
            ),
          const KeepTopAction(),
          if (!blizzard || proxies.valueOrNull == null) ...[const Gap(12), delayTestAction],
        ],
      ),
      body: proxies.when(
        data: (group) => group != null
            ? LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  // columns wide enough for a proxy's name: two on a usual window, more only when wider
                  final crossAxisCount = PlatformUtils.isMobile && width < 600 ? 1 : max(1, (width / 420).floor());
                  final inUse = group.items.where((e) => !e.resting).toList();
                  final resting = group.items.where((e) => e.resting).toList();
                  final listed = inUse.where((e) => e.tag != lowestGroupTag && e.tag != balanceGroupTag).length;
                  Widget row(List<OutboundInfo> items, int index) {
                    final proxy = items[index];
                    return ProxyTile(
                      proxy,
                      key: ValueKey(proxy.tag),
                      selected: group.selected == proxy.tag,
                      quiet: group.keepTopPicking,
                      grouped: blizzard,
                      firstInGroup: index < crossAxisCount,
                      lastInGroup: index >= items.length - crossAxisCount,
                      onTap: () async {
                        await ref.read(proxiesOverviewNotifierProvider.notifier).changeProxy(group.tag, proxy.tag);
                      },
                    );
                  }

                  Widget rows(List<OutboundInfo> items) => blizzard && crossAxisCount == 1
                      ? SliverList.builder(itemCount: items.length, itemBuilder: (context, index) => row(items, index))
                      : SliverGrid.builder(
                          itemCount: items.length,
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            mainAxisExtent: blizzard
                                ? max(BlizzardMetrics.cardMinHeight, 48 + MediaQuery.textScalerOf(context).scale(29))
                                : 72,
                          ),
                          itemBuilder: (context, index) => row(items, index),
                        );
                  final keepTop = SliverToBoxAdapter(
                    child: KeepTopFooter(listed: listed, picking: group.keepTopPicking, proxies: group.items),
                  );
                  return CustomScrollView(
                    key: const ValueKey('servers_grid'),
                    slivers: [
                      if (group.keepTopPicking) keepTop,
                      if (blizzard) ...[
                        SliverPadding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            BlizzardMetrics.screenMargin,
                            BlizzardSpacing.s4,
                            BlizzardMetrics.screenMargin,
                            BlizzardSpacing.s16,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: Text(
                              _profileServerSummary(t.$meta.locale, activeProfileName, group.items.length),
                              key: const ValueKey('servers_profile_summary'),
                              style: presentationTheme.textTheme.bodySmall?.copyWith(color: BlizzardPalette.secondary),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(
                            BlizzardMetrics.screenMargin,
                            0,
                            BlizzardMetrics.screenMargin,
                            BlizzardSpacing.s16,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: SizedBox(width: double.infinity, child: delayTestAction),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(
                            BlizzardMetrics.screenMargin,
                            0,
                            BlizzardMetrics.screenMargin,
                            BlizzardSpacing.s16,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: Text(
                              _subscriptionProxiesTitle(t.$meta.locale),
                              style: presentationTheme.textTheme.bodySmall?.copyWith(color: BlizzardPalette.secondary),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: BlizzardMetrics.screenMargin),
                          sliver: DecoratedSliver(
                            decoration: BoxDecoration(
                              color: BlizzardMaterials(highContrast: MediaQuery.highContrastOf(context)).content,
                              borderRadius: BorderRadius.circular(BlizzardRadii.card),
                            ),
                            sliver: rows(inUse),
                          ),
                        ),
                        if (t.$meta.locale.languageCode == 'ru' || t.$meta.locale.languageCode == 'en')
                          SliverPadding(
                            padding: const EdgeInsets.all(BlizzardMetrics.screenMargin),
                            sliver: SliverToBoxAdapter(
                              child: Text(
                                t.$meta.locale.languageCode == 'ru'
                                    ? 'Имена и коды переданы подпиской.'
                                    : 'Names and country codes come from the subscription.',
                                style: presentationTheme.textTheme.bodySmall?.copyWith(
                                  color: BlizzardPalette.secondary,
                                ),
                              ),
                            ),
                          ),
                      ] else
                        rows(inUse),
                      if (!group.keepTopPicking) keepTop,
                      if (resting.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: RestingProxiesHeader(
                            count: resting.length,
                            shown: showResting,
                            onToggle: () => ref.read(Preferences.showSleepingProxies.notifier).update(!showResting),
                          ),
                        ),
                        if (showResting)
                          SliverPadding(
                            padding: EdgeInsets.symmetric(horizontal: blizzard ? BlizzardMetrics.screenMargin : 0),
                            sliver: DecoratedSliver(
                              decoration: BoxDecoration(
                                color: blizzard ? BlizzardPalette.surface : null,
                                borderRadius: BorderRadius.circular(BlizzardRadii.card),
                              ),
                              sliver: rows(resting),
                            ),
                          ),
                      ],
                      const SliverPadding(padding: EdgeInsets.only(bottom: 140)),
                    ],
                  );
                },
              )
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    ref.watch(serviceRunningProvider) ? t.pages.proxies.empty : t.pages.proxies.connectToSeeProxies,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t.pages.proxies.loadFailed, textAlign: TextAlign.center),
                const Gap(12),
                TextButton(
                  onPressed: () => ref.invalidate(proxiesOverviewNotifierProvider),
                  child: Text(t.connection.tapToRetry),
                ),
              ],
            ),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
    return BlizzardPresentation(child: BlizzardBackdrop(child: page));
  }
}

String _serversTitle(AppLocale locale) => locale == AppLocale.ru ? 'Серверы' : 'Servers';

String _profileServerSummary(AppLocale locale, String? profileName, int count) {
  final countLabel = locale == AppLocale.ru
      ? _russianServerCount(count)
      : '$count ${count == 1 ? 'server' : 'servers'}';
  return [profileName?.trim() ?? '', countLabel].where((value) => value.isNotEmpty).join(' · ');
}

String _russianServerCount(int count) {
  final mod100 = count % 100;
  final mod10 = count % 10;
  final noun = mod100 >= 11 && mod100 <= 14
      ? 'серверов'
      : mod10 == 1
      ? 'сервер'
      : mod10 >= 2 && mod10 <= 4
      ? 'сервера'
      : 'серверов';
  return '$count $noun';
}

String _subscriptionProxiesTitle(AppLocale locale) => switch (locale.languageCode) {
  'ru' => 'Прокси подписки',
  'en' => 'Subscription proxies',
  _ => locale.buildSync().pages.proxies.title,
};
