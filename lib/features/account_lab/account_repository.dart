import 'package:flutter/foundation.dart';
import 'package:hiddify/features/account_lab/account_protocol.dart';
import 'package:uuid/uuid.dart';

abstract interface class LabApi {
  Future<Map<String, dynamic>> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? access,
    String? requestKey,
    int expected = 200,
    Map<String, dynamic>? query,
  });
  void close();
}

abstract interface class LabTokenStore {
  /// Durably blocks re-reading this refresh before returning it, including after a crash.
  Future<Map<String, dynamic>?> claim();
  Future<void> save(Map<String, dynamic> value);
  Future<void> clear();
}

class AccountRepository extends ChangeNotifier {
  AccountRepository(this.api, this.store);
  final LabApi api;
  final LabTokenStore store;
  LabMe? me;
  List<LabSession> sessions = [];
  String? nextCursor;
  LabChallenge? challenge;
  LabTokens? _tokens;
  int _epoch = 0;
  bool _disposed = false;
  Future<void> _storageTail = Future.value();
  (int, Future<LabTokens>)? _rotation;
  (int, String?, LabChallenge)? _reauth;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _check(int epoch) {
    if (_disposed || epoch != _epoch) throw const LabFailure('operation_cancelled');
  }

  Future<T> _storage<T>(Future<T> Function() action) {
    final result = _storageTail.then((_) => action());
    _storageTail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _forget() {
    _tokens = null;
    me = null;
    sessions = [];
    nextCursor = null;
    challenge = null;
    _reauth = null;
    _changed();
  }

  Future<void> _closeRemote(String refresh) async {
    try {
      await api.call('POST', 'auth/logout', body: {'refresh_token': refresh}, expected: 204);
    } catch (_) {
      // Best effort cleanup; never log request bodies or transport exceptions.
    }
  }

  Future<void> _invalidate(int epoch) async {
    if (epoch != _epoch) return;
    _epoch++;
    _forget();
    await _storage(store.clear);
  }

  Future<void> restore() async {
    final epoch = ++_epoch;
    _forget();
    final saved = await _storage(store.claim);
    _check(epoch);
    if (saved == null) return;
    String? refresh;
    try {
      refresh = tokenValue(saved['refresh_token'], 'lr');
      final account = uuidValue(saved['account_id']);
      final session = uuidValue(saved['session_id']);
      final pair = LabTokens.fromJson(await api.call('POST', 'auth/refresh', body: {'refresh_token': refresh}));
      if (pair.accountId != account || pair.sessionId != session) {
        await _closeRemote(pair.refresh);
        throw const LabFailure('invalid_response');
      }
      await _accept(pair, epoch);
    } catch (_) {
      try {
        await _invalidate(epoch);
      } finally {
        if (refresh != null) await _closeRemote(refresh);
      }
      rethrow;
    }
  }

  Future<void> startEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9._+-]+@example\.test$').hasMatch(normalized) || normalized.length > 254) {
      throw const LabFailure('synthetic_email_required');
    }
    // Starting another account fences any pending completion/rotation.
    await logout();
    final epoch = _epoch;
    final verifier = newVerifier();
    final response = await api.call(
      'POST',
      'auth/email/start',
      expected: 202,
      body: {'email': normalized, 'challenge_s256': pkceChallenge(verifier), 'callback_id': 'native_ios'},
    );
    _check(epoch);
    challenge = LabChallenge.fromJson(response, verifier);
    _changed();
  }

  Future<void> completeEmail(String code) async {
    final pending = challenge;
    if (pending == null || !RegExp(r'^\d{6}$').hasMatch(code)) throw const LabFailure('code_invalid');
    final epoch = _epoch;
    final response = await api.call(
      'POST',
      'auth/email/complete',
      body: {'transaction_id': pending.id, 'code': code, 'client_verifier': pending.verifier},
    );
    final pair = LabTokens.fromJson(response);
    await _accept(pair, epoch);
    _check(epoch);
    challenge = null;
    _changed();
  }

  Future<void> _accept(LabTokens pair, int epoch) async {
    try {
      _check(epoch);
      final live = LabMe.fromJson(await api.call('GET', 'me', access: pair.access));
      _check(epoch);
      if (live.accountId != pair.accountId || live.sessionId != pair.sessionId) {
        throw const LabFailure('invalid_response');
      }
      await _storage(() async {
        _check(epoch);
        await store.save(pair.stored);
      });
      _check(epoch);
      _tokens = pair;
      me = live;
      _changed();
    } catch (_) {
      try {
        await _invalidate(epoch);
      } finally {
        await _closeRemote(pair.refresh);
      }
      rethrow;
    }
  }

  Future<LabTokens> _refresh(int epoch) {
    final existing = _rotation;
    if (existing != null && existing.$1 == epoch) return existing.$2;
    late final Future<LabTokens> future;
    future = _performRefresh(epoch).whenComplete(() {
      if (_rotation?.$2 == future) _rotation = null;
    });
    _rotation = (epoch, future);
    return future;
  }

  Future<LabTokens> _performRefresh(int epoch) async {
    final previous = _tokens;
    String? refresh;
    try {
      _check(epoch);
      final saved = await _storage(() {
        _check(epoch);
        return store.claim();
      });
      _check(epoch);
      if (saved == null ||
          previous == null ||
          saved['session_id'] != previous.sessionId ||
          saved['account_id'] != previous.accountId ||
          saved['refresh_token'] != previous.refresh) {
        throw const LabFailure('session_expired');
      }
      refresh = tokenValue(saved['refresh_token'], 'lr');
      final pair = LabTokens.fromJson(await api.call('POST', 'auth/refresh', body: {'refresh_token': refresh}));
      if (pair.accountId != previous.accountId || pair.sessionId != previous.sessionId) {
        await _closeRemote(pair.refresh);
        throw const LabFailure('invalid_response');
      }
      await _storage(() async {
        _check(epoch);
        await store.save(pair.stored);
      });
      _check(epoch);
      _tokens = pair;
      return pair;
    } catch (_) {
      try {
        await _invalidate(epoch);
      } finally {
        if (refresh != null) await _closeRemote(refresh);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _authorized(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? requestKey,
    int expected = 200,
    Map<String, dynamic>? query,
  }) async {
    final epoch = _epoch;
    var pair = _tokens;
    if (pair == null || me == null) throw const LabFailure('auth_required');
    if (!pair.accessExpires.isAfter(DateTime.now().toUtc())) pair = await _refresh(epoch);
    try {
      final data = await api.call(
        method,
        path,
        body: body,
        access: pair.access,
        requestKey: requestKey,
        expected: expected,
        query: query,
      );
      _check(epoch);
      return data;
    } on LabFailure catch (error) {
      _check(epoch);
      if (error.status != 401) rethrow;
      if (method != 'GET' || !{'session_expired', 'token_replaced'}.contains(error.code)) {
        await _invalidate(epoch);
        rethrow;
      }
      final current = _tokens;
      final next = current != null && current.access != pair.access ? current : await _refresh(epoch);
      try {
        final data = await api.call(method, path, access: next.access, query: query, expected: expected);
        _check(epoch);
        return data;
      } on LabFailure catch (retryError) {
        if (retryError.status == 401) await _invalidate(epoch);
        rethrow;
      }
    }
  }

  Future<void> loadSessions({bool more = false}) async {
    final epoch = _epoch;
    final cursor = more ? nextCursor : null;
    if (more && cursor == null) return;
    final data = await _authorized('GET', 'me/sessions', query: {'limit': 20, if (cursor != null) 'cursor': cursor});
    final rows = (data['items'] as List<dynamic>).map((v) => LabSession.fromJson(objectValue(v))).toList();
    final next = data['next_cursor'];
    if (next != null) stringValue(next, max: 4096);
    _check(epoch);
    sessions = more ? [...sessions, ...rows] : rows;
    nextCursor = next as String?;
    _changed();
  }

  Future<void> startRevoke(String? sessionId) async {
    final epoch = _epoch;
    final verifier = newVerifier();
    if (sessionId != null) uuidValue(sessionId);
    final data = await _authorized(
      'POST',
      'me/reauth/start',
      expected: 202,
      body: {
        'provider': 'email',
        'action': sessionId == null ? 'sessions.revoke_all' : 'sessions.revoke',
        'target_id': sessionId,
        'challenge_s256': pkceChallenge(verifier),
        'callback_id': 'native_ios',
      },
    );
    _check(epoch);
    _reauth = (epoch, sessionId, LabChallenge.fromJson(data, verifier));
  }

  Future<void> completeRevoke(String code) async {
    final pending = _reauth;
    if (pending == null || !RegExp(r'^\d{6}$').hasMatch(code)) throw const LabFailure('code_invalid');
    _check(pending.$1);
    final data = await _authorized(
      'POST',
      'me/reauth/complete',
      body: {'method': 'email', 'transaction_id': pending.$3.id, 'code': code, 'client_verifier': pending.$3.verifier},
    );
    final proof = tokenValue(data['reauth_proof'], 'rp');
    dateValue(data['expires_at']);
    _check(pending.$1);
    _reauth = null;
    await _authorized(
      'POST',
      pending.$2 == null ? 'me/sessions/revoke-all' : 'me/sessions/${pending.$2}/revoke',
      expected: 204,
      requestKey: const Uuid().v4(),
      body: {'reauth_proof': proof},
    );
    if (pending.$2 == null || pending.$2 == me?.sessionId) {
      await _invalidate(pending.$1);
    } else {
      await loadSessions();
    }
  }

  Future<void> logout() async {
    final refresh = _tokens?.refresh;
    final pending = challenge;
    _epoch++;
    _forget();
    var storageFailed = false;
    try {
      await _storage(store.clear);
    } catch (_) {
      storageFailed = true;
    }
    if (pending != null) {
      try {
        await api.call(
          'POST',
          'auth/transactions/${pending.id}/cancel',
          body: {'client_verifier': pending.verifier},
          expected: 204,
        );
      } catch (_) {
        /* expires server-side */
      }
    }
    if (refresh != null) {
      try {
        await api.call('POST', 'auth/logout', body: {'refresh_token': refresh}, expected: 204);
      } catch (_) {
        throw const LabFailure('remote_logout_unconfirmed');
      }
    }
    if (storageFailed) throw const LabFailure('secure_storage_unavailable');
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _forget();
    api.close();
    super.dispose();
  }
}
