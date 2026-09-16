import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartx/dartx.dart';
import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/core/http_client/profile_download_policy.dart';
import 'package:hiddify/features/profile/data/profile_data_mapper.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/model/subscription_metadata_constants.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/singbox/model/singbox_proxy_type.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:meta/meta.dart';

/// parse profile subscription url and headers for data
///
/// ***name parser hierarchy:***
/// - UserOverride.name
/// - `profile-title` header
/// - `content-disposition` header
/// - url fragment (example: `https://example.com/config#user`) -> name=`user`
/// - url filename extension (example: `https://example.com/config.json`) -> name=`config`
/// - if none of these methods return a non-blank string, switch(profileType)
/// - remote:  fallback to `Remote Profile`
/// - local: fallback to protocol, extracted from content by protocol()

class ProfileParser {
  static const maxProfileLines = 32 * 1024;

  static int _boundedProfileLineCount(String content) {
    var lineCount = 1;
    for (var index = 0; index < content.length; index++) {
      if (content.codeUnitAt(index) == 0x0a && ++lineCount > maxProfileLines) return lineCount;
    }
    return lineCount;
  }

  // Synthetic sentinel assigned to `total` for "unlimited" traffic (subscription-userinfo total=0 or
  // missing). It MUST stay above the 10 TB "unlimited" threshold the UI uses to decide whether to show
  // "∞" (isInfinitSize() in lib/utils/number_formatters.dart, and profile_tile.dart). The previous
  // value (~857 GiB) was below that gate, so total=0 rendered as a finite cap / "quota exceeded".
  // See https://github.com/hiddify/hiddify-app/issues/1974 . 1000 TiB.
  static const infiniteTrafficThreshold = subscriptionInfiniteTrafficThreshold;
  static const infiniteTimeThreshold = subscriptionInfiniteTimeThreshold;
  static const allowedOverrideConfigs = [
    'connection-test-url',
    'direct-dns-address',
    'remote-dns-address',
    'tls-tricks',
    'chain-status',
    'extra-security',
  ];
  static const allowedProfileHeaders = [
    'profile-title',
    'content-disposition',
    'subscription-userinfo',
    'profile-update-interval',
    'support-url',
    'profile-web-page-url',
    'enable-warp',
    'enable-psiphon',
    'enable-fragment',
  ];

  final Ref _ref;
  final DioHttpClient _httpClient;

  ProfileParser({required Ref ref, required DioHttpClient httpClient}) : _ref = ref, _httpClient = httpClient;
  TaskEither<ProfileFailure, ProfileEntriesCompanion> addLocal({
    required String id,
    required String content,
    required String tempFilePath,
    required UserOverride? userOverride,
    CancelToken? cancelToken,
  }) {
    return TaskEither.tryCatch(() async {
          await expandRemoteLinesInParallel(
            tempFilePath: tempFilePath,
            httpClient: _httpClient,
            cancelToken: cancelToken ?? CancelToken(),
            ref: _ref,
          );
          if (cancelToken?.isCancelled ?? false) throw const ProfileFailure.cancelByUser();
        }, (error, stack) => _mapDownloadFailure(error, stack, cancelToken))
        .flatMap((_) => TaskEither.fromEither(populateHeaders(content: content)))
        .flatMap(
          (populatedHeaders) => TaskEither.fromEither(
            parse(
              tempFilePath: tempFilePath,
              profile: ProfileEntity.local(
                id: id,
                active: true,
                name: '',
                lastUpdate: DateTime.now(),
                userOverride: userOverride,
                populatedHeaders: populatedHeaders,
              ),
            ).flatMap((profEntity) => Either.tryCatch(() => profEntity.toInsertEntry(), ProfileFailure.unexpected)),
          ),
        );
  }

  TaskEither<ProfileFailure, ProfileEntriesCompanion> addRemote({
    required String id,
    required String url,
    required String tempFilePath,
    required UserOverride? userOverride,
    CancelToken? cancelToken,
    void Function()? onParsing,
  }) => _downloadProfile(url, tempFilePath, cancelToken, onParsing).flatMap(
    (remoteHeaders) =>
        TaskEither.fromEither(
          populateHeaders(content: File(tempFilePath).readAsStringSync(), remoteHeaders: remoteHeaders),
        ).flatMap(
          (populatedHeaders) => TaskEither.fromEither(
            parse(
              tempFilePath: tempFilePath,
              profile: ProfileEntity.remote(
                id: id,
                active: true,
                name: '',
                url: url,
                lastUpdate: DateTime.now(),
                userOverride: userOverride,
                populatedHeaders: populatedHeaders,
              ),
            ).flatMap((profEntity) => Either.tryCatch(() => profEntity.toInsertEntry(), ProfileFailure.unexpected)),
          ),
        ),
  );

  TaskEither<ProfileFailure, ProfileEntriesCompanion> updateRemote({
    required RemoteProfileEntity rp,
    required String tempFilePath,
    CancelToken? cancelToken,
    void Function()? onParsing,
  }) => _downloadProfile(rp.url, tempFilePath, cancelToken, onParsing).flatMap(
    (remoteHeaders) =>
        TaskEither.fromEither(
          populateHeaders(content: File(tempFilePath).readAsStringSync(), remoteHeaders: remoteHeaders),
        ).flatMap(
          (populatedHeaders) => TaskEither.fromEither(
            parse(
              tempFilePath: tempFilePath,
              profile: rp.copyWith(populatedHeaders: populatedHeaders),
            ).flatMap((profEntity) => Either.tryCatch(() => profEntity.toUpdateEntry(), ProfileFailure.unexpected)),
          ),
        ),
  );

  Either<ProfileFailure, ProfileEntriesCompanion> offlineUpdate({
    required ProfileEntity profile,
    required String tempFilePath,
  }) => profile
      .map(
        remote: (rp) => parse(profile: rp, tempFilePath: tempFilePath),
        local: (lp) => parse(tempFilePath: tempFilePath, profile: lp),
      )
      .flatMap((profEntity) => Either.tryCatch(() => profEntity.toUpdateEntry(), ProfileFailure.unexpected));

  TaskEither<ProfileFailure, Map<String, dynamic>> _downloadProfile(
    String url,
    String tempFilePath,
    CancelToken? cancelToken,
    void Function()? onParsing,
  ) => TaskEither.tryCatch(() async {
    // if (url.startsWith("http://"))
    //   throw const ProfileFailure.invalidUrl('HTTP is not supported. Please use HTTPS for secure connection.');

    final rs = await _httpClient
        .downloadProfile(
          url.trim(),
          tempFilePath,
          cancelToken: cancelToken,
          userAgent: _ref.read(ConfigOptions.useXrayCoreWhenPossible)
              ? _httpClient.userAgent.replaceAll("HiddifyNext", "HiddifyNextX")
              : null,
        )
        .catchError((Object err) {
          if (cancelToken?.isCancelled ?? false) {
            throw const ProfileFailure.cancelByUser('HTTP request for getting profile content canceled by user.');
          }
          throw err;
        });
    await expandRemoteLinesInParallel(
      tempFilePath: tempFilePath,
      httpClient: _httpClient,
      cancelToken: cancelToken ?? CancelToken(),
      ref: _ref,
    );
    onParsing?.call();
    // fixing headers before return
    return rs.headers.map.map((key, value) {
      if (value.length == 1) return MapEntry(key, value.first);
      return MapEntry(key, value);
    });
  }, (err, st) => _mapDownloadFailure(err, st, cancelToken));
  static ProfileFailure _mapDownloadFailure(Object error, StackTrace stack, CancelToken? externalToken) {
    if (externalToken?.isCancelled ?? false) return const ProfileFailure.cancelByUser();
    if (error is ProfileFailure) return error;
    if (error is ProfileDownloadException) {
      return switch (error.kind) {
        ProfileDownloadFailureKind.url ||
        ProfileDownloadFailureKind.address ||
        ProfileDownloadFailureKind.redirect => ProfileFailure.invalidUrl(error.message),
        ProfileDownloadFailureKind.size ||
        ProfileDownloadFailureKind.depth ||
        ProfileDownloadFailureKind.deadline => ProfileFailure.invalidConfig(error.message),
      };
    }
    return ProfileFailure.unexpected(error, stack);
  }

  Future<void> expandRemoteLinesInParallel({
    required String tempFilePath,
    required DioHttpClient httpClient,
    required CancelToken cancelToken,
    required Ref ref,
    int parallelism = 4,
    Duration timeLimit = ProfileDownloadPolicy.deadline,
  }) async {
    const maxSourceBytes = 8 * 1024 * 1024;
    const maxExpandedBytes = 32 * 1024 * 1024;
    const maxNestedUrls = 16;
    final sourceFile = File(tempFilePath);
    final sourceBytes = await sourceFile.length();
    if (sourceBytes > maxSourceBytes) {
      throw const ProfileDownloadException(ProfileDownloadFailureKind.size, 'Profile source byte limit exceeded.');
    }
    final content = await sourceFile.readAsString();
    final sourceLineCount = _boundedProfileLineCount(content);
    if (sourceLineCount > maxProfileLines) {
      throw const ProfileDownloadException(ProfileDownloadFailureKind.size, 'Profile line count limit exceeded.');
    }
    final lines = content.split('\n');

    final remoteLinePattern = RegExp('^https?://', caseSensitive: false);
    bool isRemoteLine(String line) => remoteLinePattern.hasMatch(line.trim());
    if (lines.where(isRemoteLine).length > maxNestedUrls) {
      throw const ProfileDownloadException(ProfileDownloadFailureKind.size, 'Nested profile URL count exceeded.');
    }
    if (parallelism < 1 || parallelism > 4) throw ArgumentError.value(parallelism, 'parallelism');
    var expandedBytes = sourceBytes;
    var expandedLineCount = sourceLineCount;
    Object? failure;
    final operationToken = CancelToken();
    if (cancelToken.isCancelled) throw const ProfileFailure.cancelByUser();
    unawaited(cancelToken.whenCancel.then((_) => operationToken.cancel('Profile expansion cancelled.')));
    final watch = Stopwatch()..start();
    var deadlineExceeded = false;
    final timer = Timer(timeLimit, () {
      deadlineExceeded = true;
      operationToken.cancel('Profile expansion deadline exceeded.');
    });
    final results = List<String?>.filled(lines.length, null);

    int index = 0;

    Future<void> worker() async {
      while (true) {
        if (operationToken.isCancelled) return;

        final currentIndex = index++;
        if (currentIndex >= lines.length) return;

        final line = lines[currentIndex];

        // Non-URL
        if (!isRemoteLine(line)) {
          results[currentIndex] = line.trim();
          continue;
        }

        final tmpFile = File('$tempFilePath.$currentIndex');
        try {
          await httpClient.downloadProfile(
            line.trim(),
            tmpFile.path,
            cancelToken: operationToken,
            timeLimit: timeLimit - watch.elapsed,
            userAgent: ref.read(ConfigOptions.useXrayCoreWhenPossible)
                ? httpClient.userAgent.replaceAll('HiddifyNext', 'HiddifyNextX')
                : null,
          );

          final nestedBytes = await tmpFile.length();
          expandedBytes += nestedBytes;
          if (nestedBytes > maxSourceBytes || expandedBytes > maxExpandedBytes) {
            throw const ProfileDownloadException(
              ProfileDownloadFailureKind.size,
              'Expanded profile byte limit exceeded.',
            );
          }
          final nestedContent = (await tmpFile.readAsString()).trim();
          final nestedLineCount = _boundedProfileLineCount(nestedContent);
          if (nestedLineCount > maxProfileLines || expandedLineCount - 1 + nestedLineCount > maxProfileLines) {
            throw const ProfileDownloadException(
              ProfileDownloadFailureKind.size,
              'Expanded profile line count limit exceeded.',
            );
          }
          expandedLineCount += nestedLineCount - 1;
          if (nestedContent.split('\n').any(isRemoteLine)) {
            throw const ProfileDownloadException(
              ProfileDownloadFailureKind.depth,
              'Nested profile depth limit exceeded.',
            );
          }
          results[currentIndex] = nestedContent;
        } catch (err) {
          failure ??= err;
          operationToken.cancel('Nested profile download failed.');
          return;
        } finally {
          if (await tmpFile.exists()) await tmpFile.delete();
        }
      }
    }

    // Start workers
    try {
      await Future.wait(List.generate(parallelism, (_) => worker()));
    } finally {
      timer.cancel();
    }
    if (cancelToken.isCancelled) throw const ProfileFailure.cancelByUser();
    if (deadlineExceeded) {
      throw const ProfileDownloadException(ProfileDownloadFailureKind.deadline, 'Profile expansion deadline exceeded.');
    }
    if (failure != null) throw failure!;
    if (operationToken.isCancelled) {
      throw const ProfileDownloadException(ProfileDownloadFailureKind.deadline, 'Profile expansion deadline exceeded.');
    }

    if (results.any((e) => e != null)) {
      final newContent = results.join("\n");
      await sourceFile.writeAsString(newContent);
    }
  }

  static Either<ProfileFailure, Map<String, dynamic>> populateHeaders({
    required String content,
    Map<String, dynamic>? remoteHeaders,
  }) => Either.tryCatch(() {
    final contentHeaders = _parseHeadersFromContent(content);
    return _mergeAndValidateHeaders(contentHeaders, remoteHeaders ?? {});
  }, ProfileFailure.unexpected);

  static Map<String, dynamic> _mergeAndValidateHeaders(
    Map<String, dynamic> contentHeaders,
    Map<String, dynamic> remoteHeaders,
  ) {
    for (final entry in contentHeaders.entries) {
      if (!remoteHeaders.keys.contains(entry.key)) {
        remoteHeaders[entry.key] = entry.value;
      }
    }
    final headers = <String, dynamic>{};
    for (final entry in remoteHeaders.entries) {
      if (allowedProfileHeaders.contains(entry.key) && entry.value != null && entry.value.toString().isNotEmpty) {
        headers[entry.key] = entry.value;
      }
    }
    return headers;
  }

  static Map<String, dynamic> _parseHeadersFromContent(String content) {
    final headers = <String, dynamic>{};
    final content_ = safeDecodeBase64(content);
    final lines = content_.split("\n");
    final linesToProcess = lines.length < 10 ? lines.length : 10;
    for (int i = 0; i < linesToProcess; i++) {
      final line = lines[i];
      if (line.startsWith("#") || line.startsWith("//")) {
        final index = line.indexOf(':');
        if (index == -1) continue;
        final key = line.substring(0, index).replaceFirst(RegExp("^#|//"), "").trim().toLowerCase();
        final value = line.substring(index + 1).trim();
        headers[key] = value;
      }
    }
    return headers;
  }

  static SubscriptionInfo? _parseSubscriptionInfo(String subInfoStr) {
    final values = subInfoStr.split(';');
    final map = {for (final v in values) v.split('=').first.trim(): num.tryParse(v.split('=').second.trim())?.toInt()};
    if (map case {"upload": final upload?, "download": final download?, "total": final total, "expire": var expire}) {
      final total1 = (total == null || total == 0) ? infiniteTrafficThreshold + 1 : total;
      expire = (expire == null || expire == 0) ? infiniteTimeThreshold : expire;
      return SubscriptionInfo(
        upload: upload,
        download: download,
        total: total1,
        expire: DateTime.fromMillisecondsSinceEpoch(expire * 1000),
      );
    }
    return null;
  }

  @visibleForTesting
  static Either<ProfileFailure, ProfileEntity> parse({required String tempFilePath, required ProfileEntity profile}) =>
      Either.tryCatch(() {
        final headers = Map<String, dynamic>.from(profile.populatedHeaders ?? {});
        var name = '';
        if (profile.userOverride?.name case final String oName when oName.isNotEmpty) {
          name = oName;
        }

        if (headers['profile-title'] case final String titleHeader when name.isEmpty) {
          if (titleHeader.startsWith("base64:")) {
            name = utf8.decode(base64.decode(titleHeader.replaceFirst("base64:", "")));
          } else {
            name = titleHeader.trim();
          }
        }
        if (headers['content-disposition'] case final String contentDispositionHeader when name.isEmpty) {
          final regExp = RegExp('filename="([^"]*)"');
          final match = regExp.firstMatch(contentDispositionHeader);
          if (match != null && match.groupCount >= 1) {
            name = match.group(1) ?? '';
          }
        }
        if (profile case RemoteProfileEntity(:final url)) {
          if (Uri.parse(url).fragment case final fragment when name.isEmpty) {
            name = fragment;
          }
          if (url.split("/").lastOrNull case final part? when name.isEmpty) {
            final pattern = RegExp(r"\.(json|yaml|yml|txt)[\s\S]*");
            name = part.replaceFirst(pattern, "");
          }
        }
        if (name.isBlank) {
          switch (profile) {
            case RemoteProfileEntity():
              name = "Remote Profile";

            case LocalProfileEntity():
              name = protocol(File(tempFilePath).readAsStringSync());
          }
        }

        final isAutoUpdateDisable = profile.userOverride?.isAutoUpdateDisable ?? false;
        ProfileOptions? options;
        if (profile.userOverride?.updateInterval case final int updateInterval
            when updateInterval > 0 && !isAutoUpdateDisable) {
          options = ProfileOptions(
            updateInterval: Duration(hours: normalizeProfileUpdateIntervalHours(updateInterval)),
          );
        }
        if (headers['profile-update-interval'] case final String updateIntervalStr
            when options == null && !isAutoUpdateDisable) {
          final updateInterval = int.tryParse(updateIntervalStr.trim());
          if (updateInterval != null) {
            options = ProfileOptions(
              updateInterval: Duration(hours: normalizeProfileUpdateIntervalHours(updateInterval)),
            );
          }
        }

        SubscriptionInfo? subInfo;
        if (headers['subscription-userinfo'] case final String subInfoStr) {
          subInfo = _parseSubscriptionInfo(subInfoStr);
        }

        if (subInfo != null) {
          if (headers['profile-web-page-url'] case final String profileWebPageUrl when isUrl(profileWebPageUrl)) {
            subInfo = subInfo.copyWith(webPageUrl: profileWebPageUrl);
          }
          if (headers['support-url'] case final String profileSupportUrl when isUrl(profileSupportUrl)) {
            subInfo = subInfo.copyWith(supportUrl: profileSupportUrl);
          }
        }

        return profile.map(
          remote: (rp) => rp.copyWith(name: name, lastUpdate: DateTime.now(), options: options, subInfo: subInfo),
          local: (lp) => lp.copyWith(name: name, lastUpdate: DateTime.now()),
        );
      }, ProfileFailure.unexpected);

  static String protocol(String content) {
    if (content.contains("[Interface]")) {
      return ProxyType.wireguard.label;
    }
    final lines = content.split('\n');
    String? name;
    for (final line in lines) {
      final uri = Uri.tryParse(line);
      if (uri == null) continue;
      final fragment = uri.hasFragment ? Uri.decodeComponent(uri.fragment.split(" -> ")[0]) : null;
      name ??= switch (uri.scheme) {
        'ss' => fragment ?? ProxyType.shadowsocks.label,
        'ssconf' => fragment ?? ProxyType.shadowsocks.label,
        'vmess' => ProxyType.vmess.label,
        'vless' => fragment ?? ProxyType.vless.label,
        'trojan' => fragment ?? ProxyType.trojan.label,
        'tuic' => fragment ?? ProxyType.tuic.label,
        'hy2' || 'hysteria2' => fragment ?? ProxyType.hysteria2.label,
        'hy' || 'hysteria' => fragment ?? ProxyType.hysteria.label,
        'ssh' => fragment ?? ProxyType.ssh.label,
        'wg' => fragment ?? ProxyType.wireguard.label,
        'awg' => fragment ?? ProxyType.awg.label,
        'shadowtls' => fragment ?? ProxyType.shadowtls.label,
        'mieru' => fragment ?? ProxyType.mieru.label,
        'warp' => fragment ?? ProxyType.warp.label,
        _ => null,
      };
    }
    return name ?? ProxyType.unknown.label;
  }

  static String profileOverrideHelper({required ProfileEntriesCompanion profile}) {
    final populatedHeaders = profile.populatedHeaders.value;

    Map<String, dynamic>? mPopulatedHeaders;
    if (populatedHeaders != null) {
      final m = jsonDecode(populatedHeaders) as Map;
      mPopulatedHeaders = m.cast<String, dynamic>();
    }

    return ProfileParser.profileOverride(
      populatedHeaders: mPopulatedHeaders,
      userOverride: UserOverride.fromStr(profile.userOverride.value),
    );
  }

  static String profileOverride({
    required Map<String, dynamic>? populatedHeaders,
    required UserOverride? userOverride,
  }) {
    final headers = Map<String, dynamic>.from(populatedHeaders ?? {});

    if (headers['enable-warp'].toString() == 'true' || userOverride?.enableWarp == true) {
      headers['chain-status'] = 'extra_security';
      headers['extra-security'] = {'mode': 'warp'};
    }

    if (headers['enable-psiphon'].toString() == 'true' || userOverride?.enablePsiphon == true) {
      headers['chain-status'] = 'extra_security';
      headers['extra-security'] = {'mode': 'psiphon'};
    }

    if (headers['enable-fragment'].toString() == 'true' || userOverride?.enableFragment == true) {
      headers['tls-tricks'] = {'enable-fragment': true};
    }

    headers.removeWhere(
      (key, value) => !allowedOverrideConfigs.contains(key) || value == null || value.toString().isEmpty,
    );

    final profileOverrideStr = jsonEncode({for (final key in headers.keys) key: headers[key]});
    return profileOverrideStr;
  }

  static Map<String, dynamic> applyProfileOverride(Map<String, dynamic> main, String? profileOverride) {
    if (profileOverride == null) return main;
    if (profileOverride.contains("{")) {
      final profileOverrideMap = jsonDecode(profileOverride) as Map<String, dynamic>;
      return _mergeJson(main, profileOverrideMap);
    } else {
      return main;
    }
  }

  static Map<String, dynamic> _mergeJson(Map<String, dynamic> main, Map<String, dynamic> override) {
    override.forEach((key, value) {
      if (main.containsKey(key)) {
        if (main[key] is Map<String, dynamic> && value is Map<String, dynamic>) {
          main[key] = _mergeJson(main[key] as Map<String, dynamic>, value);
        } else {
          main[key] = value;
        }
      } else {
        main[key] = value;
      }
    });
    return main;
  }
}
