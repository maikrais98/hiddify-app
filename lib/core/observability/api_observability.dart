import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:hiddify/core/observability/observability.dart';

/// One logical request, including redirects and retries. No transport contents
/// are accepted by the event emitter: only closed classes and numeric counts.
final class ApiRequestObservation {
  ApiRequestObservation(this._client, this.endpointClass) {
    _emit(ObservabilityStatus.started);
  }
  final ObservabilityClient _client;
  final ApiEndpointClass endpointClass;
  final String id = Observability.newOperationId();
  final Stopwatch _watch = Stopwatch()..start();
  int _hopAttempts = 0;
  int _retries = 0;
  bool _finished = false;

  void beginHop() => _hopAttempts = 0;
  void attempt() {
    if (_hopAttempts++ > 0) _retries++;
  }

  void finish(ApiStatusClass statusClass) {
    if (_finished) return;
    _finished = true;
    _watch.stop();
    _emit(
      statusClass == ApiStatusClass.http2xx
          ? ObservabilityStatus.succeeded
          : statusClass == ApiStatusClass.cancelled
          ? ObservabilityStatus.cancelled
          : ObservabilityStatus.failed,
      statusClass: statusClass,
    );
  }

  void _emit(ObservabilityStatus status, {ApiStatusClass? statusClass}) => _client.event(
    module: ObservabilityModule.api,
    operation: ObservabilityOperation.request,
    name: _finished ? ObservabilityEvent.apiRequestCompleted : ObservabilityEvent.apiRequestStarted,
    status: status,
    requestId: id,
    endpointClass: endpointClass,
    statusClass: statusClass,
    retryCount: _retries,
    durationMs: _finished ? _watch.elapsedMilliseconds : null,
    level: status == ObservabilityStatus.failed ? ObservabilityLevel.error : ObservabilityLevel.info,
  );
}

Future<Response<T>> observeApiRequest<T>(
  ObservabilityClient client,
  ApiEndpointClass endpointClass,
  Future<Response<T>> Function(ApiRequestObservation) action,
) async {
  final observation = ApiRequestObservation(client, endpointClass);
  try {
    final response = await action(observation);
    observation.finish(apiStatusClass(response.statusCode));
    return response;
  } catch (error) {
    observation.finish(apiFailureClass(error));
    rethrow;
  }
}

ApiStatusClass apiStatusClass(int? code) {
  if (code != null && code >= 200 && code < 300) return ApiStatusClass.http2xx;
  if (code != null && code >= 400 && code < 500) return ApiStatusClass.http4xx;
  if (code != null && code >= 500 && code < 600) return ApiStatusClass.http5xx;
  return ApiStatusClass.unknownSafe;
}

/// Inspects only exception type and numeric HTTP code, never messages or data.
ApiStatusClass apiFailureClass(Object error) {
  if (error is TimeoutException) return ApiStatusClass.timeout;
  if (error is HandshakeException || error is TlsException) return ApiStatusClass.tls;
  if (error is SocketException) return ApiStatusClass.networkUnavailable;
  if (error is! DioException) return ApiStatusClass.unknownSafe;
  if (error.error is HandshakeException || error.error is TlsException) return ApiStatusClass.tls;
  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => ApiStatusClass.timeout,
    DioExceptionType.cancel => ApiStatusClass.cancelled,
    DioExceptionType.badCertificate => ApiStatusClass.tls,
    DioExceptionType.connectionError => ApiStatusClass.networkUnavailable,
    DioExceptionType.badResponse => apiStatusClass(error.response?.statusCode),
    _ => error.error is SocketException ? ApiStatusClass.networkUnavailable : ApiStatusClass.unknownSafe,
  };
}
