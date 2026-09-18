import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:hiddify/core/observability/api_observability.dart';
import 'package:hiddify/core/observability/observability.dart';

enum ProfileDownloadFailureKind { url, address, redirect, size, depth, deadline }

class ProfileDownloadException extends FormatException {
  const ProfileDownloadException(this.kind, String message) : super(message);
  final ProfileDownloadFailureKind kind;
}

/// A direct, bounded transport for untrusted subscription URLs. The validated
/// address is passed to Socket; TLS then verifies the original URL hostname.
class ProfileDownloadPolicy {
  static const maxBytes = 8 * 1024 * 1024;
  static const maxRedirects = 5;
  static const deadline = Duration(seconds: 30);

  ProfileDownloadPolicy({
    Future<List<InternetAddress>> Function(String)? lookup,
    HttpClientAdapter Function(InternetAddress)? adapterFactory,
    this.byteLimit = maxBytes,
    this.timeLimit = deadline,
  }) : _lookup = lookup ?? InternetAddress.lookup,
       _adapterFactory = adapterFactory;

  final Future<List<InternetAddress>> Function(String) _lookup;
  final HttpClientAdapter Function(InternetAddress)? _adapterFactory;
  final int byteLimit;
  final Duration timeLimit;

  static bool isPublic(InternetAddress address) {
    final b = address.rawAddress;
    if (b.length == 4) {
      return !(b[0] == 0 ||
          b[0] == 10 ||
          b[0] == 127 ||
          b[0] >= 224 ||
          (b[0] == 100 && b[1] >= 64 && b[1] <= 127) ||
          (b[0] == 169 && b[1] == 254) ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && (b[1] == 168 || (b[1] == 0 && (b[2] == 0 || b[2] == 2)))) ||
          (b[0] == 198 && (b[1] == 18 || b[1] == 19 || (b[1] == 51 && b[2] == 100))) ||
          (b[0] == 203 && b[1] == 0 && b[2] == 113));
    }
    // Allow only global unicast; exclude transition/mapped/documentation ranges
    // which can encode an otherwise forbidden IPv4 destination.
    return b[0] & 0xe0 == 0x20 &&
        !(b[0] == 0x20 && b[1] == 0x02) &&
        !(b[0] == 0x20 && b[1] == 0x01 && (b[2] < 2 || (b[2] == 0x0d && b[3] == 0xb8)));
  }

  Future<Response> download(String url, String path, {CancelToken? cancelToken, required String userAgent}) =>
      observeApiRequest(Observability.client, ApiEndpointClass.profileDownload, (observation) async {
        try {
          return await _download(url, path, cancelToken: cancelToken, userAgent: userAgent);
        } on ProfileDownloadException catch (error) {
          if (error.kind == ProfileDownloadFailureKind.deadline) observation.finish(ApiStatusClass.timeout);
          rethrow;
        }
      });

  Future<Response> _download(String url, String path, {CancelToken? cancelToken, required String userAgent}) async {
    final token = CancelToken();
    if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
    unawaited(cancelToken?.whenCancel.then((_) => token.cancel('Profile download cancelled.')));
    var deadlineExceeded = false;
    final timer = Timer(timeLimit, () {
      deadlineExceeded = true;
      token.cancel('Profile download deadline exceeded.');
    });
    final watch = Stopwatch()..start();
    Dio? dio;
    final file = File(path);
    var complete = false;
    var received = 0;
    void checkActive() {
      if (watch.elapsed >= timeLimit) {
        throw const ProfileDownloadException(
          ProfileDownloadFailureKind.deadline,
          'Profile download deadline exceeded.',
        );
      }
      if (token.isCancelled) throw token.cancelError!;
    }

    try {
      checkActive();
      Uri uri;
      try {
        uri = Uri.parse(url.trim());
      } on FormatException {
        throw const ProfileDownloadException(ProfileDownloadFailureKind.url, 'Invalid profile URL.');
      }
      for (var hop = 0; hop <= maxRedirects; hop++) {
        checkActive();
        if (uri.scheme != 'https' || uri.host.isEmpty) {
          throw const ProfileDownloadException(ProfileDownloadFailureKind.url, 'Only HTTPS profile URLs are allowed.');
        }
        final literal = InternetAddress.tryParse(uri.host);
        final addresses = literal == null
            ? await Future.any<List<InternetAddress>>([
                _lookup(uri.host),
                token.whenCancel.then((error) => throw error),
              ]).timeout(timeLimit - watch.elapsed)
            : [literal];
        checkActive();
        if (addresses.isEmpty || addresses.any((address) => !isPublic(address))) {
          throw const ProfileDownloadException(
            ProfileDownloadFailureKind.address,
            'Profile URL must resolve only to public addresses.',
          );
        }
        final pinned = addresses.first;
        dio = Dio(BaseOptions(connectTimeout: timeLimit, receiveTimeout: timeLimit));
        dio.httpClientAdapter =
            _adapterFactory?.call(pinned) ??
            IOHttpClientAdapter(
              createHttpClient: () {
                final client = HttpClient();
                client.findProxy = (_) => 'DIRECT';
                client.connectionFactory = (target, proxyHost, proxyPort) async {
                  checkActive();
                  if (target.host != uri.host || proxyHost != null) {
                    throw const SocketException('Unexpected profile transport target.');
                  }
                  final task = await Socket.startConnect(pinned, target.port);
                  Socket? connected;
                  var cancelled = false;
                  final secure = task.socket.then((socket) {
                    connected = socket;
                    if (cancelled) {
                      socket.destroy();
                      throw const SocketException('Profile connection cancelled.');
                    }
                    return SecureSocket.secure(socket, host: target.host);
                  });
                  return ConnectionTask.fromSocket(secure, () {
                    cancelled = true;
                    task.cancel();
                    connected?.destroy();
                  });
                };
                return client;
              },
            );
        final response = await dio.get<ResponseBody>(
          uri.toString(),
          cancelToken: token,
          options: Options(
            responseType: ResponseType.stream,
            followRedirects: false,
            validateStatus: (status) =>
                status != null && (status >= 200 && status < 300 || [301, 302, 303, 307, 308].contains(status)),
            headers: {
              'User-Agent': userAgent,
              if (uri.userInfo.isNotEmpty) 'authorization': 'Basic ${base64.encode(utf8.encode(uri.userInfo))}',
            },
          ),
        );
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          await response.data!.stream.listen((_) {}).cancel();
          final location = response.headers.value('location');
          if (hop == maxRedirects || location == null) {
            throw const ProfileDownloadException(
              ProfileDownloadFailureKind.redirect,
              'Profile redirect limit or missing location.',
            );
          }
          final Uri next;
          try {
            next = uri.resolve(location);
          } on FormatException {
            throw const ProfileDownloadException(ProfileDownloadFailureKind.redirect, 'Invalid profile redirect.');
          }
          // A redirect cannot introduce credentials supplied by another origin.
          uri = next.replace(userInfo: next.host == uri.host && next.port == uri.port ? next.userInfo : '');
          dio.close(force: true);
          continue;
        }
        final declared = int.tryParse(response.headers.value('content-length') ?? '');
        if (declared != null && declared > byteLimit) {
          throw const ProfileDownloadException(ProfileDownloadFailureKind.size, 'Profile byte limit exceeded.');
        }
        final output = await file.open(mode: FileMode.write);
        try {
          await for (final chunk in response.data!.stream) {
            checkActive();
            received += chunk.length;
            if (received > byteLimit) {
              throw const ProfileDownloadException(ProfileDownloadFailureKind.size, 'Profile byte limit exceeded.');
            }
            await output.writeFrom(chunk);
          }
        } finally {
          await output.close();
        }
        checkActive();
        complete = true;
        return response;
      }
      throw StateError('Unreachable');
    } on TimeoutException {
      throw const ProfileDownloadException(ProfileDownloadFailureKind.deadline, 'Profile download deadline exceeded.');
    } on DioException {
      if (deadlineExceeded) {
        throw const ProfileDownloadException(
          ProfileDownloadFailureKind.deadline,
          'Profile download deadline exceeded.',
        );
      }
      rethrow;
    } finally {
      timer.cancel();
      dio?.close(force: true);
      if (!complete && await file.exists()) await file.delete();
    }
  }
}
