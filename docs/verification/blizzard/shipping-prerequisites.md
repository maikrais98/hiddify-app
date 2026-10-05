# Read-only shipping-build prerequisites — candidate01149e65

Inspected source01149e654180af858de02ff542c836c2ed282d55, lib/main_prod.dart, bootstrap/environment code, Podfile/project/config/scheme, cached prerequisite metadata and existing baseline tooling. No Flutter/Xcode/CocoaPods command, build, install, launch, signing or upload executed. No repository files changed. No secret values printed; generated configuration inspected only through presence/equality booleans for nonsecret routing metadata.

## Entrypoint and environment

lib/main_prod.dart initializes Flutter binding/system UI then lazyBootstrap(..., Environment.prod). Environment has optional compile-time sentry_dsn (defaults empty), portable (false) and release (defaults general). No dotenv loader or required secret-file prerequisite found. For a compile-only artifact, no Sentry/App Store credentials are needed. Do not invoke Makefile distribution/package targets: they incorporate SENTRY_DSN and signing/release tooling unnecessarily.

Bootstrap, if launched, accesses real directories/preferences, analytics preference, migrations, SQLite/profile repository, translations and hiddify core. In production it can clear preferences after a migration failure. A successful compile does NOT prove these initialize, and this task authorizes no app launch. No physical app, VPN or data mutation is needed for compile.

Current generated xcconfig exists; pinned Flutter root and application path match this checkout. Its target is NOT lib/main_prod.dart and DART_DEFINES is present. Do not reuse its target/defines implicitly or print them. Supply explicit FLUTTER_TARGET / build mode / fresh nonsecret DART_DEFINES on an Xcode compile command, or let an explicitly scoped Flutter build regenerate build-only metadata after prerequisites are resolved.

## Current concrete prerequisites / blockers

Present: .dart_tool/package_config.json, ios/Flutter/Generated.xcconfig, Pods/Manifest.lock, tracked Podfile.lock, Runner workspace, expected asset directories, HiddifyCore.xcframework.

HiddifyCore Info.plist declares BOTH ios-arm64 and ios-arm64_x86_64-simulator slices. Thus missing simulator slice is not the observed architecture blocker. Binary provenance/checksum verification can use the existing framework SHA manifest; no replacement/download is needed based on this read-only check.

**Known blocker1: installed Pods sandbox does not equal tracked Podfile.lock.** Current Manifest.lock has integration_test0.0.1, changed local podspec checksums and CocoaPods1.17.0 versus tracked1.16.2. Runner's existing [CP] Check Pods Manifest.lock phase will fail. Do not copy either lockfile over the other to bypass this check, disable the phase, or run pod update. A faithful locked Pods sandbox must be prepared separately without altering tracked native/dependency definitions; if that cannot be achieved within existing approved tooling, report prerequisite blockage. Merely passing --no-pub does not prevent Flutter from invoking pod install or changing tracked Podfile.lock.

**Known blocker2: original Debug Runner excludes simulator arm64 and i386.** The previous exact selected-simulator destination was rejected; original ios-harness.md records this. Use generic Simulator destination for a compile attempt and retain original architecture settings. Do not erase EXCLUDED_ARCHS, force an unapproved ARCHS setting, patch the Xcode project, remove the extension, or substitute the isolated test host as shipping evidence. Whether current generic compile succeeds remains unverified. XCFramework has x86_64 simulator support, but current toolchain/destination compatibility is a separate matter.

Podfile global iOS15.5; post_install/project settings15.0. Preserve both. This existing mismatch is not authorization to update deployment targets. Runner scheme builds the actual Runner and implicit dependencies including original extension linkage/identity.

## Concrete safe compile attempt, after host test tools are idle

Prefer direct Xcode build with generic destination to avoid Flutter's automatic CocoaPods repair while this lock mismatch exists. This command is a future root-owned compile attempt, not executed by this audit:

```
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/blizzard-shipping-01149e65-simulator \
  FLUTTER_TARGET=lib/main_prod.dart FLUTTER_BUILD_MODE=debug \
  DART_DEFINES=QkxJWlpBUkRfVklTVUFMUz10cnVl \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= build
```

The explicit DART_DEFINES is only base64(BLIZZARD_VISUALS=true), no secret. Use pinned Flutter root already verified in generated config and PUB_CACHE=/private/tmp/wir-baseline-tools/pub-cache. No specific simulator/device selection; no simulator boot/install/run. Keep stdout/stderr in a local receipt and report only redacted diagnostics. Expected first failure may be Pods sandbox sync or baseline architecture. Neither is a Blizzard UI compile failure.

Once a faithful unchanged-lock Pods sandbox is available, the approved-plan Flutter equivalent is:

```
PUB_CACHE=/private/tmp/wir-baseline-tools/pub-cache \
/private/tmp/wir-baseline-tools/flutter-3.38.5/bin/flutter --suppress-analytics \
  build ios --simulator --debug --no-codesign --no-pub \
  --target lib/main_prod.dart --dart-define=BLIZZARD_VISUALS=true
```

This is not the first safe command in the current mismatched sandbox, because its pod-install side effect may change the lock. Protect/check tracked native/dependency files around any root execution and do not call such changed output equivalent to the candidate.

## Architecture fallback only

If generic Simulator is blocked by preserved baseline architecture, a local unsigned physical Release compile is a distinct permissible artifact, not a Simulator workaround or delivery. Same Xcode command shape with -configuration Release -sdk iphoneos -destination 'generic/platform=iOS', dedicated derivedDataPath, FLUTTER_BUILD_MODE=release, explicit main_prod/defines and all signing disabled. No archive/export/IPA/install/device selection, -allowProvisioningUpdates or upload. The Pods mismatch also blocks this path; it must not be concealed.

## Receipt required

Record candidate SHA, tracked/native/dependency hashes before/after, actual target/configuration/SDK/architecture, explicit visual switch, compiler exit and resulting .app/artifact hash only after success. Separate unsigned compile proof from simulator execution, isolated synthetic test-host results, production bootstrap, physical traffic/lifecycle and release acceptance. Existing release scripts require App Store credentials and implement upload/distribution; do not invoke them for this task.
