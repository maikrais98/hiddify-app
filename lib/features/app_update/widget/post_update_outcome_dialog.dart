import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

class PostUpdateOutcomeDialog extends StatelessWidget {
  const PostUpdateOutcomeDialog({
    super.key,
    required this.currentVersion,
    required this.isConnected,
    required this.onClose,
    this.onReconnect,
  });

  final String currentVersion;
  final bool isConnected;
  final VoidCallback onClose;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) {
    final copy = _PostUpdateCopy.forLocale(Localizations.localeOf(context));
    final canReconnect = !isConnected && onReconnect != null;
    final status = isConnected
        ? copy.connected
        : canReconnect
        ? copy.canReconnect
        : copy.checkConnection;

    return AlertDialog(
      icon: const Icon(Icons.check_circle_outline),
      title: Text(copy.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(copy.version(currentVersion)),
          const Gap(12),
          Text(copy.preserved),
          const Gap(12),
          Text(status),
        ],
      ),
      actions: [
        TextButton(onPressed: onClose, child: Text(copy.close)),
        if (canReconnect) FilledButton(onPressed: onReconnect, child: Text(copy.reconnect)),
      ],
    );
  }
}

enum _PostUpdateCopy {
  russian(
    title: 'Обновление установлено',
    versionPrefix: 'Приложение запущено на версии',
    preserved: 'Проверка версии не изменяла настройки и профили.',
    connected: 'VPN уже подключён — повторное подключение не требуется.',
    canReconnect: 'VPN сейчас отключён. Можно попробовать подключиться снова с активным профилем.',
    checkConnection: 'VPN не подключён автоматически. Проверьте активный профиль на главном экране.',
    close: 'Готово',
    reconnect: 'Подключиться снова',
  ),
  english(
    title: 'Update installed',
    versionPrefix: 'The app is now running version',
    preserved: 'The version check did not change settings or profiles.',
    connected: 'The VPN is already connected. No reconnect is needed.',
    canReconnect: 'The VPN is disconnected. You can try to reconnect with the active profile.',
    checkConnection: 'The VPN did not reconnect automatically. Check the active profile on the home screen.',
    close: 'Done',
    reconnect: 'Reconnect',
  );

  const _PostUpdateCopy({
    required this.title,
    required this.versionPrefix,
    required this.preserved,
    required this.connected,
    required this.canReconnect,
    required this.checkConnection,
    required this.close,
    required this.reconnect,
  });

  static _PostUpdateCopy forLocale(Locale locale) => locale.languageCode == 'ru' ? russian : english;

  String version(String value) => '$versionPrefix $value';

  final String title;
  final String versionPrefix;
  final String preserved;
  final String connected;
  final String canReconnect;
  final String checkConnection;
  final String close;
  final String reconnect;
}
