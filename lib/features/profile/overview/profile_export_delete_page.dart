import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
import 'package:hiddify/core/widget/nova_grouped_scaffold.dart';
import 'package:hiddify/core/widget/nova_grouped_section.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProfileExportDeletePage extends ConsumerWidget {
  const ProfileExportDeletePage({super.key, required this.profile});

  final ProfileEntity profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final copy = t.pages.profiles.dataActions;

    return NovaGroupedScaffold(
      appBar: AppBar(title: Text(copy.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(top: NovaSpacing.lg, bottom: NovaSpacing.xxl),
          children: [
            NovaGroupedSection(
              children: [
                NovaSettingsRow(
                  icon: Icons.shield_outlined,
                  title: profile.name,
                  subtitle: profile.active ? copy.activeAccessBody : copy.inactiveAccessBody,
                ),
                NovaSettingsRow(
                  icon: Icons.copy_all_outlined,
                  title: copy.exportTitle,
                  subtitle: copy.exportBody,
                  onTap: () => ref.read(profilesNotifierProvider.notifier).exportConfigToClipboard(profile),
                ),
              ],
            ),
            const SizedBox(height: NovaSpacing.xl),
            NovaGroupedSection(
              title: copy.consequences.toUpperCase(),
              children: [
                NovaSettingsRow(
                  icon: Icons.warning_amber_rounded,
                  title: profile.active ? copy.activeConsequence : copy.inactiveConsequence,
                ),
                NovaSettingsRow(
                  icon: Icons.delete_outline_rounded,
                  title: copy.deleteTitle,
                  subtitle: copy.deleteBody,
                  destructive: true,
                  onTap: () => _confirmDelete(context, ref),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final t = ref.read(translationsProvider).requireValue;
    final confirmed = await ref
        .read(dialogNotifierProvider.notifier)
        .showConfirmation(
          title: t.dialogs.confirmation.profile.delete.title,
          message: profile.active
              ? t.dialogs.confirmation.profile.delete.activeMsg
              : t.dialogs.confirmation.profile.delete.msg,
        );
    if (!confirmed) return;

    await ref.read(profilesNotifierProvider.notifier).deleteProfile(profile);
    if (context.mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }
}
