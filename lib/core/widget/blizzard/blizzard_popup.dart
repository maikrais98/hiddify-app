import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';

enum BlizzardPopupRole { sheet, menu, dialog }

/// Marks content that sits on a glass popup, so its plates can be a little denser than the glass.
class BlizzardGlassPopupScope extends InheritedWidget {
  const BlizzardGlassPopupScope({super.key, required super.child});

  static bool of(BuildContext context) => context.getInheritedWidgetOfExactType<BlizzardGlassPopupScope>() != null;

  @override
  bool updateShouldNotify(BlizzardGlassPopupScope oldWidget) => false;
}

/// The one material of a sheet, a menu or a dialog while a candidate style is selected
/// ([BlizzardMenuStyleSwitch]): variant A is the neutral opaque sheet material, variant B is
/// Flutter backdrop-blur glass. Flutter glass only: popups must never create a platform view.
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
    if (highContrast || BlizzardMenuStyleSwitch.of(context) != BlizzardMenuStyle.glass) {
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
      BlizzardPopupRole.dialog => BlizzardPopupGlass.dialogTint,
    };
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: BlizzardPopupGlass.blur, sigmaY: BlizzardPopupGlass.blur),
        child: DecoratedBox(
          decoration: BoxDecoration(color: tint),
          child: CustomPaint(
            foregroundPainter: _PopupEdgePainter(radius),
            child: BlizzardGlassPopupScope(child: content),
          ),
        ),
      ),
    );
  }
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

/// An AlertDialog that follows the selected popup style. In the shipped style it is the
/// plain AlertDialog; in variant A the theme alone restyles it; in variant B it draws its own glass.
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

  /// Variants A and B keep one accent action: the last button. A dialog whose last button is
  /// only "cancel" turns this off.
  final bool accentLast;

  @override
  Widget build(BuildContext context) {
    final applied = Theme.of(context).extension<BlizzardEligibility>()?.applied ?? false;
    if ((BlizzardMenuStyleSwitch.of(context) == BlizzardMenuStyle.current) || !applied) {
      return AlertDialog(
        icon: icon,
        title: title,
        content: content,
        actions: actions,
        titlePadding: titlePadding,
        contentPadding: contentPadding,
        insetPadding: insetPadding ?? const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      );
    }
    // Rows inside a dialog sit directly on its material, not on the bluish list-tile fill.
    final neutralContent = content == null
        ? null
        : ListTileTheme.merge(tileColor: Colors.transparent, selectedTileColor: Colors.transparent, child: content!);
    final styledActions = actions == null
        ? null
        : [
            for (var i = 0; i < actions!.length; i++)
              if (accentLast && i == actions!.length - 1)
                actions![i]
              else
                TextButtonTheme(
                  data: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: BlizzardPalette.secondary)),
                  child: actions![i],
                ),
          ];
    if (BlizzardMenuStyleSwitch.of(context) != BlizzardMenuStyle.glass || MediaQuery.highContrastOf(context)) {
      return AlertDialog(
        icon: icon,
        title: title,
        content: neutralContent,
        actions: styledActions,
        titlePadding: titlePadding,
        contentPadding: contentPadding,
        insetPadding: insetPadding ?? const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      );
    }
    final theme = Theme.of(context);
    final hasActions = styledActions != null && styledActions.isNotEmpty;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      insetPadding: insetPadding ?? const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 280),
        child: BlizzardPopupMaterial(
          radius: BlizzardRadii.dialog,
          role: BlizzardPopupRole.dialog,
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (icon != null || title != null)
                  Padding(
                    padding: titlePadding ?? const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: Column(
                      crossAxisAlignment: icon != null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                      children: [
                        if (icon != null)
                          IconTheme(
                            data: IconThemeData(color: theme.colorScheme.secondary, size: 24),
                            child: icon!,
                          ),
                        if (title != null) DefaultTextStyle(style: theme.textTheme.titleLarge!, child: title!),
                      ],
                    ),
                  ),
                if (content != null)
                  Flexible(
                    child: Padding(
                      padding: contentPadding ?? const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      child: DefaultTextStyle(style: theme.textTheme.bodyLarge!, child: neutralContent!),
                    ),
                  ),
                if (hasActions)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: OverflowBar(
                        alignment: MainAxisAlignment.end,
                        spacing: 8,
                        overflowSpacing: 4,
                        children: styledActions,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
