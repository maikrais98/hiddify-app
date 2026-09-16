import 'package:flutter/services.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';

/// Native operation failure, separate from tunnel lifecycle and URL-test results.
/// Retain only stable system identifiers; localized native messages may contain
/// private configuration data and must not be sent to dialogs or logs.
class NativeConnectionError {
  const NativeConnectionError(this.operation, this.domain, this.code);

  factory NativeConnectionError.fromPlatform(PlatformException error) {
    final details = error.details;
    final domain = details is Map ? details['domain'] : null;
    final code = details is Map ? details['nativeCode'] : null;
    return NativeConnectionError(
      switch (error.code) {
        'SETUP' => 'setup',
        'SETUP_CONNECTION' => 'start',
        _ => 'platform',
      },
      domain == 'NEVPNErrorDomain' || domain == 'NEVPNConnectionErrorDomain' ? domain as String : 'system',
      code is int ? code : null,
    );
  }

  final String operation;
  final String domain;
  final int? code;

  ConnectionFailure get failure =>
      ConnectionFailure.backgroundCoreNotAvailable('VPN $operation failed ($domain${code == null ? '' : ': $code'}).');
}
