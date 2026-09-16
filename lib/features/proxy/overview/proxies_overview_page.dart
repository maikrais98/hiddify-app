import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/adaptive_layout/nova_tab_route.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
import 'package:hiddify/core/widget/nova_grouped_scaffold.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/proxy/model/auto_mode_selection.dart';
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxy_picker_content.dart';
import 'package:hiddify/features/proxy/overview/proxy_picker_state.dart';
import 'package:hiddify/features/proxy/widget/proxy_tile.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/custom_loggers.dart';
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

enum ProxiesRecoveryState { noGroup, emptyGroup, loading, serviceStopped, proxyError }

ProxiesRecoveryState? proxiesRecoveryStateFor(AsyncValue<OutboundGroup?> proxies) {
  return switch (proxies) {
    AsyncLoading() => ProxiesRecoveryState.loading,
    AsyncError(error: ServiceNotRunning()) => ProxiesRecoveryState.serviceStopped,
    AsyncError() => ProxiesRecoveryState.proxyError,
    AsyncData(value: null) => ProxiesRecoveryState.noGroup,
    AsyncData(:final value) when value?.items.isEmpty ?? false => ProxiesRecoveryState.emptyGroup,
    AsyncData() => null,
    _ => ProxiesRecoveryState.loading,
  };
}

class ProxiesOverviewPage extends HookConsumerWidget with PresLogger {
  const ProxiesOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routerDelegate = GoRouter.maybeOf(context)?.routerDelegate;
    useListenable(routerDelegate);
    final routePath = routerDelegate?.currentConfiguration.uri.path;
    final isPickerActive = routePath == null || routePath == '/proxies' || novaTabForLocation(routePath) == NovaTab.servers;
    final t = ref.watch(translationsProvider).requireValue;
    final proxies = ref.watch(proxiesOverviewNotifierProvider);
    final sortBy = ref.watch(proxiesSortNotifierProvider);
    final recentProxyTags = ref.watch(proxyRecentTagsProvider);
    final recoveryState = proxiesRecoveryStateFor(proxies);
    final readyGroup = recoveryState == null ? proxies.valueOrNull : null;
    final hasAnyProfileState =
        recoveryState == ProxiesRecoveryState.noGroup || recoveryState == ProxiesRecoveryState.emptyGroup
        ? ref.watch(hasAnyProfileProvider)
        : const AsyncData(false);
    final activeProfileState = recoveryState == ProxiesRecoveryState.emptyGroup
        ? ref.watch(activeProfileProvider)
        : const AsyncData<ProfileEntity?>(null);

    Future<void> showAccessSelection() async {
      final hasProfiles = switch (hasAnyProfileState) {
        AsyncData(:final value) => value,
        _ => false,
      };
      if (!context.mounted) return;
      if (hasProfiles) {
        await ref.read(bottomSheetsNotifierProvider.notifier).showProfilesOverview();
      } else {
        await ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile();
      }
    }

    Future<void> refreshAccess() async {
      try {
        final activeProfile = switch (activeProfileState) {
          AsyncData(:final value) => value,
          _ => null,
        };
        if (!context.mounted) return;
        switch (activeProfile) {
          case RemoteProfileEntity():
            await ref.read(updateProfileNotifierProvider(activeProfile.id).notifier).updateProfile(activeProfile);
          case LocalProfileEntity():
            await ref.read(connectionNotifierProvider.notifier).reconnect(activeProfile);
          case null:
            await showAccessSelection();
        }
      } catch (_) {
        if (context.mounted) await showAccessSelection();
      }
    }

    final activeProfileNeedsSelection = switch (activeProfileState) {
      AsyncData(value: final ProfileEntity _) => false,
      _ => true,
    };
    final canRefreshAccess =
        !activeProfileState.isLoading && (!activeProfileNeedsSelection || !hasAnyProfileState.isLoading);

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
        null => ProxyPickerContent(
          group: readyGroup!,
          recentTags: recentProxyTags,
          searchHint: t.pages.proxies.searchHint,
          clearLabel: t.pages.proxies.clearSearch,
          selectedLabel: t.pages.proxies.selectedServer,
          recentLabel: t.pages.proxies.recentServers,
          noResultsTitle: t.pages.proxies.noSearchResults,
          noResultsBody: t.pages.proxies.noSearchResultsBody,
          isActive: isPickerActive,
          itemBuilder: (context, proxy, selected, onSelect) => ProxyTile(proxy, selected: selected, onTap: onSelect),
          onSelect: (proxy) async {
            final recent = ref.read(proxyRecentTagsProvider.notifier);
            recent.record(readyGroup.selected);
            await ref.read(proxiesOverviewNotifierProvider.notifier).changeProxy(readyGroup.tag, proxy.tag);
            recent.record(proxy.tag);
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
        ProxiesRecoveryState.noGroup => ProxiesRecoveryPanel(
          title: t.pages.proxies.noAccessTitle,
          message: t.pages.proxies.noAccessBody,
          actionLabel: t.pages.proxies.selectAccess,
          actionIcon: Icons.vpn_key_rounded,
          onAction: hasAnyProfileState.isLoading ? null : showAccessSelection,
        ),
        ProxiesRecoveryState.emptyGroup => ProxiesRecoveryPanel(
          title: t.pages.proxies.empty,
          message: t.pages.proxies.emptyBody,
          actionLabel: t.pages.proxies.refreshAccess,
          onAction: canRefreshAccess ? refreshAccess : null,
          secondaryActionLabel: t.pages.proxies.selectAccess,
          onSecondaryAction: hasAnyProfileState.isLoading ? null : showAccessSelection,
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
    this.secondaryActionLabel,
    this.secondaryActionIcon = Icons.vpn_key_rounded,
    this.onSecondaryAction,
  });

  final String title;
  final String message;
  final bool loading;
  final String? actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final IconData secondaryActionIcon;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final nova = NovaThemeData.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(NovaSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
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
                if (!loading && actionLabel != null) ...[
                  const Gap(NovaSpacing.lg),
                  FilledButton.icon(
                    key: const ValueKey('proxies_recovery_primary_action'),
                    onPressed: onAction,
                    icon: Icon(actionIcon),
                    label: Text(actionLabel!),
                  ),
                ],
                if (!loading && secondaryActionLabel != null) ...[
                  const Gap(NovaSpacing.sm),
                  OutlinedButton.icon(
                    key: const ValueKey('proxies_recovery_secondary_action'),
                    onPressed: onSecondaryAction,
                    icon: Icon(secondaryActionIcon),
                    label: Text(secondaryActionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
