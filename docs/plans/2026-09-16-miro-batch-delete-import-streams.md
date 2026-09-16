---
title: "fix: Complete Missing-delete, Perf-import, and Arch-streams"
date: 2026-09-16
type: fix
status: ready
origin:
  - "Miro: https://miro.com/app/board/uXjVHcRGjhM=/"
  - "../../../audit-2026-09-14/report.md"
target_repo: maikrais98/hiddify-app
target_branch: checkpoint/mvp-before-dark-theme
---

# Complete the next non-device Miro batch

## Goal Capsule

Implement and verify three independent backlog items that do not require a signed iOS device: explain deletion consequences and keep secret export explicit, bound and measure large profile imports, and make core stream-listener replacement and cleanup deterministic. Update the existing pull request; do not merge it.

## Problem Frame and Scope

The current profile menu uses a generic delete confirmation even when deleting the active profile will interrupt the active connection. Profile expansion already bounds source bytes, expanded bytes, nested URLs, depth, redirects, and time, but it lacks a line/entry bound and synthetic performance evidence. Core stream listeners are replaced by key, but cleanup and error paths are not protected by focused lifecycle tests.

In scope: the three Miro cards, their targeted tests, the existing PR, and Miro status/date updates. Out of scope: signed-device VPN validation, unrelated analyzer debt, the pre-existing Xcode project change, derived-data directories, and artifacts.

## Requirements

- **R1 Missing-delete:** an active profile's delete confirmation states that the connection will stop; inactive deletion stays accurate; cancel and confirm are tested. Export or copy of access secrets remains behind a separate explicit menu action, and secrets do not enter logs.
- **R2 Perf-import:** enforce finite limits for source/expanded bytes, entries or lines, nesting depth, redirects, and wall-clock time. Normal, large, and hostile synthetic fixtures demonstrate bounded behavior and leave no nested temporary files after success or failure. Record elapsed time and a stable process-memory proxy when the platform exposes one without making the test flaky.
- **R3 Arch-streams:** replacing a listener for the same key leaves one live listener; error, explicit cancellation, and service disposal close resources once and remove stale bookkeeping.

## Key Technical Decisions

- **KTD-1:** Keep export/copy as the existing explicit submenu actions. Do not introduce automatic export or reveal secrets in confirmation text.
- **KTD-2:** Put import rejection before expensive downstream parsing, using deterministic count/size checks. Performance assertions use generous ceilings and synthetic input to avoid machine-dependent microbenchmarks.
- **KTD-3:** Own stream subscriptions by key and remove only the subscription instance being closed, so a stale callback cannot delete a newer replacement.
- **KTD-4:** Preserve pre-existing unrelated workspace changes and update the already-open PR for the branch. Never merge in this run.

## Implementation Units

### U1 — Missing-delete

**Files:** `lib/features/profile/widget/profile_tile.dart`, `lib/features/profile/overview/profiles_notifier.dart` for deletion/export behavior and logging coverage, translation sources only if needed, and focused widget/unit tests under `test/features/profile/`.

**Approach:** derive confirmation copy from `profile.active`; state the stop/disconnect consequence only for the active profile. Keep URL/JSON export actions separate. Cover active and inactive copy, cancel, confirm, export isolation, deletion failure, and absence of secrets in logs. In particular, verify the notifier’s existing profile-name log cannot expose a secret-bearing name.

**Satisfies:** R1.

### U2 — Perf-import

**Files:** `lib/features/profile/data/profile_parser.dart`, `lib/core/http_client/profile_download_policy.dart` only if shared constants belong there, and `test/features/profile/data/profile_parser_test.dart`.

**Approach:** add an entry/line ceiling alongside existing byte, nested-URL, depth, redirect, and deadline limits. Add normal, large, and hostile generated fixtures; prove early rejection, cleanup, elapsed-time bounds, and a non-flaky memory observation where supported.

**Satisfies:** R2.

### U3 — Arch-streams

**Files:** `lib/hiddifycore/hiddify_core_service.dart`, `lib/hiddifycore/hiddify_core_service_provider.dart` only if needed to connect cleanup to provider disposal, and a focused test under `test/hiddifycore/`.

**Approach:** make replacement/cancel/error cleanup instance-safe and awaitable where possible. Preserve the intentional prefix cancellation used by `closeFront()` for `fg`/`bg` while keeping replacement scoped to its intended key. Use controllable fake streams to count listen, callbacks, cancellation, overlapping replacements, normal completion, error cleanup, and final disposal. Connect final cleanup to an actual owner lifecycle; the current provider has no disposal hook.

**Satisfies:** R3.

## Verification Contract

Run the focused test files first, then `flutter test`. Run `bash scripts/check_analyzer_ratchet.sh` and `bash test/ci/release_gate_test.sh`. Inspect the final diff for unrelated files and secret material. Commit the three coherent changes, push `checkpoint/mvp-before-dark-theme`, update PR #1, and wait for CI on the exact pushed SHA. Miro moves each card to Complete with start/end `Sep 16, 2026` only after its acceptance checks pass.

## Definition of Done

- R1-R3 are each covered by focused passing tests.
- The full Flutter suite, analyzer ratchet, release gate, and exact-head GitHub Actions run pass.
- Only task-related files and this plan are committed; the pre-existing Xcode/derived-data/artifact changes remain untouched.
- PR #1 contains the pushed changes and updated validation notes, remains open, and is not merged.
- All three Miro cards are Complete with verified dates.

## Work Relationships

The three units are independent and may run in parallel. Integration, review, full-suite verification, shipping, CI observation, and Miro completion happen after all three return.
