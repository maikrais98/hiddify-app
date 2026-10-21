// Explicit beta:false checks remain stable when tests use the beta define.
// ignore_for_file: avoid_redundant_argument_values
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/model/environment.dart';

void main() {
  test('beta automatically enables and production respects consent', () {
    expect(const TelemetryPolicy(beta: true).enabled(false), isTrue);
    expect(const TelemetryPolicy(beta: true).tracesSampleRate, 0);
    expect(const TelemetryPolicy(beta: false).enabled(false), isFalse);
    expect(const TelemetryPolicy(beta: false).enabled(true), isTrue);
    expect(const TelemetryPolicy(beta: false).tracesSampleRate, 0);
    expect(const TelemetryPolicy(beta: true).environment, 'beta');
    expect(const TelemetryPolicy(beta: false).environment, 'prod');
    expect(const TelemetryPolicy(beta: true).canDisable, isFalse);
    expect(const TelemetryPolicy(beta: false).canDisable, isTrue);
  });
  test('TestFlight build uses the validated diagnostic mode', () {
    final workflow = File('.github/workflows/testflight.yml').readAsStringSync();

    expect(workflow, contains(r'--dart-define-from-file "$RUNNER_TEMP/wir-telemetry.json"'));
    expect(workflow, contains(r'SENTRY_DSN: ${{ secrets.SENTRY_DSN }}'));
    expect(workflow, contains(r'BETTERSTACK_SOURCE_TOKEN: ${{ secrets.BETTERSTACK_SOURCE_TOKEN }}'));
    expect(workflow, contains('python3 scripts/prepare_telemetry.py'));
  });
}
