import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/app_update/model/post_update_state.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:version/version.dart';

final postUpdateNotifierProvider = StateNotifierProvider<PostUpdateNotifier, PostUpdateState>((ref) {
  final appInfo = ref.watch(appInfoProvider).requireValue;
  return PostUpdateNotifier(
    preferences: ref.watch(sharedPreferencesProvider).requireValue,
    currentVersion: appInfo.version,
    currentBuildNumber: appInfo.buildNumber,
  );
});

class PostUpdateNotifier extends StateNotifier<PostUpdateState> {
  PostUpdateNotifier({
    required SharedPreferences preferences,
    required String currentVersion,
    required String currentBuildNumber,
  }) : _preferences = preferences,
       _currentVersion = currentVersion,
       _currentRevision = _revision(currentVersion, currentBuildNumber),
       super(const PostUpdateIdle());

  static const lastAcknowledgedRevisionKey = 'last_acknowledged_app_revision';

  final SharedPreferences _preferences;
  final String _currentVersion;
  final String _currentRevision;
  bool _checked = false;

  Future<void> detect() async {
    if (_checked) return;
    _checked = true;

    final previousRevision = _preferences.getString(lastAcknowledgedRevisionKey);
    if (previousRevision == null) {
      await _preferences.setString(lastAcknowledgedRevisionKey, _currentRevision);
      return;
    }
    if (previousRevision == _currentRevision) return;
    if (!_isUpgrade(previousRevision, _currentRevision)) {
      await _preferences.setString(lastAcknowledgedRevisionKey, _currentRevision);
      return;
    }

    state = PostUpdateInstalled(
      previousRevision: previousRevision,
      currentRevision: _currentRevision,
      currentVersion: _currentVersion,
    );
  }

  Future<void> acknowledge() async {
    if (state is! PostUpdateInstalled) return;
    if (await _preferences.setString(lastAcknowledgedRevisionKey, _currentRevision)) {
      state = const PostUpdateIdle();
    }
  }

  static String _revision(String version, String buildNumber) => '$version+$buildNumber';

  static bool _isUpgrade(String previousRevision, String currentRevision) {
    final previous = _parseRevision(previousRevision);
    final current = _parseRevision(currentRevision);
    if (previous == null || current == null) return false;

    final versionComparison = current.$1.compareTo(previous.$1);
    if (versionComparison != 0) return versionComparison > 0;
    return current.$2 > previous.$2;
  }

  static (Version, int)? _parseRevision(String revision) {
    final separator = revision.lastIndexOf('+');
    if (separator <= 0 || separator == revision.length - 1) return null;
    try {
      final version = Version.parse(revision.substring(0, separator));
      final buildNumber = int.parse(revision.substring(separator + 1));
      return (version, buildNumber);
    } on FormatException {
      return null;
    }
  }
}
