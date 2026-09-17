import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';

enum NovaProtectionState { checking, verified, failed }

class NovaProtectionStatus extends StatelessWidget {
  const NovaProtectionStatus({
    super.key,
    required this.state,
    required this.checkingTitle,
    required this.verifiedTitle,
    required this.failedTitle,
    required this.tunnelStartedLabel,
    required this.checkingMessage,
    required this.verifiedMessage,
    required this.failedMessage,
    required this.retryLabel,
    this.onRetry,
  });

  final NovaProtectionState state;
  final String checkingTitle;
  final String verifiedTitle;
  final String failedTitle;
  final String tunnelStartedLabel;
  final String checkingMessage;
  final String verifiedMessage;
  final String failedMessage;
  final String retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final nova = NovaThemeData.of(context);
    final (title, message, icon, color) = switch (state) {
      NovaProtectionState.checking => (checkingTitle, checkingMessage, Icons.shield_outlined, NovaColors.signalMid),
      NovaProtectionState.verified => (
        verifiedTitle,
        verifiedMessage,
        Icons.verified_user_rounded,
        NovaColors.signalGood,
      ),
      NovaProtectionState.failed => (failedTitle, failedMessage, Icons.gpp_maybe_rounded, NovaColors.signalBad),
    };

    return Semantics(
      container: true,
      excludeSemantics: true,
      liveRegion: true,
      label: '$title. $tunnelStartedLabel. $message',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: nova.surface,
          borderRadius: BorderRadius.circular(NovaRadii.large),
          border: Border.all(color: color.withValues(alpha: 0.34)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(NovaSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox.square(
                dimension: 32,
                child: state == NovaProtectionState.checking
                    ? CircularProgressIndicator(strokeWidth: 2, color: color)
                    : Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: NovaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: NovaSpacing.xs),
                    Text(tunnelStartedLabel, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: NovaSpacing.xs),
                    Text(message, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: nova.secondaryText)),
                    if (state == NovaProtectionState.failed && onRetry != null) ...[
                      const SizedBox(height: NovaSpacing.sm),
                      TextButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(retryLabel),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
