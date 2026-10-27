import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/account_lab/account_protocol.dart';
import 'package:hiddify/features/account_lab/account_repository.dart';

import 'protocol_test.dart' show tokenJson;

const accountId = '11111111-1111-4111-8111-111111111111';
const sessionId = '22222222-2222-4222-8222-222222222222';
Map<String, dynamic> meJson() => {
  'account_id': accountId,
  'session_id': sessionId,
  'identities': [
    {'provider': 'email', 'display': 'a***@example.test'},
  ],
  'capabilities': <String>[],
};
Map<String, dynamic> challengeJson() => {
  'transaction_id': accountId,
  'expires_at': '2090-01-01T00:00:00Z',
  'resend_after': 30,
};

class MemoryStore implements LabTokenStore {
  Map<String, dynamic>? value;
  bool blocked = false;
  bool failSave = false;
  bool failClear = false;
  int claims = 0;
  @override
  Future<Map<String, dynamic>?> claim() async {
    claims++;
    if (blocked) return null;
    blocked = true;
    return value;
  }

  @override
  Future<void> save(Map<String, dynamic> value) async {
    blocked = true;
    if (failSave) throw const LabFailure('secure_storage_unavailable');
    this.value = Map.of(value);
    blocked = false;
  }

  @override
  Future<void> clear() async {
    blocked = true;
    if (failClear) throw const LabFailure('secure_storage_unavailable');
    value = null;
  }
}

class FakeApi implements LabApi {
  final calls = <String>[];
  Future<Map<String, dynamic>> Function(String path, Map<String, dynamic>? body, String? access)? handler;
  @override
  Future<Map<String, dynamic>> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? access,
    String? requestKey,
    int expected = 200,
    Map<String, dynamic>? query,
  }) async {
    calls.add(path);
    if (handler != null) return handler!(path, body, access);
    if (path.endsWith('/start')) return challengeJson();
    if (path == 'auth/email/complete' || path == 'auth/refresh') return tokenJson();
    if (path == 'me') return meJson();
    if (path == 'me/sessions') return {'items': <dynamic>[], 'next_cursor': null};
    return {};
  }

  @override
  void close() {}
}

void main() {
  late MemoryStore store;
  late FakeApi api;
  late AccountRepository repo;
  setUp(() {
    store = MemoryStore();
    api = FakeApi();
    repo = AccountRepository(api, store);
  });
  Future<void> login() async {
    await repo.startEmail(' ALICE@example.test ');
    await repo.completeEmail('123456');
  }

  test('PKCE login validates me and stores only refresh and IDs', () async {
    await login();
    expect(repo.me?.accountId, accountId);
    expect(store.value!.keys.toSet(), {'account_id', 'session_id', 'refresh_token'});
    expect(repo.challenge, isNull);
  });
  test('only synthetic email accepted', () async {
    await expectLater(repo.startEmail('someone@gmail.com'), throwsA(isA<LabFailure>()));
    expect(api.calls, isEmpty);
  });
  test('restore claims durable token before refresh and validates IDs', () async {
    store.value = {'account_id': accountId, 'session_id': sessionId, 'refresh_token': tokenJson()['refresh_token']};
    api.handler = (path, body, access) async {
      if (path == 'auth/refresh') {
        expect(store.blocked, isTrue);
        return tokenJson(suffix: 'b');
      }
      return meJson();
    };
    await repo.restore();
    expect(repo.me?.sessionId, sessionId);
    expect(store.blocked, isFalse);
  });
  test('crash pending token cannot be replayed on restart', () async {
    store.value = tokenJson();
    store.blocked = true;
    await repo.restore();
    expect(api.calls, isEmpty);
    expect(repo.me, isNull);
  });
  test('concurrent 401 GETs rotate refresh only once', () async {
    await login();
    final rotation = Completer<Map<String, dynamic>>();
    final oldAccess = tokenJson()['access_token'];
    api.handler = (path, body, access) async {
      if (path == 'auth/refresh') return rotation.future;
      if (path == 'me/sessions' && access == oldAccess) throw const LabFailure('token_replaced', status: 401);
      return {'items': <dynamic>[], 'next_cursor': null};
    };
    final a = repo.loadSessions();
    final b = repo.loadSessions();
    await Future<void>.delayed(Duration.zero);
    expect(api.calls.where((p) => p == 'auth/refresh').length, 1);
    rotation.complete(tokenJson(suffix: 'b'));
    await Future.wait([a, b]);
    expect(store.claims, 1);
  });
  test('lost refresh response is never retried or restorable', () async {
    await login();
    api.handler = (path, body, access) async {
      if (path == 'auth/refresh') throw const LabFailure('network_unavailable');
      if (path == 'auth/logout') return {};
      throw const LabFailure('session_expired', status: 401);
    };
    await expectLater(repo.loadSessions(), throwsA(isA<LabFailure>()));
    await repo.restore();
    expect(api.calls.where((p) => p == 'auth/refresh').length, 1);
    expect(repo.me, isNull);
    expect(store.value, isNull);
  });
  test('late login after logout is discarded and server session closed', () async {
    await repo.startEmail('alice@example.test');
    final response = Completer<Map<String, dynamic>>();
    api.handler = (path, body, access) async => path == 'auth/email/complete' ? response.future : {};
    final loginFuture = repo.completeEmail('123456');
    final assertion = expectLater(loginFuture, throwsA(isA<LabFailure>()));
    await repo.logout();
    response.complete(tokenJson());
    await assertion;
    expect(repo.me, isNull);
    expect(store.value, isNull);
    expect(api.calls, contains('auth/logout'));
  });
  test('Keychain failure never leaves an authenticated account', () async {
    store.failSave = true;
    await expectLater(login(), throwsA(isA<LabFailure>()));
    expect(repo.me, isNull);
    expect(store.blocked, isTrue);
    expect(api.calls, contains('auth/logout'));
  });
  test('mismatched me account is rejected', () async {
    api.handler = (path, body, access) async {
      if (path.endsWith('/start')) return challengeJson();
      if (path.endsWith('/complete')) return tokenJson();
      if (path == 'me') return {...meJson(), 'account_id': sessionId};
      return {};
    };
    await expectLater(login(), throwsA(isA<LabFailure>()));
    expect(repo.me, isNull);
    expect(store.value, isNull);
  });
  test('revoked session clears locally without refresh', () async {
    await login();
    api.handler = (path, body, access) async => throw const LabFailure('session_revoked', status: 401);
    await expectLater(repo.loadSessions(), throwsA(isA<LabFailure>()));
    expect(repo.me, isNull);
    expect(store.value, isNull);
    expect(api.calls, isNot(contains('auth/refresh')));
  });
  test('late refresh cannot resurrect a logged out session', () async {
    await login();
    final response = Completer<Map<String, dynamic>>();
    api.handler = (path, body, access) async {
      if (path == 'auth/refresh') return response.future;
      if (path == 'auth/logout') return {};
      throw const LabFailure('session_expired', status: 401);
    };
    final request = repo.loadSessions();
    final assertion = expectLater(request, throwsA(isA<LabFailure>()));
    await Future<void>.delayed(Duration.zero);
    await repo.logout();
    response.complete(tokenJson(suffix: 'b'));
    await assertion;
    expect(repo.me, isNull);
    expect(store.value, isNull);
  });
  test('reauth action and proof are sent once with an idempotency key', () async {
    await login();
    api.handler = (path, body, access) async {
      if (path == 'me/reauth/start') {
        expect(body!['action'], 'sessions.revoke_all');
        expect(body['target_id'], isNull);
        return challengeJson();
      }
      if (path == 'me/reauth/complete') {
        expect(body!['method'], 'email');
        return {'reauth_proof': 'rp_${List.filled(43, 'c').join()}', 'expires_at': '2090-01-01T00:00:00Z'};
      }
      if (path == 'me/sessions/revoke-all') {
        expect(body!.keys, ['reauth_proof']);
        return {};
      }
      throw const LabFailure('unexpected_call');
    };
    await repo.startRevoke(null);
    await repo.completeRevoke('123456');
    expect(repo.me, isNull);
    expect(store.value, isNull);
    await expectLater(repo.completeRevoke('123456'), throwsA(isA<LabFailure>()));
    expect(api.calls.where((path) => path == 'me/sessions/revoke-all').length, 1);
  });
  test('failed remote logout keeps local state cleared and reports uncertainty', () async {
    await login();
    api.handler = (path, body, access) async => throw const LabFailure('network_unavailable');
    await expectLater(
      repo.logout(),
      throwsA(isA<LabFailure>().having((e) => e.code, 'code', 'remote_logout_unconfirmed')),
    );
    expect(repo.me, isNull);
    expect(store.value, isNull);
  });
  test('storage deletion failure still attempts server logout', () async {
    await login();
    store.failClear = true;
    await expectLater(repo.logout(), throwsA(isA<LabFailure>()));
    expect(repo.me, isNull);
    expect(api.calls, contains('auth/logout'));
  });
}
