import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/account_lab/account_protocol.dart';

void main() {
  test('RFC 7636 S256 vector', () {
    expect(pkceChallenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'), 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
    expect(newVerifier(Random(42)), matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
  });
  test('private HTTPS and loopback HTTP only, exact API path', () {
    expect(privateApiUri('https://192.168.1.5:55443/api/luma/v1/').host, '192.168.1.5');
    expect(privateApiUri('http://127.0.0.1:55442/api/luma/v1/').port, 55442);
    for (final url in [
      'http://192.168.1.5/api/luma/v1/',
      'https://example.com/api/luma/v1/',
      'https://8.8.8.8/api/luma/v1/',
      'https://010.0.0.1/api/luma/v1/',
      'https://user:pass@192.168.1.5/api/luma/v1/',
      'https://192.168.1.5/api/luma/v1/?token=secret',
      'https://192.168.1.5/other/',
    ]) {
      expect(() => privateApiUri(url), throwsA(isA<LabFailure>()), reason: url);
    }
  });
  test('strict token kinds, IDs and expiry ordering', () {
    final json = tokenJson();
    expect(() => LabTokens.fromJson(json), returnsNormally);
    for (final change in [
      {'refresh_token': json['access_token']},
      {'session_id': 'bad'},
      {'absolute_expires_at': '2020-01-01T00:00:00Z'},
      {'access_expires_at': '2026-01-01T00:00:00'},
    ]) {
      expect(() => LabTokens.fromJson({...json, ...change}), throwsA(isA<LabFailure>()));
    }
  });
  test('errors do not stringify server content or secrets', () {
    expect(const LabFailure('network_unavailable').toString(), 'network_unavailable');
  });
}

Map<String, dynamic> tokenJson({String suffix = 'a'}) => {
  'account_id': '11111111-1111-4111-8111-111111111111',
  'session_id': '22222222-2222-4222-8222-222222222222',
  'access_token': 'la_${List.filled(43, suffix).join()}',
  'refresh_token': 'lr_${List.filled(43, suffix).join()}',
  'access_expires_at': '2090-01-01T00:00:00Z',
  'idle_expires_at': '2090-01-02T00:00:00Z',
  'absolute_expires_at': '2090-02-01T00:00:00Z',
};
