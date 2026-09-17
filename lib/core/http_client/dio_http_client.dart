import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';

import 'package:hiddify/core/http_client/profile_download_policy.dart';
import 'package:hiddify/utils/custom_loggers.dart';

class DioHttpClient with InfraLogger {
  static const _redirectStatusCodes = {301, 302, 303, 307, 308};

  final Map<String, Dio> _dio = {};
  DioHttpClient({
    required Duration timeout,
    required this.userAgent,
    required bool debug,
    HttpClientAdapter Function()? httpClientAdapterFactory,
  }) {
    for (var mode in ["proxy", "direct", "both"]) {
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
            if (mode != "proxy") ...[const Duration(seconds: 2), const Duration(seconds: 3)],
          ],
        ),
      );

      _dio[mode]!.httpClientAdapter =
          httpClientAdapterFactory?.call() ??
          IOHttpClientAdapter(
            createHttpClient: () {
              final client = HttpClient();
              client.findProxy = (url) {
                if (mode == "proxy") {
                  return "PROXY localhost:$port";
                } else if (mode == "direct") {
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
  }) async {
    var requestUri = _requireHttps(url);
    var requestCredentials = credentials;
    final mode = proxyOnly
        ? "proxy"
        : await isPortOpen("127.0.0.1", port)
        ? "both"
        : "direct";
    final dio = _dio[mode]!;

    for (var redirectCount = 0; redirectCount <= dio.options.maxRedirects; redirectCount++) {
      final response = await dio.get<T>(
        requestUri.toString(),
        cancelToken: cancelToken,
        options: _options(requestUri, userAgent: userAgent, credentials: requestCredentials),
      );
      final redirectUri = _redirectUri(response, requestUri);
      if (redirectUri == null) return response;
      if (redirectCount == dio.options.maxRedirects) {
        throw DioException.badResponse(
          statusCode: response.statusCode ?? 0,
          requestOptions: response.requestOptions,
          response: response,
        );
      }
      final nextRequestUri = _requireHttps(redirectUri.toString());
      if (!_hasSameOrigin(requestUri, nextRequestUri)) requestCredentials = null;
      requestUri = nextRequestUri;
    }
    throw StateError('unreachable');
  }

  Future<Response> downloadProfile(
    String url,
    String path, {
    CancelToken? cancelToken,
    String? userAgent,
    Duration timeLimit = ProfileDownloadPolicy.deadline,
  }) => ProfileDownloadPolicy(
    timeLimit: timeLimit,
  ).download(url, path, cancelToken: cancelToken, userAgent: userAgent ?? this.userAgent);

  Future<Response> download(
    String url,
    String path, {
    CancelToken? cancelToken,
    String? userAgent,
    ({String username, String password})? credentials,
    bool proxyOnly = false,
  }) async {
    var requestUri = _requireHttps(url);
    var requestCredentials = credentials;
    final mode = proxyOnly
        ? "proxy"
        : await isPortOpen("127.0.0.1", port)
        ? "both"
        : "direct";
    final dio = _dio[mode]!;

    for (var redirectCount = 0; redirectCount <= dio.options.maxRedirects; redirectCount++) {
      final response = await dio.download(
        requestUri.toString(),
        path,
        cancelToken: cancelToken,
        options: _options(requestUri, userAgent: userAgent, credentials: requestCredentials),
      );
      final redirectUri = _redirectUri(response, requestUri);
      if (redirectUri == null) return response;
      if (redirectCount == dio.options.maxRedirects) {
        throw DioException.badResponse(
          statusCode: response.statusCode ?? 0,
          requestOptions: response.requestOptions,
          response: response,
        );
      }
      final nextRequestUri = _requireHttps(redirectUri.toString());
      if (!_hasSameOrigin(requestUri, nextRequestUri)) requestCredentials = null;
      requestUri = nextRequestUri;
    }
    throw StateError('unreachable');
  }

  Options _options(Uri uri, {String? userAgent, ({String username, String password})? credentials}) {
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
      followRedirects: false,
      validateStatus: (status) =>
          status != null && ((status >= 200 && status < 300) || _redirectStatusCodes.contains(status)),
      headers: {
        if (userAgent != null) "User-Agent": userAgent,
        if (basicAuth != null) "authorization": basicAuth,
        // "Accept": "application/json",
        // "Content-Type": "application/json",
      },
    );
  }

  Uri _requireHttps(String url) {
    final Uri uri;
    try {
      uri = Uri.parse(url.trim());
    } on FormatException catch (error) {
      throw DioException(
        requestOptions: RequestOptions(path: url),
        type: DioExceptionType.badResponse,
        error: error,
      );
    }
    if (uri.scheme.toLowerCase() != 'https' || !uri.hasAuthority || uri.host.isEmpty) {
      throw DioException(
        requestOptions: RequestOptions(path: url),
        type: DioExceptionType.badResponse,
        error: const FormatException('Only HTTPS URLs are allowed.'),
      );
    }
    return uri;
  }

  Uri? _redirectUri(Response response, Uri requestUri) {
    if (!_redirectStatusCodes.contains(response.statusCode)) return null;
    final location = response.headers.value(HttpHeaders.locationHeader);
    if (location == null || location.isEmpty) {
      throw DioException.badResponse(
        statusCode: response.statusCode ?? 0,
        requestOptions: response.requestOptions,
        response: response,
      );
    }
    return requestUri.resolve(location);
  }

  bool _hasSameOrigin(Uri first, Uri second) =>
      first.scheme.toLowerCase() == second.scheme.toLowerCase() &&
      first.host.toLowerCase() == second.host.toLowerCase() &&
      first.port == second.port;
}
