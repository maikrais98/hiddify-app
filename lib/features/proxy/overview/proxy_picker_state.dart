import 'package:hooks_riverpod/hooks_riverpod.dart';

final proxyRecentTagsProvider = StateNotifierProvider<ProxyRecentTagsNotifier, List<String>>(
  (ref) => ProxyRecentTagsNotifier(),
);

class ProxyRecentTagsNotifier extends StateNotifier<List<String>> {
  ProxyRecentTagsNotifier() : super(const []);

  static const maxEntries = 3;

  void record(String tag) {
    final normalized = tag.trim();
    if (normalized.isEmpty) return;
    state = [normalized, ...state.where((existing) => existing != normalized)].take(maxEntries).toList(growable: false);
  }
}
