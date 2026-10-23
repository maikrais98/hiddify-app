# Release readiness — native acceptance pending

Source candidate: `dec72444026886d2338edb14818628f5d14c78fa` on `fix/aurora-recovery-release`. All three requested code changes are present. Original build24 checkout is preserved. Supplemental tests and evidence do not change the47 captured production/integration inputs.

## Verified

- Connection/budget117 tests, native XCTest16, action bindings81, source boundary45tests/1314assertions, capture contracts39passed. Final full Flutter run including55new state/context tests:972passed,5skipped.
- Analyzer candidate:0errors and33preexisting warnings, no newwarning. Final complete analyzer:0errors,33warnings equal to baseline.
- Exact-source no-VPN iOS26.5 capture completed. Independent limited review:10PNG,12sampled video frames,2controlled-opticsPNG. All72unique SF Symbols decoded via native channel.
- Registry:114/115 rows have widget/shared-context or simulator evidence. The static menu board is resolved as4owners, not one app route. One OS-only row remains unverified. Camera mock composition is not a live camera session.
- Free Better Stack:3GB/month and3-day retention; measured109.55kB last30days. Budget5MiB/day/install does not itself require a paidplan.

## Open native gates

- Real OS Reduce Transparency visual verification (`b2r9G`); highcontrast and ReduceMotion are different settings. Native callbacks/fallback source exists, but the OS setting has not been enabled and observed.
- Native touch/hit-testing, VoiceOver, dynamic type/RTL and device acceptance. Current enabled tools provide simulator screenshots/inspection but no native tap control; CUA native APIs are disabled. A physical iPhone or enabled native UI automation/manual observation is needed for these claims.
- Real foreground/lock/unlock/connect/reconnect and traffic/manualOFF acceptance. The upstream stale-registry defect remains source-confirmed; a persistent native failure has not been reproduced after the minimal patch, and no core binary fix is claimed.
- Final release-controller source/native/design/visual pins must be prepared only after acceptance. Live main still pins build24. Its shallow source job must also fetch exact521274baseline for the new guard. Query fresh ASC inventory for a free build; preserve0.0.1 and existing Test group; do not assume25. No signing/upload/workflow/release mutations were performed.

## Explicit design/source reconciliation

- `fRoyp`: the specimen's Error/Retry text is absent from the baseline. Current source preserves blank status + Connect. R7 requires preserving functions/text; no new error UI was invented. Real context and existing action are tested.
- `U1dZz`: baseline hides profile/server footer when disconnected with no profile. Its source-reachable composition is tested; the specimen's server card is not added under a cosmetic change.
- `ocbyB`: live Pencil explicitly calls this a static menu specimen board for R05/R03/S02/R13. Each menu owner is tested separately. `W7Ainm` is About → Add to clipboard, verified against appInfo.format().

## Separate pre-existing issue found

`lib/features/profile/details/profile_details_page.dart`: the non-JSON text field has neither an initialValue nor a controller seeded from stored configContent. Verified in both521274baseline and candidate. This patch does not change that behavior. Draft entry and production setContent remain tested; initial stored-text display needs a separate fix. Do not claim pixel parity for stored text based on an empty editor.

This is a reviewable source candidate, not delivered TestFlight or physical VPN proof. Delivery requires exact version/build, AppleVALID, existingTest assignment and beta-ready state. Native/device acceptance remains separate.
