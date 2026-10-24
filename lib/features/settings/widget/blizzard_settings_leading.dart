import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_glass.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_presentation.dart';

Widget? blizzardSettingsLeading(BuildContext context) {
  final blizzard =
      BlizzardPresentation.isActive(context) ||
      (Theme.of(context).extension<BlizzardEligibility>()?.applied ?? false);
  if (!blizzard || !(ModalRoute.of(context)?.canPop ?? false)) return null;

  return const Center(
    child: BlizzardGlass(
      active: true,
      radius: BlizzardRadii.sheet,
      child: SizedBox.square(dimension: 48, child: BackButton()),
    ),
  );
}
