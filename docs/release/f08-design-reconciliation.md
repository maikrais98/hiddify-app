# F08 design reconciliation

Date: 2026-09-16

Implementation source: `5c302e7a` (`fix/audit-f08`, fast-forwarded from the integrated remediation branch)

Canvas: `/Users/stasyudkin/.pencil/documents/12d0964c-5822-4806-bfe2-7ef00579dcd9/pencil-welcome-desktop.pen`

## Canonical source and scope

Per KTD6 in the remediation plan, the verified Flutter implementation is canonical. This reconciliation does not change production behavior. It aligns the legacy CSS token bundle and only the four existing Auto Mode canvas states. No neighbouring pen.dev screens or Miro artifacts were changed.

Runtime behavior retained:

- a different Auto Mode candidate opens an `AlertDialog` and changes the server only after confirmation;
- no candidate, unchanged selection, cancellation, URL-test failure and write failure report through `SnackBar` messages;
- a successful change reports through a `SnackBar`;
- the current server remains selected on cancellation or failure.

The canonical implementation is `lib/features/proxy/overview/proxies_overview_page.dart`; the canonical dark tokens are `lib/core/theme/nova_tokens.dart`.

## Token mapping

`nova_tokens.dart` already matched the live `wir-*` canvas variables for backgrounds, surfaces, text hierarchy, accent, status colours, borders and separators. It required no code change. `design/tokens/colors.css` was the stale representation.

| Semantic role | Legacy CSS before | Canonical Flutter / CSS after | Pencil |
|---|---:|---:|---:|
| surface | `#101015` | `#1C1C1E` | `wir-surface` |
| elevated surface | `#16161C` | `#2C2C2E` | `wir-elevated` |
| pressed surface | `#1E1E26` | `#3A3A3C` | `wir-pressed` |
| primary text | `#F2F2F5` | `#F2F2F7` | `wir-text` |
| secondary text | `#9A9AA4` | `#A1A1AA` | `wir-text-2` |
| tertiary text | `#7C7C86` | `#98989F` | `wir-text-3` |
| muted text | `#42424B` | `#48484A` | `wir-muted` |
| text on accent | `#FFFFFF` | `#101015` | new `wir-on-accent` |
| red tint | 10% | 14% | `wir-red-tint` (`#FF2D3E24`) |
| good signal | `#3DD6B0` | `#30D158` | `wir-good` |
| medium signal | `#E9B23C` | `#FF9F0A` | `wir-warn` |

`surface-4` and `sig-slow` have no one-to-one Flutter token, so F08 leaves them unchanged rather than inventing a new mapping.

## Canvas reconciliation

The document had 42 top-level frames before and after the update. No new screen or backup frame was added.

| Screen | Existing frame | Updated representation |
|---|---|---|
| Auto Mode confirmation | `ApdPQ` | `no6Gt` changed from a bottom sheet to the centered runtime confirmation dialog. `DCHnJ` uses `wir-on-accent`; actions reflect Cancel and confirmed selection. The modal scrim remains because the runtime dialog is modal. |
| No candidate | `AaKdu` | `whfQl` changed from a bottom sheet to the runtime Snackbar message. Obsolete modal children and scrim `JlIEZ` are disabled. |
| Selection failure | `Co3OM` | `AxGqL` changed from a retry bottom sheet to the runtime failure Snackbar. Obsolete modal children and scrim `TveRm` are disabled. No unimplemented retry behavior is promised. |
| Success | `ymOCw` | `VHcbN` remains a Snackbar; `DChJx` now uses the shipped message form and the non-runtime success icon is disabled. |

Before and after exports are stored outside Git under:

- `/Users/stasyudkin/Documents/KVN/.audit-remediation/F08/before/`
- `/Users/stasyudkin/Documents/KVN/.audit-remediation/F08/after/`

The property-level rollback snapshot is `/Users/stasyudkin/Documents/KVN/.audit-remediation/F08/canvas-before.md`.

## Verification

- A pre-change token check failed on all 11 mapped CSS values.
- The same check passed after the edit: `TOKEN_PARITY_OK 11`.
- Pencil post-write readback confirmed frames `ApdPQ`, `AaKdu`, `Co3OM`, and `ymOCw` were `READY` and that `wir-on-accent` resolves to `#101015`.
- Targeted visitor scans returned no `ctx.problems` for the four updated frame subtrees after the final updates.
- After screenshots were visually reviewed for the confirmation dialog and all three Snackbar states. The obsolete dimming overlays were removed from the two converted outcome states.
- `git -c core.whitespace=cr-at-eol diff --check` passed. The checked-in CSS file intentionally uses CRLF (`i/crlf`, `w/crlf`), so the check declares carriage return valid at end of line.
- `/Users/stasyudkin/fvm/versions/3.38.5/bin/flutter test --no-pub test/core/theme/nova_tokens_test.dart` did not start the test suite: Flutter crashed in `testCompilerBuildNativeAssets` with `Bad state: No element`. This is recorded as `NOT RUN`, not PASS or a product-test failure. The generated crash log was removed from the worktree.

## Evidence boundary

This evidence establishes source/token/canvas reconciliation. It does not establish native typography, Material layout pixel parity, Simulator launch, physical-device accessibility, signing, packet-tunnel operation or protected VPN traffic. Native screenshots remain gated by U1; the canvas screenshots must not be presented as a running build.
