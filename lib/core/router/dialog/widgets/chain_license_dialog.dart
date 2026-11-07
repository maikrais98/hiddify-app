import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_presentation.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/utils/uri_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ChainLicenseDialog extends HookConsumerWidget {
  const ChainLicenseDialog({required this.mode, super.key});

  final ChainMode mode;

  KeyEventResult _handleKeyEvent(KeyEvent event, String key) {
    if (KeyboardConst.select.contains(event.logicalKey) && event is KeyUpEvent) {
      final url = mode.isWarp() ? WarpConst.url[key] : PsiphonConst.url[key];
      if (url != null) {
        UriUtils.tryLaunch(Uri.parse(url));
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = BlizzardPresentation.themeOf(context);
    final luma =
        BlizzardPresentation.isActive(context) ||
        (Theme.of(context).extension<BlizzardEligibility>()?.applied ?? false);
    TextStyle linkStyle(bool focused) => TextStyle(
      color: luma ? theme.colorScheme.primary : (focused ? Colors.green : Colors.blue),
      decoration: luma && focused ? TextDecoration.underline : null,
      decorationColor: luma ? theme.colorScheme.primary : null,
    );

    final termsKey = mode.isWarp() ? WarpConst.warpTermsOfServiceKey : PsiphonConst.psiphonTermsOfServiceKey;
    final privacyKey = mode.isWarp() ? WarpConst.warpPrivacyPolicyKey : PsiphonConst.psiphonPrivacyPolicyKey;

    final focusStates = <String, ValueNotifier<bool>>{
      termsKey: useState<bool>(false),
      privacyKey: useState<bool>(false),
    };
    final focusNodes = <String, FocusNode>{termsKey: useFocusNode(), privacyKey: useFocusNode()};

    useEffect(() {
      for (final entry in focusNodes.entries) {
        entry.value.addListener(() => focusStates[entry.key]!.value = entry.value.hasPrimaryFocus);
      }
      return null;
    }, []);

    final title = mode.isWarp() ? t.dialogs.warpLicense.title : t.dialogs.psiphonLicense.title;

    final description = mode.isWarp()
        ? t.dialogs.warpLicense.description(
            tos: (text) => TextSpan(
              text: text,
              style: linkStyle(focusStates[termsKey]!.value),
              recognizer: TapGestureRecognizer()
                ..onTap = () async {
                  await UriUtils.tryLaunch(Uri.parse(WarpConst.url[termsKey]!));
                },
            ),
            privacy: (text) => TextSpan(
              text: text,
              style: linkStyle(focusStates[privacyKey]!.value),
              recognizer: TapGestureRecognizer()
                ..onTap = () async {
                  await UriUtils.tryLaunch(Uri.parse(WarpConst.url[privacyKey]!));
                },
            ),
          )
        : t.dialogs.psiphonLicense.description(
            tos: (text) => TextSpan(
              text: text,
              style: TextStyle(
                color: luma ? theme.colorScheme.primary : (focusStates[termsKey]!.value ? Colors.green : Colors.blue),
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () async {
                  await UriUtils.tryLaunch(Uri.parse(PsiphonConst.url[termsKey]!));
                },
            ),
            privacy: (text) => TextSpan(
              text: text,
              style: TextStyle(
                color: luma ? theme.colorScheme.primary : (focusStates[privacyKey]!.value ? Colors.green : Colors.blue),
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () async {
                  await UriUtils.tryLaunch(Uri.parse(PsiphonConst.url[privacyKey]!));
                },
            ),
          );

    return BlizzardPresentation(
      child: AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: AlertDialogConst.boxConstraints,
          child: SingleChildScrollView(
            child: Column(
              children: [
                Focus(
                  focusNode: focusNodes[termsKey],
                  onKeyEvent: (node, event) => _handleKeyEvent(event, termsKey),
                  child: const Gap(0.1),
                ),
                Focus(
                  focusNode: focusNodes[privacyKey],
                  onKeyEvent: (node, event) => _handleKeyEvent(event, privacyKey),
                  child: const Gap(0.1),
                ),
                Text.rich(description),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              context.pop(false);
            },
            child: Text(t.common.decline),
          ),
          TextButton(
            onPressed: () {
              context.pop(true);
            },
            child: Text(t.common.agree),
          ),
        ],
      ),
    );
  }
}
