import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_presentation.dart';
import 'package:upgrader/upgrader.dart';

/// Uses Upgrader's version checks, dialog contents and actions with the app's
/// popup transition.
class StoreUpgradeAlert extends UpgradeAlert {
  StoreUpgradeAlert({super.key, required super.upgrader, super.navigatorKey, required super.child});

  @override
  UpgradeAlertState createState() => _StoreUpgradeAlertState();
}

class _StoreUpgradeAlertState extends UpgradeAlertState {
  @override
  void showTheDialog({
    Key? key,
    required BuildContext context,
    required String? title,
    required String message,
    required String? releaseNotes,
    required bool barrierDismissible,
    required UpgraderMessages messages,
  }) {
    if (!mounted || !context.mounted) return;
    final animationStyle = BlizzardPopupTransition.styleOf(context);
    if (animationStyle == null) {
      super.showTheDialog(
        key: key,
        context: context,
        title: title,
        message: message,
        releaseNotes: releaseNotes,
        barrierDismissible: barrierDismissible,
        messages: messages,
      );
      return;
    }

    unawaited(widget.upgrader.saveLastAlerted());
    unawaited(
      showDialog<void>(
        context: context,
        animationStyle: animationStyle,
        barrierDismissible: barrierDismissible,
        builder: (context) => BlizzardPresentation(
          child: PopScope(
            canPop: onCanPop(),
            child: Builder(
              builder: (context) => alertDialog(key, title ?? '', message, releaseNotes, context, false, messages),
            ),
          ),
        ),
      ),
    );
  }
}
