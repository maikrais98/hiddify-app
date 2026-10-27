import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/features/account_lab/account_protocol.dart';
import 'package:hiddify/features/account_lab/account_repository.dart';

class DioLabApi implements LabApi {
  DioLabApi(String url, {Uint8List? certificateDer, bool enabled = labEnabled}) {
    if (!kDebugMode || !enabled) throw const LabFailure('debug_only');
    final uri = privateApiUri(url);
    final context = SecurityContext();
    if (uri.scheme == 'https') {
      if (certificateDer == null || certificateDer.isEmpty) throw const LabFailure('certificate_required');
      try {
        // Dart's iOS TLS implementation accepts a single DER certificate; desktop uses PEM.
        final encoded = base64Encode(certificateDer).replaceAllMapped(RegExp('.{1,64}'), (m) => '${m[0]}\n');
        context.setTrustedCertificatesBytes(
          Platform.isIOS
              ? certificateDer
              : ascii.encode('-----BEGIN CERTIFICATE-----\n$encoded-----END CERTIFICATE-----\n'),
        );
      } catch (_) {
        throw const LabFailure('invalid_certificate');
      }
    }
    _dio = Dio(
      BaseOptions(
        baseUrl: uri.toString(),
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 10),
        followRedirects: false,
        maxRedirects: 0,
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
        headers: {'Accept': 'application/json', 'Cache-Control': 'no-store'},
      ),
    );
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => HttpClient(context: context)..findProxy = (_) => 'DIRECT',
    );
  }
  late final Dio _dio;
  static final _dynamicPath = RegExp(
    r'^(auth/transactions/[a-fA-F0-9-]{36}/cancel|me/sessions/[a-fA-F0-9-]{36}/revoke)$',
  );
  static const _post = {
    'auth/email/start',
    'auth/email/complete',
    'auth/refresh',
    'auth/logout',
    'me/reauth/start',
    'me/reauth/complete',
    'me/sessions/revoke-all',
  };
  static const _codes = {
    'auth_required',
    'session_expired',
    'session_revoked',
    'token_replaced',
    'refresh_invalid',
    'refresh_expired',
    'refresh_reused',
    'account_blocked',
    'forbidden',
    'code_invalid',
    'challenge_used',
    'challenge_expired',
    'rate_limited',
    'auth_unavailable',
    'invalid_request',
    'reauth_required',
    'reauth_invalid',
    'reauth_expired',
    'not_found',
    'cursor_invalid',
  };
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
    if (!(method == 'GET' && {'me', 'me/sessions'}.contains(path)) &&
        !(method == 'POST' && (_post.contains(path) || _dynamicPath.hasMatch(path)))) {
      throw const LabFailure('invalid_operation');
    }
    if (access != null) tokenValue(access, 'la');
    if (requestKey != null) uuidValue(requestKey);
    if (query != null && (path != 'me/sessions' || query.keys.any((k) => !{'cursor', 'limit'}.contains(k)))) {
      throw const LabFailure('invalid_operation');
    }
    try {
      final response = await _dio.request<String>(
        path,
        data: body,
        queryParameters: query,
        options: Options(
          method: method,
          headers: {
            if (access != null) 'Authorization': 'Bearer $access',
            if (requestKey != null) 'Idempotency-Key': requestKey,
            if (body != null) 'Content-Type': 'application/json',
          },
        ),
      );
      if (response.statusCode == 204 && expected == 204) return {};
      final text = response.data ?? '';
      if (text.length > 65536) throw const LabFailure('invalid_response');
      final json = objectValue(jsonDecode(text));
      uuidValue(json['request_id']);
      if (response.statusCode == expected && json['ok'] == true) return objectValue(json['data']);
      final status = response.statusCode ?? 0;
      final code = json['error'];
      throw LabFailure(
        json['ok'] == false && _codes.contains(code) ? code as String : 'request_failed',
        status: status,
      );
    } on LabFailure {
      rethrow;
    } on DioException {
      throw const LabFailure('network_unavailable');
    } catch (_) {
      throw const LabFailure('invalid_response');
    }
  }

  @override
  void close() => _dio.close(force: true);
}

class KeychainLabStore implements LabTokenStore {
  KeychainLabStore(
    this.scope, {
    this.channel = const MethodChannel('com.hiddify.app/platform'),
    bool enabled = labEnabled,
  }) {
    if (!kDebugMode || !enabled) throw const LabFailure('debug_only');
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(scope)) throw const LabFailure('invalid_storage_scope');
  }
  final String scope;
  final MethodChannel channel;
  @override
  Future<Map<String, dynamic>?> claim() async {
    final result = await _invoke('lab_session_claim');
    if (result == null) return null;
    return _stored(Map<String, dynamic>.from(result as Map));
  }

  Map<String, dynamic> _stored(Map<String, dynamic> value) => {
    'account_id': uuidValue(value['account_id']),
    'session_id': uuidValue(value['session_id']),
    'refresh_token': tokenValue(value['refresh_token'], 'lr'),
  };
  Future<dynamic> _invoke(String method, [Map<String, dynamic>? value]) async {
    try {
      return await channel.invokeMethod<dynamic>(method, {'scope': scope, if (value != null) 'value': value});
    } catch (_) {
      throw const LabFailure('secure_storage_unavailable');
    }
  }

  @override
  Future<void> save(Map<String, dynamic> value) async {
    await _invoke('lab_session_save', _stored(value));
  }

  @override
  Future<void> clear() async {
    await _invoke('lab_session_clear');
  }
}
