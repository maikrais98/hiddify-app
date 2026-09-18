import 'package:dartx/dartx.dart';

final class TelemetryPolicy {
  const TelemetryPolicy({this.beta = const bool.fromEnvironment('telemetry_beta')});
  final bool beta;
  bool enabled(bool consent) => beta || consent;
  bool get canDisable => !beta;
  double get tracesSampleRate => beta ? .20 : .05;
  String get environment => beta ? 'beta' : 'prod';
}

enum Environment {
  prod,
  dev;

  static const sentryDSN = String.fromEnvironment("sentry_dsn");
  // This environment variable is set in the 'windows-release-zip' command
  static const isPortable = bool.fromEnvironment("portable");
}

enum Release {
  general("general"),
  // This environment variable is set in the 'android-release-aab' command
  googlePlay("google-play");

  const Release(this.key);

  final String key;

  bool get allowCustomUpdateChecker => this == general;

  static Release read() =>
      Release.values.firstOrNullWhere((e) => e.key == const String.fromEnvironment("release")) ?? Release.general;
}
