# iOS VPN audit and regression verification — 2026-10-02

## Scope and release identity

The user reports that the failing installed TestFlight release is **0.0.1 (2)**.
Historical release logs select source `c8341f31a80bf5fb835eb5063b093892e705a241` in
[upload run 35268587029](https://github.com/maikrais98/hiddify-app/actions/runs/35268587029).
[Resume run 35271924241](https://github.com/maikrais98/hiddify-app/actions/runs/35271924241)
records `VALID` and `IN_BETA_TESTING`. Neither log independently identifies the
bytes currently installed on the phone.

This fix starts from canonical `main` at
`e40d2dd6da2626ca752e1a5b508fbed92416fb8f`, after the GitHub branch audit. Seven
old remote branches were already ancestors; the remaining historical documentation
branch was incorporated with a history-only merge preserving main's tree. Eight
obsolete remote branches were removed after an all-refs backup. The user's dirty
primary checkout was preserved. The diagnostic branch's unrelated commits are not
part of this change.

The screenshot establishes `NEVPNErrorDomain: 4`. The installed Apple SDK maps
this to configuration stale. Controlled preference tests reproduce overlapping
saves in the source, but their revision rule generates the stale error itself.
**The cause of the installed TestFlight failure remains unconfirmed on-device.**
The two screenshots also do not establish that both dialogs belong to one attempt.

## Confirmed source findings and fixes

| Priority | Trigger and source | Result and fix |
| --- | --- | --- |
| P0 | `VPNManager.disconnect` returned before its preference save; another setup/start or reset could run meanwhile | Serialize setup/start/stop/reset preference transactions; await save and return its domain/code through MethodHandler. Stop the tunnel even if save fails, and preserve the in-memory on-demand setting for an explicit retry. |
| P0 | Reset used published status, which can be stale after loading an existing tunnel | Wait for the actual connection to stop before removing preferences. |
| P1 | Profile remote/offline operations returned lazy TaskEither inside synchronous finally | Cleanup now surrounds execution of the task, including success, failure, and cancellation. |
| P1 | Validation promoted a final config before DAO persistence; later failure left an orphan or replaced the previous config | All three import/update seams back up an existing file, restore it on failure, and remove a new orphan. Preserve typed cancellation/validation failures. A failed backup preparation never deletes the original; failed restoration retains the recovery file. |
| P1 | Unblocker options read `extraSecurityMode` | Read the independent unblocker mode; retain per-profile overrides. |
| P1 | Restart swallowed unavailable/HTTP2/deadline RPC failures and returned success | Return failure for every GrpcError with a safe numeric code. An accepted delayed command remains acceptance, not tunnel-readiness proof. |
| P1 | Native preference/privacy tests were absent from iOS release gates | Run all three Swift scripts before unsigned iOS and TestFlight builds. |

## Tests written before production changes

The initial complete production VPNManager test harness observed 9 PASS / 7 FAIL
across 16 scenarios. Settings observed 1 PASS / 3 FAIL. Profile cleanup/rollback
observed 3 PASS / 19 FAIL across 22 scenarios. RPC, platform-error, and release-gate
tests also reproduced their targeted failures before the corresponding changes.
Additional tests first reproduced typed-error loss, failed backup preparation,
retention of a recovery backup, safe RPC messages, and reset with stale published
status before those cases were corrected.

| Check | Result | Real components and limits |
| --- | --- | --- |
| Full `flutter test --no-pub` | PASS — 575 tests | Flutter tests under `test/`; does not automatically run integration, shell, Swift, or device checks. |
| `scripts/check_analyzer_ratchet.sh` | PASS — 224 existing signatures | Whole-project analysis matches the versioned baseline; baseline was not relaxed. |
| Profile regression + existing DAO/mapper tests | PASS — 30 tests | Real repository, temporary filesystem, in-memory Drift; parser/network and core validation boundary are controlled. |
| Settings regression | PASS — 4 tests | Real provider container, preferences, and full option serialization. |
| Connection regression + repository tests | PASS — 24 tests | Real service/repository and MethodChannel transport seam; controlled native/RPC responses. |
| `native_vpn_preferences_test.sh` | PASS — 17 scenarios | Complete production VPNManager, real Foundation/Combine; fake NetworkExtension preference revisions and status delivery. |
| Native failure-store and extension log privacy scripts | PASS | Existing Swift checks; excludes real app/extension IPC. |
| TestFlight build contract | PASS — 7 tests, 18 assertions | Ruby release-selection contract, not an upload. |
| Release-gate script | PASS | Includes expected failing negative controls. |
| Core Go local-auth/hcore tests | PASS | Pinned patched source, Go 1.25.6; no device tunnel. |
| Packaged-core source contract and provenance | PASS | Core `f2034de7`, sing-box `170d8315`, existing patch and source-tree hashes; both framework slice hashes match manifest. |
| Packaged-core iOS Simulator integration | PASS — 1 test | Built and installed app on existing iPhone 17 Pro Simulator, iOS 26.5. Real packaged core, pinned TLS/bearer lifecycle, rejected wrong/old credentials and stale TLS pin, released control port. Simulator was shut down afterward. |
| Signed iPhone / TestFlight 0.0.1 (2) traffic | BLOCKED | No fresh physical acceptance or installed-byte verification in this run. |

Local logs are retained under `/private/tmp/wir-vpn-fix-20261002` and
`/private/tmp/wir-audit-20261002`; these are local verification evidence, not public
release artifacts. No TestFlight upload, phone installation, server change, or
kernel/framework replacement was performed.

## Remaining test tasks and release gates

1. **P0 — notifier/dialog lifecycle:** use the complete UI attempt lifecycle to
   test start error plus late status, retry B plus late error A, and double tap.
   The attempted fixture did not establish a working lifecycle and was excluded
   from the suite. Existing lower-level passing tests do not prove a single dialog
   per attempt. Add a test before any notifier/protocol change.
2. **P0 — import through the actual validator:** synthetic subscription → real
   repository/Drift → generated file → packaged core validator. Current profile
   tests control validation; the simulator auth test does not validate a VPN profile.
3. **P0 — physical acceptance of the exact candidate:** record version/build,
   app/core provenance and signing; reproduce the original error before resetting
   configuration. Then five connect/disconnect cycles with controlled TCP/UDP,
   selected egress, DNS A/AAAA, and IPv4/IPv6 according to the profile routes.
4. **P1 — device lifecycle and negative paths:** denied permission, invalid profile,
   unavailable server, timeout, Wi-Fi ↔ cellular, two-minute lock and background
   return. System state, UI and measured traffic must agree.
5. **P1 — import interruption:** test process death between file promotion and DB
   persistence, recovery of retained backups, and concurrent updates to one profile.
   The current rollback covers in-process failures; it is not a crash journal.
6. **P1 — native system failure duration:** reset still relies on system status
   notification when stopping an active tunnel. Measure stalled stop/save/load paths
   on-device before introducing a timeout policy.

All candidate tests and native gates must pass on the final source. Simulator,
unsigned build, upload and a “Connected” label cannot substitute for the physical
traffic acceptance above. Sentry/release policy and unrelated Android failures
remain outside this fix.
