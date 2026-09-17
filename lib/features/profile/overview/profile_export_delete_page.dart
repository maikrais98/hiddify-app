import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
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

    return Scaffold(
      appBar: AppBar(title: Text(copy.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(copy.accessTitle),
                subtitle: Text(copy.accessBody),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: const Icon(Icons.copy_all_outlined),
                title: Text(copy.exportTitle),
                subtitle: Text(copy.exportBody),
                onTap: () => ref.read(profilesNotifierProvider.notifier).exportConfigToClipboard(profile),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              copy.consequences,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.error, letterSpacing: 0.8),
            ),
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(profile.active ? copy.activeConsequence : copy.inactiveConsequence),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
                    title: Text(copy.deleteTitle, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    subtitle: Text(copy.deleteBody),
                    onTap: () => _confirmDelete(context, ref),
                  ),
                ],
              ),
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
