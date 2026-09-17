import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:fpdart/fpdart.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
import 'package:hiddify/core/widget/adaptive_icon.dart';
import 'package:hiddify/core/widget/nova_grouped_scaffold.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_summary.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostics_page.dart';
import 'package:hiddify/features/log/data/log_data_providers.dart';
import 'package:hiddify/features/log/model/log_level.dart';
import 'package:hiddify/features/log/overview/logs_overview_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sliver_tools/sliver_tools.dart';

class LogsPage extends HookConsumerWidget with PresLogger {
  const LogsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final state = ref.watch(logsOverviewNotifierProvider);
    final notifier = ref.watch(logsOverviewNotifierProvider.notifier);

    final debug = ref.watch(debugModeNotifierProvider);
    final pathResolver = ref.watch(logPathResolverProvider);

    final filterController = useTextEditingController(text: state.filter);
    final nova = NovaThemeData.of(context);

    final List<PopupMenuEntry> popupButtons = debug || PlatformUtils.isDesktop
        ? [
            PopupMenuItem(
              child: Text(t.pages.logs.shareCoreLogs),
              onTap: () async {
                await UriUtils.tryShareOrLaunchFile(
                  Uri.parse(pathResolver.coreFile().path),
                  fileOrDir: pathResolver.directory.uri,
                );
              },
            ),
            PopupMenuItem(
              child: Text(t.pages.logs.shareAppLogs),
              onTap: () async {
                await UriUtils.tryShareOrLaunchFile(
                  Uri.parse(pathResolver.appFile().path),
                  fileOrDir: pathResolver.directory.uri,
                );
              },
            ),
          ]
        : [];

    return NovaGroupedScaffold(
      appBar: AppBar(
        title: Text(t.pages.logs.title),
        actions: [
          IconButton(
            tooltip: Localizations.localeOf(context).languageCode == 'ru'
                ? 'Безопасная диагностика'
                : 'Safe diagnostics',
            icon: const Icon(Icons.health_and_safety_outlined),
            onPressed: () {
              final summary = SafeDiagnosticSummary.capture(
                ref.read(connectionNotifierProvider).valueOrNull,
                defaultTargetPlatform,
              );
              Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => SafeDiagnosticsPage(summary: summary)));
            },
          ),
          if (state.paused)
            IconButton(
              onPressed: notifier.resume,
              icon: const Icon(FluentIcons.play_20_regular),
              tooltip: t.common.resume,
              iconSize: 20,
            )
          else
            IconButton(
              onPressed: notifier.pause,
              icon: const Icon(FluentIcons.pause_20_regular),
              tooltip: t.common.pause,
              iconSize: 20,
            ),
          IconButton(
            onPressed: notifier.clear,
            icon: const Icon(FluentIcons.delete_lines_20_regular),
            tooltip: t.common.clear,
            iconSize: 20,
          ),
          if (popupButtons.isNotEmpty)
            PopupMenuButton(
              icon: Icon(AdaptiveIcon(context).more),
              itemBuilder: (context) {
                return popupButtons;
              },
            ),
          const Gap(8),
        ],
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return <Widget>[
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: MultiSliver(
                children: [
                  // NestedAppBar(
                  //   forceElevated: innerBoxIsScrolled,
                  // ),
                  SliverPinnedHeader(
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: nova.groupedBackground),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          NovaSpacing.lg,
                          NovaSpacing.sm,
                          NovaSpacing.lg,
                          NovaSpacing.md,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: nova.surface,
                            borderRadius: BorderRadius.circular(NovaRadii.large),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: NovaSpacing.md, vertical: NovaSpacing.xs),
                            child: Row(
                              children: [
                                Flexible(
                                  child: TextFormField(
                                    controller: filterController,
                                    onChanged: notifier.filterMessage,
                                    decoration: InputDecoration(
                                      border: InputBorder.none,
                                      isDense: true,
                                      hintText: t.common.filter,
                                      prefixIcon: const Icon(Icons.search_rounded),
                                    ),
                                  ),
                                ),
                                const Gap(NovaSpacing.md),
                                DropdownButton<Option<LogLevel>>(
                                  value: optionOf(state.levelFilter),
                                  onChanged: (v) {
                                    if (v == null) return;
                                    notifier.filterLevel(v.toNullable());
                                  },
                                  underline: const SizedBox.shrink(),
                                  padding: const EdgeInsets.symmetric(horizontal: NovaSpacing.sm),
                                  borderRadius: BorderRadius.circular(NovaRadii.medium),
                                  items: [
                                    DropdownMenuItem(value: none(), child: Text(t.common.all)),
                                    ...LogLevel.choices.map(
                                      (e) => DropdownMenuItem(value: some(e), child: Text(e.name)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ];
        },
        body: Builder(
          builder: (context) {
            return CustomScrollView(
              primary: false,
              reverse: true,
              slivers: <Widget>[
                switch (state.logs) {
                  AsyncData(value: final logs) => SliverPadding(
                    padding: const EdgeInsets.fromLTRB(NovaSpacing.lg, 0, NovaSpacing.lg, NovaSpacing.xl),
                    sliver: SliverList.builder(
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            color: nova.surface,
                            borderRadius: BorderRadius.vertical(
                              top: index == 0 ? const Radius.circular(NovaRadii.large) : Radius.zero,
                              bottom: index == logs.length - 1 ? const Radius.circular(NovaRadii.large) : Radius.zero,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: NovaSpacing.md,
                                  vertical: NovaSpacing.sm,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (log.level != null)
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            log.level!.name.toUpperCase(),
                                            style: Theme.of(
                                              context,
                                            ).textTheme.labelMedium?.copyWith(color: log.level!.color),
                                          ),
                                          if (log.time != null)
                                            Text(
                                              log.time!.toString(),
                                              style: Theme.of(
                                                context,
                                              ).textTheme.labelSmall?.copyWith(color: nova.tertiaryText),
                                            ),
                                        ],
                                      ),
                                    Text(extractMessage(log.message), style: Theme.of(context).textTheme.bodySmall),
                                  ],
                                ),
                              ),
                              if (index != logs.length - 1)
                                Divider(height: 1, indent: NovaSpacing.md, color: nova.separator),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  AsyncError(:final error) => SliverErrorBodyPlaceholder(t.presentShortError(error)),
                  _ => const SliverLoadingBodyPlaceholder(),
                },
                SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
              ],
            );
          },
        ),
      ),
    );
  }
}

String extractMessage(String message) {
  final parts = message.split(' ');
  return parts.length <= 2 ? parts.last : parts.sublist(2).join(' ');
}
