import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
import 'package:hiddify/core/widget/nova_grouped_scaffold.dart';
import 'package:hiddify/core/widget/nova_grouped_section.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum ConfigOptionSection {
  warp,
  fragment;

  static final _warpKey = GlobalKey(debugLabel: "warp-section-key");
  static final _fragmentKey = GlobalKey(debugLabel: "fragment-section-key");

  GlobalKey get key => switch (this) {
    ConfigOptionSection.warp => _warpKey,
    ConfigOptionSection.fragment => _fragmentKey,
  };
}

class SettingsPage extends HookConsumerWidget {
  SettingsPage({super.key, String? section})
    : section = section != null ? ConfigOptionSection.values.byName(section) : null;

  final ConfigOptionSection? section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    // final scrollController = useScrollController();

    // useMemoized(
    //   () {
    //     if (section != null) {
    //       WidgetsBinding.instance.addPostFrameCallback(
    //         (_) {
    //           final box = section!.key.currentContext?.findRenderObject() as RenderBox?;

    //           final offset = box?.localToGlobal(Offset.zero);
    //           if (offset == null) return;
    //           final height = scrollController.offset + offset.dy - MediaQueryData.fromView(View.of(context)).padding.top - kToolbarHeight;
    //           scrollController.animateTo(
    //             height,
    //             duration: const Duration(milliseconds: 500),
    //             curve: Curves.decelerate,
    //           );
    //         },
    //       );
    //     }
    //   },
    // );

    return NovaGroupedScaffold(
      appBar: AppBar(title: Text(t.pages.settings.title), actions: const [Gap(8)]),
      body: ListView(
        padding: const EdgeInsets.only(top: NovaSpacing.lg, bottom: NovaSpacing.xxl),
        children: [
          NovaGroupedSection(
            title: t.pages.settings.title.toUpperCase(),
            children: [
              SettingsSection(
                title: t.pages.settings.general.title,
                icon: Icons.layers_rounded,
                namedLocation: context.namedLocation('general'),
              ),
              SettingsSection(
                title: t.pages.settings.advanced.title,
                icon: Icons.tune_rounded,
                subtitle: t.pages.settings.advanced.subtitle,
                namedLocation: context.namedLocation('advanced'),
              ),
            ],
          ),
          if (Breakpoint(context).isMobile()) ...[
            const Gap(NovaSpacing.xl),
            NovaGroupedSection(
              title: t.common.help.toUpperCase(),
              children: [
                SettingsSection(
                  title: t.pages.logs.title,
                  icon: Icons.description_rounded,
                  namedLocation: context.namedLocation('logs'),
                ),
                SettingsSection(
                  title: t.pages.about.title,
                  icon: Icons.info_rounded,
                  namedLocation: context.namedLocation('about'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class SettingsSection extends HookConsumerWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    required this.namedLocation,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final String namedLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NovaSettingsRow(title: title, icon: icon, subtitle: subtitle, onTap: () => context.go(namedLocation));
  }
}
