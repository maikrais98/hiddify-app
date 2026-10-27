import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/account_lab/account_protocol.dart';
import 'live_hermes_test.dart' show liveSettings;

void main() {
  test('live lab requires explicit local settings without infrastructure defaults', () {
    expect(() => liveSettings({}), throwsA(isA<LabFailure>()));
    expect(
      liveSettings({
        'LUMA_LIVE_SSH_TARGET': 'tester@lab.example.test',
        'LUMA_LIVE_MAILBOX_DIR': '/private/lab/mailbox',
      }),
      ('tester@lab.example.test', '/private/lab/mailbox'),
    );
  });
  test('live settings cannot inject SSH options or remote shell commands', () {
    for (final target in ['-oProxyCommand=command', 'tester@lab;command', 'tester@lab host']) {
      expect(
        () => liveSettings({'LUMA_LIVE_SSH_TARGET': target, 'LUMA_LIVE_MAILBOX_DIR': '/private/lab/mailbox'}),
        throwsA(isA<LabFailure>()),
      );
    }
    for (final path in ['/private/box;command', '/private/box\ncommand', 'relative/path', '/private/../secret']) {
      expect(
        () => liveSettings({'LUMA_LIVE_SSH_TARGET': 'tester@lab.example.test', 'LUMA_LIVE_MAILBOX_DIR': path}),
        throwsA(isA<LabFailure>()),
      );
    }
  });
}
