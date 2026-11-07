import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/profile/add/widgets/widgets.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class FixBtns extends ConsumerWidget {
  const FixBtns({super.key, required this.height, this.canScan = true, this.blizzardPresentation = false});
  final double height;
  final bool blizzardPresentation;

  /// False on a device with no camera to scan a QR code with, such as a TV.
  final bool canScan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    final isDesktop = PlatformUtils.isDesktop && !blizzardPresentation;
    return LayoutBuilder(
      builder: (context, constraints) {
        var effectiveHeight = height;
        if (blizzardPresentation) {
          final itemCount = isDesktop || !canScan
              ? AddProfileModalConst.fixBtnsItemCountDesktop
              : AddProfileModalConst.fixBtnsItemCount;
          final gaps = AddProfileModalConst.fixBtnsGap * (itemCount + 1);
          final itemWidth = math.max(1.0, (constraints.maxWidth - gaps) / itemCount);
          final textWidth = math.max(1.0, itemWidth - 8);
          final style = Theme.of(context).textTheme.titleSmall!;
          final textScaler = MediaQuery.textScalerOf(context);
          final direction = Directionality.of(context);
          var labelHeight = 0.0;
          for (final label in [t.common.qrCode, t.common.clipboard, t.common.file, t.common.manually]) {
            final painter = TextPainter(
              text: TextSpan(text: label, style: style),
              textAlign: TextAlign.center,
              textDirection: direction,
              textScaler: textScaler,
            )..layout(maxWidth: textWidth);
            labelHeight = math.max(labelHeight, painter.height);
          }
          effectiveHeight = math.max(height, 20 + 24 + 8 + labelHeight);
        }
        return Row(
          children: [
            const Gap(AddProfileModalConst.fixBtnsGap),
            FixBtn(
              key: const ValueKey('add_from_clipboard_button'),
              height: effectiveHeight,
              wrapLabel: blizzardPresentation,
              title: t.common.clipboard,
              icon: blizzardPresentation ? Icons.content_paste_outlined : Icons.content_paste,
              onTap: () async {
                final cr = await Clipboard.getData(Clipboard.kTextPlain).then((value) => value?.text ?? '');
                ref.read(addProfileNotifierProvider.notifier).addClipboard(cr);
              },
            ),
            const Gap(AddProfileModalConst.fixBtnsGap),
            FixBtn(
              key: const ValueKey('add_from_file_button'),
              height: effectiveHeight,
              wrapLabel: blizzardPresentation,
              title: t.common.file,
              icon: blizzardPresentation ? Icons.insert_drive_file_outlined : Icons.insert_drive_file,
              onTap: () async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['txt', 'json', 'yaml', 'yml', 'conf', 'ovpn', 'zip'],
                );
                if (result == null) return;
                final picked = result.files.single;
                var bytes = picked.bytes;
                if (bytes == null) {
                  final path = picked.path;
                  if (path == null) return;
                  final file = File(path);
                  if (!await file.exists()) return;
                  bytes = await file.readAsBytes();
                }
                final notifier = ref.read(addProfileNotifierProvider.notifier);
                if (picked.extension?.toLowerCase() == 'zip') {
                  notifier.addArchive(
                    bytes,
                    name: picked.name.replaceFirst(RegExp(r'\.zip$', caseSensitive: false), ''),
                  );
                } else {
                  notifier.addClipboard(decodeTextBytes(bytes));
                }
              },
            ),
            if (!isDesktop && canScan) ...[
              const Gap(AddProfileModalConst.fixBtnsGap),
              FixBtn(
                key: const ValueKey('add_by_qr_code_button'),
                height: effectiveHeight,
                wrapLabel: blizzardPresentation,
                title: t.common.qrCode,
                icon: blizzardPresentation ? Icons.qr_code_scanner_outlined : Icons.qr_code_scanner,
                onTap: () async {
                  final cr = await ref.read(dialogNotifierProvider.notifier).showQrScanner();
                  if (cr == null) return;
                  ref.read(addProfileNotifierProvider.notifier).addClipboard(cr);
                },
              ),
            ],
            const Gap(AddProfileModalConst.fixBtnsGap),
            FixBtn(
              key: const ValueKey('add_manually_button'),
              height: effectiveHeight,
              wrapLabel: blizzardPresentation,
              title: t.common.manually,
              icon: Icons.add,
              onTap: () {
                ref.read(addProfilePageNotifierProvider.notifier).goManual();
              },
            ),
            const Gap(AddProfileModalConst.fixBtnsGap),
          ],
        );
      },
    );
  }
}
