import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_glass.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_presentation.dart';

bool _active(BuildContext context) =>
    BlizzardPresentation.isActive(context) || (Theme.of(context).extension<BlizzardEligibility>()?.applied ?? false);

Widget? blizzardToolbarLeading(BuildContext context) {
  final route = ModalRoute.of(context);
  if (!_active(context) || !(route?.canPop ?? false)) return null;
  final close = route is PageRoute && route.fullscreenDialog;
  return Center(
    child: BlizzardGlass(
      active: true,
      radius: BlizzardRadii.sheet,
      child: SizedBox.square(dimension: 48, child: close ? const CloseButton() : const BackButton()),
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
