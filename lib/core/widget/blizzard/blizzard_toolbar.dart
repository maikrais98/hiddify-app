import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_glass.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_presentation.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_tooltip.dart';

bool _active(BuildContext context) =>
    BlizzardPresentation.isActive(context) || (Theme.of(context).extension<BlizzardEligibility>()?.applied ?? false);

Widget? blizzardToolbarLeading(BuildContext context, {bool glass = true}) {
  final route = ModalRoute.of(context);
  final dismissible = glass ? route?.canPop : route?.impliesAppBarDismissal;
  if (!_active(context) || dismissible != true) return null;
  final button = route is PageRoute && route.fullscreenDialog
      ? const BlizzardTooltip.button(child: CloseButton())
      : const BlizzardTooltip.button(child: BackButton());
  if (!glass) return button;
  return Center(
    child: BlizzardGlass(
      active: true,
      radius: BlizzardRadii.sheet,
      child: SizedBox.square(dimension: 48, child: button),
    ),
  );
}

List<Widget> blizzardToolbarActions(BuildContext context, List<Widget> actions) {
  if (!_active(context) || actions.isEmpty) return actions;
  return [
    Center(
      child: BlizzardGlass(
        active: true,
        radius: BlizzardRadii.sheet,
        child: Row(mainAxisSize: MainAxisSize.min, children: actions),
      ),
    ),
  ];
}
