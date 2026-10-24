import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:hiddify/features/diagnostics/safe_diagnostic_event.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:meta/meta.dart';

final class DiagnosticHttpResult {
  const DiagnosticHttpResult({required this.outcome, required this.selectedMode, this.httpStatus, this.retryCount});

  final DiagnosticHttpOutcome outcome;
  final DiagnosticHttpMode selectedMode;
  final int? httpStatus;
  final int? retryCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiagnosticHttpResult &&
          outcome == other.outcome &&
          selectedMode == other.selectedMode &&
          httpStatus == other.httpStatus &&
          retryCount == other.retryCount;

  @override
  int get hashCode => Object.hash(outcome, selectedMode, httpStatus, retryCount);
}

class DioHttpClient with InfraLogger {
  final Map<DiagnosticHttpMode, Dio> _dio = {};
  DioHttpClient({
    required Duration timeout,
    required this.userAgent,
    required bool debug,
    @visibleForTesting Map<DiagnosticHttpMode, Dio>? clients,
  }) {
    if (clients != null) {
      _dio.addAll(clients);
      return;
    }
    for (final mode in DiagnosticHttpMode.values) {
      _dio[mode] = Dio(
        BaseOptions(
          connectTimeout: timeout,
          sendTimeout: timeout,
          receiveTimeout: timeout,
          headers: {"User-Agent": userAgent},
        ),
      );
      _dio[mode]!.interceptors.add(
        RetryInterceptor(
          dio: _dio[mode]!,
          retryDelays: [
            const Duration(seconds: 1),
            if (mode != DiagnosticHttpMode.proxy) ...[const Duration(seconds: 2), const Duration(seconds: 3)],
          ],
        ),
      );

      _dio[mode]!.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.findProxy = (url) {
            if (mode == DiagnosticHttpMode.proxy) {
              return "PROXY localhost:$port";
            } else if (mode == DiagnosticHttpMode.direct) {
              return "DIRECT";
            } else {
              return "PROXY localhost:$port; DIRECT";
            }
          };
          return client;
        },
      );
    }

    if (debug) {
      // _dio.interceptors.add(LoggyDioInterceptor(requestHeader: true));
    }
  }

  int port = 0;

  String userAgent;
  // bool isPortOpen(String host, int port, {Duration timeout = const Duration(milliseconds: 200)}) async{
  //   try {
  //     Socket.connect(host, port, timeout: timeout).then((socket) {
  //       socket.destroy();
  //     });
  //     return true;
  //   } on SocketException catch (_) {
  //     return false;
  //   } catch (_) {
  //     return false;
  //   }
  // }
  Future<bool> isPortOpen(String host, int port, {Duration timeout = const Duration(seconds: 5)}) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      await socket.close();
      return true;
    } on SocketException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  void setProxyPort(int port) {
    this.port = port;
    loggy.debug("setting proxy port: [$port]");
  }

  Future<Response<T>> get<T>(
    String url, {
    CancelToken? cancelToken,
    String? userAgent,
    ({String username, String password})? credentials,
    bool proxyOnly = false,
    void Function(DiagnosticHttpResult result)? onDiagnostic,
  }) async {
    final mode = proxyOnly
        ? DiagnosticHttpMode.proxy
        : await isPortOpen("127.0.0.1", port)
        ? DiagnosticHttpMode.both
        : DiagnosticHttpMode.direct;
    final dio = _dio[mode]!;

    try {
      final response = await dio.get<T>(
        url,
        cancelToken: cancelToken,
        options: _options(url, userAgent: userAgent, credentials: credentials),
      );
      _notify(
        onDiagnostic,
        DiagnosticHttpResult(
          outcome: DiagnosticHttpOutcome.success,
          selectedMode: mode,
          httpStatus: response.statusCode,
          retryCount: _retryCount(response.requestOptions),
        ),
      );
      return response;
    } on DioException catch (error) {
      _notify(onDiagnostic, _dioFailure(error, mode));
      rethrow;
    } on Object {
      _notify(onDiagnostic, DiagnosticHttpResult(outcome: DiagnosticHttpOutcome.unknown, selectedMode: mode));
      rethrow;
    }
  }

  Future<Response> download(
    String url,
    String path, {
    CancelToken? cancelToken,
    String? userAgent,
    ({String username, String password})? credentials,
    bool proxyOnly = false,
    void Function(DiagnosticHttpResult result)? onDiagnostic,
  }) async {
    final mode = proxyOnly
        ? DiagnosticHttpMode.proxy
        : await isPortOpen("127.0.0.1", port)
        ? DiagnosticHttpMode.both
        : DiagnosticHttpMode.direct;
    final dio = _dio[mode]!;
    try {
      final response = await dio.download(
        url,
        path,
        cancelToken: cancelToken,
        options: _options(url, userAgent: userAgent, credentials: credentials),
      );
      _notify(
        onDiagnostic,
        DiagnosticHttpResult(
          outcome: DiagnosticHttpOutcome.success,
          selectedMode: mode,
          httpStatus: response.statusCode,
          retryCount: _retryCount(response.requestOptions),
        ),
      );
      return response;
    } on DioException catch (error) {
      _notify(onDiagnostic, _dioFailure(error, mode));
      rethrow;
    } on Object {
      _notify(onDiagnostic, DiagnosticHttpResult(outcome: DiagnosticHttpOutcome.unknown, selectedMode: mode));
      rethrow;
    }
  }

  DiagnosticHttpResult _dioFailure(DioException error, DiagnosticHttpMode mode) => DiagnosticHttpResult(
    outcome: switch (error.type) {
      DioExceptionType.connectionTimeout => DiagnosticHttpOutcome.connectionTimeout,
      DioExceptionType.sendTimeout => DiagnosticHttpOutcome.sendTimeout,
      DioExceptionType.receiveTimeout => DiagnosticHttpOutcome.receiveTimeout,
      DioExceptionType.badCertificate => DiagnosticHttpOutcome.badCertificate,
      DioExceptionType.badResponse => DiagnosticHttpOutcome.badResponse,
      DioExceptionType.cancel => DiagnosticHttpOutcome.cancel,
      DioExceptionType.connectionError => DiagnosticHttpOutcome.connectionError,
      DioExceptionType.unknown => DiagnosticHttpOutcome.unknown,
    },
    selectedMode: mode,
    httpStatus: error.response?.statusCode,
    retryCount: _retryCount(error.requestOptions),
  );

  int? _retryCount(RequestOptions options) {
    if (!options.extra.containsKey('ro_attempt')) return null;
    final attempt = options.attempt;
    return attempt >= 0 && attempt <= 3 ? attempt : null;
  }

  void _notify(void Function(DiagnosticHttpResult result)? observer, DiagnosticHttpResult result) {
    try {
      observer?.call(result);
    } on Object {
      // Diagnostics must not change the request being observed.
    }
  }

  Options _options(String url, {String? userAgent, ({String username, String password})? credentials}) {
    final uri = Uri.parse(url);

    String? userInfo;
    if (credentials != null) {
      userInfo = "${credentials.username}:${credentials.password}";
    } else if (uri.userInfo.isNotEmpty) {
      userInfo = uri.userInfo;
    }

    String? basicAuth;
    if (userInfo != null) {
      basicAuth = "Basic ${base64.encode(utf8.encode(userInfo))}";
    }

    return Options(
      headers: {
        if (userAgent != null) "User-Agent": userAgent,
        if (basicAuth != null) "authorization": basicAuth,
        // "Accept": "application/json",
        // "Content-Type": "application/json",
      },
    );
  }
}
