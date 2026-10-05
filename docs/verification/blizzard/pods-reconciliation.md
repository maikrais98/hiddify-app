# Pods reconciliation assessment — read-only

Candidate01149e65. Parsed both lockfiles as YAML; normalized PODS by name/version and sorted dependency edges. No Flutter, CocoaPods install/update, Xcode, network, global change or repository mutation performed. Read shipping attempt log: observed failure is [CP] sandbox mismatch. Parent reports x86_64 dependency compilation succeeded before that; no architecture failure established by this attempt.

## Complete semantic delta

- Tracked PODS39 entries; installed40. Only added entry: integration_test0.0.1→Flutter. No removed entry. Every common pod/subspec name+version and its dependency-edge set is identical. Therefore **zero changed versions or edges among existing runtime pods**.
- DEPENDENCIES: only addition integration_test from .symlinks/plugins/integration_test/ios; no removal/change of existing entries.
- EXTERNAL SOURCES: only added integration_test path above; all common source declarations identical.
- SPEC REPOS identical; PODFILE CHECKSUM identical.
- COCOAPODS1.16.2 tracked versus1.17.0 installed.
- SPEC CHECKSUMS: added integration_test;18 changed common local plugin spec checksums: app_links, cupertino_http, device_info_plus, file_picker, flutter_keyboard_visibility, flutter_native_splash, in_app_review, mobile_scanner, network_info_plus, objective_c, package_info_plus, path_provider_foundation, pointer_interceptor_ios, sentry_flutter, share_plus, shared_preferences_foundation, sqlite3_flutter_libs, url_launcher_ios. Other common spec checksums identical.
- No other YAML section differs.

integration_test is explicitly sdk:flutter under dev_dependencies in current pubspec.yaml; generated plugin inventory marks native_build=true and dev_dependency=true. It is a test SDK dependency addition, not a version upgrade of the existing runtime pods. However its current generated Pods integration may include native test code in a Debug compile. Do not claim artifact-identical production dependency graph solely because pubspec calls it dev.

**Checksum qualification:** Changed SPEC CHECKSUMS are not proven harmless serialization metadata by this audit. Equal pod versions/edges and identical source declarations do not prove identical podspec content, source files or generated build settings. Do not state “only metadata changed” without comparing the actual specs against a proven baseline. Current facts support “unchanged existing versions/edges, added dev SDK pod, changed tool receipt and local spec checksums.”

## Local CocoaPods1.16.2

/opt/homebrew/bin/pod wrapper points to /opt/homebrew/Cellar/cocoapods/1.17.0/libexec. Found1.17.0 installed gemspec and core. System Ruby2.6.10 Gem specifications contain no CocoaPods. Searched local Homebrew CocoaPods cellar, Homebrew Ruby gem tree, user ~/.gem (absent), and /private/tmp/wir-baseline-tools for cocoapods1.16.2 gemspec/cache: none found. Thus1.16.2 is **not available in inspected standard/local tool locations**; do not assert it exists or install it in this read-only task. This is a bounded availability check, not a full-disk proof of absence.

## Faithful reconciliation

There is no currently demonstrated exact-lock reconciliation path using the unmodified present inputs. The current generated plugin set asks for integration_test absent from original lock, and local podspec checksums differ. A real CocoaPods install would regenerate lock+Manifest coherently; --deployment is a guard against needed lock changes, not a way to make these divergent inputs identical. Copying original lock over Manifest, overwriting either to appease [CP], or disabling the phase would falsify sandbox evidence and is not acceptable. Switching to1.16.2 alone is neither locally available nor proven sufficient.

## Bounded compile-only option

The explicitly approved §8 Flutter build can be attempted as a **compile experiment with regenerated native bookkeeping**, with preservation checks below. It may legitimately regenerate a coherent Podfile.lock and Pods/Manifest.lock from current exact input, allowing [CP] to verify the real generated sandbox. Keep their actual generated copies/hashes with the build receipt, then restore ONLY the tracked lock from the saved pre-run exact bytes after compilation; do not rewrite generated Manifest to fake equality. The final checkout will again correctly show a sandbox-sync prerequisite for future builds. Prefer a disposable build workspace if root needs both a clean final source checkout and coherent retained generated sandbox.

This yields at most “candidate app source compiled using documented generated sandbox, existing runtime pod versions unchanged, added test SDK pod/changed spec receipts.” It is **not exact original-lock shipping proof**, signed delivery, installation, production bootstrap or VPN runtime proof. Whether §8 compile gate accepts that limited result is a scope decision; do not conceal the qualification.

### Concrete invariants for root

1. Snapshot candidate SHA and bytes/hashes of tracked ios/, pubspec.yaml, pubspec.lock plus existing pre-run dirty state; retain original Podfile.lock separately. Preserve original Podfile/project/identity/architectures/entitlements/runtime version constraints.
2. Pinned Flutter3.38.5, --no-pub, explicit main_prod.dart, --simulator --no-codesign and explicit visual define. No pod update, dependency upgrade, repo update, signing, provisioning update, release/package/export/upload or device actions.
3. Inspect generated diff before treating any output as success. Existing PODS name/version/dependency edges and sources must remain identical. The already characterized integration_test addition and tool/spec-checksum differences must be recorded exactly; any new runtime pod/version/source/edge difference invalidates the bounded premise and needs separate review.
4. Retain coherent generated lock+Manifest and relevant podspec hashes/build settings as artifact provenance, not merely the restored original lock. Do not assume checksum differences benign.
5. Restore tracked baseline lock after saving evidence; verify all tracked native source, dependencies, identity and configuration equal their pre-run state. Do not blanket-reset unrelated work. Any additional tracked change is not automatically permitted bookkeeping.
6. Record actual compiler exit, SDK/architecture, target, source/lock/podspec receipts and artifact hash; no success claim on partial compilation.

No architecture workaround is presently warranted: first generic attempt reached dependency compile and failed at manifest verification. Re-test ordinary generic behavior only after valid generated sandbox preparation, without ARCHS/EXCLUDED_ARCHS overrides or project changes.
