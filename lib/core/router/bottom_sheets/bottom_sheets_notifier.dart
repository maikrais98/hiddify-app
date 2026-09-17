import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/bottom_sheets/widgets/auto_apps_selection_modal.dart';
import 'package:hiddify/core/router/bottom_sheets/widgets/quick_settings_modal.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/features/per_app_proxy/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/profile/add/add_profile_modal.dart';
import 'package:hiddify/features/profile/overview/profiles_modal.dart';
import 'package:hiddify/features/route_rules/overview/predefined_rules_modal.dart';

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'bottom_sheets_notifier.g.dart';

String? _deepLinkImportSourceHost(String deepLink) {
  try {
    final wrapper = Uri.tryParse(deepLink.trim());
    if (wrapper == null) return null;

    var source = wrapper.queryParameters['url'];
    if ((source == null || source.isEmpty) && wrapper.path.length > 1) {
      source = wrapper.path.substring(1) + (wrapper.hasQuery ? '?${wrapper.query}' : '');
    }

    if (source == null || source.isEmpty) return null;
    final sourceUri = Uri.tryParse(source.trim());
    if (sourceUri == null || !sourceUri.hasAuthority || sourceUri.host.isEmpty) return null;
    return sourceUri.host;
  } on FormatException {
    return null;
  }
}

class ThemedBottomSheetSurface extends StatelessWidget {
  const ThemedBottomSheetSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BottomSheetConst.borderRadius,
      child: Material(
        key: const ValueKey('themed_bottom_sheet_material'),
        color: theme.bottomSheetTheme.modalBackgroundColor ?? theme.colorScheme.surface,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: child,
        ),
      ),
    );
  }
}

@riverpod
class BottomSheetsNotifier extends _$BottomSheetsNotifier {
  @override
  void build() {}

  Future<T?> _show<T>({required Widget child, required bool isScrollControlled}) async {
    final context = rootNavKey.currentContext;
    if (context == null) return null;
    // ref.read(popupCountNotifierProvider.notifier).increase();
    return await Navigator.of(context)
        .push<T>(
          ModalBottomSheetRoute(
            constraints: BottomSheetConst.boxConstraints,
            isScrollControlled: isScrollControlled,
            builder: (context) => ThemedBottomSheetSurface(child: child),
          ),
        )
        .then((value) {
          // ref.read(popupCountNotifierProvider.notifier).decrease();
          return value;
        });
  }

  Future<T?> _showPage<T>(Widget child) async {
    final context = rootNavKey.currentContext;
    if (context == null) return null;
    return Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => child, fullscreenDialog: true));
  }

  Future<void> showAddProfile({String? url, bool triggeredByDeepLink = false}) async {
    if (url != null && triggeredByDeepLink) {
      // Preventing Zero-click SSRF
      final t = ref.watch(translationsProvider).requireValue;
      final isConfirmed = await ref
          .read(dialogNotifierProvider.notifier)
          .showConfirmation(
            title: t.dialogs.confirmation.addProfileByDeepLinkWarning.title,
            message: t.dialogs.confirmation.addProfileByDeepLinkWarning.message(
              host: _deepLinkImportSourceHost(url) ?? t.common.unknown,
            ),
            positiveBtnTxt: t.common.import,
          );
      if (isConfirmed) {
        await _showPage(AddProfileModal(url: url));
      }
    } else {
      await _showPage(AddProfileModal(url: url));
    }
  }

  Future<void> showProfilesOverview() async => await _show(isScrollControlled: true, child: const ProfilesModal());

  Future<void> showQuickSettings() async => await _show(isScrollControlled: false, child: const QuickSettingsModal());

  Future<void> showAutoAppsSelection({required AppProxyMode mode}) async =>
      await _show(isScrollControlled: false, child: AutoAppsSelectionModal(mode: mode));

  Future<void> showPredefinedRules() async =>
      await _show(isScrollControlled: true, child: const PredefinedRulesModal());
}
