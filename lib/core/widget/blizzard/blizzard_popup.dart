import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_scene_glass.dart';

enum BlizzardPopupRole { sheet, menu }

/// Paints one opaque material for the entire popup.
class BlizzardPopupMaterial extends StatelessWidget {
  const BlizzardPopupMaterial({super.key, required this.child, required this.radius, required this.role});

  final Widget child;
  final double radius;
  final BlizzardPopupRole role;

  @override
  Widget build(BuildContext context) => BlizzardSceneGlass(
    radius: radius,
    tint: switch (role) {
      BlizzardPopupRole.sheet => BlizzardPopupGlass.sheetTint,
      BlizzardPopupRole.menu => BlizzardPopupGlass.menuTint,
    },
    child: Material(type: MaterialType.transparency, child: child),
  );
}

/// A Material alert whose surface follows the selected Aurora popup style.
class BlizzardAlertDialog extends StatelessWidget {
  const BlizzardAlertDialog({
    super.key,
    this.icon,
    this.title,
    this.content,
    this.actions,
    this.titlePadding,
    this.contentPadding,
    this.insetPadding,
    this.accentLast = true,
  });

  final Widget? icon;
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? titlePadding;
  final EdgeInsetsGeometry? contentPadding;
  final EdgeInsets? insetPadding;
  final bool accentLast;

  @override
  Widget build(BuildContext context) {
    final applied = Theme.of(context).extension<BlizzardEligibility>()?.applied ?? false;
    final buttonStyle = TextButtonTheme.of(context).style ?? const ButtonStyle();
    final secondary = buttonStyle.copyWith(
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? buttonStyle.foregroundColor?.resolve(states)
            : BlizzardPalette.secondary,
      ),
    );

    return _BlizzardAlertLayout(
      applied: applied,
      icon: icon,
      title: title,
      content: applied && content != null
          ? ListTileTheme.merge(tileColor: Colors.transparent, selectedTileColor: Colors.transparent, child: content!)
          : content,
      actions: applied && actions != null
          ? [
              for (var i = 0; i < actions!.length; i++)
                if (accentLast && i == actions!.length - 1)
                  actions![i]
                else
                  TextButtonTheme(
                    data: TextButtonThemeData(style: secondary),
                    child: actions![i],
                  ),
            ]
          : actions,
      titlePadding: titlePadding,
      contentPadding: contentPadding,
      insetPadding: insetPadding,
    );
  }
}

class _BlizzardAlertLayout extends AlertDialog {
  const _BlizzardAlertLayout({
    required this.applied,
    super.icon,
    super.title,
    super.content,
    super.actions,
    super.titlePadding,
    super.contentPadding,
    super.insetPadding,
  });

  final bool applied;

  @override
  Widget build(BuildContext context) {
    final dialog = super.build(context);
    if (!applied) return dialog;

    // AlertDialog builds a Dialog in the pinned Flutter SDK. Reuse its laid-out
    // child (including alert semantics, focus, and scrolling) inside the surface.
    final material = dialog as Dialog;
    final highContrast = MediaQuery.highContrastOf(context);
    final glass = !highContrast && BlizzardMenuStyleScope.of(context) == BlizzardMenuStyle.glass;
    return Dialog(
      backgroundColor: glass
          ? Colors.transparent
          : highContrast
          ? BlizzardPalette.background
          : BlizzardPalette.sheet,
      elevation: glass ? 0 : material.elevation,
      shadowColor: material.shadowColor,
      surfaceTintColor: Colors.transparent,
      insetPadding: material.insetPadding,
      clipBehavior: material.clipBehavior,
      shape: material.shape,
      alignment: material.alignment,
      constraints: material.constraints,
      semanticsRole: material.semanticsRole,
      child: BlizzardSceneGlass(
        radius: BlizzardRadii.dialog,
        tint: BlizzardPopupGlass.dialogTint,
        drawSolidBorder: false,
        child: material.child!,
      ),
    );
  }
}
