import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/features/app_update/model/post_update_state.dart';
import 'package:hiddify/features/app_update/notifier/post_update_notifier.dart';
import 'package:hiddify/features/app_update/widget/post_update_outcome_dialog.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum _PostUpdateAction { close, reconnect }

final postUpdateReconnectIntentProvider = Provider<bool>((ref) => ref.watch(Preferences.startedByUser));
final postUpdateStartupResolutionTimeoutProvider = Provider<Duration>((ref) => const Duration(seconds: 3));

bool canReconnectAfterUpdate({
  required ConnectionStatus? connection,
  required bool startedByUser,
  required bool hasActiveProfile,
}) {
  final disconnectedWithoutFailure = switch (connection) {
    Disconnected(:final connectionFailure) => connectionFailure == null,
    _ => false,
  };
  return disconnectedWithoutFailure && startedByUser && hasActiveProfile;
}

class PostUpdateGate extends HookConsumerWidget {
  const PostUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postUpdate = ref.watch(postUpdateNotifierProvider);
    final mounted = useRef(true);

    useEffect(() {
      return () => mounted.value = false;
    }, const []);

    useEffect(() {
      Future.microtask(ref.read(postUpdateNotifierProvider.notifier).detect);
      return null;
    }, const []);

    useEffect(() {
      if (postUpdate case PostUpdateInstalled(:final currentVersion)) {
        Future.microtask(() => _showOutcome(ref, currentVersion, () => mounted.value));
      }
      return null;
    }, [postUpdate]);

    return child;
  }

  bool _canReconnect(WidgetRef ref, ConnectionStatus? connection) {
    return canReconnectAfterUpdate(
      connection: connection,
      startedByUser: ref.read(postUpdateReconnectIntentProvider),
      hasActiveProfile: ref.read(activeProfileProvider).valueOrNull != null,
    );
  }

  Future<void> _showOutcome(WidgetRef ref, String currentVersion, bool Function() isMounted) async {
    final connection = await _resolveConnection(ref);
    final hasActiveProfile = await _resolveActiveProfile(ref);
    if (!isMounted()) return;

    NavigatorState? navigator = rootNavKey.currentState;
    while (isMounted() && navigator == null) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      navigator = rootNavKey.currentState;
    }
    if (!isMounted() || navigator == null) return;

    final reconnectAvailable = canReconnectAfterUpdate(
      connection: connection,
      startedByUser: ref.read(postUpdateReconnectIntentProvider),
      hasActiveProfile: hasActiveProfile,
    );
    final action = await _pushOutcomeDialog(
      navigator,
      currentVersion: currentVersion,
      isConnected: connection is Connected,
      reconnectAvailable: reconnectAvailable,
    );

    if (!isMounted()) return;
    final acknowledged = await ref.read(postUpdateNotifierProvider.notifier).acknowledge();
    if (!acknowledged) return;
    if (action == _PostUpdateAction.reconnect) {
      final currentConnection = ref.read(connectionNotifierProvider).valueOrNull;
      if (_canReconnect(ref, currentConnection)) {
        await ref.read(connectionNotifierProvider.notifier).mayConnect();
      }
    }
  }

  Future<_PostUpdateAction?> _pushOutcomeDialog(
    NavigatorState navigator, {
    required String currentVersion,
    required bool isConnected,
    required bool reconnectAvailable,
  }) {
    return navigator.push<_PostUpdateAction>(
      DialogRoute(
        context: navigator.context,
        barrierDismissible: false,
        builder: (dialogContext) => PostUpdateOutcomeDialog(
          currentVersion: currentVersion,
          isConnected: isConnected,
          onClose: () => Navigator.of(dialogContext).pop(_PostUpdateAction.close),
          onReconnect: reconnectAvailable ? () => Navigator.of(dialogContext).pop(_PostUpdateAction.reconnect) : null,
        ),
      ),
    );
  }

  Future<ConnectionStatus?> _resolveConnection(WidgetRef ref) async {
    try {
      return await ref
          .read(connectionNotifierProvider.future)
          .timeout(ref.read(postUpdateStartupResolutionTimeoutProvider));
    } on Object {
      return null;
    }
  }

  Future<bool> _resolveActiveProfile(WidgetRef ref) async {
    try {
      return await ref
              .read(activeProfileProvider.future)
              .timeout(ref.read(postUpdateStartupResolutionTimeoutProvider)) !=
          null;
    } on Object {
      return false;
    }
  }
}
