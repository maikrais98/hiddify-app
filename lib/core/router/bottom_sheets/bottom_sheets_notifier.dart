import 'package:flutter/material.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/bottom_sheets/widgets/auto_apps_selection_modal.dart';
import 'package:hiddify/core/router/bottom_sheets/widgets/quick_settings_modal.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_glass.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_presentation.dart';
import 'package:hiddify/features/per_app_proxy/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/profile/add/add_profile_modal.dart';
import 'package:hiddify/features/profile/overview/profiles_modal.dart';

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'bottom_sheets_notifier.g.dart';

@riverpod
class BottomSheetsNotifier extends _$BottomSheetsNotifier {
  @override
  void build() {}

  Future<T?> _show<T>({required Widget child, required bool isScrollControlled, bool useBlizzardSheet = false}) async {
    final context = rootNavKey.currentContext;
    if (context == null) return null;
    final blizzard = useBlizzardSheet && BlizzardPresentation.isActive(context);
    // ref.read(popupCountNotifierProvider.notifier).increase();
    return await Navigator.of(context)
        .push<T>(
          ModalBottomSheetRoute(
            constraints: BottomSheetConst.boxConstraints,
            isScrollControlled: isScrollControlled,
            backgroundColor: blizzard ? Colors.transparent : null,
            shape: blizzard ? const RoundedRectangleBorder(borderRadius: BottomSheetConst.borderRadius) : null,
            clipBehavior: blizzard ? Clip.none : null,
            builder: (context) {
              final surface = _BottomSheetSurface(blizzard: blizzard, child: child);
              return blizzard ? BlizzardPresentation(child: surface) : surface;
            },
          ),
        )
        .then((value) {
          // ref.read(popupCountNotifierProvider.notifier).decrease();
          return value;
        });
  }

  Future<void> showAddProfile({String? url}) async =>
      await _show(isScrollControlled: true, useBlizzardSheet: true, child: AddProfileModal(url: url));

  Future<void> showProfilesOverview() async =>
      await _show(isScrollControlled: true, useBlizzardSheet: true, child: const ProfilesModal());

  Future<void> showQuickSettings() async =>
      await _show(isScrollControlled: false, useBlizzardSheet: true, child: const QuickSettingsModal());
  Future<void> showAutoAppsSelection({required AppProxyMode mode}) async =>
      await _show(isScrollControlled: false, child: AutoAppsSelectionModal(mode: mode));
}

class _BottomSheetSurface extends StatelessWidget {
  const _BottomSheetSurface({required this.child, required this.blizzard});

  final Widget child;
  final bool blizzard;

  @override
  Widget build(BuildContext context) {
    final content = Material(
      type: blizzard ? MaterialType.transparency : MaterialType.canvas,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: child,
      ),
    );
    if (!blizzard) {
      return ClipRRect(borderRadius: BottomSheetConst.borderRadius, child: content);
    }
    return BlizzardGlass(
      active: true,
      radius: BottomSheetConst.borderRadius.topLeft.x,
      contentSurface: true,
      child: content,
    );
  }
}
