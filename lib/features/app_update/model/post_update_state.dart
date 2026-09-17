sealed class PostUpdateState {
  const PostUpdateState();
}

final class PostUpdateIdle extends PostUpdateState {
  const PostUpdateIdle();
}

final class PostUpdateInstalled extends PostUpdateState {
  const PostUpdateInstalled({
    required this.previousRevision,
    required this.currentRevision,
    required this.currentVersion,
  });

  final String previousRevision;
  final String currentRevision;
  final String currentVersion;
}
