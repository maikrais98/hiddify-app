import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/features/account_lab/account_io.dart';
import 'package:hiddify/features/account_lab/account_protocol.dart';
import 'package:hiddify/features/account_lab/account_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final accountLabProvider = Provider<AccountRepository>((ref) {
  final api = DioLabApi(labBaseUrl, certificateDer: base64Decode(labCertificate));
  final scope = sha256.convert(utf8.encode('$labBaseUrl|$labCertificate')).toString();
  final repository = AccountRepository(api, KeychainLabStore(scope));
  ref.onDispose(repository.dispose);
  return repository;
});

class AccountLabPage extends ConsumerStatefulWidget {
  const AccountLabPage({super.key});
  @override
  ConsumerState<AccountLabPage> createState() => _AccountLabPageState();
}

class _AccountLabPageState extends ConsumerState<AccountLabPage> {
  final _email = TextEditingController(text: 'alice@example.test');
  final _code = TextEditingController();
  AccountRepository? _repository;
  bool _busy = false;
  bool _revoking = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() async {
      if (!mounted) return;
      try {
        _repository = ref.read(accountLabProvider);
      } catch (_) {
        setState(() => _error = 'Не настроено закрытое тестовое подключение. Проверь инструкцию для Mac.');
        return;
      }
      await _run(() async {
        await _repository!.restore();
        if (_repository!.me != null) await _repository!.loadSessions();
      });
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object error) {
    final code = error is LabFailure ? error.code : 'invalid_response';
    return switch (code) {
      'synthetic_email_required' => 'Используй alice@example.test или bob@example.test.',
      'code_invalid' => 'Код не подошёл. Проверь шесть цифр.',
      'challenge_expired' || 'challenge_used' => 'Код больше не действует. Начни вход заново.',
      'rate_limited' => 'Слишком много попыток. Подожди перед повтором.',
      'network_unavailable' || 'auth_unavailable' => 'Тестовый сервер недоступен. Проверь соединение с Mac.',
      'secure_storage_unavailable' => 'Не удалось открыть защищённое хранилище. Разблокируй iPhone и повтори вход.',
      'remote_logout_unconfirmed' =>
        'На этом устройстве выполнен выход. Отзыв на сервере не подтверждён; проверь сессии после восстановления связи.',
      'operation_cancelled' => 'Действие отменено.',
      'auth_required' ||
      'session_expired' ||
      'session_revoked' ||
      'refresh_invalid' ||
      'refresh_reused' ||
      'refresh_expired' ||
      'token_replaced' => 'Сессия закрыта. Войди заново.',
      _ => 'Действие не завершено. Повтори вход или проверь настройки тестовой сборки.',
    };
  }

  Future<void> _beginRevoke(String? target) => _run(() async {
    await _repository!.startRevoke(target);
    if (mounted) {
      setState(() {
        _revoking = true;
        _code.clear();
      });
    }
  });
  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = _repository;
    return Scaffold(
      appBar: AppBar(title: const Text('Тестовый аккаунт U3')),
      body: repository == null
          ? Padding(padding: const EdgeInsets.all(24), child: Text(_error ?? 'Подготовка…'))
          : ListenableBuilder(
              listenable: repository,
              builder: (context, _) {
                final me = repository.me;
                return ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const Text('Закрытая тестовая сборка • синтетические данные'),
                    const SizedBox(height: 16),
                    if (_busy) const LinearProgressIndicator(),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                    if (me == null) ...[
                      TextField(
                        controller: _email,
                        enabled: !_busy && repository.challenge == null,
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Тестовый email'),
                      ),
                      const SizedBox(height: 12),
                      if (repository.challenge == null)
                        FilledButton(
                          onPressed: _busy ? null : () => _run(() => repository.startEmail(_email.text)),
                          child: const Text('Получить тестовый код'),
                        )
                      else ...[
                        const Text('Код из тестового почтового ящика'),
                        _codeField(),
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  final code = _code.text;
                                  _code.clear();
                                  _run(() async {
                                    await repository.completeEmail(code);
                                    await repository.loadSessions();
                                  });
                                },
                          child: const Text('Войти'),
                        ),
                        TextButton(
                          onPressed: _busy ? null : () => _run(repository.logout),
                          child: const Text('Начать вход заново'),
                        ),
                      ],
                    ] else ...[
                      ...me.identities.map((value) => Text(value, style: Theme.of(context).textTheme.titleMedium)),
                      const SizedBox(height: 16),
                      const Text('Активные сессии'),
                      ...repository.sessions.map(
                        (session) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(session.label),
                          subtitle: Text(session.current ? 'Это устройство' : 'Другая сессия'),
                          trailing: TextButton(
                            onPressed: _busy || _revoking ? null : () => _beginRevoke(session.id),
                            child: const Text('Закрыть'),
                          ),
                        ),
                      ),
                      if (repository.nextCursor != null)
                        TextButton(
                          onPressed: _busy ? null : () => _run(() => repository.loadSessions(more: true)),
                          child: const Text('Показать ещё'),
                        ),
                      if (_revoking) ...[
                        const Text('Подтверди отзыв новым тестовым кодом'),
                        _codeField(),
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  final code = _code.text;
                                  _code.clear();
                                  _run(() async {
                                    await repository.completeRevoke(code);
                                    if (mounted) setState(() => _revoking = false);
                                  });
                                },
                          child: const Text('Подтвердить отзыв'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _revoking = false;
                                  _code.clear();
                                }),
                          child: const Text('Отмена'),
                        ),
                      ],
                      OutlinedButton(
                        onPressed: _busy || _revoking ? null : () => _beginRevoke(null),
                        child: const Text('Закрыть все сессии'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : () => _run(repository.loadSessions),
                        child: const Text('Обновить список'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                _revoking = false;
                                _code.clear();
                                await repository.logout();
                              }),
                        child: const Text('Выйти из аккаунта'),
                      ),
                    ],
                  ],
                );
              },
            ),
    );
  }

  Widget _codeField() => TextField(
    key: const Key('lab-code'),
    controller: _code,
    enabled: !_busy,
    obscureText: true,
    autofillHints: null,
    autocorrect: false,
    enableSuggestions: false,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
    decoration: const InputDecoration(labelText: 'Код из 6 цифр'),
  );
}
