// Explicit beta:false checks remain stable when tests use the beta define.
// ignore_for_file: avoid_redundant_argument_values
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/model/environment.dart';

void main() {
  test('beta automatically enables and production respects consent', () {
    expect(const TelemetryPolicy(beta: true).enabled(false), isTrue);
    expect(const TelemetryPolicy(beta: true).tracesSampleRate, .20);
    expect(const TelemetryPolicy(beta: false).enabled(false), isFalse);
    expect(const TelemetryPolicy(beta: false).enabled(true), isTrue);
    expect(const TelemetryPolicy(beta: false).tracesSampleRate, .05);
    expect(const TelemetryPolicy(beta: true).environment, 'beta');
    expect(const TelemetryPolicy(beta: false).environment, 'prod');
    expect(const TelemetryPolicy(beta: true).canDisable, isFalse);
    expect(const TelemetryPolicy(beta: false).canDisable, isTrue);
  });
  test('TestFlight build selects beta policy explicitly', () {
    final workflow = File('.github/workflows/testflight.yml').readAsStringSync();

    expect(workflow, contains('--dart-define "telemetry_beta=true"'));
    expect(workflow, contains(r'SENTRY_DSN: ${{ secrets.SENTRY_DSN }}'));
    expect(workflow, contains('ENV.fetch("SENTRY_DSN")'));
    expect(workflow, contains('SENTRY_DSN must be a valid Sentry DSN for diagnostic uploads'));
  });
}
