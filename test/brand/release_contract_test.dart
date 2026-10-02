import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only iOS builds remain enabled in CI and legacy release workflows', () async {
    final result = await Process.run('ruby', [
      '-ryaml',
      '-rjson',
      '-e',
      'puts JSON.generate(ARGV.map { |path| YAML.load_file(path).fetch("jobs") })',
      '.github/workflows/build.yml',
      '.github/workflows/signed-release.yml',
      '.github/workflows/release.yml',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final workflows = jsonDecode(result.stdout as String) as List<Object?>;
    final unsignedJobs = workflows[0]! as Map<String, Object?>;
    final signedJobs = workflows[1]! as Map<String, Object?>;
    final tagJobs = workflows[2]! as Map<String, Object?>;
    final unsignedBuild = unsignedJobs['build']! as Map<String, Object?>;
    final signedBuild = signedJobs['build']! as Map<String, Object?>;
    final tagBuild = tagJobs['build-release']! as Map<String, Object?>;
    final testJob = unsignedJobs['test']! as Map<String, Object?>;
    final iosJob = unsignedJobs['ios-build']! as Map<String, Object?>;
    expect(unsignedBuild['if'], r'${{ false }}');
    expect(signedBuild['if'], startsWith(r'${{ false && '));
    expect(tagBuild['if'], r'${{ false }}');
    expect(testJob.containsKey('if'), isFalse);
    expect(iosJob.containsKey('if'), isFalse);
    expect(iosJob['needs'], 'test');
    final testSteps = (testJob['steps']! as List<Object?>).cast<Map<String, Object?>>();
    final prepare = testSteps.singleWhere((step) => step['name'] == 'Prepare');
    expect(prepare['run'], 'make common-prepare');
  });

  test('keeps 0.0.1 build 1 synchronized across release metadata', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final project = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final runnerInfo = File('ios/Runner/Info.plist').readAsStringSync();
    final android = File('android/app/build.gradle').readAsStringSync();
    final msix = File('windows/packaging/msix/make_config.yaml').readAsStringSync();

    expect(pubspec, contains('version: 0.0.1+1'));
    expect(RegExp(r'MARKETING_VERSION = 0\.0\.1;').allMatches(project).length, 6);
    expect(RegExp('CURRENT_PROJECT_VERSION = 1;').allMatches(project).length, 6);
    expect(runnerInfo, contains(r'<string>$(FLUTTER_BUILD_NAME)</string>'));
    expect(runnerInfo, contains(r'<string>$(FLUTTER_BUILD_NUMBER)</string>'));
    expect(android, contains('versionCode flutterVersionCode.toInteger()'));
    expect(android, contains('versionName flutterVersionName'));
    expect(msix, contains('msix_version: 0.0.1.1'));
  });

  test('release version tool accepts marketing and build independently', () {
    final script = File('.github/change_version.sh').readAsStringSync();

    expect(script, contains('MARKETING_VERSION'));
    expect(script, contains('BUILD_NUMBER'));
    expect(script, contains('VERSION_ONLY'));
    expect(script, isNot(contains('* 10000')));
  });

  test('TestFlight workflow is explicit-ref, iOS-only, and isolated from other stores', () {
    final workflow = File('.github/workflows/testflight.yml').readAsStringSync();

    expect(workflow, contains('workflow_dispatch:'));
    expect(workflow, contains('ref:'));
    expect(workflow, contains(r'ref: ${{ needs.resolve-ref.outputs.sha }}'));
    expect(workflow, contains('environment: release-signing'));
    expect(workflow, contains('environment: release-publish'));
    expect(workflow, contains('Build signed IPA with App Store Connect API'));
    expect(workflow, contains('flutter build ios --release --no-codesign'));
    expect(workflow, contains(r'--build-name "$MARKETING_VERSION"'));
    expect(workflow, contains(r'--build-number "$BUILD_NUMBER"'));
    expect(workflow, contains('-allowProvisioningUpdates'));
    expect(workflow, contains(r'-authenticationKeyPath "$api_key_path"'));
    expect(workflow, contains(r'-authenticationKeyID "$APPSTORE_API_KEY_ID"'));
    expect(workflow, contains(r'-authenticationKeyIssuerID "$APPSTORE_ISSUER_ID"'));
    expect(workflow, contains('-exportArchive'));
    expect(workflow, isNot(contains('APPLE_CERTIFICATE_P12')));
    expect(workflow, isNot(contains('APPLE_MOBILE_PROVISIONING_PROFILES')));
    expect(workflow, contains('Assign existing TestFlight group'));
    expect(workflow, contains("mode:"));
    expect(workflow, contains("- resume"));
    expect(workflow, contains("resume-testflight:"));
    expect(workflow, isNot(contains('upload-google-play')));
    expect(workflow, isNot(contains('action-gh-release')));
    expect(workflow, isNot(contains('android-aab')));
  });

  test('next TestFlight build is selected above occupied builds', () async {
    final result = await Process.run('ruby', ['.github/testflight_build.rb', 'next-number', '2', '1', '3', '2']);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect((result.stdout as String).trim(), '4');
  });

  test('TestFlight readiness distinguishes internal testing from Beta App Review', () {
    final script = File('.github/testflight_build.rb').readAsStringSync();

    expect(script, contains('buildBetaDetail'));
    expect(script, contains('isInternalGroup'));
    expect(script, contains('Beta App Review gate'));
    expect(script, contains('MISSING_EXPORT_COMPLIANCE'));
    expect(script, contains('PROCESSING_EXCEPTION'));
  });

  for (final diagnosticCase in <String, bool?>{
    '': false,
    'https://synthetic-public-key@ingest.sentry.io/123': true,
    'https://synthetic secret@ingest.sentry.io/123': null,
    'https://ingest.sentry.io/project': null,
  }.entries) {
    test('TestFlight selects safe telemetry for DSN case ${diagnosticCase.value}', () async {
      final result = await Process.run('ruby', [
        '-ryaml',
        '-rjson',
        '-e',
        'puts JSON.generate(YAML.load_file(ARGV[0]).fetch("jobs").fetch("build-ios").fetch("steps"))',
        '.github/workflows/testflight.yml',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final steps = (jsonDecode(result.stdout as String) as List<Object?>).cast<Map<String, Object?>>();
      final selectors = steps.where((step) => step['name'] == 'Select diagnostic mode').toList();
      expect(selectors, hasLength(1), reason: 'diagnostic mode must be selected before preparing and signing iOS');
      final selector = selectors.single;
      expect(steps.indexOf(selector), lessThan(steps.indexWhere((step) => step['name'] == 'Generate Flutter sources')));
      expect(selector['continue-on-error'], isNot(true));
      final environment = selector['env']! as Map<String, Object?>;
      expect(environment['SENTRY_DSN'], r'${{ secrets.SENTRY_DSN }}');
      final temporary = Directory.systemTemp.createTempSync('testflight-diagnostics-');
      try {
        final githubEnvironment = File('${temporary.path}/environment');
        final selection = await Process.run(
          'bash',
          ['-e', '-c', selector['run']! as String],
          environment: {'SENTRY_DSN': diagnosticCase.key, 'GITHUB_ENV': githubEnvironment.path},
          includeParentEnvironment: false,
        );
        expect(selection.exitCode == 0, diagnosticCase.value != null);
        final exported = githubEnvironment.existsSync() ? githubEnvironment.readAsStringSync() : '';
        expect(exported, diagnosticCase.value == null ? '' : 'TELEMETRY_BETA=${diagnosticCase.value}\n');
        if (diagnosticCase.key.isNotEmpty) {
          expect('${selection.stdout}${selection.stderr}', isNot(contains(diagnosticCase.key)));
        }
      } finally {
        temporary.deleteSync(recursive: true);
      }
    });
  }

  for (final jobName in ['select-build', 'build-ios', 'upload-testflight', 'resume-testflight']) {
    test('TestFlight $jobName rejects an unready environment before credentials', () async {
      final result = await Process.run('ruby', [
        '-ryaml',
        '-rjson',
        '-e',
        'puts JSON.generate(YAML.load_file(ARGV[0]).fetch("jobs").fetch(ARGV[1]))',
        '.github/workflows/testflight.yml',
        jobName,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final job = jsonDecode(result.stdout as String) as Map<String, Object?>;
      expect(job['environment'], jobName == 'build-ios' ? 'release-signing' : 'release-publish');
      final steps = (job['steps']! as List<Object?>).cast<Map<String, Object?>>();
      final guard = steps.first;
      expect(guard['name'], 'Require protected release environment');
      expect(guard['continue-on-error'], isNot(true));
      final environment = guard['env']! as Map<String, Object?>;
      expect(environment['READY'], r'${{ vars.RELEASE_ENVIRONMENT_READY }}');
      final command = guard['run']! as String;
      for (final readiness in [null, '', 'false', 'true']) {
        final check = await Process.run(
          'bash',
          ['-c', command],
          environment: {if (readiness != null) 'READY': readiness},
          includeParentEnvironment: false,
        );
        expect(check.exitCode == 0, readiness == 'true', reason: '$jobName readiness=$readiness');
      }
    });
  }

  for (final workflow in ['build.yml', 'testflight.yml']) {
    test('$workflow runs native preference and privacy gates before building iOS', () {
      final source = File('.github/workflows/$workflow').readAsStringSync();
      final jobName = workflow == 'build.yml' ? 'ios-build' : 'build-ios';
      final job = source.split('\n  $jobName:').last.split(RegExp(r'\n  [a-z-]+:')).first;
      final build = job.indexOf('flutter build ios');
      expect(build, greaterThan(0));
      for (final script in ['native_vpn_preferences_test.sh', 'native_tunnel_failure_store_test.sh', 'native_extension_log_privacy_test.sh']) {
        final command = RegExp('^\\s+bash test/security/$script\\s*\$', multiLine: true).firstMatch(job);
        expect(command, isNotNull, reason: '$jobName must run $script as a failing gate');
        expect(command!.start, lessThan(build), reason: '$script must block the iOS build when it fails');
      }
    });
  }
}
