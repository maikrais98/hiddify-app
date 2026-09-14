import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/identity/data/identity_data_providers.dart';
import 'package:hiddify/features/identity/model/email_address.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum _SaveStatus { idle, saving, saved, failed }

enum _LeaveAction { save, discard, continueEditing }

class IdentityProfilePage extends HookConsumerWidget {
  const IdentityProfilePage({super.key});

  static const _maxAvatarBytes = 5 * 1024 * 1024;
  static const _avatarExtensions = {'png', 'jpg', 'jpeg', 'webp', 'heic'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final translations = ref.watch(translationsProvider).requireValue;
    final t = translations.pages.identity;
    final profile = ref.watch(identityProfileProvider);
    final controller = useTextEditingController(text: profile.email ?? '');
    final saveStatus = useState(_SaveStatus.idle);
    final isSaving = useState(false);
    final isDirty = useState(false);
    final allowPop = useState(false);
    final editRevision = useRef(0);
    final savedEmail = useRef(profile.email ?? '');
    final validationError = useState<String?>(null);
    final avatarError = useState<String?>(null);
    final avatarFile = profile.avatarPath == null ? null : File(profile.avatarPath!);

    Future<bool> save() async {
      if (isSaving.value) return false;
      FocusScope.of(context).unfocus();
      final input = controller.text;
      final normalized = normalizeOptionalEmail(input);
      if (normalized != null && !isValidEmail(normalized)) {
        validationError.value = t.invalidEmail;
        return false;
      }
      validationError.value = null;
      final revision = editRevision.value;
      isSaving.value = true;
      saveStatus.value = _SaveStatus.saving;
      try {
        await ref.read(identityProfileProvider.notifier).saveEmail(input);
        savedEmail.value = normalized ?? '';
        final draftMatchesSaved = controller.text == savedEmail.value;
        isDirty.value = !draftMatchesSaved;
        if (editRevision.value == revision) {
          controller.text = savedEmail.value;
          isDirty.value = false;
          saveStatus.value = _SaveStatus.saved;
        } else {
          saveStatus.value = _SaveStatus.idle;
        }
        return draftMatchesSaved;
      } catch (_) {
        isDirty.value = controller.text != savedEmail.value;
        saveStatus.value = editRevision.value == revision ? _SaveStatus.failed : _SaveStatus.idle;
        return false;
      } finally {
        isSaving.value = false;
      }
    }

    void leavePage(Object? result) {
      allowPop.value = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).pop(result);
      });
    }

    Future<void> confirmLeave(Object? result) async {
      final action = await showDialog<_LeaveAction>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(t.unsavedChangesTitle),
          content: Text(t.unsavedChangesBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(_LeaveAction.continueEditing),
              child: Text(t.continueEditing),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(_LeaveAction.discard),
              child: Text(translations.common.discard),
            ),
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(_LeaveAction.save), child: Text(t.save)),
          ],
        ),
      );
      switch (action) {
        case _LeaveAction.save:
          if (await save() && context.mounted) leavePage(result);
        case _LeaveAction.discard:
          if (context.mounted) leavePage(result);
        case _LeaveAction.continueEditing || null:
          break;
      }
    }

    Future<void> chooseAvatar() async {
      avatarError.value = null;
      try {
        final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
        if (result == null) return;
        final picked = result.files.single;
        final extension = (picked.extension ?? p.extension(picked.name).replaceFirst('.', '')).toLowerCase();
        if (!_avatarExtensions.contains(extension) || picked.size > _maxAvatarBytes) {
          avatarError.value = t.avatarFailed;
          return;
        }
        final directory = await getApplicationSupportDirectory();
        final destination = File(p.join(directory.path, 'woman_in_red_avatar.$extension'));
        if (picked.bytes != null) {
          await destination.writeAsBytes(picked.bytes!, flush: true);
        } else if (picked.path != null) {
          await File(picked.path!).copy(destination.path);
        } else {
          throw const FileSystemException('Picker did not return image data');
        }
        final previousPath = profile.avatarPath;
        await ref.read(identityProfileProvider.notifier).saveAvatarPath(destination.path);
        if (previousPath != null && previousPath != destination.path) {
          final previous = File(previousPath);
          if (await previous.exists()) await previous.delete();
        }
      } catch (_) {
        avatarError.value = t.avatarFailed;
      }
    }

    Future<void> removeAvatar() async {
      final previousPath = profile.avatarPath;
      await ref.read(identityProfileProvider.notifier).saveAvatarPath(null);
      if (previousPath != null) {
        final previous = File(previousPath);
        if (await previous.exists()) await previous.delete();
      }
    }

    final page = Scaffold(
      appBar: AppBar(title: Text(t.title)),
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: CircleAvatar(
                radius: 48,
                foregroundImage: avatarFile != null && avatarFile.existsSync() ? FileImage(avatarFile) : null,
                child: const Icon(Icons.person_rounded, size: 44),
              ),
            ),
            const Gap(12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: chooseAvatar,
                  icon: const Icon(Icons.photo_outlined),
                  label: Text(t.chooseAvatar),
                ),
                if (profile.avatarPath != null)
                  TextButton.icon(
                    onPressed: removeAvatar,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(t.removeAvatar),
                  ),
              ],
            ),
            if (avatarError.value != null) ...[
              Text(
                avatarError.value!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const Gap(16),
            ],
            TextField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
              decoration: InputDecoration(
                labelText: t.email,
                hintText: t.emailHint,
                errorText: validationError.value,
                suffixIcon: profile.email == null
                    ? null
                    : Tooltip(message: t.unverified, child: const Icon(Icons.info_outline_rounded)),
              ),
              onChanged: (value) {
                editRevision.value++;
                validationError.value = null;
                isDirty.value = value != savedEmail.value;
                saveStatus.value = _SaveStatus.idle;
              },
              onSubmitted: (_) => save(),
            ),
            const Gap(8),
            Text(t.emailHelp, style: Theme.of(context).textTheme.bodySmall),
            const Gap(24),
            FilledButton(
              onPressed: isSaving.value ? null : save,
              child: isSaving.value
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(t.save),
            ),
            if (saveStatus.value == _SaveStatus.saved) ...[const Gap(8), Text(t.saved, textAlign: TextAlign.center)],
            if (saveStatus.value == _SaveStatus.failed) ...[
              const Gap(8),
              Text(
                t.saveFailed,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
    return PopScope<Object?>(
      canPop: allowPop.value || !isDirty.value,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && isDirty.value) confirmLeave(result);
      },
      child: page,
    );
  }
}
