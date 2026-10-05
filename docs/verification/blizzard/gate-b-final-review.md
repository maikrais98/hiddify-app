# Independent Gate B remediation review

Verdict: **NOT READY for Gate C under the approved plan; one Important readiness gap remains.** No Critical defect found. Production UI/protected native/runtime code is unchanged in the reviewed remediation diff. This is a read-only review; no tests, simulator actions, commits or repository edits were performed. The expanded actual-iOS run was still pending when this review was written; its result can close execution evidence but does not remove the preparation gap below.

Reviewed `.superpowers/sdd/review-f78b1306..1ae3876b.diff`, relevant current tests/fixtures/scripts, the two remediation reports, coverage-readiness.json, ios-harness.md and plan Global Constraints / sections 4–5. Parent reports baseline 266 PASS, AST 48 files / 651 bindings, Ruby 6 tests / 615 assertions and native separate-process preferences PASS; these were not independently rerun.

## Closed or substantially resolved

- Previous protected-additions hole is closed: repository-wide cached/untracked nonignored inventory rejects new native/workflow files, with narrow exact tool/integration allowances and sensitivity examples. Existing protected-file and dependency checks remain.
- Missing Home/Profile coverage is materially improved: actual Home/ProfileTile/ProfilesModal, bound profile IDs, pending/repeated actions, immediate close and safe late completion, edit/delete/share paths are exercised. Callback-level menu tests accurately stop short of claiming pointer-based submenu usability.
- Actual JSON text editor draft/controller/focus/selection and debounce survive an appearance rebuild; actual redirect forwards encoded import once; actual UpdateProfileNotifier waits then reconnects the active profile. Manual invalid/cancel/close paths characterize the existing continuing-download behavior rather than changing it.
- Six real settings sections now have nonempty row-control hit-size assertions and end-of-scroll checks. Dialogs, About/Intro/Logs/Proxies/profile details and QR have runnable family assertions; modal traversal, numerical contrast and candidate high-contrast/reduced-motion contracts improve the previous vacuous coverage.
- Actual iOS native preference persistence has a separate-process protocol. Isolated template host is explicitly distinguished from shipping Runner and VPN/device proof. No native workaround is slipped into production.

## Important: runnable action/state preparation remains incomplete before production UI

Locations: `docs/verification/blizzard/coverage-readiness.json:1788`, `:1889`, `:1906`, `:1923`, `:1971`; `test/visual/blizzard_surface_coverage_test.dart:183`; `test/ui_preservation/proxy_settings_contract_test.dart:159` and `:213`.

The coverage ledger honestly records app-owned, simulator-testable continuations as `FAMILY_FIXTURE_ONLY_SPECIFIC_TRANSIENT_NOT_FULLY_ASSERTED`, with no physical-only rationale: settings overflow import/export/reset continuation, JSON tree/schema menus, preference-instance modals, Intro region continuation and WARP generation states. Inspection confirms the Settings test only finds ListTiles, the preference loop directly writes raw providers, and the WARP enablement case checks source text. These do not assert that each displayed control opens the correct editor, returns the correct value/cancel result, remains usable under its dependent state, or delivers the intended action from its actual rendered location.

This matters for the planned shared presentation/theme boundary: its restructuring can hide, intercept or remount existing controls while raw-provider tests and preserved AST bindings stay green. Source protection and generic input/picker/slider tests reduce risk, but do not cover those instance-to-action paths. This is the still-open portion of the previous behavioral/visual readiness findings, not a demand for all final screenshots to pass on legacy UI.

The plan explicitly requires every displayed switch/radio/slider/input/reset as separate cases, source transient preparation, and all necessary runnable scenarios before the first production UI edit. Section C consumes Gate B. Deferring exact 89-frame plus 17-transient **screenshot acceptance** to D is correct; deferring these app-runtime fixture/actions until after C is a different exception not granted by the plan.

Fix before declaring B complete: prepare baseline executable, table-driven cases through the real section/menu/editor controls for these identified app-owned continuations (including cancel/disabled/busy/error branches with held external boundaries), with expected storage/result/action bindings. Prepare state-specific layout/action-access assertions for applicable transient variants. Reuse generic renderer/controller tests where equivalent, but document that equivalence per binding/state rather than treating a family mount as its execution. Keep genuinely native camera/VoiceOver/share-sheet/device outcomes on their existing physical protocol; no repair of baseline source bugs is requested.

## Smaller accuracy/quality observations

- `blizzard_surface_coverage_test.dart:76` says logs retain noncolor state in loading/empty/error/data, but empty/error cases assert no specific feedback text/semantics; they can pass when that feedback vanishes. Add state assertions while closing the state-preparation gap.
- `coverage-readiness.json:1831` understates existing proxy longpress proof: proxy_settings_contract_test already sends a real long press and checks the exact outbound passed to ProxyInfoDialog. Link that test when reconciling the ledger.
- ios-harness.md describes visual phase=read, while the current runner uses phase=write for the independent visual run. The separate write/read persistence proof remains valid; refresh the reproduction receipt after the expanded run rather than transferring the old 46/7 numbers.

## Boundaries

No claim here requires physical E or final D screenshots now. Actual-iOS numerical RED remains meaningful only when its failures are the intended appearance/accessibility expectations; harness exceptions must be separated. The known ProfileDetails overflow must remain a named baseline characterization until an authorized visual change removes it. Production C should remain unstarted while the one Important gate-preparation item is open, unless the user explicitly changes the approved gate sequencing.

---

# Focused re-review — remediation through dd0e4cb2

**Updated verdict: Gate B preparation is sufficient to start the constrained section-C work. The previous Important finding is closed; no remaining Critical/Important finding identified in this focused review.** This verdict supersedes the earlier NOT READY verdict above. It is readiness to implement and verify C, not acceptance of the candidate UI or shipping app.

Read-only inspection covered `.superpowers/sdd/review-1ae3876b..dd0e4cb2.diff`, the complete new remaining_surface_actions_contract_test.dart and remaining_surface_fixtures.dart, the worker receipt, revised coverage ledger/equivalence and iOS receipt. No suites rerun or production/repository files changed by reviewer. Parent reports baseline 276 PASS, the 10 new cases PASS with explicit switch off/on, unchanged AST 48 files / 651 bindings and runtime boundary PASS.

## Why the Important finding is closed

- Settings overflow now receives actual pointer/menu selection, import confirmation cancellation/acceptance and exact export privacy arguments. A separate case uses the real ConfigOptionNotifier with platform-boundary spies and verifies clipboard content, persisted port, file picker/save parameters and payload, cancellation preservation and actual reset. This closes the missing continuation rather than only mounting the screen.
- Intro region receives actual picker selection/cancel, checks persisted region and dependent DNS result.
- WARP renders busy/error/generated states through real controls: dependency enablement, null callback while loading, textual missing-config state and exact generation call count are asserted. Using a generation-action spy here is appropriate to preservation of presentation bindings; it does not pretend to test the frozen notifier/core generation implementation.
- General reaches an actual off-screen input, verifies cancel preserves value and scroll position, confirms exact persisted integer, then drives the slider and verifies minute-to-second storage units. Combined with existing choice/toggle/reset/modal tests, six-section inventory/end-scroll checks, individual raw-key contracts and exact binding guards, this supplies a defensible equivalence strategy for repeated generic modal instances. It is not a claim that every instance received a pointer-level test, and duplicating all 61 generic modal permutations is not necessary to close this finding.
- JSON tree add/delete/schema menus now execute and assert the exact changed data and one emission; retained draft is read through the actual editor-switch menu after appearance rebuild. The existing text-controller identity test covers the other editor mode. Baseline UniqueKey child lifetime is explicitly not upgraded into an invented guarantee.
- Logs now asserts the error placeholder and actual baseline empty behavior. Focused real-iOS evidence verifies the corrected SafeArea opener and bounded popup closing, so that harness error is not relabeled as a visual RED.

## Evidence classification and onward conditions

The expanded unchanged-source iOS run has 101 cases: 78 PASS and 23 failures, of which 22 are documented candidate appearance/layout/contrast RED and one was a fixture tap-delivery error. The corrected focused native run has 6/6 PASS including native smoke, all four Logs states and input focus traversal. These are separate receipts; do not report an unexecuted full 101-case green or a rerun count. The older 46/7 result in ios-harness.md is historical and the appended expanded/focused receipts govern current readiness.

Exact 89 mapped frames plus 17 transient screenshot acceptance remains D, as intended. Native permissions, VPN/core behavior, upgrade, device lifecycle/accessibility and shipping Runner remain outside the isolated-host proof. The already documented shipping Runner destination blocker still exists and must be resolved within authorized boundaries when the plan requires that artifact; the working isolated harness is sufficient for B's test environment and numerical RED evidence.

Proceed with C's default-false compile switch, legacy global theme, existing breakpoint/platform eligibility, stable scoped presentation boundary and noninteractive primitives only. Run the prepared targeted tests and guards as that change is made. Preserve observed source bugs and protected controller/router/native/storage paths. Nothing in this review authorizes a broad runtime fix or promotes future D/E acceptance to PASS.

Minor documentation cleanup remains optional: the earlier ios-harness.md paragraph says its opener rerun is pending although a later paragraph records 6/6 PASS; consolidate historical/current wording when updating the next receipt. This is not a gate blocker.
