# Aurora release implementation evidence

Baseline: `521274b84c55b15027de43bf2d6c28fe85731cb5`. Work is isolated in `blizzard-aurora-release`; the installed build and original source checkout are unchanged.

## Implemented scope

- iOS connect/reconnect reuse `ensureForegroundReady()` before options/start; historical initialization is not treated as current readiness. The exact closed unavailable marker uses the existing core failure. No automatic VPN restart, new recovery manager, or XCFramework patch.
- Remote-log default is 5 × 1024 × 1024 attempted bytes per installation per UTC day. Existing persisted consumption, failures/retries, rollback protection, exception caps, TTL and outbox rules remain.
- Aurora uses one cached immutable FragmentProgram and per-scene disposable shaders. Existing lifecycle/TickerMode/accessibility clocks remain; missing assets use the dark fallback.
- Primary control is one native UIButton in regular interactive UIGlassEffect. Native tab bar remains UITabBar; compact Home actions reuse BlizzardGlass. Applied Aurora is dark, so native materials explicitly use the same appearance even when the OS is light.
- The reviewed 81 symbol mappings (72 unique names) use UIImage(systemName:), a bounded cache, and the previous Flutter Icon when unavailable. Pencil PNGs are not runtime assets.

## Simplification review

Three independent reuse, quality and efficiency passes completed. Applied: existing FlutterPlugin registration pattern; retained shader-backed Paint per painter; removed redundant shader-failure flag and duplicate Swift connection-state storage; immutable native callback. Retained protocol validation and atomic Dart payload. New enum layers and a new generator were not necessary for this patch; the frozen mapping and exact source guard already prevent unreviewed drift. The existing design PNG generator remains a design tool, not a runtime dependency.

## Verification recorded so far

- Repository/recovery/budget regressions: 117 passed after observed RED.
- Scene/native Flutter behavior: 23 passed; symbols/remaining visual contracts: 18 passed.
- AST action-binding guard: 81 passed, including executable-code mutation negatives.
- Native XCTest on iOS 26.5 simulator: 16 passed. The dark-appearance expectation first failed on the old view, then passed after the change.
- Runtime/native/source boundary: 45 tests, 1314 assertions passed. Capture runner: 39 tests passed after review finding #2.
- Native setup-mode, manual OFF and diagnostics privacy scripts passed.
- First full Flutter pass: 900 passed, 5 failed; second: 915 passed, 2 mutation-fixture failures. Both mutation fixtures were subsequently corrected to mutate executable statements rather than historical comments; targeted guard is green. The final full rerun passed: 917 passed, 5 skipped.
- Analyzer baseline: zero errors, 33 existing warnings. Initial candidate: zero errors, those warnings plus one new unused test import, now removed. Final comparison: zero errors and the same 33 existing warnings; no new warning.

## Evidence boundaries

Pilot r2 produced ten native compositor screenshots and two videos, but its primary lens was rejected as too light. That immutable capture is retained. The corrected dark-appearance pilot received an independent limited visual pass for all ten PNGs. Exact-source candidate dec72444026886d2338edb14818628f5d14c78fa capture completed; independent review passed for 10 PNG, 12 sampled video frames and controlled A/B optics. All 72 distinct runtime symbols decoded; this does not close the full115 registry or physical acceptance. Neither synthetic Connected nor native XCTest proves VPN traffic or physical iPhone behavior.

TestFlight source pin, live build inventory, signing/upload, beta-ready states, physical traffic/lifecycle/accessibility and older-iOS runtime acceptance remain separate gates. The upstream stale gRPC registry is a source-confirmed defect and a causal hypothesis for the incident; this patch is not evidence that a persistent native registry failure has been repaired.

## Telemetry volume model

At complete budget consumption for 31 days, one installation attempts 155 MiB (162,529,280 bytes). Five installations: 775 MiB; ten: 1,550 MiB (about 1.63 decimal GB). This is attempted serialized log volume, not measured Better Stack billable ingestion. Live read-only verification with explicit user permission: Free plan, 3 GB logs/month, 3-day retention; last 30 days usage 109.55 kB. See telemetry-volume-review.md. No purchase or setting change was made.


Nineteen additional existing-state widget tests passed with no analyzer issues. Final registry map:114 rows have widget/shared-context evidence, one OS Reduce Transparency row remains unverified. Source-incompatible fRoyp/U1dZz specimens preserve baseline behavior under R7; the static menu board has four independently tested owners. All47 production/integration input digests remain equal to the captured source candidate; supplemental tests/docs do not change the app implementation.


The final supplemental corpus adds55 state/context tests. Full final run and analyzer outcomes are in progress-evidence.json. Native physical interaction and traffic remain open gates; no TestFlight delivery is claimed.


Final complete Flutter result:972passed,5skipped. Final complete analyzer:0errors,33existing warnings, none added. Exact source boundary remains45tests/1314assertions passing.
