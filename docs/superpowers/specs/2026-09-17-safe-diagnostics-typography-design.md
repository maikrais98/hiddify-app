# Safe diagnostics typography design

## Scope

Reconcile Pencil state `KIFo1` (`23 · Безопасная диагностика`) with the shipped safe-diagnostics contract. Do not edit the `.pen` document in this change, do not change neighbouring screens, and do not add a font binary.

## Decision

The runtime safe screen remains a separate route from raw Logs. It uses the existing closed `SafeDiagnosticSummary` schema, previews the complete JSON, creates a temporary file only after an explicit action, and shares only after a second explicit action.

The Pencil log rows, search/filter controls, pause/export affordances, and bottom dock are not implementable inside Safe diagnostics without creating a false privacy guarantee. They must be replaced in Pencil by the runtime summary card, scoped privacy copy, JSON preview, and Create/Share states described in `docs/release/pen-diagnostics-typography-reconciliation.md`.

Human-readable text inherits the locale/platform theme. The JSON preview uses the platform monospace fallback. Inter and JetBrains Mono are not bundled; there is therefore no new font license or binary provenance to maintain.

## Verification contract

- Diagnostics sources do not import raw-log features.
- The safe page has no log search, filter, severity list, pause, clear, or raw-log share control.
- Hostile failure payloads remain absent from state, preview, file, logging, breadcrumbs, and native share payloads.
- Copy says "this report" rather than claiming the whole app never collects logs.
- Cleanup copy states that the app attempts deletion and cannot delete copies the user saves or shares.
