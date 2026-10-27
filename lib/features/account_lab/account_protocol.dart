import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

const labEnabled = kDebugMode && bool.fromEnvironment('LUMA_ACCOUNT_LAB');
const labBaseUrl = String.fromEnvironment('LUMA_ACCOUNT_BASE_URL');
const labCertificate = String.fromEnvironment('LUMA_ACCOUNT_CERT_BASE64');

String pkceChallenge(String verifier) =>
    base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
String newVerifier([Random? random]) {
  final source = random ?? Random.secure();
  return base64Url.encode(List.generate(32, (_) => source.nextInt(256))).replaceAll('=', '');
}

Uri privateApiUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.path != '/api/luma/v1/' ||
      !isPrivateHost(uri.host) ||
      (uri.scheme != 'https' && !(uri.scheme == 'http' && uri.host == '127.0.0.1'))) {
    throw const LabFailure('invalid_private_endpoint');
  }
  return uri;
}

bool isPrivateHost(String host) {
  final parts = host.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null || p < 0 || p > 255)) return false;
  if (parts.join('.') != host) return false;
  return host == '127.0.0.1' ||
      parts[0] == 10 ||
      (parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31) ||
      (parts[0] == 192 && parts[1] == 168);
}

final _uuid = RegExp(r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$');
String uuidValue(dynamic value) {
  if (value is! String || !_uuid.hasMatch(value)) throw const LabFailure('invalid_response');
  return value;
}

String stringValue(dynamic value, {int max = 512}) {
  if (value is! String || value.isEmpty || value.length > max) throw const LabFailure('invalid_response');
  return value;
}

Map<String, dynamic> objectValue(dynamic value) {
  if (value is! Map<String, dynamic>) throw const LabFailure('invalid_response');
  return value;
}

DateTime dateValue(dynamic value) {
  final raw = stringValue(value, max: 40);
  if (!RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(raw)) throw const LabFailure('invalid_response');
  final date = DateTime.tryParse(raw);
  if (date == null) throw const LabFailure('invalid_response');
  return date.toUtc();
}

String tokenValue(dynamic value, String prefix) {
  if (value is! String || !RegExp('^${prefix}_[A-Za-z0-9_-]{43}\$').hasMatch(value)) {
    throw const LabFailure('invalid_response');
  }
  return value;
}

class LabFailure implements Exception {
  const LabFailure(this.code, {this.status = 0});
  final String code;
  final int status;
  @override
  String toString() => code;
}

class LabTokens {
  LabTokens.fromJson(Map<String, dynamic> json)
    : accountId = uuidValue(json['account_id']),
      sessionId = uuidValue(json['session_id']),
      access = tokenValue(json['access_token'], 'la'),
      refresh = tokenValue(json['refresh_token'], 'lr'),
      accessExpires = dateValue(json['access_expires_at']),
      idleExpires = dateValue(json['idle_expires_at']),
      absoluteExpires = dateValue(json['absolute_expires_at']) {
    if (accessExpires.isAfter(idleExpires) || idleExpires.isAfter(absoluteExpires)) {
      throw const LabFailure('invalid_response');
    }
  }
  final String accountId;
  final String sessionId;
  final String access;
  final String refresh;
  final DateTime accessExpires;
  final DateTime idleExpires;
  final DateTime absoluteExpires;
  Map<String, dynamic> get stored => {'account_id': accountId, 'session_id': sessionId, 'refresh_token': refresh};
}

class LabMe {
  LabMe.fromJson(Map<String, dynamic> json)
    : accountId = uuidValue(json['account_id']),
      sessionId = uuidValue(json['session_id']),
      identities = (json['identities'] as List<dynamic>)
          .map((e) {
            final row = objectValue(e);
            return '${stringValue(row['provider'], max: 30)}: ${stringValue(row['display'], max: 200)}';
          })
          .toList(growable: false);
  final String accountId;
  final String sessionId;
  final List<String> identities;
}

class LabSession {
  LabSession.fromJson(Map<String, dynamic> json)
    : id = uuidValue(json['session_id']),
      label = stringValue(json['label'], max: 200),
      current = json['is_current'] as bool,
      created = dateValue(json['created_at']),
      lastSeen = dateValue(json['last_seen_at']),
      idleExpires = dateValue(json['idle_expires_at']),
      absoluteExpires = dateValue(json['absolute_expires_at']);
  final String id;
  final String label;
  final bool current;
  final DateTime created;
  final DateTime lastSeen;
  final DateTime idleExpires;
  final DateTime absoluteExpires;
}

class LabChallenge {
  LabChallenge.fromJson(Map<String, dynamic> json, this.verifier)
    : id = uuidValue(json['transaction_id']),
      expires = dateValue(json['expires_at']),
      resendAfter = json['resend_after'] as int;
  final String id;
  final String verifier;
  final DateTime expires;
  final int resendAfter;
}
