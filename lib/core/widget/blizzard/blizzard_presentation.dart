import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Stable boundary: switching eligibility changes data, never the child location.
class BlizzardPresentation extends ConsumerWidget {
  const BlizzardPresentation({super.key, required this.child});
  final Widget child;

  /// Lets host-side tests and render scripts exercise the iOS presentation.
  @visibleForTesting
  static bool debugAssumeIOS = false;

  static bool isActive(BuildContext context) {
    final theme = Theme.of(context);
    return blizzardVisuals &&
        (PlatformUtils.isIOS || (!kReleaseMode && debugAssumeIOS)) &&
        Breakpoint(context).isMobile() &&
        theme.extension<BlizzardEligibility>() != null;
  }

  static ThemeData themeOf(BuildContext context) {
    final theme = Theme.of(context);
    if (!isActive(context) || (theme.extension<BlizzardEligibility>()?.applied ?? false)) return theme;
    return BlizzardTheme.from(
      theme,
      highContrast: MediaQuery.highContrastOf(context),
      menuStyle: BlizzardMenuStyleScope.of(context),
    );
  }

  static BlizzardMenuStyle watchMenuStyle(WidgetRef ref) =>
      ref.watch(sharedPreferencesProvider).hasValue ? ref.watch(Preferences.menuStyle) : BlizzardMenuStyle.neutral;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = BlizzardMenuStyleScope.maybeOf(context) ?? watchMenuStyle(ref);
    final highContrast = MediaQuery.highContrastOf(context);
    final base = Theme.of(context);
    final applied = base.extension<BlizzardEligibility>()?.applied ?? false;
    final active = applied || isActive(context);
    final theme = applied
        ? BlizzardTheme.withPopupStyle(base, menuStyle: style, highContrast: highContrast)
        : active
        ? BlizzardTheme.from(base, menuStyle: style, highContrast: highContrast)
        : base;
    return BlizzardMenuStyleScope(
      style: style,
      child: Theme(
        data: theme,
        child: BlizzardPopupRouteTheme(enabled: active, child: child),
      ),
    );
  }
}

/// Material routes that would fade the paint of an Aurora surface present it
/// immediately. A route with a geometric transition can keep it.
abstract final class BlizzardPopupTransition {
  static AnimationStyle? styleOf(BuildContext context, {bool alreadyOpaque = false}) {
    if (MediaQuery.disableAnimationsOf(context)) return AnimationStyle.noAnimation;
    if (alreadyOpaque) return null;
    final applied = Theme.of(context).extension<BlizzardEligibility>()?.applied ?? false;
    return applied || BlizzardPresentation.isActive(context) ? AnimationStyle.noAnimation : null;
  }
}

/// Flutter captures inherited themes when pushing a popup. Reapply the popup
/// palette in the route, where the preference and MediaQuery are still live.
class BlizzardPopupRouteTheme extends InheritedTheme {
  const BlizzardPopupRouteTheme({super.key, required this.enabled, required super.child});

  final bool enabled;

  @override
  Widget wrap(BuildContext context, Widget child) => enabled ? BlizzardPresentation(child: child) : child;

  @override
  bool updateShouldNotify(BlizzardPopupRouteTheme oldWidget) => enabled != oldWidget.enabled;
}
