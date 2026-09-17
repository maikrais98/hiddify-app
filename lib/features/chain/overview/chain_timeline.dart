import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/chain/model/chain_enum.dart';
import 'package:hiddify/features/chain/overview/chain_timeline_arrow.dart';
import 'package:hiddify/features/chain/overview/chain_timeline_header.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ChainTimeline extends HookConsumerWidget {
  const ChainTimeline({super.key, required this.level, this.childeren = const []});
  final ChainTimelineLevel level;
  final List<Widget> childeren;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    return Column(
      children: [
        ChainTimelineHeader(level),
        Stack(
          children: [
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              child: ChainTimelineArrow(showArrow: !level.isFiltering()),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 20.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!level.isMainProfile())
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 10, 16, childeren.isEmpty ? 10 : 4),
                      child: Text(
                        level.present(t).message,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ...childeren,
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
