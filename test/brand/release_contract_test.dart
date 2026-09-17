import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
