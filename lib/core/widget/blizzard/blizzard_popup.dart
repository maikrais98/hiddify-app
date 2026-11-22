import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';

enum BlizzardPopupRole { sheet, menu }

/// Marks content that sits on a glass popup, so its plates can be a little denser than the glass.
class BlizzardGlassPopupScope extends InheritedWidget {
  const BlizzardGlassPopupScope({super.key, this.active = true, required super.child});
  final bool active;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BlizzardGlassPopupScope>()?.active ?? false;

  @override
  bool updateShouldNotify(BlizzardGlassPopupScope oldWidget) => active != oldWidget.active;
}

/// Paints a single material for the popup. The glass uses Flutter's compositor
/// so the popup never needs a native platform view.
class BlizzardPopupMaterial extends StatelessWidget {
  const BlizzardPopupMaterial({super.key, required this.child, required this.radius, required this.role});

  final Widget child;
  final double radius;
  final BlizzardPopupRole role;

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.highContrastOf(context);
    final shape = BorderRadius.circular(radius);
    final content = Material(type: MaterialType.transparency, child: child);
    if (highContrast || BlizzardMenuStyleScope.of(context) != BlizzardMenuStyle.glass) {
      return ClipRRect(
        borderRadius: shape,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: highContrast ? BlizzardPalette.background : BlizzardPalette.sheet,
            borderRadius: shape,
            border: Border.all(color: highContrast ? BlizzardPalette.secondary : BlizzardPalette.separator),
          ),
          child: content,
        ),
      );
    }
    final tint = switch (role) {
      BlizzardPopupRole.sheet => BlizzardPopupGlass.sheetTint,
      BlizzardPopupRole.menu => BlizzardPopupGlass.menuTint,
    };
    return _PopupBackdrop(radius: radius, tint: tint, enabled: true, child: content);
  }
}

class _PopupBackdrop extends StatelessWidget {
  const _PopupBackdrop({required this.radius, required this.tint, required this.enabled, required this.child});

  final double radius;
  final Color tint;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    clipBehavior: enabled ? Clip.antiAlias : Clip.none,
    child: BackdropFilter(
      enabled: enabled,
      filter: ui.ImageFilter.blur(sigmaX: BlizzardPopupGlass.blur, sigmaY: BlizzardPopupGlass.blur),
      child: DecoratedBox(
        decoration: BoxDecoration(color: enabled ? tint : Colors.transparent),
        child: CustomPaint(
          foregroundPainter: enabled ? _PopupEdgePainter(radius) : null,
          child: BlizzardGlassPopupScope(active: enabled, child: child),
        ),
      ),
    ),
  );
}

class _PopupEdgePainter extends CustomPainter {
  const _PopupEdgePainter(this.radius);
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius((Offset.zero & size).deflate(0.5), Radius.circular(radius));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height.clamp(1, 160)), [
        BlizzardPopupGlass.edgeTop,
        BlizzardPopupGlass.edgeSide,
      ]);
    canvas.drawRRect(rect, paint);
    paint.shader!.dispose();
  }

  @override
  bool shouldRepaint(covariant _PopupEdgePainter oldDelegate) => oldDelegate.radius != radius;
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
      child: _PopupBackdrop(
        radius: BlizzardRadii.dialog,
        tint: BlizzardPopupGlass.dialogTint,
        enabled: glass,
        child: material.child!,
      ),
    );
  }
}
