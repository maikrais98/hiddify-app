import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';

enum DiagnosticCategory { status, permission, configuration, core, access, unknown }

enum DiagnosticStage { unavailable, idle, connecting, connected, disconnecting }

enum DiagnosticCode {
  none,
  unavailable,
  vpnPermission,
  notificationPermission,
  privilege,
  configurationOptions,
  configuration,
  coreUnavailable,
  warpLicense,
  psiphonLicense,
  unexpected,
}

/// Closed vocabulary only: never retains source objects, error text, identifiers,
/// URLs or hashes of secrets. This is a snapshot, not a reachability assertion.
final class SafeDiagnosticSummary {
  const SafeDiagnosticSummary._(this.category, this.stage, this.code, this.platform);

  factory SafeDiagnosticSummary.capture(ConnectionStatus? status, TargetPlatform platform) {
    final stage = switch (status) {
      Disconnected() => DiagnosticStage.idle,
      Connecting() => DiagnosticStage.connecting,
      Connected() => DiagnosticStage.connected,
      Disconnecting() => DiagnosticStage.disconnecting,
      null => DiagnosticStage.unavailable,
    };
    final failure = status is Disconnected ? status.connectionFailure : null;
    final (category, code) = switch (failure) {
      MissingVpnPermission() => (DiagnosticCategory.permission, DiagnosticCode.vpnPermission),
      MissingNotificationPermission() => (DiagnosticCategory.permission, DiagnosticCode.notificationPermission),
      MissingPrivilege() => (DiagnosticCategory.permission, DiagnosticCode.privilege),
      InvalidConfigOption() => (DiagnosticCategory.configuration, DiagnosticCode.configurationOptions),
      InvalidConfig() => (DiagnosticCategory.configuration, DiagnosticCode.configuration),
      BackgroundCoreNotAvailable() => (DiagnosticCategory.core, DiagnosticCode.coreUnavailable),
      MissingWarpLicense() => (DiagnosticCategory.access, DiagnosticCode.warpLicense),
      MissingPsiphonLicense() => (DiagnosticCategory.access, DiagnosticCode.psiphonLicense),
      UnexpectedConnectionFailure() => (DiagnosticCategory.unknown, DiagnosticCode.unexpected),
      null when status == null => (DiagnosticCategory.unknown, DiagnosticCode.unavailable),
      null => (DiagnosticCategory.status, DiagnosticCode.none),
    };
    return SafeDiagnosticSummary._(category, stage, code, platform);
  }

  final DiagnosticCategory category;
  final DiagnosticStage stage;
  final DiagnosticCode code;
  final TargetPlatform platform;

  String get json => const JsonEncoder.withIndent('  ').convert({
    'schema': 1,
    'category': category.name,
    'stage': stage.name,
    'code': code.name,
    'platform': platform.name,
    'reachability': 'not_checked',
  });

  @override
  String toString() => json;
}
