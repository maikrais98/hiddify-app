import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_presentation.dart';

/// Shows Aurora's tooltip surface without fading the surrounding page into it.
class BlizzardTooltip extends StatelessWidget {
  const BlizzardTooltip({super.key, required String this.message, this.verticalOffset, required this.child});

  /// Retains the button's own localized tooltip semantics.
  const BlizzardTooltip.button({super.key, required this.child}) : message = null, verticalOffset = null;

  final String? message;
  final double? verticalOffset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final label =
        message ??
        switch (child) {
          BackButton() => MaterialLocalizations.of(context).backButtonTooltip,
          CloseButton() => MaterialLocalizations.of(context).closeButtonTooltip,
          IconButton(:final tooltip) => tooltip,
          PopupMenuButton<Object?>(:final tooltip) => tooltip ?? MaterialLocalizations.of(context).showMenuTooltip,
          FloatingActionButton(:final tooltip) => tooltip,
          _ => null,
        };
    final anchor = message == null ? child : Tooltip(message: message, verticalOffset: verticalOffset, child: child);
    final applied = Theme.of(context).extension<BlizzardEligibility>()?.applied ?? false;
    if (label == null ||
        label.isEmpty ||
        !TooltipVisibility.of(context) ||
        (!applied && !BlizzardPresentation.isActive(context))) {
      return anchor;
    }
    return _InstantTooltip(
      message: label,
      verticalOffset: verticalOffset,
      // TooltipVisibility keeps the label on the trigger for screen readers.
      child: TooltipVisibility(visible: false, child: anchor),
    );
  }
}

extension BlizzardButtonTooltip on Widget {
  Widget withBlizzardTooltip() => BlizzardTooltip.button(child: this);
}

class _InstantTooltip extends StatefulWidget {
  const _InstantTooltip({required this.message, required this.verticalOffset, required this.child});

  final String message;
  final double? verticalOffset;
  final Widget child;

  @override
  State<_InstantTooltip> createState() => _InstantTooltipState();
}

class _InstantTooltipState extends State<_InstantTooltip> {
  final _overlay = OverlayPortalController();
  Timer? _timer;
  bool _watchingPointer = false;
  bool _hovering = false;
  bool _holding = false;

  void _watchPointer() {
    if (_watchingPointer) return;
    _watchingPointer = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handlePointer);
  }

  void _stopWatchingInput() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleKey);
    if (!_watchingPointer) return;
    _watchingPointer = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_handlePointer);
  }

  void _handlePointer(PointerEvent event) {
    if (event is PointerDownEvent) _hide();
  }

  KeyEventResult _handleKey(KeyEvent event) {
    if (!_overlay.isShowing ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    _hide();
    return KeyEventResult.handled;
  }

  void _show() {
    _timer?.cancel();
    _watchPointer();
    if (!_overlay.isShowing) FocusManager.instance.addEarlyKeyEventHandler(_handleKey);
    _overlay.show();
  }

  void _hide() {
    _timer?.cancel();
    _stopWatchingInput();
    _overlay.hide();
  }

  void _delay(Duration duration, VoidCallback callback) {
    _timer?.cancel();
    if (duration == Duration.zero) {
      callback();
    } else {
      _timer = Timer(duration, callback);
    }
  }

  void _longPress() {
    _holding = true;
    _show();
    if (TooltipTheme.of(context).enableFeedback ?? true) Feedback.forLongPress(context);
  }

  void _release() {
    _holding = false;
    if (!_hovering) _delay(TooltipTheme.of(context).showDuration ?? const Duration(milliseconds: 1500), _hide);
  }

  void _enter(PointerEnterEvent event) {
    _hovering = true;
    _watchPointer();
    _delay(TooltipTheme.of(context).waitDuration ?? Duration.zero, _show);
  }

  void _exit(PointerExitEvent event) {
    _hovering = false;
    if (!_holding) {
      _delay(TooltipTheme.of(context).exitDuration ?? const Duration(milliseconds: 100), _hide);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopWatchingInput();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OverlayPortal.overlayChildLayoutBuilder(
    controller: _overlay,
    overlayChildBuilder: (context, layout) {
      if (layout.childPaintTransform.determinant() == 0) return const SizedBox.shrink();
      final theme = BlizzardTheme.tooltipStyle(Theme.of(context), highContrast: MediaQuery.highContrastOf(context));
      final target = MatrixUtils.transformPoint(layout.childPaintTransform, layout.childSize.center(Offset.zero));
      return Positioned.fill(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: CustomSingleChildLayout(
              delegate: _TooltipPosition(
                target: target,
                verticalOffset: widget.verticalOffset ?? theme.verticalOffset ?? 24,
                preferBelow: theme.preferBelow ?? true,
              ),
              child: Container(
                constraints: theme.constraints ?? const BoxConstraints(minHeight: 32),
                decoration: theme.decoration,
                padding: theme.padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Text(widget.message, style: theme.textStyle, textAlign: theme.textAlign ?? TextAlign.center),
                ),
              ),
            ),
          ),
        ),
      );
    },
    child: MouseRegion(
      onEnter: _enter,
      onExit: _exit,
      child: GestureDetector(
        excludeFromSemantics: true,
        behavior: HitTestBehavior.opaque,
        supportedDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.unknown,
        },
        onLongPress: _longPress,
        onLongPressUp: _release,
        child: widget.child,
      ),
    ),
  );
}

class _TooltipPosition extends SingleChildLayoutDelegate {
  const _TooltipPosition({required this.target, required this.verticalOffset, required this.preferBelow});

  final Offset target;
  final double verticalOffset;
  final bool preferBelow;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen().deflate(const EdgeInsets.symmetric(horizontal: 20));

  @override
  Offset getPositionForChild(Size size, Size childSize) => positionDependentBox(
    size: size,
    childSize: childSize,
    target: target,
    verticalOffset: verticalOffset,
    preferBelow: preferBelow,
  );

  @override
  bool shouldRelayout(_TooltipPosition oldDelegate) =>
      target != oldDelegate.target ||
      verticalOffset != oldDelegate.verticalOffset ||
      preferBelow != oldDelegate.preferBelow;
}
