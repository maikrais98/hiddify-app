import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/account_lab/account_io.dart';
import 'package:hiddify/features/account_lab/account_protocol.dart';
import 'protocol_test.dart' show tokenJson;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('native protocol persists only refresh and claims once', () async {
    const channel = MethodChannel('test/lab');
    final calls = <MethodCall>[];
    Map<String, dynamic>? saved;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'lab_session_save') saved = Map<String, dynamic>.from((call.arguments as Map)['value'] as Map);
      if (call.method == 'lab_session_claim') {
        final result = saved;
        saved = null;
        return result;
      }
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
    );
    final store = KeychainLabStore(List.filled(64, 'a').join(), channel: channel, enabled: true);
    final stored = LabTokens.fromJson(tokenJson()).stored;
    await store.save(stored);
    expect(await store.claim(), stored);
    expect(await store.claim(), isNull);
    await store.clear();
    expect(calls.map((c) => c.method), [
      'lab_session_save',
      'lab_session_claim',
      'lab_session_claim',
      'lab_session_clear',
    ]);
    expect(jsonEncode(calls.map((c) => c.arguments).toList()), isNot(contains('access_token')));
  });
  test('debug gate off by default and missing TLS certificate fails closed', () {
    expect(labEnabled, isFalse);
    expect(() => DioLabApi('http://127.0.0.1/api/luma/v1/'), throwsA(isA<LabFailure>()));
    expect(() => DioLabApi('https://192.168.1.5/api/luma/v1/', enabled: true), throwsA(isA<LabFailure>()));
    expect(() => KeychainLabStore('bad', enabled: true), throwsA(isA<LabFailure>()));
  });
}
