import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/logger/log_sanitizer.dart';

void main() {
  test('redacts quoted JSON secrets and complete spaced credential values', () {
    for (final value in [
      '{"password":"PRIVATE_CANARY with spaces","nested":{"token":"PRIVATE_CANARY"}}',
      'password=PRIVATE_CANARY with spaces; status=failed',
      "{'private_key': 'PRIVATE_CANARY with spaces'}",
    ]) {
      expect(sanitizeLogText(value), isNot(contains('PRIVATE_CANARY')));
      expect(sanitizeLogText(value), isNot(contains('with spaces')));
    }
  });
  test('redacts access URLs and credential values', () {
    const canary = 'PRIVATE_CANARY_7d91';
    final sanitized = sanitizeLogText(
      'url=https://user:$canary@vpn.example/path?token=$canary '
      'password=$canary Authorization: Bearer $canary',
    );

    expect(sanitized, contains('<redacted-url>'));
    expect(sanitized, contains('password=<redacted>'));
    expect(sanitized, contains('Authorization=<redacted>'));
    expect(sanitized, isNot(contains(canary)));
  });

  test('keeps ordinary diagnostic text useful', () {
    expect(sanitizeLogText('connection timed out after 5000ms'), 'connection timed out after 5000ms');
  });

  test('redacts addresses, email and absolute paths before every sink', () {
    const canary =
        'server=vpn.private.example ip=203.0.113.42 ipv6=2001:db8::1 '
        'email=user@example.com path=/Users/test/private/config.json';

    final sanitized = sanitizeLogText(canary);

    expect(sanitized, isNot(contains('vpn.private.example')));
    expect(sanitized, isNot(contains('203.0.113.42')));
    expect(sanitized, isNot(contains('2001:db8::1')));
    expect(sanitized, isNot(contains('user@example.com')));
    expect(sanitized, isNot(contains('/Users/test/private/config.json')));
  });
}
