import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/home/widget/nova_connection_control.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ConnectionButton extends HookConsumerWidget {
  const ConnectionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final connectionStatus = ref.watch(connectionNotifierProvider);
    final activeProfileState = ref.watch(activeProfileProvider);
    final hasNoActiveProfile = switch (activeProfileState) {
      AsyncData(value: null) => true,
      _ => false,
    };
    final requiresReconnect = ref.watch(configOptionNotifierProvider).valueOrNull;

    final needsInitializationRetry =
        connectionStatus.hasError && ref.read(connectionNotifierProvider.notifier).needsInitializationRetry;
    final control = NovaConnectionControl(
      onTap: needsInitializationRetry
          ? () => ref.read(connectionNotifierProvider.notifier).retryInitialization()
          : hasNoActiveProfile
          ? () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile()
          : switch (connectionStatus) {
              AsyncData(value: Connected()) when requiresReconnect == true => () async {
                final activeProfile = await ref.read(activeProfileProvider.future);
                return ref.read(connectionNotifierProvider.notifier).reconnect(activeProfile);
              },
              AsyncData(value: Disconnected()) || AsyncError() => () async {
                switch (activeProfileState) {
                  case AsyncData(value: null):
                    return ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile();
                  case AsyncData():
                    if (await ref.read(dialogNotifierProvider.notifier).showExperimentalFeatureNotice()) {
                      return ref.read(connectionNotifierProvider.notifier).toggleConnection();
                    }
                  case AsyncLoading() || AsyncError():
                    return;
                }
              },
              AsyncData(value: Connected()) => () async {
                if (requiresReconnect == true &&
                    await ref.read(dialogNotifierProvider.notifier).showExperimentalFeatureNotice()) {
                  return ref
                      .read(connectionNotifierProvider.notifier)
                      .reconnect(await ref.read(activeProfileProvider.future));
                }
                return ref.read(connectionNotifierProvider.notifier).toggleConnection();
              },
              _ => () {},
            },
      enabled:
          needsInitializationRetry ||
          hasNoActiveProfile ||
          switch (connectionStatus) {
            AsyncData(value: Connected()) when requiresReconnect != true => true,
            AsyncData(value: Connected()) ||
            AsyncData(value: Disconnected()) ||
            AsyncError() => activeProfileState is AsyncData<ProfileEntity?>,
            _ => false,
          },
      connected: !hasNoActiveProfile && (connectionStatus.valueOrNull?.isConnected ?? false),
      loading: !hasNoActiveProfile && (connectionStatus.valueOrNull?.isSwitching ?? connectionStatus.isLoading),
      label: needsInitializationRetry
          ? t.common.retry
          : hasNoActiveProfile
          ? t.pages.home.addAccess
          : switch (connectionStatus) {
              AsyncData(value: Connected()) when requiresReconnect == true => t.connection.reconnect,
              AsyncData(value: Connected()) => t.connection.disconnect,
              AsyncData(value: final status) => status.present(t),
              AsyncError() => t.connection.tapToConnect,
              _ => t.connection.connecting,
            },
    );
    if (connectionStatus.error case final ConnectionFailure failure when needsInitializationRetry) {
      final presentation = failure.present(t);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          control,
          const SizedBox(height: 12),
          Text(
            [presentation.type, if (presentation.message != null) presentation.message!].join('\n'),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    return control;
  }
}
