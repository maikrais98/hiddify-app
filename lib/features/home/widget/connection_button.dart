import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/home/widget/nova_connection_control.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
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
    final delay = ref.watch(activeProxyNotifierProvider).valueOrNull?.urlTestDelay ?? 0;
    final requiresReconnect = ref.watch(configOptionNotifierProvider).valueOrNull;

    return NovaConnectionControl(
      onTap: hasNoActiveProfile
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
      label: hasNoActiveProfile
          ? t.pages.home.addAccess
          : switch (connectionStatus) {
              AsyncData(value: Connected()) when requiresReconnect == true => t.connection.reconnect,
              AsyncData(value: Connected()) when delay <= 0 || delay >= 65000 => t.connection.connecting,
              AsyncData(value: final status) => status.present(t),
              AsyncError() => t.connection.tapToConnect,
              _ => t.connection.connecting,
            },
    );
  }
}
