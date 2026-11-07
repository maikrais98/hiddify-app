import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/model/trusted_links.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/adaptive_icon.dart';
import 'package:hiddify/core/widget/adaptive_menu.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_glass.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_presentation.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_system_symbol.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/gen/fonts.gen.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:simple_icons/simple_icons.dart';

class ProfileTile extends HookConsumerWidget {
  const ProfileTile({super.key, required this.profile, this.isMain = false, this.margin = EdgeInsets.zero, this.color});

  final ProfileEntity profile;

  /// home screen active profile card
  final bool isMain;
  final EdgeInsets margin;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = BlizzardPresentation.themeOf(context);
    final blizzard =
        BlizzardPresentation.isActive(context) || (theme.extension<BlizzardEligibility>()?.applied ?? false);

    final selectActiveMutation = useMutation(
      initialOnFailure: (err) {
        ref.read(inAppNotificationControllerProvider).showErrorToast(t.presentShortError(err));
      },
      initialOnSuccess: () {
        if (context.mounted && context.canPop()) context.pop();
      },
    );

    final subInfo = switch (profile) {
      RemoteProfileEntity(:final subInfo) => subInfo,
      _ => null,
    };

    final showActionButton = profile is RemoteProfileEntity || !isMain;

    // final effectiveMargin = isMain ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8) : const EdgeInsets.only(left: 12, right: 12, bottom: 12);
    // final double effectiveElevation = profile.active ? 12 : 4;
    // final effectiveOutlineColor = profile.active ? theme.colorScheme.outline : Colors.transparent;
    return Theme(
      data: theme,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _profileCardSurface(
            blizzard && isMain,
            Card(
              // margin: effectiveMargin,
              // elevation: effectiveElevation,
              margin: margin,
              shape: RoundedRectangleBorder(
                side: blizzard && isMain
                    ? BorderSide.none
                    : profile.active
                    ? BorderSide(color: blizzard ? BlizzardPalette.glassEdge : theme.colorScheme.outline)
                    : BorderSide.none,
                borderRadius: blizzard ? BorderRadius.circular(BlizzardRadii.card) : ProfileTileConst.cardBorderRadius,
              ),
              color: blizzard ? Colors.transparent : null,
              // color: color ?? theme.colorScheme.secondaryContainer,
              elevation: profile.active ? 0 : (blizzard ? 0 : 1),

              // shadowColor: Colors.transparent,
              child: IntrinsicHeight(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: blizzard ? (isMain ? 76 : 96) : 48),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showActionButton) ...[
                        if (!(blizzard && isMain)) ...[
                          SizedBox(
                            width: 48,
                            child: Semantics(
                              sortKey: const OrdinalSortKey(1),
                              child: ProfileActionButton(profile, !isMain),
                            ),
                          ),
                          if (profile.active)
                            VerticalDivider(width: 1, color: theme.colorScheme.outline)
                          else
                            const Gap(1),
                        ],
                      ],
                      Expanded(
                        child: Semantics(
                          button: true,
                          sortKey: isMain ? const OrdinalSortKey(0) : null,
                          focused: isMain,
                          liveRegion: isMain,
                          namesRoute: isMain,
                          label: isMain ? t.pages.profiles.viewAllProfiles : null,
                          child: InkWell(
                            borderRadius: showActionButton
                                ? (blizzard
                                      ? const BorderRadiusDirectional.horizontal(
                                          end: Radius.circular(BlizzardRadii.card),
                                        ).resolve(Directionality.of(context))
                                      : ProfileTileConst.endBorderRadius(Directionality.of(context)))
                                : (blizzard
                                      ? BorderRadius.circular(BlizzardRadii.card)
                                      : ProfileTileConst.cardBorderRadius),
                            onTap: () {
                              if (isMain) {
                                if (Breakpoint(context).isMobile()) {
                                  ref.read(bottomSheetsNotifierProvider.notifier).showProfilesOverview();
                                } else {
                                  context.goNamed('profiles');
                                }
                              } else {
                                if (selectActiveMutation.state.isInProgress) return;
                                // if (profile.active) return;
                                selectActiveMutation.setFuture(
                                  ref.read(profilesNotifierProvider.notifier).selectActiveProfile(profile.id),
                                );
                                if (context.canPop()) {
                                  context.pop();
                                } else {
                                  context.goNamed('home');
                                }
                              }
                            },
                            child: Row(
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: blizzard && isMain ? 16 : 12,
                                      vertical: blizzard && !isMain ? 8 : 4,
                                    ),
                                    child: Column(
                                      // mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (isMain)
                                          if (blizzard)
                                            Text(
                                              profile.name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.titleMedium?.copyWith(
                                                fontFamily: PlatformUtils.isWindows ? FontFamily.emoji : null,
                                              ),
                                              semanticsLabel: t.pages.profiles.activeProfileName(name: profile.name),
                                            )
                                          else
                                            Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 4),
                                              child: Material(
                                                borderRadius: BorderRadius.circular(8),
                                                color: Colors.transparent,
                                                clipBehavior: Clip.antiAlias,
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        profile.name,
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: theme.textTheme.titleMedium?.copyWith(
                                                          fontFamily: PlatformUtils.isWindows ? FontFamily.emoji : null,
                                                        ),
                                                        semanticsLabel: t.pages.profiles.activeProfileName(
                                                          name: profile.name,
                                                        ),
                                                      ),
                                                    ),
                                                    const BlizzardSystemSymbol(icon: Icons.arrow_drop_down_rounded),
                                                  ],
                                                ),
                                              ),
                                            )
                                        else
                                          Text(
                                            profile.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: (blizzard ? theme.textTheme.bodyLarge : theme.textTheme.titleMedium)
                                                ?.copyWith(
                                                  fontFamily: PlatformUtils.isWindows ? FontFamily.emoji : null,
                                                ),
                                            semanticsLabel: profile.active
                                                ? t.pages.profiles.activeProfileName(name: profile.name)
                                                : t.pages.profiles.nonActiveProfileName(name: profile.name),
                                          ),
                                        if (subInfo != null) ...[
                                          if (!(blizzard && isMain)) ...[
                                            const Gap(4),
                                            if (subInfo.hasFiniteTrafficLimit)
                                              RemainingTrafficIndicator(subInfo.ratio)
                                            else
                                              const SizedBox(height: 6),
                                          ],
                                          const Gap(4),
                                          ProfileSubscriptionInfo(subInfo, inline: blizzard),
                                          if (!(blizzard && isMain)) const Gap(4),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                if (showActionButton && blizzard && isMain)
                                  SizedBox(
                                    width: 40,
                                    child: Semantics(
                                      sortKey: const OrdinalSortKey(1),
                                      child: ProfileActionButton(profile, !isMain),
                                    ),
                                  ),
                                if (blizzard && isMain)
                                  const Padding(
                                    padding: EdgeInsetsDirectional.only(end: 12),
                                    child: Icon(Icons.arrow_forward_ios, size: 16),
                                  ),
                                if (blizzard && !isMain)
                                  const Padding(
                                    padding: EdgeInsetsDirectional.only(end: 12),
                                    child: BlizzardSystemSymbol(icon: Icons.arrow_drop_down_rounded, size: 20),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (ProfileTileConst.showProviderLinks && isMain)
            if (profile case RemoteProfileEntity(:final webPageUrl, :final supportUrl))
              ProfileLinkButtons(webPageUrl: webPageUrl, supportUrl: supportUrl),
        ],
      ),
    );
  }
}

class ProfileActionButton extends HookConsumerWidget {
  const ProfileActionButton(this.profile, this.showAllActions, {super.key, this.squareBottom = false});

  final ProfileEntity profile;
  final bool showAllActions;

  /// Zeroes this button's bottom corner, matching the card when a link chip
  /// is attached flush below it.
  final bool squareBottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final update = ref.watch(updateProfileNotifierProvider(profile.id));
    final isUpdating = update.isLoading;
    // Success/failure flash is derived straight from the provider state, which
    // UpdateProfileNotifier holds for 2s then resets. It lives in the provider
    // (not widget state), so it survives the list re-sorting after an update.
    final bool? outcome = isUpdating
        ? null
        : update.hasError
        ? false
        : (update.value != null ? true : null);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      // drive(), not CurvedAnimation: the switcher calls this builder again on every rebuild,
      // and a CurvedAnimation registers itself on the switcher's controller and is never
      // disposed, so every rebuild of the tile leaked two of them for good.
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation.drive(CurveTween(curve: const Interval(0, 0.6, curve: Curves.easeOut))),
        child: ScaleTransition(
          scale: animation.drive(CurveTween(curve: Curves.easeOutBack)),
          child: child,
        ),
      ),
      // Expand children so the interactive leading keeps its full tap target.
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [...previousChildren, if (currentChild != null) currentChild],
      ),
      child: _leading(context, ref, t, isUpdating, outcome),
    );
  }

  /// The current leading content. Each state carries a distinct key so the
  /// [AnimatedSwitcher] cross-fades between them.
  Widget _leading(BuildContext context, WidgetRef ref, TranslationsEn t, bool isUpdating, bool? outcome) {
    final theme = BlizzardPresentation.themeOf(context);
    final blizzard =
        BlizzardPresentation.isActive(context) || (theme.extension<BlizzardEligibility>()?.applied ?? false);
    final direction = Directionality.of(context);
    const radius = Radius.circular(BlizzardRadii.card);
    final startRadius = blizzard
        ? BorderRadiusDirectional.only(
            topStart: radius,
            bottomStart: squareBottom ? Radius.zero : radius,
          ).resolve(direction)
        : ProfileTileConst.startBorderRadius(direction, squareBottom: squareBottom);
    if (profile case RemoteProfileEntity()) {
      // While updating, the leading is a spinning indicator; its action is blocked.
      if (isUpdating) {
        return Semantics(
          key: const ValueKey('updating'),
          label: t.pages.profiles.update,
          liveRegion: true,
          child: Tooltip(message: t.pages.profiles.update, child: const _UpdatingIndicator()),
        );
      }

      // Transient success/failure feedback shown for 2s right after the spinner.
      if (outcome case final success?) {
        return Semantics(
          key: ValueKey(success),
          label: success ? t.pages.profiles.msg.update.success : t.pages.profiles.msg.update.failure,
          liveRegion: true,
          child: Icon(
            success ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
            color: success ? Colors.green : Theme.of(context).colorScheme.error,
          ),
        );
      }

      if (!showAllActions) {
        return Semantics(
          key: const ValueKey('update'),
          button: true,
          child: Tooltip(
            message: t.pages.profiles.update,
            child: InkWell(
              borderRadius: startRadius,
              onTap: () => ref
                  .read(updateProfileNotifierProvider(profile.id).notifier)
                  .updateProfile(profile as RemoteProfileEntity),
              child: const Icon(Icons.sync_rounded),
            ),
          ),
        );
      }
    }
    return ProfileActionsMenu(profile, (context, toggleVisibility, _) {
      return Semantics(
        button: true,
        child: Tooltip(
          message: MaterialLocalizations.of(context).showMenuTooltip,
          child: InkWell(
            borderRadius: startRadius,
            onTap: toggleVisibility,
            child: BlizzardSystemSymbol(
              icon: blizzard ? Icons.more_vert_rounded : AdaptiveIcon(context).more,
              color: blizzard ? theme.colorScheme.onSurfaceVariant : null,
            ),
          ),
        ),
      );
    }, key: const ValueKey('menu'));
  }
}

/// A minimal, continuously spinning icon shown in the leading slot while a
/// remote profile is being updated.
class _UpdatingIndicator extends StatefulWidget {
  const _UpdatingIndicator();

  @override
  State<_UpdatingIndicator> createState() => _UpdatingIndicatorState();
}

class _UpdatingIndicatorState extends State<_UpdatingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))
    ..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // the spin repaints the icon alone, not the tile
    return RepaintBoundary(
      child: RotationTransition(
        turns: ReverseAnimation(_controller),
        child: Icon(Icons.sync_rounded, color: Theme.of(context).colorScheme.onSurface),
      ),
    );
  }
}

class ProfileActionsMenu extends HookConsumerWidget {
  const ProfileActionsMenu(this.profile, this.builder, {super.key, this.child});

  final ProfileEntity profile;
  final AdaptiveMenuBuilder builder;
  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    final menuItems = [
      AdaptiveMenuItem(
        title: profile.pinned ? t.common.unpin : t.common.pin,
        leadingIcon: Icon(profile.pinned ? Icons.push_pin : Icons.push_pin_outlined),
        onTap: () => ref.read(profilesNotifierProvider.notifier).togglePin(profile),
      ),
      if (profile case RemoteProfileEntity())
        AdaptiveMenuItem(
          title: t.common.update,
          leadingIcon: const Icon(Icons.sync_rounded),
          onTap: () {
            if (ref.read(updateProfileNotifierProvider(profile.id)).isLoading) {
              return;
            }
            ref.read(updateProfileNotifierProvider(profile.id).notifier).updateProfile(profile as RemoteProfileEntity);
          },
        ),
      AdaptiveMenuItem(
        title: t.common.share,
        leadingIcon: Icon(AdaptiveIcon(context).share),
        onTap: () async {
          final link = switch (profile) {
            RemoteProfileEntity(:final url, :final name) => LinkParser.generateSubShareLink(url, name),
            _ => '',
          };
          await ref
              .read(dialogNotifierProvider.notifier)
              .showShareProfile(
                name: profile.name,
                link: link.isEmpty ? null : link,
                loadConfig: () => ref.read(profilesNotifierProvider.notifier).generateConfig(profile),
              );
        },
      ),
      AdaptiveMenuItem(
        leadingIcon: const Icon(Icons.edit_rounded),
        title: t.common.edit,
        onTap: () {
          if (Breakpoint(context).isMobile()) context.pop();
          context.goNamed('profileDetails', pathParameters: {'id': profile.id});
        },
      ),
      AdaptiveMenuItem(
        leadingIcon: const Icon(Icons.delete_outline_rounded),
        title: t.common.delete,
        onTap: () async => await ref
            .read(dialogNotifierProvider.notifier)
            .showConfirmation(
              title: t.dialogs.confirmation.profile.delete.title,
              message: t.dialogs.confirmation.profile.delete.msg,
            )
            .then((deleteConfirmed) async {
              if (!deleteConfirmed) return;
              await ref.read(profilesNotifierProvider.notifier).deleteProfile(profile);
            }),
      ),
    ];

    return AdaptiveMenu(builder: builder, items: menuItems, child: child);
  }
}

/// Provider links from the `profile-web-page-url` / `support-url` subscription
/// headers, rendered as a single full-width pill below the main card.
///
/// One link fills the row as a static chip. Two links share the slot and
/// swap every few seconds: the current chip slides fully up and out, then
/// the next slides down from the top into place.
class ProfileLinkButtons extends HookConsumerWidget {
  const ProfileLinkButtons({super.key, this.webPageUrl, this.supportUrl});

  final String? webPageUrl;
  final String? supportUrl;

  /// Top-line label:
  /// - Telegram (`t.me` / `telegram.me`): the path after the host, which covers
  ///   every form — `hiddify`, `c/2681822178/1`, `joinchat/xxx`, `+xxx`.
  /// - GitHub: the provider (repo owner) — e.g. `barry-far`.
  /// - anything else: the domain.
  static String _value(String url) {
    final uri = Uri.parse(url);
    final host = uri.host.startsWith("www.") ? uri.host.substring(4) : uri.host;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    if (const ["t.me", "telegram.me"].contains(host)) {
      return segments.isEmpty ? host : segments.join("/");
    }
    if (host == "github.com" && segments.isNotEmpty) {
      return segments.first;
    }
    return host;
  }

  /// Brand icon for the link's platform (leading), or null for a generic site.
  static IconData? _leadingIcon(String url) {
    final host = Uri.parse(url).host;
    final bare = host.startsWith("www.") ? host.substring(4) : host;
    if (const ["t.me", "telegram.me"].contains(bare)) return SimpleIcons.telegram;
    if (bare == "github.com") return SimpleIcons.github;
    return null;
  }

  /// Confirm before opening a subscription-provided link. Curated/trusted links
  /// (see [TrustedLinks]) get a light confirmation; anything else gets a serious
  /// anti-impersonation warning with a countdown, so scammers can't pass off a
  /// look-alike channel/site as an official one.
  static Future<void> _confirmAndOpen(WidgetRef ref, TranslationsEn t, String url) async {
    final notifier = ref.read(dialogNotifierProvider.notifier);
    final bool confirmed;
    if (TrustedLinks.isTrusted(url)) {
      confirmed = await notifier.showConfirmation(
        title: t.components.subscriptionInfo.openLinkTitle,
        message: url,
        positiveBtnTxt: t.components.subscriptionInfo.openLinkAction,
      );
    } else {
      confirmed = await notifier.showUnknownDomainsWarning(url: url);
    }
    if (confirmed) await UriUtils.tryLaunch(Uri.parse(url));
  }

  static const _chipRadius = BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12));

  static Widget _chip(ThemeData theme, VoidCallback onTap, String url, String title) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainer,
      borderRadius: _chipRadius,
      border: Border(
        left: BorderSide(color: theme.colorScheme.outline),
        right: BorderSide(color: theme.colorScheme.outline),
        bottom: BorderSide(color: theme.colorScheme.outline),
      ),
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: _chipRadius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              if (_leadingIcon(url) case final icon?) ...[
                Icon(icon, size: 24, color: theme.colorScheme.onSurfaceVariant),
                const Gap(8),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    // const Gap(1),
                    Text(
                      _value(url),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurface),
                    ),
                  ],
                ),
              ),
              const Gap(4),
              Icon(Icons.open_in_new_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    final items = [
      if (webPageUrl case final url? when url.isNotEmpty) (url, t.components.subscriptionInfo.openWebPage),
      if (supportUrl case final url? when url.isNotEmpty) (url, t.components.subscriptionInfo.support),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    if (items.length == 1) {
      final (url, title) = items.single;
      return SizedBox(
        width: double.infinity,
        child: _chip(Theme.of(context), () => _confirmAndOpen(ref, t, url), url, title),
      );
    }
    return _LinkChipCarousel(items: items);
  }
}

/// Cycles [items] one at a time: holds for [holdDuration], slides fully out
/// upward over [slideDuration], swaps content while hidden, then slides the
/// next item down from the top into place.
class _LinkChipCarousel extends HookConsumerWidget {
  const _LinkChipCarousel({required this.items});

  final List<(String url, String title)> items;

  static const _holdDuration = Duration(seconds: 10);
  static const _slideDuration = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    final index = useState(0);
    final offset = useState(Offset.zero);
    // Paused while the confirmation dialog is open, so the chip doesn't swap
    // out from under the URL the user is reviewing.
    final paused = useState(false);

    useEffect(() {
      var active = true;
      Future<void> loop() async {
        while (active) {
          await Future.delayed(_holdDuration);
          while (active && paused.value) {
            await Future.delayed(const Duration(milliseconds: 200));
          }
          if (!active) return;
          offset.value = const Offset(0, -1);
          await Future.delayed(_slideDuration);
          if (!active) return;
          index.value = (index.value + 1) % items.length;
          offset.value = Offset.zero;
        }
      }

      loop();
      return () => active = false;
    }, [items.length]);

    final (url, title) = items[index.value];
    return SizedBox(
      width: double.infinity,
      child: ClipRect(
        child: AnimatedSlide(
          offset: offset.value,
          duration: _slideDuration,
          curve: Curves.easeInOut,
          child: ProfileLinkButtons._chip(
            theme,
            () async {
              paused.value = true;
              await ProfileLinkButtons._confirmAndOpen(ref, t, url);
              if (context.mounted) paused.value = false;
            },
            url,
            title,
          ),
        ),
      ),
    );
  }
}

class ProfileSubscriptionInfo extends HookConsumerWidget {
  const ProfileSubscriptionInfo(this.subInfo, {super.key, this.inline = false});

  final SubscriptionInfo subInfo;
  final bool inline;

  (String, Color?) remainingText(TranslationsEn t, ThemeData theme) {
    if (subInfo.isExpired) {
      return (t.components.subscriptionInfo.expired, theme.colorScheme.error);
    } else if (subInfo.hasFiniteTrafficLimit && subInfo.ratio >= 1) {
      return (t.components.subscriptionInfo.noTraffic, theme.colorScheme.error);
    } else if (subInfo.remaining.inDays > 365) {
      return (t.components.subscriptionInfo.remainingUnlimited, null);
    } else {
      return (t.components.subscriptionInfo.remainingDuration(days: subInfo.remaining.inDays), null);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    final remaining = remainingText(t, theme);
    final traffic = subInfo.hasFiniteTrafficLimit
        ? subInfo.consumption.sizeOf(subInfo.total)
        : '${subInfo.consumption.sizeGB()} / —';
    final trafficSemantics = t.components.subscriptionInfo.remainingTrafficSemanticLabel(
      consumed: subInfo.consumption.sizeGB(),
      total: subInfo.hasFiniteTrafficLimit ? subInfo.total.sizeGB() : t.common.notSet,
    );
    if (inline) {
      return Text(
        '\u2066$traffic\u2069 · ${remaining.$1}',
        semanticsLabel: '$trafficSemantics, ${remaining.$1}',
        style: theme.textTheme.bodySmall?.copyWith(color: remaining.$2),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Directionality(
          textDirection: TextDirection.ltr,
          child: Flexible(
            child: Text(
              traffic,
              semanticsLabel: trafficSemantics,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        Flexible(
          child: Text(
            remaining.$1,
            style: theme.textTheme.bodySmall?.copyWith(color: remaining.$2),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// TODO change colors
class RemainingTrafficIndicator extends StatelessWidget {
  const RemainingTrafficIndicator(this.ratio, {super.key});

  final double ratio;

  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(value: ratio, borderRadius: BorderRadius.circular(16), minHeight: 6);
  }
}

Widget _profileCardSurface(bool glass, Widget child) =>
    glass ? BlizzardGlass(active: true, radius: BlizzardRadii.card, child: child) : child;
