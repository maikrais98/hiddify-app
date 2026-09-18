import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/observability/api_observability.dart';
import 'package:hiddify/core/observability/observability.dart';

void main() {
  test('one logical request emits one start and terminal with closed bounded fields', () async {
    final events = <Map<String, Object>>[];
    final client = ObservabilityClient(sink: (payload, _) => events.add(payload));
    await observeApiRequest<String>(client, ApiEndpointClass.profileDownload, (request) async {
      request.beginHop();
      request.attempt();
      request.attempt();
      request.beginHop();
      request.attempt();
      return Response(
        data: 'PRIVATE_CANARY',
        statusCode: 200,
        requestOptions: RequestOptions(path: 'https://PRIVATE_CANARY/token?secret=PRIVATE_CANARY'),
      );
    });
    expect(events.length, 2);
    expect(events.first['event'], 'api_request_started');
    expect(events.last['event'], 'api_request_completed');
    expect(events.last['request_id'], events.first['request_id']);
    expect(events.last['request_id'], matches(r'^[a-f0-9-]{36}$'));
    expect(events.last['endpoint_class'], 'profile_download');
    expect(events.last['status_class'], 'http_2xx');
    expect(events.last['retry_count'], 1);
    expect(events.last['duration_ms'], isNonNegative);
    expect(jsonEncode(events), isNot(contains('PRIVATE_CANARY')));
    expect(safeObservabilityPayload(jsonEncode(events.last))!['request_id'], events.last['request_id']);
  });
  test('failure classes are closed and original exception identity is preserved', () async {
    final options = RequestOptions(path: 'https://PRIVATE_CANARY');
    final cases = <(Object, String)>[
      (DioException(requestOptions: options, type: DioExceptionType.receiveTimeout), 'network_timeout'),
      (DioException(requestOptions: options, type: DioExceptionType.cancel), 'cancelled'),
      (DioException(requestOptions: options, type: DioExceptionType.badCertificate), 'tls_failure'),
      (DioException(requestOptions: options, type: DioExceptionType.connectionError), 'network_unavailable'),
      (const HandshakeException('PRIVATE_CANARY'), 'tls_failure'),
      (const SocketException('PRIVATE_CANARY'), 'network_unavailable'),
      (StateError('PRIVATE_CANARY'), 'unexpected_network_failure'),
      for (final code in [404, 503])
        (
          DioException.badResponse(
            statusCode: code,
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: code),
          ),
          code == 404 ? 'http_4xx' : 'http_5xx',
        ),
    ];
    for (final item in cases) {
      final events = <Map<String, Object>>[];
      final client = ObservabilityClient(sink: (payload, _) => events.add(payload));
      await expectLater(
        observeApiRequest(client, ApiEndpointClass.other, (_) async => throw item.$1),
        throwsA(same(item.$1)),
      );
      expect(events.length, 2);
      expect(events.last['status_class'], item.$2);
      expect(jsonEncode(events), isNot(contains('PRIVATE_CANARY')));
    }
  });
}
