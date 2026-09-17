import 'dart:convert';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
import 'package:hiddify/core/widget/nova_grouped_scaffold.dart';
import 'package:hiddify/core/widget/nova_grouped_section.dart';
import 'package:hiddify/features/profile/details/json_editor.dart';
import 'package:hiddify/features/profile/details/profile_details_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/subscription_metadata_state.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProfileDetailsPage extends HookConsumerWidget with PresLogger {
  const ProfileDetailsPage({super.key, required this.id});

  final String id;

  String _genSliderText(Translations t, int sliderValue) {
    if (sliderValue == 0) {
      return t.common.auto;
    } else if (sliderValue < 24) {
      return t.common.interval.hour(n: sliderValue);
    }
    final day = t.common.interval.day(n: sliderValue ~/ 24);
    final hour = t.common.interval.hour(n: sliderValue % 24);
    return '$day $hour';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final provider = profileDetailsNotifierProvider(id);

    return ref
        .watch(ProfileDetailsNotifierProvider(id))
        .when(
          data: (data) {
            final isLoading = data.loadingState is AsyncLoading;
            final userOverride = data.profile.userOverride ?? const UserOverride();
            final updateIntervalHours = switch (data.profile) {
              RemoteProfileEntity(:final options) => resolveProfileUpdateIntervalHours(
                userOverrideHours: userOverride.updateInterval,
                profileInterval: options?.updateInterval,
              ),
              LocalProfileEntity() => minProfileUpdateIntervalHours,
            };
            final subscriptionMetadata = data.profile is RemoteProfileEntity
                ? SubscriptionMetadataState.fromProfile(data.profile, now: DateTime.now())
                : null;
            final sliderFocusNode = useFocusNode(
              onKeyEvent: (node, event) {
                if (KeyboardConst.verticalArrows.contains(event.logicalKey) && event is KeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    node.previousFocus();
                  } else {
                    node.nextFocus();
                  }
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
            );
            return NovaGroupedScaffold(
              appBar: AppBar(
                title: Text(t.pages.profileDetails.title),
                actions: [
                  TextButton.icon(
                    onPressed: isLoading || !data.isDetailsChanged
                        ? null
                        : () async {
                            if (formKey.currentState!.validate()) {
                              try {
                                final success = await ref.read(provider.notifier).save();
                                if (success && context.mounted) context.pop();
                              } catch (error) {
                                if (context.mounted) {
                                  ref
                                      .read(inAppNotificationControllerProvider)
                                      .showErrorToast(
                                        t.presentShortError(error, action: t.pages.profiles.msg.update.failure),
                                      );
                                }
                              }
                            }
                          },
                    icon: const Icon(Icons.check),
                    label: Text(t.common.save),
                  ),
                  const Gap(8),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.only(top: NovaSpacing.lg, bottom: NovaSpacing.xxl),
                children: [
                  NovaGroupedSection(
                    children: [
                      Form(
                        key: formKey,
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: CustomTextFormField(
                                maxLines: 1,
                                initialValue: userOverride.name ?? data.profile.name,
                                validator: (value) =>
                                    (value?.isEmpty ?? true) ? t.pages.profileDetails.form.emptyName : null,
                                onChanged: (value) => ref
                                    .read(ProfileDetailsNotifierProvider(id).notifier)
                                    .setUserOverride(userOverride.copyWith(name: value)),
                                label: t.common.name,
                                hint: t.pages.profileDetails.form.nameHint,
                              ),
                            ),
                            if (data.profile case RemoteProfileEntity(:final url))
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t.common.url,
                                      style: theme.textTheme.labelMedium!.copyWith(color: theme.colorScheme.onSurface),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const Gap(4),
                                    SelectableText(
                                      url,
                                      style: theme.textTheme.bodySmall!.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const Divider(indent: 16, endIndent: 16),
                            if (data.profile case RemoteProfileEntity()) ...[
                              SwitchListTile.adaptive(
                                title: Text(
                                  t.pages.profileDetails.form.disableAutoUpdate,
                                  style: theme.textTheme.titleSmall!.copyWith(color: theme.colorScheme.onSurface),
                                ),
                                value: userOverride.isAutoUpdateDisable,
                                onChanged: (value) => ref
                                    .read(ProfileDetailsNotifierProvider(id).notifier)
                                    .setUserOverride(userOverride.copyWith(isAutoUpdateDisable: value)),
                              ),
                              AnimatedSize(
                                alignment: Alignment.topCenter,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                                child: !userOverride.isAutoUpdateDisable
                                    ? Column(
                                        children: [
                                          const Divider(indent: 16, endIndent: 16),
                                          const Gap(12),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 16),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    t.pages.profileDetails.form.autoUpdateInterval,
                                                    style: theme.textTheme.titleSmall!.copyWith(
                                                      color: theme.colorScheme.onSurface,
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  _genSliderText(t, updateIntervalHours),
                                                  style: theme.textTheme.labelSmall!.copyWith(
                                                    color: theme.colorScheme.onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Gap(4),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 10),
                                            child: Slider(
                                              focusNode: sliderFocusNode,
                                              value: updateIntervalHours.toDouble(),
                                              min: minProfileUpdateIntervalHours.toDouble(),
                                              max: maxProfileUpdateIntervalHours.toDouble(),
                                              divisions: maxProfileUpdateIntervalHours - minProfileUpdateIntervalHours,
                                              label: updateIntervalHours.toString(),
                                              onChanged: (double value) => ref
                                                  .read(ProfileDetailsNotifierProvider(id).notifier)
                                                  .setUserOverride(
                                                    userOverride.copyWith(updateInterval: value.toInt()),
                                                  ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              const Divider(indent: 16, endIndent: 16),
                            ],
                            ListTile(
                              title: Text(t.pages.profileDetails.lastUpdate),
                              leading: const Icon(FluentIcons.history_24_regular),
                              subtitle: Text(data.profile.lastUpdate.format()),
                              dense: true,
                            ),
                            if (data.profile case RemoteProfileEntity(:final subInfo)) ...[
                              const Divider(indent: 16, endIndent: 16),
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text.rich(
                                        style: Theme.of(context).textTheme.bodySmall,
                                        TextSpan(
                                          children: [
                                            _buildSubProp(
                                              FluentIcons.arrow_upload_16_regular,
                                              subInfo?.upload.size() ?? t.common.unknown,
                                              t.components.subscriptionInfo.upload,
                                            ),
                                            const TextSpan(text: "     "),
                                            _buildSubProp(
                                              FluentIcons.arrow_download_16_regular,
                                              subInfo?.download.size() ?? t.common.unknown,
                                              t.components.subscriptionInfo.download,
                                            ),
                                            const TextSpan(text: "     "),
                                            _buildSubProp(
                                              FluentIcons.arrow_bidirectional_up_down_16_regular,
                                              _quotaText(subscriptionMetadata!, subInfo, t),
                                              t.components.subscriptionInfo.total,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Gap(12),
                                      Text.rich(
                                        style: Theme.of(context).textTheme.bodySmall,
                                        TextSpan(
                                          children: [
                                            _buildSubProp(
                                              FluentIcons.clock_dismiss_20_regular,
                                              switch (subscriptionMetadata.expiry) {
                                                SubscriptionExpiryStatus.finite =>
                                                  subscriptionMetadata.expiresAt!.format(),
                                                SubscriptionExpiryStatus.unlimited => '∞',
                                                SubscriptionExpiryStatus.unknown => t.common.unknown,
                                              },
                                              t.components.subscriptionInfo.expireDate,
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (subscriptionMetadata.quota == SubscriptionQuotaStatus.exhausted) ...[
                                        const Gap(12),
                                        Text(
                                          t.components.subscriptionInfo.noTraffic,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
                                        ),
                                      ],
                                      if (subscriptionMetadata.freshness == SubscriptionMetadataFreshness.stale) ...[
                                        const Gap(12),
                                        Text(
                                          '${t.pages.profileDetails.lastUpdate}: '
                                          '${subscriptionMetadata.lastUpdate.format()} · '
                                          '${t.pages.profiles.updateSubscriptions}',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            const Divider(),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Gap(NovaSpacing.xl),
                  NovaGroupedSection(
                    children: [
                      ExpansionTile(
                        key: const ValueKey('profile_advanced_configuration'),
                        title: Text(t.pages.profileDetails.form.advanced),
                        subtitle: Text(t.pages.profileDetails.form.advancedBody),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.7,
                            child: isJson(data.configContent)
                                ? JsonEditor(
                                    expandedObjects: const ["outbounds", "endpoints"],
                                    onChanged: (value) {
                                      if (value == null) return;
                                      try {
                                        const encoder = JsonEncoder.withIndent('  ');
                                        ref.read(provider.notifier).setContent(encoder.convert(value));
                                      } catch (e) {
                                        ref.read(provider.notifier).setContent("$value");
                                      }
                                    },
                                    enableHorizontalScroll: true,
                                    json: data.configContent,
                                  )
                                : TextFormField(
                                    onChanged: (value) {
                                      ref.read(provider.notifier).setContent(value);
                                    },
                                    maxLines: null,
                                    expands: true,
                                    textAlignVertical: TextAlignVertical.top,
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.only(left: 5, top: 8, bottom: 8),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
          error: (error, stackTrace) => NovaGroupedScaffold(
            appBar: AppBar(title: Text(t.pages.profileDetails.title)),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(FluentIcons.error_circle_12_filled),
                  Text(t.presentShortError(error)),
                  Text(error.toString()),
                ],
              ),
            ),
          ),
          loading: () => NovaGroupedScaffold(
            appBar: AppBar(title: Text(t.pages.profileDetails.title)),
            body: const Center(child: CircularProgressIndicator()),
          ),
        );
  }

  InlineSpan _buildSubProp(IconData icon, String text, String semanticLabel) {
    return TextSpan(
      children: [
        WidgetSpan(child: Icon(icon, size: 16, semanticLabel: semanticLabel)),
        const TextSpan(text: " "),
        TextSpan(text: text),
      ],
    );
  }

  String _quotaText(SubscriptionMetadataState metadata, SubscriptionInfo? subInfo, Translations t) =>
      switch (metadata.quota) {
        SubscriptionQuotaStatus.unlimited => '∞',
        SubscriptionQuotaStatus.unknown => t.common.unknown,
        SubscriptionQuotaStatus.available ||
        SubscriptionQuotaStatus.exhausted => subInfo?.total.size() ?? t.common.unknown,
      };
}

bool isJson(String value) {
  try {
    jsonDecode(value);
    return true;
  } catch (_) {
    return false;
  }
}
