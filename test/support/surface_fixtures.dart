import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/router/dialog/widgets/confirmation_dialog.dart';
import 'package:hiddify/core/router/dialog/widgets/custom_alert_dialog.dart';
import 'package:hiddify/core/router/dialog/widgets/experimental_feature_notice.dart';
import 'package:hiddify/core/router/dialog/widgets/free_profile_consent_dialog.dart';
import 'package:hiddify/core/router/dialog/widgets/new_version_dialog.dart';
import 'package:hiddify/core/router/dialog/widgets/no_active_profile_dialog.dart';
import 'package:hiddify/core/router/dialog/widgets/ok_dialog.dart';
import 'package:hiddify/core/router/dialog/widgets/proxy_info_dialog.dart';
import 'package:hiddify/core/router/dialog/widgets/setting_input_dialog.dart';
import 'package:hiddify/core/router/dialog/widgets/setting_picker_dialog.dart';
import 'package:hiddify/core/router/dialog/widgets/setting_slider_dialog.dart';
import 'package:hiddify/core/router/dialog/widgets/sort_profiles_dialog.dart';
import 'package:hiddify/core/router/dialog/widgets/unknown_domains_warning_dialog.dart';
import 'package:hiddify/core/router/dialog/widgets/warp_license_dialog.dart';
import 'package:hiddify/features/app_update/model/remote_version_entity.dart';
import 'package:hiddify/features/app_update/notifier/app_update_notifier.dart';
import 'package:hiddify/features/app_update/notifier/app_update_state.dart';
import 'package:hiddify/features/log/overview/logs_overview_notifier.dart';
import 'package:hiddify/features/log/overview/logs_overview_state.dart';
import 'package:hiddify/features/profile/details/profile_details_notifier.dart';
import 'package:hiddify/features/profile/details/profile_details_state.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/settings/overview/sections/dns_options_page.dart';
import 'package:hiddify/features/settings/overview/sections/general_page.dart';
import 'package:hiddify/features/settings/overview/sections/inbound_options_page.dart';
import 'package:hiddify/features/settings/overview/sections/route_options_page.dart';
import 'package:hiddify/features/settings/overview/sections/tls_tricks_page.dart';
import 'package:hiddify/features/settings/overview/sections/warp_options_page.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const settingsSurfaces = <String, Widget>{
  'general': GeneralPage(),
  'dns': DnsOptionsPage(),
  'inbound': InboundOptionsPage(),
  'route': RouteOptionsPage(),
  'tls': TlsTricksPage(),
  'warp': WarpOptionsPage(),
};

/// Count actual row controls, including adaptive switches. IconButton-only
/// inventories silently pass on preferences pages with no icon buttons.
Finder interactiveRows() => find.byWidgetPredicate(
  (w) => (w is ListTile && w.enabled && w.onTap != null) || (w is SwitchListTile && w.onChanged != null),
);

double contrastRatio(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
}

class SurfaceLogs extends LogsOverviewNotifier {
  SurfaceLogs(this.initial);
  final LogsOverviewState initial;
  @override
  LogsOverviewState build() => initial;
}

class SurfaceProxies extends ProxiesOverviewNotifier {
  SurfaceProxies(this.initial);
  final AsyncValue<OutboundGroup?> initial;
  @override
  Stream<OutboundGroup?> build() => switch (initial) {
    AsyncData(:final value) => Stream.value(value),
    AsyncError(:final error, :final stackTrace) => Stream.error(error, stackTrace),
    _ => const Stream.empty(),
  };
}

class SurfaceAppUpdate extends AppUpdateNotifier {
  @override
  AppUpdateState build() => const AppUpdateState.disabled();
}

final dialogSurfaces = <String, Widget>{
  'D01': const NoActiveProfileDialog(),
  'D02': const ConfirmationDialog(title: 'Synthetic confirmation', message: 'Keep this action?'),
  'D03': const ExperimentalFeatureNoticeDialog(),
  'D04': const WarpLicenseDialog(),
  'D07': const SortProfilesDialog(),
  'D08': ProxyInfoDialog(
    outboundInfo: OutboundInfo(tag: 'Synthetic proxy', type: 'vless'),
  ),
  'D09': const UnknownDomainsWarningDialog(url: 'https://example.invalid'),
  'D10': const FreeProfileConsentDialog(title: 'Synthetic consent', consent: '**Terms** for synthetic profile'),
  'D11': NewVersionDialog(
    '1.0',
    RemoteVersionEntity(
      version: '2.0',
      buildNumber: '2',
      releaseTag: 'synthetic',
      preRelease: false,
      url: 'https://example.invalid',
      publishedAt: DateTime(2026),
      flavor: Environment.prod,
    ),
  ),
  'D12': const CustomAlertDialog(title: 'Synthetic error', message: 'Synthetic error details'),
  'D13': const OkDialog(title: 'Synthetic info', description: 'Synthetic information'),
  'input': const SettingInputDialog<int>(title: 'Port', initialValue: 1080, mapTo: int.tryParse, digitsOnly: true),
  'picker': SettingPickerDialog<String>(
    title: 'Synthetic choice',
    selected: 'One',
    options: const ['One', 'Two'],
    getTitle: (v) => v,
  ),
  'slider': const SettingsSliderDialog(title: 'Synthetic interval', initialValue: 10, min: 1, max: 60, divisions: 59),
};

class SurfaceDetails extends ProfileDetailsNotifier {
  SurfaceDetails(this.initial);
  final ProfileDetailsState initial;
  @override
  Future<ProfileDetailsState> build(String id) async => initial;
}
