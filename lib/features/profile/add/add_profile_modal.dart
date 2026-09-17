import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
import 'package:hiddify/features/profile/add/widgets/widgets.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AddProfileModal extends HookConsumerWidget {
  const AddProfileModal({super.key, this.url});
  // static const warpConsentGiven = "warp_consent_given";
  final String? url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(addProfileNotifierProvider);
    final phase = ref.watch(importPhaseProvider);
    final currentWidget = ref.watch(addProfilePageNotifierProvider);
    useEffect(() {
      Future.microtask(() {
        if (!context.mounted) return;
        final notifier = ref.read(addProfileNotifierProvider.notifier);
        notifier.reset();
        if (url != null) notifier.addClipboard(url!);
      });
      return null;
    }, const []);

    final copy = _ImportCopy.forLocale(Localizations.localeOf(context));
    final nova = NovaThemeData.of(context);
    return Scaffold(
      backgroundColor: nova.background,
      appBar: AppBar(
        backgroundColor: nova.background,
        foregroundColor: nova.primaryText,
        centerTitle: true,
        title: Text(copy.importTitle),
        leading: Navigator.canPop(context)
            ? IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.chevron_left_rounded),
              )
            : null,
      ),
      body: SafeArea(
        top: false,
        child: phase != ImportPhase.idle
            ? ImportOutcome(phase: phase)
            : switch (currentWidget) {
                AddProfilePages.options => const AddProfileOptions(),
                AddProfilePages.manual => const AddProfileManual(),
              },
      ),
    );
  }
}

class ImportOutcome extends ConsumerWidget {
  const ImportOutcome({super.key, required this.phase});
  final ImportPhase phase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final notifier = ref.read(addProfileNotifierProvider.notifier);
    final busy = {ImportPhase.validating, ImportPhase.fetching, ImportPhase.parsing}.contains(phase);
    final error = ref.watch(addProfileNotifierProvider).error;
    final copy = _ImportCopy.forLocale(Localizations.localeOf(context));
    final nova = NovaThemeData.of(context);
    final title = switch (phase) {
      ImportPhase.success => copy.savedDetail,
      ImportPhase.cancel || ImportPhase.invalid || ImportPhase.unsafe || ImportPhase.network => copy.failureTitle,
      _ => copy.checkingTitle,
    };
    final detail = switch (phase) {
      ImportPhase.success => t.pages.profiles.msg.save.success,
      ImportPhase.cancel => t.errors.profiles.canceledByUser,
      ImportPhase.invalid => error == null ? t.errors.profiles.invalidUrl : t.errorToPair(error).type,
      ImportPhase.unsafe => copy.unsafeSource,
      ImportPhase.network => copy.networkIssue,
      _ => copy.checkingDetail,
    };
    final help = switch (phase) {
      ImportPhase.success => t.pages.profiles.msg.save.body,
      ImportPhase.invalid || ImportPhase.unsafe => copy.invalidHelp,
      ImportPhase.network => copy.networkHelp,
      ImportPhase.cancel => copy.cancelHelp,
      _ => copy.checkingHelp,
    };
    final color = switch (phase) {
      ImportPhase.success => NovaColors.signalGood,
      ImportPhase.validating || ImportPhase.fetching || ImportPhase.parsing => NovaColors.signalMid,
      _ => NovaColors.signalBad,
    };
    final icon = switch (phase) {
      ImportPhase.success => Icons.check_circle_outline_rounded,
      ImportPhase.validating || ImportPhase.fetching || ImportPhase.parsing => null,
      _ => Icons.help_outline_rounded,
    };

    return ColoredBox(
      key: ValueKey('import_${phase.name}'),
      color: nova.background,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: (constraints.maxHeight - 48).clamp(0, double.infinity)),
            child: Column(
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(color: color.withValues(alpha: .14), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: icon == null
                      ? SizedBox.square(dimension: 42, child: CircularProgressIndicator(color: color, strokeWidth: 3))
                      : Icon(icon, color: color, size: 42),
                ),
                const Gap(22),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: nova.primaryText, fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const Gap(22),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 58),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: nova.surface,
                    borderRadius: BorderRadius.circular(NovaRadii.medium),
                    border: Border.all(color: nova.border),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.description_outlined, color: nova.secondaryText, size: 20),
                      const Gap(12),
                      Expanded(
                        child: Text(
                          detail,
                          style: TextStyle(
                            color: busy || phase == ImportPhase.success ? nova.secondaryText : color,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Gap(14),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(help, style: TextStyle(color: nova.secondaryText, height: 1.45, fontSize: 12)),
                ),
                const Gap(22),
                if (busy) ...[
                  _ImportButton(label: copy.wait, onPressed: null),
                  if (phase == ImportPhase.validating || phase == ImportPhase.fetching)
                    TextButton(onPressed: notifier.cancel, child: Text(t.common.cancel)),
                ] else if (phase == ImportPhase.success)
                  _ImportButton(
                    label: t.pages.profiles.msg.save.chooseAccess,
                    onPressed: () async {
                      final bottomSheets = ref.read(bottomSheetsNotifierProvider.notifier);
                      if (context.mounted && Navigator.canPop(context)) {
                        Navigator.of(context).pop();
                        await Future<void>.delayed(Duration.zero);
                      }
                      await bottomSheets.showProfilesOverview();
                    },
                  )
                else ...[
                  if (phase != ImportPhase.cancel) _ImportButton(label: t.common.retry, onPressed: notifier.retry),
                  const Gap(10),
                  _ImportButton(label: copy.chooseAnother, secondary: true, onPressed: notifier.reset),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImportButton extends StatelessWidget {
  const _ImportButton({required this.label, required this.onPressed, this.secondary = false});

  final String label;
  final VoidCallback? onPressed;
  final bool secondary;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 52,
    child: secondary
        ? OutlinedButton(onPressed: onPressed, child: Text(label))
        : FilledButton(onPressed: onPressed, child: Text(label)),
  );
}

enum _ImportCopy {
  russian(
    importTitle: 'Импорт профиля',
    checkingTitle: 'Проверяем профиль…',
    failureTitle: 'Не удалось импортировать',
    checkingDetail: 'Читаем конфигурацию и доступность',
    checkingHelp: 'Проверяем формат локально. Секреты и полный URL не показываются в диагностике.',
    unsafeSource: 'Источник не прошёл проверку безопасности',
    networkIssue: 'Источник сейчас недоступен',
    invalidHelp: 'Проверьте источник и повторите. Токены, ключи и полный URL не выводятся.',
    networkHelp: 'Проверьте интернет и доступность источника, затем повторите.',
    cancelHelp: 'Импорт отменён. Можно выбрать другой источник.',
    savedDetail: 'Профиль сохранён на этом устройстве',
    chooseSource: 'Как добавить VPN-доступ?',
    wait: 'Подождите',
    chooseAnother: 'Выбрать другой источник',
  ),
  english(
    importTitle: 'Import profile',
    checkingTitle: 'Checking profile…',
    failureTitle: 'Could not import',
    checkingDetail: 'Reading configuration and availability',
    checkingHelp: 'The format is checked locally. Secrets and the full URL are never shown in diagnostics.',
    unsafeSource: 'The source did not pass the safety check',
    networkIssue: 'The source is currently unavailable',
    invalidHelp: 'Check the source and try again. Tokens, keys, and the full URL are never shown.',
    networkHelp: 'Check your connection and source availability, then try again.',
    cancelHelp: 'Import was cancelled. You can choose another source.',
    savedDetail: 'Profile stored on this device',
    chooseSource: 'How would you like to add VPN access?',
    wait: 'Please wait',
    chooseAnother: 'Choose another source',
  );

  const _ImportCopy({
    required this.importTitle,
    required this.checkingTitle,
    required this.failureTitle,
    required this.checkingDetail,
    required this.checkingHelp,
    required this.unsafeSource,
    required this.networkIssue,
    required this.invalidHelp,
    required this.networkHelp,
    required this.cancelHelp,
    required this.savedDetail,
    required this.chooseSource,
    required this.wait,
    required this.chooseAnother,
  });

  final String importTitle;
  final String checkingTitle;
  final String failureTitle;
  final String checkingDetail;
  final String checkingHelp;
  final String unsafeSource;
  final String networkIssue;
  final String invalidHelp;
  final String networkHelp;
  final String cancelHelp;
  final String savedDetail;
  final String chooseSource;
  final String wait;
  final String chooseAnother;

  static _ImportCopy forLocale(Locale locale) => locale.languageCode == 'ru' ? russian : english;
}

class AddProfileOptions extends HookConsumerWidget {
  const AddProfileOptions({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // final isLoadingProfile = ref.watch(addProfileNotifierProvider).isLoading;
    final isDesktop = PlatformUtils.isDesktop;
    final gapCount = isDesktop ? AddProfileModalConst.fixBtnsGapCountDesktop : AddProfileModalConst.fixBtnsGapCount;
    final itemCount = isDesktop ? AddProfileModalConst.fixBtnsItemCountDesktop : AddProfileModalConst.fixBtnsItemCount;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fixBtnsHeight = (constraints.maxWidth - AddProfileModalConst.fixBtnsGap * gapCount) / itemCount;
        final copy = _ImportCopy.forLocale(Localizations.localeOf(context));
        final nova = NovaThemeData.of(context);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(0, 28, 0, 32),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  copy.chooseSource,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: nova.primaryText, fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              const Gap(24),
              FixBtns(height: fixBtnsHeight),
            ],
          ),
        );
      },
    );
  }
}

class AddProfileManual extends HookConsumerWidget {
  const AddProfileManual({super.key});

  String _genSliderText(Translations t, int sliderValue) {
    if (sliderValue == 0) {
      return t.common.auto;
    } else if (sliderValue < 24) {
      return t.common.interval.hour(n: sliderValue);
    }
    final day = t.common.interval.day(n: sliderValue ~/ 24);
    final hour = t.common.interval.hour(n: sliderValue % 24);
    return '$day $hour';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    final media = MediaQuery.of(context);
    final availableHeight = (media.size.height - media.viewInsets.bottom - media.padding.vertical).clamp(
      0.0,
      double.infinity,
    );
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final nameTextController = useTextEditingController();
    final urlTextController = useTextEditingController();
    final isAutoUpdateDisable = useState<bool>(false);
    final updateInterval = useState(.0);
    final sliderFocusNode = useFocusNode(
      onKeyEvent: (node, event) {
        if (KeyboardConst.verticalArrows.contains(event.logicalKey) && event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            node.previousFocus();
          } else {
            node.nextFocus();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: availableHeight),
      child: Form(
        key: formKey,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 12),
                child: Row(
                  children: [
                    Expanded(child: Text(t.common.manually, style: theme.textTheme.headlineMedium)),
                    IconButton(
                      tooltip: '${MaterialLocalizations.of(context).backButtonTooltip}: ${t.pages.profiles.add}',
                      icon: const Icon(Icons.close),
                      onPressed: () => ref.read(addProfilePageNotifierProvider.notifier).goOptions(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: CustomTextFormField(
                  maxLines: 1,
                  controller: nameTextController,
                  validator: (value) => (value?.isEmpty ?? true) ? t.pages.profileDetails.form.emptyName : null,
                  label: t.common.name,
                  hint: t.pages.profileDetails.form.nameHint,
                ),
              ),
              const Gap(16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: CustomTextFormField(
                  maxLines: 1,
                  controller: urlTextController,
                  validator: (value) =>
                      (value != null && !isUrl(value)) ? t.pages.profileDetails.form.invalidUrl : null,
                  label: t.common.url,
                  hint: t.pages.profileDetails.form.urlHint,
                ),
              ),
              const Gap(12),
              SwitchListTile.adaptive(
                title: Text(
                  t.pages.profileDetails.form.disableAutoUpdate,
                  style: theme.textTheme.titleSmall!.copyWith(color: theme.colorScheme.onSurface),
                ),
                value: isAutoUpdateDisable.value,
                onChanged: (value) => isAutoUpdateDisable.value = value,
              ),
              AnimatedSize(
                alignment: Alignment.topCenter,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: !isAutoUpdateDisable.value
                    ? Column(
                        children: [
                          const Divider(indent: 16, endIndent: 16),
                          const Gap(12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    t.pages.profileDetails.form.autoUpdateInterval,
                                    style: theme.textTheme.titleSmall!.copyWith(color: theme.colorScheme.onSurface),
                                  ),
                                ),
                                Text(
                                  _genSliderText(t, updateInterval.value.round()),
                                  style: theme.textTheme.labelSmall!.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Gap(4),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Slider(
                              focusNode: sliderFocusNode,
                              value: updateInterval.value,
                              min: minProfileUpdateIntervalHours.toDouble(),
                              max: maxProfileUpdateIntervalHours.toDouble(),
                              divisions: maxProfileUpdateIntervalHours - minProfileUpdateIntervalHours,
                              label: updateInterval.value.round().toString(),
                              onChanged: (double value) => updateInterval.value = value,
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        child: Text(t.common.add),
                        onPressed: () async {
                          if (formKey.currentState!.validate()) {
                            final i = updateInterval.value.toInt();
                            final interval = i > 0 ? i : null;
                            await ref
                                .read(addProfileNotifierProvider.notifier)
                                .addManual(
                                  url: urlTextController.text.trim(),
                                  userOverride: UserOverride(
                                    name: nameTextController.text.trim(),
                                    isAutoUpdateDisable: isAutoUpdateDisable.value,
                                    updateInterval: interval,
                                  ),
                                );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              // const Gap(16),
            ],
          ),
        ),
      ),
    );
  }
}
