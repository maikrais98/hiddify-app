# Gate B iOS verification

## Result
Isolated iOS test host: native write/read across separate processes PASS; real UI smoke PASS; candidate visual/a11y run completed with 46 PASS and 7 expected visual RED. No production native or UI changes made by this task. Shipping Runner remains unbuilt: its exact simulator destination is rejected by Xcode. The separate host is a test environment, not shipping app or VPN evidence.

## Source/environment
Source /LOCAL_USER_HOME/Documents/KVN/blizzard-ios-migration.
SDK /private/tmp/wir-baseline-tools/flutter-3.38.5/bin/flutter --suppress-analytics; PUB_CACHE=/private/tmp/wir-baseline-tools/pub-cache.
Xcode26.6 build17F113. Strict unique named simulator WIR UI Verification, iOS26.5. Selector IDs omitted from receipts. Only selected simulator boot/host termination; no physical-device actions or reset.
Test host /private/tmp/blizzard-ios-test-host, isolated bundle dev.blizzardharness.hiddify. Flutter template Runner, no PacketTunnel or AppGroup. lib/assets/test/integration_test are symlinks to actual source. Copied pubspec.yaml/lock, offline pubget kept whole lock byte-identical. Host-only Podfile minimum iOS15.5 for existing plugins.

## Reproduction
1. python3 scripts/blizzard_prepare_test_host.py (fresh host only; refuses overwrite).
2. python3 scripts/blizzard_simulator_run.py --test-host --preserve-storage
3. python3 scripts/blizzard_simulator_run.py --test-host --visual-checks

Storage runner invokes pinned Flutter run --no-pub -d <strict-selected-ID> --target integration_test/blizzard_preservation_test.dart --dart-define=BLIZZARD_STORAGE_PHASE=write/read. It waits for All tests passed, sends q, explicitly terminates only verified host bundle on same simulator, then launches separate process for read.
Visual runner invokes pinned Flutter test integration_test/blizzard_preservation_test.dart --no-pub -d <strict-selected-ID> --dart-define=BLIZZARD_STORAGE_PHASE=write --dart-define=BLIZZARD_VISUAL_CHECKS=true --dart-define=BLIZZARD_VISUALS=true. Candidate checks are intentionally enabled before production UI implementation.

## Verified receipts/logs
/private/tmp/blizzard-ios-write.log: exit0, actual Platform.isIOS, native preference write/readback, real theme tile selects dark, real QuickSettings open/dismiss, ConnectionButton callback spy, actual adaptive navigation branch. BLIZZARD_STORAGE backend=ios_shared_preferences phase=write level=native_reopen result=PASS; BLIZZARD_IOS_UI phase=write platform=ios fixtures=synthetic connection_boundary=spy result=PASS.
/private/tmp/blizzard-ios-read.log: exit0, existing marker and theme read BEFORE seed/init, actual iOS. BLIZZARD_STORAGE backend=ios_shared_preferences phase=read level=process_restart result=PASS; BLIZZARD_IOS_UI phase=read platform=ios fixtures=synthetic connection_boundary=spy result=PASS.
/private/tmp/blizzard-ios-visual.log: completed 2min, 46 PASS/7 FAIL exit1. Native read+UI smoke passed first. Six eligible dark-mobile palette failures expected06121D vs actual121318: system/dark at393,599; dark/light at393,599; dark/dark at393,599. One connection geometry failure expectedRoundedRectangleBorder vs actualCircleBorder. Remaining matrix incl accessibility passed. These are expected product visual RED, not missing classes, compiler errors or broken harness.
Pinned Flutter analyze --no-pub integration_test/blizzard_preservation_test.dart: exit0 No issues found. Both Python scripts AST syntax PASS. git diff --exit-code -- ios/Podfile.lock ios/Runner.xcodeproj/project.pbxproj PASS.

## Storage semantics and boundaries
No SharedPreferences.setMockInitialValues in native storage smoke. Actual iOS plugin/store in isolated test host; process_restart proved by two processes. Visual tests use mock preferences only after smoke in their own renderer fixture. Synthetic profiles/stats/proxy and connection spy isolate external boundaries; no production main/bootstrap, VPN/core startup, network or native permission proof. Physical traffic, device permission/lifecycle, upgrade/rollback and candidate signed-app build remain separate gates.
Pinned SDK integration_test_device.dart kill() line144 uninstalls app after flutter test. Initial two-flutter-test attempt: write smoke PASS, subsequent read marker null because uninstall clears store. Resolved without SDK patch by flutter run process phases above. Original smoke had fixture-only tile under iOS status bar; test-only SafeArea fixed it.

## Original Runner blocker and native lockfile
Original Flutter test -d selectedID fails before app build: Unable to find a destination matching provided destination specifier. Source Debug has EXCLUDED_ARCHS[sdk=iphonesimulator*]=i386 arm64. Diagnostic task-scoped XCODE_XCCONFIG_FILE and FLUTTER_XCODE_EXCLUDED_ARCHS/ARCHS/SUPPORTED_PLATFORMS overrides did not resolve exact destination. Direct generic simulator showBuildSettings returns0 with arm64/x86_64 and empty EXCLUDED_ARCHS, while exact selectedID exits64; selectedID privately verified in showdestinations. No native source workaround applied.
Original flutter pod install added integration_test0.0.1, changed local podspec checksums and CocoaPods receipt1.16.2→1.17.0; existing PODS versions unchanged. Restored tracked ios/Podfile.lock byte-for-byte from HEAD. Evidence /private/tmp/blizzard-podfile.diff, /private/tmp/blizzard-baseline-Podfile.lock and /private/tmp/blizzard-integration-Podfile.lock. Test-only host has its own native pods.

## Expanded pre-UI run
Expanded actual iOS run on unchanged source: 78 PASS, 23 FAIL (101 cases). Fourteen palette, one control shape, one high-contrast response and six source layout overflow assertions are meaningful candidate visual RED. One test-only opener was under the native status bar and did not receive its tap; that fixture is now wrapped in SafeArea and is pending its focused native re-run. It is not counted as visual RED. Known baseline overflows are confined to Home320 enlarged text, D09 and JSON editor toolbar and are separately tracked for eligible presentation geometry. No compiler or plugin prerequisite failures.

The revised runner default uses two Flutter run processes and requires a zero process exit as well as All tests passed; native write/read both passed again. Visual phase seeds write independently because Flutter test uninstalls its host after completion. Existing mock renderer preferences do not provide native persistence proof.

Focused corrected actual iOS run: 6/6 PASS (native smoke, four logs states, modal input focus and closed traversal). Logs error placeholder and baseline empty area now asserted; popup close uses Back with bounded pumps. The under-status-bar test-only opener is fixed. This execution is before production UI edits. Receipt ios-focus-and-logs-baseline.log.
