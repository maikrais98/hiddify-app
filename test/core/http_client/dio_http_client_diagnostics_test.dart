import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_event.dart';

void main() {
  group('DioHttpClient diagnostics', () {
    test('reports successful response with actual status, mode, and retry metadata', () async {
      final options = RequestOptions(path: 'https://private.invalid');
      options.extra['ro_attempt'] = 2;
      final response = Response<String>(requestOptions: options, statusCode: 204, data: 'ok');
      final dio = _StubDio(response);
      final client = _client(dio, portOpen: true);
      final diagnostics = <DiagnosticHttpResult>[];

      final actual = await client.get<String>(
        'https://user:password@private.invalid/profile?token=secret',
        onDiagnostic: diagnostics.add,
      );

      expect(actual, same(response));
      expect(diagnostics, [
        const DiagnosticHttpResult(
          outcome: DiagnosticHttpOutcome.success,
          selectedMode: DiagnosticHttpMode.both,
          httpStatus: 204,
          retryCount: 2,
        ),
      ]);
    });

    test('reports the selected proxy policy without claiming an actual route', () async {
      final response = Response<void>(requestOptions: RequestOptions(path: '/'), statusCode: 200);
      final dio = _StubDio(response);
      final client = _client(dio, portOpen: false);
      DiagnosticHttpResult? diagnostic;

      await client.get<void>('https://private.invalid', proxyOnly: true, onDiagnostic: (value) => diagnostic = value);

      expect(diagnostic?.selectedMode, DiagnosticHttpMode.proxy);
    });

    for (final entry in <DioExceptionType, DiagnosticHttpOutcome>{
      DioExceptionType.connectionTimeout: DiagnosticHttpOutcome.connectionTimeout,
      DioExceptionType.sendTimeout: DiagnosticHttpOutcome.sendTimeout,
      DioExceptionType.receiveTimeout: DiagnosticHttpOutcome.receiveTimeout,
      DioExceptionType.badCertificate: DiagnosticHttpOutcome.badCertificate,
      DioExceptionType.badResponse: DiagnosticHttpOutcome.badResponse,
      DioExceptionType.cancel: DiagnosticHttpOutcome.cancel,
      DioExceptionType.connectionError: DiagnosticHttpOutcome.connectionError,
      DioExceptionType.unknown: DiagnosticHttpOutcome.unknown,
    }.entries) {
      test('maps ${entry.key.name} and rethrows the identical DioException', () async {
        final request = RequestOptions(path: 'https://private.invalid');
        request.extra['ro_attempt'] = 3;
        final response = entry.key == DioExceptionType.badResponse
            ? Response<void>(requestOptions: request, statusCode: 503)
            : null;
        final error = DioException(requestOptions: request, response: response, type: entry.key);
        final client = _client(_StubDio(error), portOpen: false);
        DiagnosticHttpResult? diagnostic;

        Object? thrown;
        try {
          await client.get<void>('https://private.invalid', onDiagnostic: (value) => diagnostic = value);
        } on Object catch (error) {
          thrown = error;
        }

        expect(thrown, same(error));
        expect(diagnostic?.outcome, entry.value);
        expect(diagnostic?.selectedMode, DiagnosticHttpMode.direct);
        expect(diagnostic?.httpStatus, response?.statusCode);
        expect(diagnostic?.retryCount, 3);
      });
    }

    test('callback failures do not change a response or an error', () async {
      final response = Response<void>(requestOptions: RequestOptions(path: '/'), statusCode: 200);
      final successful = _client(_StubDio(response), portOpen: false);

      expect(
        await successful.download(
          'https://private.invalid',
          '/tmp/unused',
          onDiagnostic: (_) => throw StateError('observer failed'),
        ),
        same(response),
      );

      final request = RequestOptions(path: '/');
      final failure = DioException(requestOptions: request, type: DioExceptionType.cancel);
      final failing = _client(_StubDio(failure), portOpen: false);
      Object? thrown;
      try {
        await failing.get<void>('https://private.invalid', onDiagnostic: (_) => throw StateError('observer failed'));
      } on Object catch (error) {
        thrown = error;
      }
      expect(thrown, same(failure));
    });

    test('reports unknown for a non-Dio object and preserves its identity', () async {
      final failure = Object();
      final client = _client(_StubDio(failure), portOpen: false);
      DiagnosticHttpResult? diagnostic;

      Object? thrown;
      try {
        await client.get<void>('https://private.invalid', onDiagnostic: (value) => diagnostic = value);
      } on Object catch (error) {
        thrown = error;
      }

      expect(thrown, same(failure));
      expect(
        diagnostic,
        const DiagnosticHttpResult(outcome: DiagnosticHttpOutcome.unknown, selectedMode: DiagnosticHttpMode.direct),
      );
    });
  });
}

_TestDioHttpClient _client(Dio dio, {required bool portOpen}) => _TestDioHttpClient(
  portOpen: portOpen,
  clients: {DiagnosticHttpMode.direct: dio, DiagnosticHttpMode.proxy: dio, DiagnosticHttpMode.both: dio},
);

final class _TestDioHttpClient extends DioHttpClient {
  _TestDioHttpClient({required this.portOpen, required super.clients})
    : super(timeout: const Duration(seconds: 1), userAgent: 'test', debug: false);

  final bool portOpen;

  @override
  Future<bool> isPortOpen(String host, int port, {Duration timeout = const Duration(seconds: 5)}) async => portOpen;
}

final class _StubDio implements Dio {
  _StubDio(this.result);

  final Object result;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    if (result case final Response<T> response) return response;
    throw result;
  }

  @override
  Future<Response> download(
    String urlPath,
    dynamic savePath, {
    ProgressCallback? onReceiveProgress,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    FileAccessMode fileAccessMode = FileAccessMode.write,
    String lengthHeader = Headers.contentLengthHeader,
    Object? data,
    Options? options,
  }) async {
    if (result case final Response response) return response;
    throw result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
