import 'package:dio/dio.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/data/proxy_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum ProtectionReachability { notChecked, verified, failed }

Future<ProtectionReachability> measureProtectedReachability(ProxyRepository repository, CancelToken cancelToken) async {
  final result = await repository.getCurrentIpInfo(cancelToken).run();
  return result.fold((_) => ProtectionReachability.failed, (_) => ProtectionReachability.verified);
}

/// Measures reachability independently from the tunnel lifecycle.
///
/// [ProxyRepository.getCurrentIpInfo] uses `proxyOnly: true`, so a successful
/// result cannot be produced by the HTTP client's direct fallback path.
final protectedReachabilityProvider = FutureProvider.autoDispose<ProtectionReachability>((ref) async {
  final connection = await ref.watch(connectionNotifierProvider.future);
  if (connection is! Connected) return ProtectionReachability.notChecked;

  final cancelToken = CancelToken();
  ref.onDispose(cancelToken.cancel);
  return measureProtectedReachability(ref.watch(proxyRepositoryProvider), cancelToken);
});
