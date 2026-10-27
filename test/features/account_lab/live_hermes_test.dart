// Opt-in synthetic integration, through an owned loopback SSH tunnel only.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/account_lab/account_io.dart';
import 'package:hiddify/features/account_lab/account_protocol.dart';
import 'package:hiddify/features/account_lab/account_repository.dart';

import 'repository_test.dart' show MemoryStore;

(String, String) liveSettings(Map<String, String> environment) {
  final target = environment['LUMA_LIVE_SSH_TARGET'];
  final mailbox = environment['LUMA_LIVE_MAILBOX_DIR'];
  if (target == null ||
      mailbox == null ||
      !RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_.-]*@[A-Za-z0-9][A-Za-z0-9.-]*$').hasMatch(target) ||
      !RegExp(r'^/[A-Za-z0-9_./-]+$').hasMatch(mailbox) ||
      mailbox.split('/').contains('..')) {
    throw const LabFailure('local_lab_settings_required');
  }
  return (target, mailbox);
}

void main() {
  test(
    'Hermes synthetic login, durable restore, reauth and revoke all',
    () async {
      final (host, mailbox) = liveSettings(Platform.environment);
      const email = 'alice@example.test';
      final reserved = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = reserved.port;
      await reserved.close();
      final ssh = await Process.start('ssh', [
        '-N',
        '-T',
        '-o',
        'BatchMode=yes',
        '-o',
        'ExitOnForwardFailure=yes',
        '-L',
        '127.0.0.1:$port:127.0.0.1:55441',
        host,
      ]);
      unawaited(ssh.stdout.drain<void>());
      unawaited(ssh.stderr.drain<void>());
      AccountRepository? repository;
      try {
        var connected = false;
        for (var i = 0; i < 50; i++) {
          try {
            final socket = await Socket.connect('127.0.0.1', port, timeout: const Duration(milliseconds: 200));
            socket.destroy();
            connected = true;
            break;
          } on SocketException {
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
        }
        expect(connected, isTrue, reason: 'Owned SSH tunnel must be ready');
        Future<String> otp() async {
          final name = sha256.convert(utf8.encode(email)).toString();
          final read = await Process.run('ssh', [
            '-T',
            '-o',
            'BatchMode=yes',
            host,
            'sudo',
            '-n',
            'cat',
            '$mailbox/$name.json',
          ]);
          if (read.exitCode != 0) throw const LabFailure('mailbox_unavailable');
          final payload = jsonDecode(read.stdout as String) as Map<String, dynamic>;
          if (payload['email'] != email) throw const LabFailure('mailbox_mismatch');
          return payload['code'] as String;
        }

        final store = MemoryStore();
        final url = 'http://127.0.0.1:$port/api/luma/v1/';
        repository = AccountRepository(DioLabApi(url, enabled: true), store);
        await repository.startEmail(email);
        await repository.completeEmail(await otp());
        await repository.loadSessions();
        expect(repository.sessions.where((row) => row.current).length, 1);
        final account = repository.me!.accountId;
        final session = repository.me!.sessionId;
        repository.dispose();
        repository = AccountRepository(DioLabApi(url, enabled: true), store);
        await repository.restore();
        expect(repository.me!.accountId, account);
        expect(repository.me!.sessionId, session);
        final revokedRefresh = store.value!['refresh_token'];
        await repository.startRevoke(null);
        await repository.completeRevoke(await otp());
        expect(repository.me, isNull);
        expect(store.value, isNull);
        final probe = DioLabApi(url, enabled: true);
        try {
          await expectLater(
            probe.call('POST', 'auth/refresh', body: {'refresh_token': revokedRefresh}),
            throwsA(isA<LabFailure>().having((error) => error.status, 'revoked on server', 401)),
          );
        } finally {
          probe.close();
        }
        await repository.restore();
        expect(repository.me, isNull);
      } finally {
        if (repository != null) {
          try {
            await repository.logout();
          } catch (_) {
            /* reported by failed test, never print tokens */
          }
          repository.dispose();
        }
        ssh.kill();
        await ssh.exitCode;
      }
    },
    skip: Platform.environment['LUMA_LIVE_HERMES'] != '1',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
