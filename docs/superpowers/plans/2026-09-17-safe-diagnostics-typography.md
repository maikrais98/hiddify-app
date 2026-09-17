# Safe Diagnostics Typography Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the runtime safe-diagnostics screen with the dark Pencil intent without admitting raw logs or bundling Inter.

**Architecture:** Keep `SafeDiagnosticSummary` and `SafeDiagnosticExport` unchanged as the privacy boundary. Restyle only `SafeDiagnosticsPage`, inherit the application font, use the platform monospace fallback for the exact JSON preview, and document the matching Pencil correction without editing `.pen`.

**Tech Stack:** Flutter 3.38.5, Material 3, Nova theme tokens, Flutter widget tests.

## Global Constraints

- Never read raw logs, URLs, identifiers, tokens, configuration, provider values, error text, or secrets into Safe diagnostics.
- Do not add a font binary without its license and provenance.
- Do not edit pen.dev or any Pencil state other than specifying the correction for `KIFo1`.

---

### Task 1: Lock the privacy and typography boundary

**Files:**
- Modify: `test/security/safe_diagnostics_test.dart`

**Interfaces:**
- Consumes: `SafeDiagnosticsPage`, `SafeDiagnosticSummary.capture`, `AppLocale.preferredFontFamily`.
- Produces: regression coverage for the safe UI and system-font decision.

- [x] Add a widget test that requires `diagnostic-summary-card` and `diagnostic-preview-card`, rejects log controls/content, and checks the title does not request Inter.
- [x] Add a source-boundary test rejecting `features/log` imports from `features/diagnostics`.
- [x] Add locale assertions proving Russian and English select the system font.
- [x] Run the focused test and observe failure on the missing structured-card keys and truthful cleanup copy.

### Task 2: Implement the safe visual reconciliation

**Files:**
- Modify: `lib/features/diagnostics/safe_diagnostics_page.dart`
- Modify: `docs/safe-diagnostics.md`
- Create: `docs/release/pen-diagnostics-typography-reconciliation.md`

**Interfaces:**
- Consumes: `SafeDiagnosticSummary.json`, `SafeDiagnosticExport.create`, `SafeDiagnosticExport.share`, `NovaThemeData`.
- Produces: a dark structured-summary page whose preview bytes remain the export bytes.

- [x] Build a Nova summary card showing only translated category, stage, and the explicit reachability limitation.
- [x] Put the exact JSON preview in a bordered code surface using generic `monospace` rather than a bundled font.
- [x] Scope privacy copy to this report and describe cleanup as best-effort.
- [x] Preserve separate Create and Share actions and all closed result messages.
- [x] Run the full focused test file, analyzer on changed Dart files, and `git diff --check`.
- [x] Review the final diff for raw data ingress, generated files, binaries, and out-of-scope edits, then commit.
