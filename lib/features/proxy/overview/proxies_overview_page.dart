import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
import 'package:hiddify/core/widget/nova_grouped_scaffold.dart';
import 'package:hiddify/features/proxy/model/auto_mode_selection.dart';
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/widget/proxy_tile.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

String autoModeSelectionFeedback(
  AutoModeSelection selection, {
  required String autoLabel,
  required String timeoutLabel,
  required String emptyLabel,
}) {
  return switch (selection.reason) {
    AutoModeSelectionReason.lowestLatency =>
      '$autoLabel: ${selection.outboundTag} · ${selection.latency!.inMilliseconds} ms',
    AutoModeSelectionReason.deterministicFallback => '$autoLabel: ${selection.outboundTag}',
    AutoModeSelectionReason.latencyUnavailable => '$autoLabel: ${selection.outboundTag} · $timeoutLabel',
    AutoModeSelectionReason.noAuthorizedServers => emptyLabel,
  };
}

enum ProxiesRecoveryState { empty, loading, serviceStopped, proxyError }

ProxiesRecoveryState? proxiesRecoveryStateFor(AsyncValue<OutboundGroup?> proxies) {
  return switch (proxies) {
    AsyncLoading() => ProxiesRecoveryState.loading,
    AsyncError(error: ServiceNotRunning()) => ProxiesRecoveryState.serviceStopped,
    AsyncError() => ProxiesRecoveryState.proxyError,
    AsyncData(value: null) => ProxiesRecoveryState.empty,
    AsyncData(:final value) when value?.items.isEmpty ?? false => ProxiesRecoveryState.empty,
    AsyncData() => null,
    _ => ProxiesRecoveryState.loading,
  };
}

class ProxiesOverviewPage extends HookConsumerWidget with PresLogger {
  const ProxiesOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    final proxies = ref.watch(proxiesOverviewNotifierProvider);
    final sortBy = ref.watch(proxiesSortNotifierProvider);
    final recoveryState = proxiesRecoveryStateFor(proxies);
    final readyGroup = recoveryState == null ? proxies.valueOrNull : null;

    // final selectActiveProxyMutation = useMutation(
    //   initialOnFailure: (error) => CustomToast.error(t.presentShortError(error)).show(context),
    // );

    return NovaGroupedScaffold(
      appBar: AppBar(
        title: Text(t.pages.proxies.title),
        actions: [
          PopupMenuButton<ProxiesSort>(
            initialValue: sortBy,
            onSelected: ref.read(proxiesSortNotifierProvider.notifier).update,
            icon: const Icon(FluentIcons.arrow_sort_24_regular),
            tooltip: t.pages.proxies.sort,
            itemBuilder: (context) {
              return [...ProxiesSort.values.map((e) => PopupMenuItem(value: e, child: Text(e.present(t))))];
            },
          ),
          const Gap(8),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: readyGroup == null
            ? null
            : () async {
                final result = await ref.read(proxiesOverviewNotifierProvider.notifier).urlTest("select");
                if (!context.mounted || result == null) return;
                final message = autoModeSelectionFeedback(
                  result,
                  autoLabel: t.common.auto,
                  timeoutLabel: t.pages.proxies.delay.timeout,
                  emptyLabel: t.pages.proxies.empty,
                );
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
              },
        tooltip: t.pages.proxies.testDelay,
        child: const Icon(FluentIcons.flash_24_filled),
      ),
      body: switch (recoveryState) {
        null => LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final crossAxisCount = PlatformUtils.isMobile && width < 600 ? 1 : max(1, (width / 268).floor());
            return GridView.builder(
              padding: const EdgeInsets.only(bottom: 86),
              itemCount: readyGroup!.items.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisExtent: 72,
              ),
              itemBuilder: (context, index) {
                final proxy = readyGroup.items[index];
                return ProxyTile(
                  proxy,
                  selected: readyGroup.selected == proxy.tag,
                  onTap: () async {
                    await ref.read(proxiesOverviewNotifierProvider.notifier).changeProxy(readyGroup.tag, proxy.tag);
                  },
                );
              },
            );
          },
        ),
        ProxiesRecoveryState.loading => ProxiesRecoveryPanel(
          title: t.pages.proxies.loadingTitle,
          message: t.pages.proxies.loadingBody,
          loading: true,
        ),
        ProxiesRecoveryState.serviceStopped => ProxiesRecoveryPanel(
          title: t.pages.proxies.serviceStoppedTitle,
          message: t.pages.proxies.serviceStoppedBody,
          actionLabel: t.pages.proxies.goToConnection,
          actionIcon: Icons.power_settings_new_rounded,
          onAction: () => context.goNamed('home'),
        ),
        ProxiesRecoveryState.empty => ProxiesRecoveryPanel(
          title: t.pages.proxies.empty,
          message: t.pages.proxies.emptyBody,
          actionLabel: t.pages.profiles.title,
          actionIcon: Icons.vpn_key_rounded,
          onAction: () => ref.read(bottomSheetsNotifierProvider.notifier).showProfilesOverview(),
        ),
        ProxiesRecoveryState.proxyError => ProxiesRecoveryPanel(
          title: t.pages.proxies.loadFailed,
          message: t.pages.proxies.loadFailedBody,
          actionLabel: t.common.retry,
          onAction: () => ref.invalidate(proxiesOverviewNotifierProvider),
        ),
      },
    );
  }
}

class ProxiesRecoveryPanel extends StatelessWidget {
  const ProxiesRecoveryPanel({
    super.key,
    required this.title,
    required this.message,
    this.loading = false,
    this.actionLabel,
    this.actionIcon = Icons.refresh_rounded,
    this.onAction,
  });

  final String title;
  final String message;
  final bool loading;
  final String? actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final nova = NovaThemeData.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(NovaSpacing.xl),
          child: Semantics(
            liveRegion: true,
            container: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  CircularProgressIndicator(color: nova.accent)
                else
                  Icon(Icons.dns_rounded, color: nova.accent, size: 40),
                const Gap(NovaSpacing.md),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: nova.primaryText, fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const Gap(NovaSpacing.xs),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: nova.tertiaryText),
                ),
                if (!loading && actionLabel != null && onAction != null) ...[
                  const Gap(NovaSpacing.lg),
                  FilledButton.icon(onPressed: onAction, icon: Icon(actionIcon), label: Text(actionLabel!)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
