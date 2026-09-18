import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/observability/observability.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

FutureOr<SentryEvent?> sentryBeforeSend(SentryEvent event, Hint hint) {
  if (!canSendEvent(event.throwable)) return null;
  final payload = safeObservabilityPayload(event.message?.formatted);
  // Reconstruct rather than copy: SDK contexts, exceptions, requests, threads,
  // attachments and arbitrary fields must not cross this boundary.
  hint.attachments.clear();
  return SentryEvent(
    eventId: event.eventId,
    timestamp: event.timestamp,
    release: event.release,
    dist: event.dist,
    environment: event.environment,
    level: event.level,
    platform: event.platform,
    message: SentryMessage(payload == null ? 'application_error' : jsonEncode(payload)),
    contexts: payload == null ? null : (Contexts()..['observability'] = payload),
    fingerprint: payload == null
        ? ['application_error']
        : [
            '${payload['module']}',
            '${payload['operation']}',
            '${payload['event']}',
            '${payload['error_code'] ?? 'none'}',
          ],
    tags: payload == null
        ? null
        : {
            for (final key in [
              'module',
              'operation',
              'event',
              'status',
              'error_code',
              'session_id',
              'operation_id',
              'endpoint_class',
              'status_class',
              'request_id',
            ])
              if (payload.containsKey(key)) key: '${payload[key]}',
          },
    breadcrumbs: event.breadcrumbs?.map((b) => sentryBeforeBreadcrumb(b, hint)).whereType<Breadcrumb>().toList(),
  );
}

Breadcrumb? sentryBeforeBreadcrumb(Breadcrumb? breadcrumb, Hint hint) {
  if (breadcrumb == null) return null;
  final payload = safeObservabilityPayload(breadcrumb.message);
  if (payload == null) return null;
  return Breadcrumb(
    message: jsonEncode(payload),
    timestamp: breadcrumb.timestamp,
    level: breadcrumb.level,
    category: 'observability',
    type: 'debug',
  );
}

bool canSendEvent(dynamic throwable) {
  return switch (throwable) {
    UnexpectedFailure(:final error) => canSendEvent(error),
    DioException _ => false,
    SocketException _ => false,
    HttpException _ => false,
    HandshakeException _ => false,
    ExpectedFailure _ => false,
    ExpectedMeasuredFailure _ => false,
    _ => true,
  };
}

bool canLogEvent(dynamic throwable) => switch (throwable) {
  ExpectedMeasuredFailure _ => true,
  _ => canSendEvent(throwable),
};
