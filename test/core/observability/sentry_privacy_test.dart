import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/analytics/analytics_filter.dart';
import 'package:hiddify/core/observability/observability.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  test('validated API context retains queryable numeric measurements and safe tags', () async {
    late Map<String, Object> payload;
    ObservabilityClient(sink: (value, _) => payload = value).event(
      module: ObservabilityModule.api,
      operation: ObservabilityOperation.request,
      name: ObservabilityEvent.apiRequestCompleted,
      status: ObservabilityStatus.succeeded,
      requestId: '12345678-1234-4234-8234-123456789abc',
      endpointClass: ApiEndpointClass.profileDownload,
      statusClass: ApiStatusClass.http2xx,
      durationMs: 123,
      retryCount: 2,
      count: 3,
    );
    final unsafeContext = Contexts()..['raw'] = {'url': 'PRIVATE_CANARY'};
    final event = await sentryBeforeSend(
      SentryEvent(message: SentryMessage(jsonEncode(payload)), contexts: unsafeContext),
      Hint(),
    );
    final context = event!.contexts['observability'] as Map<String, Object>;
    expect(context['duration_ms'], 123);
    expect(context['retry_count'], 2);
    expect(context['count'], 3);
    expect(event.tags!['endpoint_class'], 'profile_download');
    expect(event.tags!['status_class'], 'http_2xx');
    expect(event.tags!['request_id'], payload['request_id']);
    expect(jsonEncode(event.toJson()), isNot(contains('PRIVATE_CANARY')));
  });
  test('automatic transactions are fail-closed until a typed exporter exists', () {
    expect(
      File('lib/core/analytics/analytics_controller.dart').readAsStringSync(),
      contains('options.beforeSendTransaction = (_) => null;'),
    );
  });
  test('native crash capture is fail-closed until a native typed exporter exists', () {
    final source = File('lib/core/analytics/analytics_controller.dart').readAsStringSync();

    expect(source, contains('options.enableNativeCrashHandling = false;'));
    expect(source, contains('options.enableNdkScopeSync = false;'));
  });
  test('final Sentry boundary removes raw exceptions, stack and arbitrary context', () async {
    final result = await sentryBeforeSend(
      SentryEvent(
        throwable: StateError('PRIVATE_CANARY'),
        message: const SentryMessage('{"password":"PRIVATE_CANARY"}'),
        // ignore: deprecated_member_use
        extra: const {'raw': 'PRIVATE_CANARY'},
        tags: const {'profile': 'PRIVATE_CANARY'},
        breadcrumbs: [
          Breadcrumb(message: 'PRIVATE_CANARY', data: const {'raw': 'PRIVATE_CANARY'}),
        ],
      ),
      Hint(),
    );
    expect(result, isNotNull);
    expect(jsonEncode(result!.toJson()), isNot(contains('PRIVATE_CANARY')));
    expect(result.throwable, isNull);
    expect(result.exceptions, isNull);
    expect(result.threads, isNull);
  });
}
