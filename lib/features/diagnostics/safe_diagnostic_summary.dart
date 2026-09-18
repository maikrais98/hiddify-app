import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hiddify/core/observability/observability.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:uuid/uuid.dart';

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
  const SafeDiagnosticSummary._({
    required this.diagnosticId,
    required this.category,
    required this.stage,
    required this.code,
    required this.appVersion,
    required this.buildNumber,
    required this.environment,
    required this.platform,
    required this.latestErrorCode,
    required this.recentEvents,
  });

  factory SafeDiagnosticSummary.capture(
    ConnectionStatus? status,
    TargetPlatform targetPlatform, {
    ObservabilityDiagnosticSnapshot? observabilitySnapshot,
  }) {
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
    final snapshot = observabilitySnapshot;
    return SafeDiagnosticSummary._(
      diagnosticId: const Uuid().v4(),
      category: category,
      stage: stage,
      code: code,
      appVersion: snapshot?.appVersion ?? 'unknown',
      buildNumber: snapshot?.buildNumber ?? 'unknown',
      environment: snapshot?.environment ?? 'unknown',
      platform: snapshot == null || snapshot.platform == 'unknown' ? targetPlatform.name : snapshot.platform,
      latestErrorCode: snapshot?.latestErrorCode,
      recentEvents: snapshot?.recentEvents ?? const [],
    );
  }

  final String diagnosticId;
  final DiagnosticCategory category;
  final DiagnosticStage stage;
  final DiagnosticCode code;
  final String appVersion;
  final String buildNumber;
  final String environment;
  final String platform;
  final String? latestErrorCode;
  final List<Map<String, Object>> recentEvents;

  String get json => const JsonEncoder.withIndent('  ').convert({
    'schema': 2,
    'diagnostic_id': diagnosticId,
    'category': category.name,
    'stage': stage.name,
    'code': code.name,
    'app_version': appVersion,
    'build_number': buildNumber,
    'environment': environment,
    'platform': platform,
    'latest_error_code': latestErrorCode,
    'recent_events': recentEvents,
    'reachability': 'not_checked',
  });

  @override
  String toString() => json;
}
