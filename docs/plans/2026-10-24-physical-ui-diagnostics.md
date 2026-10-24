# Blizzard: UI patch and diagnostics integration — release candidate status

Updated 24 October 2026. Checkout: `/Users/stasyudkin/Documents/KVN/blizzard-physical-ui`, branch `fix/aurora-physical-ui`, base `b37b073eef2be19f2534443469c4fd22e7238463`. This document describes the patch candidate; the exact committed source and delivery result belong to the new release receipts. Existing build25 evidence remains separate.

## Intended result and sources

Fix the reported opaque Aurora rectangle, barely perceptible motion, missing glass on navigation controls, grouped General settings and occluded primary control. Preserve existing settings, actions, order, manual OFF and reconnect policy. Integrate the explicitly approved neighboring-chat diagnostics handoff using the current journal, bridge and sender.

Sources: four user photos, live pen.dev Kf5tC / Xdkgz / A7GOi inventory from the preceding investigation, user confirmation that Reduce Motion is OFF, and `/Users/stasyudkin/Documents/KVN/docs/2026-10-24-diagnostics-integration-handoff.md`. The minimal implementation contract is `2026-10-24-diagnostics-minimal-contract.md` in this folder.

## Implemented; current patch verification in progress

- [x] Aurora shader emits transparent premultiplied light with feathered bounds instead of an opaque rectangular sky. Existing background remains continuous; the existing sixteen stars also drift and twinkle through the same shader clock.
- [x] The existing 12-second animation cycle has a larger phase amplitude. Increase Contrast no longer silently enables Reduce Motion. Explicit motion accessibility settings still stop decoration.
- [x] Animated fullscreen snowfall and the existing local envelope. Both reuse the current scene clock, shader and route/lifecycle events; root modals pause both clocks, and offstage Home stops decoration. Pixel-motion tests cover both presets. No new animation engine.
- [x] Home header reuses the original BlizzardGlass, IconButton and BlizzardSystemSymbol. The existing native UIGlassEffect material, connection lens and dock are retained. The extra native header bridge was removed; real Flutter taps, labels, 48-point targets, RTL and modal barriers are tested.
- [x] Existing BlizzardGlass reused for Settings overflow, Profiles sort/update and Servers back/sort anchors. A shared pure leading helper covers General, Route, DNS, Inbound, TLS and WARP back controls. Content lists/forms keep their dense surfaces. Menu contents and transitions remain the existing widgets; this does not claim every app route uses a native UIKit menu.
- [x] General reuses the existing grouped settings container with three groups. Original preference order is restored: memory, debug mode, logging, connection URL, interval, API port and Xray. An order regression failed before the change and passes afterward; the bottom-inset check is retained. No replacement dock-height constant.
- [x] Primary lens stays visible below a root sheet while interaction and accessibility are blocked. Background/tab hiding and fresh route checks remain. Native RED then 5 control XCTest GREEN.
- [x] Shared server subtitle helper omits the repeated display name, retaining a distinct selected server and protocol.
- [x] Subscription import/update phases, Dio outcome/status/selected mode/observed retry, nested aggregate, validation-and-commit, DB persistence, reconnect decision/result and parent attempt correlation.
- [x] Native six statuses before UI collapse, own-connection identity gate, preferences, stop reason, settings/TUN fact, sleep/wake and guarded last-disconnect error. Previous structured history survives reconnect.
- [x] Non-destructive native read; existing outbox persists imported event and cursor together before sending. Failed writes, missing writer, capacity, restart and retry tested. Local assigned sequence survives handoff retry. History gaps/rotation/storage failure are explicit.
- [x] Exact two-source OFF boundary persists before enabling analytics, resumes after crash without advancing to a newer baseline, and is strictly validated. Disable boundary persists before teardown; individual failed writes remain fail-closed. Total storage failure stops current-process delivery and reports failure; it cannot guarantee persistence after process death.
- [x] Failed native writes discard the uncommitted payload and restore the prior sequence, so OFF observations cannot flush after a later consent baseline. Bounded loss counters and a categorical marker in the existing shared UserDefaults expose the failure. Marker clears only after the journal persists its failure flag. RED reproduced the leak; GREEN covers recovery, bridge, restart and contiguous records.
- [x] Existing sender and 5 MiB/UTC-day budget retained. No second transport, monitor, probe, packet capture, core replacement or capacity increase.

## Verification

Current checks are marked below. Earlier frozen snapshots are preserved; they do not establish the final animated patch build. New evidence is collected under `physical-ui-patch-02`.

| Check | Result and practical limit |
|---|---|
| Complete Flutter application tests, no dependency resolution | Current: 1064 passed, 5 skipped, exit 0; reduced count follows removal of the extra native header layer |
| Combined UI/connection/diagnostics regression | Previous candidate: 925 passed, 5 skipped; current full suite above supersedes it |
| Strict presentation binding / Home actions | Current header simplification regression: 113 passed, with real taps and callback mutation rejection; baseline unchanged |
| Independent final consent/importer review | No actionable findings; 23 focused tests passed; 4 production/test files analyze clean |
| Runner and PacketTunnel compilation | Current: both succeeded with the official pinned HiddifyCore v4.1.0, signing disabled; eight source files byte-matched QA before and after builds |
| Native privacy / VPN manual policy / extension source contract | Current: passed; foreground mode harness passed; synthetic tests do not establish physical traffic |
| Native control XCTest | 5 passed after a confirmed RED; earlier full native suite 21 passed |
| Historical UI snapshot03 | 10 screenshots, 2 videos, capture exit0, frozen snapshot unchanged, no semantics leak; synthetic data and programmatic header callbacks |
| Actual shell / animation integration | Current: General and transition samples passed; shader-loaded check measures changing top/bottom pixels over 600 ms, and verifies root-modal/tab clock gates. Simulator only |
| Exact telemetry CI analysis scope | Current: exact strict command passes with No issues found; the three syntax-only lint corrections are included |
| Working diff / dependencies | diff check clean; pubspec.lock unchanged; no codegen or package updates |

The three previously identified analysis findings were corrected within the approved update: braces in `telemetry_transport_attempt.dart` and two const exception fixtures in `better_stack_outbox_test.dart`. Relevant telemetry tests: 47 passed. No delivery or diagnostic behavior changed.

Native storage visibility limit: shared UserDefaults is best-effort, and immediate cross-process visibility cannot be guaranteed if both shared storage paths fail. The failed payload is never retried. A known source storage failure remains fail-closed for new analytics baselines until explicit source recovery; exact loss count across writer crash is unavailable.

Native capacity examples: a synthetic normal episode used 12/128 records and 2421/65536 bytes; failure episode 5/128 and 1169/65536. Saturation retained a bounded suffix and exposed dropped_count=77. This is not a guarantee that every real-world episode fits.

## Performance and remaining acceptance

- [x] Debug simulator FrameTiming measured separately for cold/warm Home→Settings and root-sheet opening. Counters use build and raster durations separately, not totalSpan as missed frames.
- [ ] Physical iPhone profile measurement and acceptance of menu/page smoothness. The simulator still has expensive raster frames: latest p95 approximately 29–33 ms for Home→Settings and 53–81 ms for the root sheet. These debug/simulator samples are not a controlled device benchmark and do not prove the reported jank is fixed.
- [ ] Physical native touch, VoiceOver, Reduce Transparency/Motion, Increase Contrast and long real data acceptance.
- [ ] Physical VPN traffic and reconnect episode acceptance, separate from Connected/RPC/ping/status.

The reported motion setting being OFF rules out that switch as the explanation. It does not establish the cause of every physical dropped frame. Do not replace this gate with a successful build or a video from the simulator.

## Release sequence

1. Finish the approved animated patch, remove the extra header layer, restore preference order and retain the approved diagnostics. Run targeted tests before and after behavioral changes.
2. Run the full application tests and exact telemetry CI analysis, native privacy/manual-policy/release contracts and unsigned Runner/PacketTunnel compilation. Freeze a new source snapshot and native input hashes. Do not reuse the old candidate receipts as current proof.
3. Capture the final animated UI using the existing simulator harness and obtain an independent visual verdict against the pinned design. Keep physical smoothness, accessibility and VPN acceptance explicitly unverified until observed; a simulator capture cannot close them.
4. Resolve one exact source commit and review it through the existing release controller/source pin/visual receipt process. Query live Apple inventory, retain marketing version 0.0.1 and select the first unused build number. Use the existing protected TestFlight workflow and its current toolchain and readiness gates.
5. Verify the exact Apple build is VALID, assigned to the existing Test group and READY_FOR_BETA_TESTING or IN_BETA_TESTING. Only this is delivery. Preserve source, artifact and workflow provenance, and return protected readiness to its prior state.

User authorization: the 24 October request explicitly asks for the updated patch and a new build with a living animated background. No new signing or upload has occurred at this update. Any failed visual/protected gate remains a real blocker and must be reported, not bypassed.

## Evidence locations

- Main UI evidence: `/Users/stasyudkin/Documents/KVN/review-evidence/2026-10-24/physical-ui-patch-01/` (snapshot03, captures, lens RED/GREEN, integration timing).
- Historical native source/build receipt: `/Users/stasyudkin/Documents/KVN/blizzard-physical-ui/review-evidence/2026-10-24/physical-ui-patch-01/native-integration-final/receipt.md`.
- Historical source and consolidated verification receipt: `candidate-final-source` and `verification-final.json` in the main UI evidence directory, retained unchanged from the preceding candidate.
