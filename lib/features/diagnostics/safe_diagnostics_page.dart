import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
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
    final nova = NovaThemeData.of(context);
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
      appBar: AppBar(centerTitle: true, title: Text(tr('Безопасная диагностика', 'Safe diagnostics'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(NovaSpacing.gutter, NovaSpacing.lg, NovaSpacing.gutter, NovaSpacing.xl),
        children: [
          DecoratedBox(
            key: const Key('diagnostic-summary-card'),
            decoration: BoxDecoration(
              color: nova.surface,
              borderRadius: BorderRadius.circular(NovaRadii.large),
              border: Border.all(color: nova.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(NovaSpacing.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(color: nova.accentFill, shape: BoxShape.circle),
                    child: Padding(
                      padding: const EdgeInsets.all(NovaSpacing.sm),
                      child: Icon(Icons.health_and_safety_outlined, color: nova.accent, size: 22),
                    ),
                  ),
                  const SizedBox(width: NovaSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$category · $stage', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: NovaSpacing.xs),
                        Text(
                          tr('Доступность интернета не проверялась.', 'Internet reachability has not been checked.'),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: nova.secondaryText),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: NovaSpacing.lg),
          Text(
            tr(
              'Снимок состояния на момент открытия. Этот отчёт содержит только поля, показанные ниже.',
              'Snapshot when opened. This report contains only the fields shown below.',
            ),
          ),
          const SizedBox(height: NovaSpacing.sm),
          Text(
            tr(
              'Отчёт не включает исходные логи, адреса, почту, конфигурацию, токены и идентификаторы.',
              'This report does not include raw logs, URLs, email, configuration, tokens, or identifiers.',
            ),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: nova.secondaryText),
          ),
          const SizedBox(height: NovaSpacing.xl),
          Text(tr('Содержимое отчёта', 'Report contents'), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: NovaSpacing.sm),
          DecoratedBox(
            key: const Key('diagnostic-preview-card'),
            decoration: BoxDecoration(
              color: nova.groupedBackground,
              borderRadius: BorderRadius.circular(NovaRadii.medium),
              border: Border.all(color: nova.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(NovaSpacing.md),
              child: SelectableText(
                widget.summary.json,
                key: const Key('diagnostic-preview'),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: nova.secondaryText, fontFamily: 'monospace', height: 1.45),
              ),
            ),
          ),
          const SizedBox(height: NovaSpacing.md),
          Text(
            tr(
              'При создании файла приложение сохраняет временную копию и попытается удалить её при закрытии экрана. '
                  'Сохранённые и отправленные копии приложение не удаляет.',
              'Creating a file stores a temporary copy. The app attempts to delete it when this screen closes. '
                  'Copies you save or share are not deleted by the app.',
            ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: nova.tertiaryText),
          ),
          const SizedBox(height: NovaSpacing.xl),
          if (!_created)
            FilledButton.icon(
              key: const Key('diagnostic-create-button'),
              onPressed: _busy ? null : _create,
              icon: const Icon(Icons.description_outlined),
              label: Text(tr('Создать файл', 'Create file')),
            ),
          if (_created) ...[
            Text(
              tr('Создан файл: ', 'File created: ') + SafeDiagnosticExport.fileName,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: NovaSpacing.xs),
            Text(
              tr(
                'Нажмите «Поделиться» и выберите, кому отправить или куда сохранить файл. '
                    'Отправка происходит только после отдельного действия.',
                'Choose Share to select a recipient or save location. Sharing happens only after a separate action.',
              ),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: nova.secondaryText),
            ),
            const SizedBox(height: NovaSpacing.md),
            Builder(
              builder: (buttonContext) => FilledButton.icon(
                key: const Key('diagnostic-share-button'),
                onPressed: _busy ? null : () => _share(buttonContext),
                icon: const Icon(Icons.share_outlined),
                label: Text(tr('Поделиться файлом', 'Share file')),
              ),
            ),
          ],
          if (_failed) ...[
            const SizedBox(height: NovaSpacing.md),
            Text(tr('Не удалось создать файл. Попробуйте ещё раз.', 'Could not create file. Try again.')),
          ],
          if (_result != null)
            Padding(
              padding: const EdgeInsets.only(top: NovaSpacing.md),
              child: Text(switch (_result!) {
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
            ),
        ],
      ),
    );
  }
}
