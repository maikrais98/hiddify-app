# Final task-created test analyzer cleanup

Source FROZEN. Edited11 task-created test files only (listed in `/private/tmp/analyzer-test-files.json`). No production, dependency/lock, native, index, commit, integration-entry or parent-owned home/visual fixture changes. Original `test/drift/db/migration_test.dart` untouched.

## Repairs

- Heterogeneous61-setting loop now stores original `.notifier` selections as `ProviderListenable<PreferencesNotifier<Object?, Object?>>`; typed `c.read(provider)` removes3 strict errors and dynamic dispatch infos. All61 provider identities/keys/defaults match pre-edit snapshot; raw-write, fresh-container, persistence and reset assertions preserved.
- Sorted import blocks in listed task-created tests, added const only to diagnosed fixed import-form wrappers, removed two unnecessary raw prefixes, equivalent WARP regex interpolation.
- Async preference override functions now return Future.value, retaining asynchronous fixture result shape. TearDown directly returns original disposal Future.
- Exact AST receipt now uses stdout.writeln rather than print. Three individual analyzer-import lint ignores explain pinned transitive analyzer/frozen dependency boundary; no dependency edits. Single expression-local groupValue deprecation ignore documents intentional characterization of shipped legacy SDK API. No file-wide disables.

## Verification

- Focused analyze11files: **No issues found** (`/private/tmp/blizzard-test-analyzer-focus.log`).
- Full analyze: **440 → 369**, normalized diagnostics **71 removed / 0 added** (`/private/tmp/blizzard-test-analyzer-after-full.log`). All remaining test diagnostics consist solely of unchanged drift import-order info. Earlier quick substring count74 was imprecise: diagnostic-location parsing confirms72 test diagnostics including drift1; task-created cleanup removed71. Parent reconciles remaining369 with older366 baseline; no unrelated file was changed to force a total.
- Every expect/expectLater/test/testWidgets call count identical in all11files; all61 preference case tuples identical except deliberate `.notifier` selection. Receipt `/private/tmp/blizzard-test-assertion-counts.json`; original files snapshot `/private/tmp/blizzard-test-analyzer-before`.
- `git diff --check` PASS. Diff for lib/, pubspec/lock, test/drift and excluded home/visual fixtures empty at freeze.
- Parent host full relevant UI/visual and AST regression requested, result pending at report creation. Existing assertions were not removed; native exact-source followup/default activation remains parent-owned.
