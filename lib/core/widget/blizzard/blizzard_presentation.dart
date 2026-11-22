import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
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
    return BlizzardTheme.from(theme, highContrast: MediaQuery.highContrastOf(context));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The theme reads the selected style while it is built, so a change applies at once.
    final style = ref.watch(Preferences.menuStyle);
    BlizzardMenuStyleSwitch.value = style;
    return BlizzardMenuStyleScope(
      style: style,
      child: Theme(data: themeOf(context), child: child),
    );
  }
}
