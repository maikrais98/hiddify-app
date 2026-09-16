import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_export.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_summary.dart';

class SafeDiagnosticsPage extends StatefulWidget {
  const SafeDiagnosticsPage({super.key, required this.summary, this.exporter});

  final SafeDiagnosticSummary summary;
  final SafeDiagnosticExport? exporter;

  @override
  State<SafeDiagnosticsPage> createState() => _SafeDiagnosticsPageState();
}

class _SafeDiagnosticsPageState extends State<SafeDiagnosticsPage> {
  late final _exporter = widget.exporter ?? SafeDiagnosticExport();
  bool _busy = false;
  bool _created = false;
  bool _failed = false;
  DiagnosticExportResult? _result;

  @override
  void dispose() {
    unawaited(_exporter.discard());
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    final created = await _exporter.create(widget.summary);
    if (!mounted) {
      await _exporter.discard();
      return;
    }
    setState(() {
      _busy = false;
      _created = created;
      _failed = !created;
    });
  }

  Future<void> _share(BuildContext buttonContext) async {
    final box = buttonContext.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() => _busy = true);
    final result = await _exporter.share(origin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ru = Localizations.localeOf(context).languageCode == 'ru';
    String tr(String russian, String english) => ru ? russian : english;
    final category = switch (widget.summary.category) {
      DiagnosticCategory.status => tr('Состояние подключения', 'Connection status'),
      DiagnosticCategory.permission => tr('Разрешения', 'Permissions'),
      DiagnosticCategory.configuration => tr('Настройка подключения', 'Connection configuration'),
      DiagnosticCategory.core => tr('Служба VPN', 'VPN service'),
      DiagnosticCategory.access => tr('Доступ к сервису', 'Service access'),
      DiagnosticCategory.unknown => tr('Причина не определена', 'Cause unknown'),
    };
    final stage = switch (widget.summary.stage) {
      DiagnosticStage.unavailable => tr('Состояние недоступно', 'Status unavailable'),
      DiagnosticStage.idle => tr('Отключено', 'Disconnected'),
      DiagnosticStage.connecting => tr('Подключение', 'Connecting'),
      DiagnosticStage.connected => tr('Туннель подключён', 'Tunnel connected'),
      DiagnosticStage.disconnecting => tr('Отключение', 'Disconnecting'),
    };
    return Scaffold(
      appBar: AppBar(title: Text(tr('Безопасная диагностика', 'Safe diagnostics'))),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('$category · $stage', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Text(
            tr(
              'Снимок состояния на момент открытия. Доступность интернета не проверялась.',
              'Snapshot when opened. Internet reachability has not been checked.',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            tr(
              'Ниже — всё содержимое файла: категория, этап, безопасный код и платформа. '
                  'Адреса, почта, конфигурация, токены и исходные логи не собираются.',
              'The complete file is below: category, stage, safe code and platform. '
                  'Addresses, email, configuration, tokens and raw logs are not collected.',
            ),
          ),
          const SizedBox(height: 16),
          SelectableText(widget.summary.json, key: const Key('diagnostic-preview')),
          const SizedBox(height: 24),
          if (!_created)
            FilledButton(onPressed: _busy ? null : _create, child: Text(tr('Создать файл', 'Create file'))),
          if (_created) ...[
            Text(tr('Создан файл: ', 'File created: ') + SafeDiagnosticExport.fileName),
            Text(
              tr(
                'Нажмите «Поделиться» и выберите, кому отправить или куда сохранить файл. '
                    'Временная копия удаляется при закрытии этого экрана.',
                'Choose Share to select a recipient or save location. '
                    'The temporary copy is deleted when this screen closes.',
              ),
            ),
            Builder(
              builder: (buttonContext) => FilledButton.icon(
                onPressed: _busy ? null : () => _share(buttonContext),
                icon: const Icon(Icons.share_outlined),
                label: Text(tr('Поделиться файлом', 'Share file')),
              ),
            ),
          ],
          if (_failed) Text(tr('Не удалось создать файл. Попробуйте ещё раз.', 'Could not create file. Try again.')),
          if (_result != null)
            Text(switch (_result!) {
              DiagnosticExportResult.shared => tr(
                'Файл передан выбранному приложению.',
                'File handed to the selected app.',
              ),
              DiagnosticExportResult.dismissed => tr('Отправка отменена.', 'Sharing cancelled.'),
              DiagnosticExportResult.unavailable => tr(
                'Система не подтвердила отправку файла.',
                'The system did not confirm sharing.',
              ),
              DiagnosticExportResult.failed => tr(
                'Не удалось открыть отправку. Попробуйте ещё раз.',
                'Could not share. Try again.',
              ),
            }),
        ],
      ),
    );
  }
}
