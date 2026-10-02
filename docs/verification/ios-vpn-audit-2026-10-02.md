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
| P1 | Reset waited forever when an active connection never stopped, blocking queued operations | Poll actual connection status with an iOS 15.5-compatible five-second monotonic deadline. Return `VPNPreferencesErrorDomain/1` without removing active preferences. |
| P2 | Temporary-file existence/deletion errors escaped the typed result or masked the primary failure | Return typed cleanup failure after success; retain an existing Left or thrown parser failure. Log a fixed safe message. |
| P2 | Overlapping profile transactions shared temp/final paths; rollback overwrote another committed update | Serialize normalized-URL lookup and full per-ID transactions through cleanup, including offline updates and deletion. Different IDs remain independent. |
| P1 | A waiting update recreated a profile deleted after its initial lookup | Return typed not-found if an existing row disappears under the ID guard. Explicit reimport after completed deletion can create a fresh identity. |
| P1 | Known late error A replaced retry B or an already-handled failure; start returned during dialog handling | Preserve known operation IDs and latest/handled attempt identity. Keep current tunnel failures and uncorrelated failures visible; await failed-start handling and set terminal state before the dialog. |
| P1 | gRPC start failure left core state/late subscribers at Starting | Publish correlated internal Stopped before returning Left. No operation identity is invented for protobuf events. |

## Tests written before production changes

The initial complete production VPNManager test harness observed 9 PASS / 7 FAIL
across 16 scenarios. Settings observed 1 PASS / 3 FAIL. Profile cleanup/rollback
observed 3 PASS / 19 FAIL across 22 scenarios. RPC, platform-error, and release-gate
tests also reproduced their targeted failures before the corresponding changes.
Additional tests first reproduced typed-error loss, failed backup preparation,
retention of a recovery backup, safe RPC messages, and reset with stale published
status before those cases were corrected.
The final review also reproduced repeated execution of one local-import task:
its eagerly captured UUID made the second insert fail. UUID allocation now runs
inside each lazy execution; the two-execution regression passed after the fix.

| Check | Result | Real components and limits |
| --- | --- | --- |
| Full `flutter test --no-pub` | PASS — 602 tests | Flutter tests under `test/`; does not automatically run integration, shell, Swift, or device checks. |
| `scripts/check_analyzer_ratchet.sh` | PASS — 224 existing signatures | Whole-project analysis matches the versioned baseline; baseline was not relaxed. |
| Profile cleanup/rollback/concurrency regression | PASS — 39 tests | Real repository, temporary filesystem, in-memory Drift; parser/network and core validation boundary are controlled. Existing DAO/mapper tests also pass in the full suite. |
| Settings regression | PASS — 4 tests | Real provider container, preferences, and full option serialization. |
| Connection/core regressions | PASS | Real service/repository and MethodChannel transport seam; controlled native/RPC responses. Includes correlated terminal publication after gRPC failure. |
| Additional notifier attempt lifecycle | PASS — 10 tests | Real notifier and repository status mapping; controlled start/core-status/dialog boundaries. Old/current/uncorrelated errors, failure after Connected, double tap and pending dialog. |
| `native_vpn_preferences_test.sh` | PASS — 18 scenarios | Complete production VPNManager, real Foundation/Combine; fake NetworkExtension preference revisions/status delivery, including a stalled stop. |
| Native failure-store and extension log privacy scripts | PASS | Existing Swift checks; excludes real app/extension IPC. |
| TestFlight build contract | PASS — 7 tests, 18 assertions | Ruby release-selection contract, not an upload. |
| Release-gate script | PASS | Includes expected failing negative controls. |
| Core Go local-auth/hcore tests | PASS — initial verification | Pinned patched source, Go 1.25.6; core source/patch unchanged in this follow-up. No device tunnel. |
| Packaged-core source contract and provenance | PASS | Core `f2034de7`, sing-box `170d8315`, existing patch and source-tree hashes; both framework slice hashes match manifest. |
| Packaged-core iOS Simulator integration | PASS — 2 tests | Existing iPhone 17 Pro Simulator, iOS 26.5. Real packaged TLS/bearer lifecycle and parser/repository/Drift/config generation/validator. Invalid update retains previous profile/file. RPC and cleanup steps bounded; simulator shut down afterward. |
| Final unsigned iOS release build | PASS | `flutter build ios --release --no-codesign --no-pub --target lib/main_prod.dart`; real iOS SDK, Runner and Packet Tunnel compile. No signing, phone installation or upload. |
| Signed iPhone / TestFlight 0.0.1 (2) traffic | BLOCKED | No fresh physical acceptance or installed-byte verification in this run. |

Local logs are retained under `/private/tmp/wir-vpn-fix-20261002`,
`/private/tmp/wir-audit-20261002`, and `/private/tmp/wir-pr7-followup`; these are local verification evidence, not public
release artifacts. No TestFlight upload, phone installation, server change, or
kernel/framework replacement was performed.

## Remaining test tasks and release gates

### Follow-up regression evidence

The user authorized the remaining source fixes, with all necessary tests written
before production changes. The held-stop native regression observed 17 PASS / 1
FAIL: reset exceeded the six-second test watchdog and blocked queued setup. The
required result is a five-second reset deadline with safe error domain
`VPNPreferencesErrorDomain`, code `1`, while retaining active preferences.
Profile regressions observed 26 PASS / 11 FAIL, including filesystem cleanup
faults, overlapping remote/offline updates, simultaneous first imports of a
normalized URL, cleanup ownership, and deletion during rollback.
The deletion-first review case separately observed 38 PASS / 1 FAIL before its
guard was added. An explicit import after completed deletion remains supported.
Notifier lifecycle tests observed 5 PASS / 2 FAIL through the real repository's
status mapping: attempt A's correlated late error replaced retry B's connecting
state, and failed-start dialog handling was detached from the returned Future.
Positive controls retain matching and uncorrelated failures, including a failure
after the current tunnel reaches Connected. Pending starts permit only one call.
All these tests and the packaged check below ran before follow-up source edits.
Subsequent review regressions first reproduced the loss of an already-handled
attempt error, replayed Starting after gRPC failure, and incorrect retirement of
an uncorrelated event before their corresponding fixes. A native-router identity
assertion was also added during final verification.

Before follow-up production edits, the expanded packaged-core integration
observed **2 PASS** on the existing iPhone 17 Pro Simulator (iOS 26.5). The new
test uses the real parser, repository, in-memory Drift, filesystem, option
serialization, service, authenticated RPC, and packaged validator. HTTP input is
fixed; provider state is isolated and bootstrap uses the simulator core bridge
rather than shipping OS setup. Valid synthetic Shadowsocks input is
persisted and read back through the real generation path; an unsupported
outbound is rejected without changing the prior profile/file. This does not
exercise a Packet Tunnel, DNS/route readiness, or traffic through a server.
The simulator integration requires its explicit driver and is not included in
the ordinary Flutter unit-test CI job. Follow-up logs:
`/private/tmp/wir-pr7-followup`.

The initial review's three open source findings (reset queue starvation, cleanup
exception, overlapping rollback) are resolved by the follow-up regressions and
fixes above. The bounded reset uses polling rather than racing a potentially
non-cancellable `AsyncPublisher.values` task; active preferences remain intact.

The user subsequently restricted builds to iOS. A workflow contract first failed
against enabled non-iOS matrices and Linux-specific test preparation. Unsigned
and legacy signed non-iOS matrices and the tag-release caller are now disabled;
the test job uses common preparation without downloading Linux platform binaries.
Flutter/core/native gates and the explicit iOS/TestFlight paths remain enabled.
The previous all-platform CI run was cancelled and replaced with this policy.

### Authorized TestFlight delivery preparation

Live GitHub inspection on 2026-10-02 confirmed that both protected release
environments have App Store credential secret names and require the repository
owner's review on the `main` workflow branch. `release-publish` selects the
configured group `Internal QA`. Neither environment has
`RELEASE_ENVIRONMENT_READY`; neither the repository nor `release-signing` has
the `SENTRY_DSN` required by the current diagnostic upload workflow.

Four readiness contract tests first failed before any workflow change. Each
credential-bearing job now checks the environment readiness flag as its first
step. The tests execute the actual YAML shell command for unset, empty, false,
and true values. All 12 release-contract tests, the 224-signature analyzer
ratchet, and the 7-test/18-assertion build-selection contract pass locally.
Independent review found no material guard issue.

Delivery is blocked pending readiness configuration and the user's Sentry-mode
decision. No new signed archive or upload was produced, no TestFlight build
number was selected from Apple, and no tester/group change was made. The next
selection must query Apple live and honor minimum build 3 for version 0.0.1;
historical build-number selection is not a reservation.

Review run: `20261002-202106-e95e2e79`; local report directory:
`/tmp/compound-engineering-501/ce-code-review/20261002-202106-e95e2e79`.

1. **P0 — physical acceptance of the exact candidate:** record version/build,
   app/core provenance and signing; reproduce the original error before resetting
   configuration. Then five connect/disconnect cycles with controlled TCP/UDP,
   selected egress, DNS A/AAAA, and IPv4/IPv6 according to the profile routes.
2. **P1 — device lifecycle and negative paths:** denied permission, invalid profile,
   unavailable server, timeout, Wi-Fi ↔ cellular, two-minute lock and background
   return. System state, UI and measured traffic must agree.
3. **P1 — import interruption:** test process death between file promotion and DB
   persistence and recovery of retained backups. Current transaction serialization
   and rollback cover in-process failures; they are not a crash journal. Test
   distinct per-profile overrides against the core's shared option state.
4. **P1 — native system failure duration:** measure stop/save/load stalls on-device.
   The reset terminal-status wait is bounded; system preference callbacks are not.
5. **P1 — legacy status correlation:** uncorrelated gRPC events remain accepted
   for compatibility because the protobuf has no attempt ID. Known-ID regression
   guarantees do not establish the origin/order of uncorrelated device events.
6. **Before each TestFlight candidate:** run the Flutter/analyzer/native gates,
   then the explicit packaged-core simulator driver against the built framework
   and its provenance manifest, followed by physical traffic acceptance. The
   simulator driver is not part of the ordinary Flutter CI test job.

All candidate tests and native gates must pass on the final source. Simulator,
unsigned build, upload and a “Connected” label cannot substitute for the physical
traffic acceptance above. Sentry/release policy and unrelated Android failures
remain outside this fix.
