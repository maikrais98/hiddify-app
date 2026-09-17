import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/features/per_app_proxy/data/per_app_routing_repository.dart';

class PerAppRoutingRecoveryView extends StatelessWidget {
  const PerAppRoutingRecoveryView({
    super.key,
    required this.failure,
    required this.onRetry,
    required this.onContinueWithoutPerApp,
    this.onOpenSettings,
  });

  final PerAppRoutingException failure;
  final VoidCallback onRetry;
  final VoidCallback onContinueWithoutPerApp;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final ru = Localizations.localeOf(context).languageCode == 'ru';
    String tr(String russian, String english) => ru ? russian : english;
    final description = switch (failure.kind) {
      PerAppRoutingFailureKind.denied => tr(
        'Android ограничил чтение списка установленных приложений. Это не запрашиваемое разрешение: '
            'его нельзя включить в настройках Android.',
        'Android restricted access to the installed-app list. This is not a runtime permission and cannot be enabled '
            'in Android settings.',
      ),
      PerAppRoutingFailureKind.unavailable => tr(
        'Не удалось прочитать список установленных приложений. Можно повторить попытку или продолжить без '
            'маршрутизации по приложениям.',
        'The app could not read the installed-app list. Retry, or continue without per-app routing.',
      ),
      PerAppRoutingFailureKind.unsupported => tr(
        'Маршрутизация по приложениям недоступна на этой платформе.',
        'Per-app routing is unavailable on this platform.',
      ),
    };
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.apps_outage_rounded, size: 40, color: Theme.of(context).colorScheme.error),
              const Gap(16),
              Text(
                tr('Маршрутизация приложений недоступна', 'App routing unavailable'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Gap(12),
              Text(description, textAlign: TextAlign.center),
              const Gap(24),
              FilledButton(onPressed: onRetry, child: Text(tr('Повторить', 'Retry'))),
              if (failure.canOpenSettings && onOpenSettings != null) ...[
                const Gap(8),
                OutlinedButton(
                  onPressed: onOpenSettings,
                  child: Text(tr('Открыть настройки Android', 'Open Android settings')),
                ),
              ],
              const Gap(8),
              TextButton(
                onPressed: onContinueWithoutPerApp,
                child: Text(tr('Продолжить без маршрутизации приложений', 'Continue without per-app routing')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
