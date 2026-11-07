# Blizzard Design System — Dark v1

Design handoff for a dark-only Blizzard reskin of the current iPhone Flutter application. The target is a separate component library and a one-to-one visual reskin of the approved 89-frame source set. This package is design documentation; it does not change application code, navigation, behavior, Apple configuration, or runtime claims.

Package status: `STATIC_DESIGN_COMPLETE_WITH_INHERITED_BASELINE_NOTES / RUNTIME_NOT_RUN`. Last source and artifact review: 2026-10-04. Inspected checkout: `chore/clean-hiddify-ios-baseline` at `fe6f971674787ec0ae2955ef0cba456857324810`; installed baseline provenance recorded by the source inventory: WIR Baseline `0.0.1 (1)` from `0830294eff5b8cd86324545ed00689648c70bd23`. The source and target revisions are separate evidence.

## Approved direction

- Visual reference: the existing `ijVeD` frame, **Blizzard · 07 Dense particles / Home**, in the current `pen.dev` document.
- Product structure: preserve the current composition, copy, actions, states, and reachability. The two top-level mobile tabs remain **«Главная»** and **«Настройки»**.
- Theme: Dark only for v1. Every target frame is tagged `targetTheme=Dark`; source theme provenance stays attached where known.
- Scope: all 89 source stateframes now have 89 unique Dark target copies in `mapping.json`. The older local inventory records an earlier partial canvas receipt, so it is supporting source evidence rather than the current mapping authority.
- Components: the separate Blizzard library contains 83 independent masters: 75 structural masters and 8 shared masters. All mapped target frames have master references; `component-catalog.json` is the ID authority.
- Brand: use replaceable `BrandMarkSlot`, `BrandNameSlot`, app-icon, and splash slots. No final brand, logo, or marketing claim is invented in this handoff.
- Typography: prefer the iOS system family (SF Pro at runtime). Inter is the verified canvas fallback because `SF Pro Text` is unavailable in pen.dev; this does not change runtime typography guidance.
- Product behavior: no new features, routes, tabs, states, protection claims, or data fields.

“Exact reskin” means preserving order, grouping, the position of semantic blocks, copy, actions, states, and action availability. Color, material, border, shadow, type treatment, icons, and decorative layers may change. Any size or line-wrap change that affects composition must be logged in [coverage-gaps.md](coverage-gaps.md). Apple HIG guidance does not authorize restructuring the baseline.

## Evidence boundary

The current source establishes a Flutter Material 3 app, not a native Cupertino shell and not native Liquid Glass. Blizzard glass and particles describe a visual target with implementable fallbacks. They do not prove a native material, animation, haptic, VoiceOver result, device performance, VPN traffic, or physical-device behavior.

Connection copy must follow the current model:

| Model / condition | Display rule |
|---|---|
| `disconnected` | «Нажмите для подключения» |
| `connecting` | «Подключение...» |
| `connected` with missing/invalid latency | «Подключение...» |
| `connected` with valid latency | «Подключено» |
| `connected` with `needsReconnect` | «Переподключить»; this condition takes priority |
| `disconnecting` | «Отключение...» |
| async loading / async error | preserve the current enabled/disabled and alert behavior; do not invent a new status label |

The secure sublabel is permitted only for the existing WARP-over-proxy condition, a connected model, and valid latency. Generic claims such as «Вы защищены», «Безопасно», or “traffic verified” are prohibited. Canvas latency, selected server, IP/country, and connection outcomes are fixtures.

## Target frame provenance

Target frames use this naming contract:

`Rxx/Sxx/Dxx — state — viewport — locale — targetTheme=Dark`

The authoritative static artifacts record:

- `mapping.json`: source and target IDs, source name, surface ID, phase, coordinates, source metadata/path/state/build/SHA/locale/viewport, target bounds/theme, surface owner, fixture provenance, screenshots, copy-parity/branding notes, and referenced master IDs;
- `component-catalog.json`: master ID, name, role, bounds, and canvas API data;
- target-root context: `sourceFrameId`, `surfaceId`, and `targetTheme` because pen.dev Copy/Update retains the copied source metadata.

Use those files rather than inferring linkage from names or screenshots. Route triggers, platform gates, safe-area assumptions, executable callbacks, test IDs, and runtime accessibility bindings are implementation contracts derived from inspected source; they are not asserted as fields already present in the static mapping/catalog.

Evidence vocabulary used across the package:

- `PROVEN_SOURCE` — inspected source establishes behavior or reachability.
- `PROVEN_RUNTIME` — exact build/device evidence establishes rendered or interactive behavior.
- `APPROVED_TARGET` — the user approved the intended design direction/scope.
- `RECOMMENDATION` — implementation guidance awaiting proof.
- `GAP` — missing, unresolved, or incompletely mapped evidence.
- `FUTURE_ACCEPTANCE` — can be decided only after implementation or device testing.

## Visual foundation

Reference colors:

| Role | Value |
|---|---|
| Background | `#06121D` |
| Surface | `#102235` |
| Elevated surface | `#19374C` |
| Accent | `#72D1FF` |
| Primary text | `#EFF7FD` |
| Secondary text | `#BACDDB` |
| Muted text | `#9BB3C5` |
| Error | `#F7AAAA` |
| Warning | `#EAC586` |

The design system uses three visual layers:

1. `layer.scene` — background color, gradient, wave, and particle field; never carries interaction or essential meaning.
2. `layer.content` — readable cards, lists, forms, sheets, and dialogs; isolates content from the scene.
3. `layer.control` — navigation and important interactive controls; highest visual separation and focus treatment.

Particle presets are `hero`, `quiet`, and `off`. Home uses `hero` to match the approved reference. Lists, settings, forms, sheets, and dialogs use `quiet`; dense text, input, QR, critical feedback, and accessibility fallbacks may use `off`. Particles must be masked away from text and controls.

## Surface coverage

- Routes `R01–R13`: Intro, Home, Proxies, Profile details, Settings, General, Routing, DNS, Inbound, TLS tricks, WARP, Logs, About.
- Sheets `S01–S03`: Add profile, Profiles overview, Quick settings.
- Dialog families present in the approved canvas set: `D01–D13`, including QR scanner/display variants already represented there. Source review found D09 dormant/unreachable on the current iPhone path; its canvas presence is provenance, not reachability proof.
- Seven final mapped settings/dialog stateframes are live-identified: `R05-D01` import-settings confirmation; `R06-D01` Language picker (11 options); `R06-D02` Theme picker (4 options); `R06-D03` debug-mode/restart information dialog; `R06-D04` Log level picker (4 options); `R06-D05` connection-test URL input; and `R06-D06` URL-test interval slider. They are not seven generic picker/input variants. The exact source/target IDs remain authoritative in `mapping.json`.

Profiles remain a sheet on iPhone. Logs and About remain rows under Settings. Android per-app routing, desktop/tablet branches, unreachable route-rule editors, and commented source remnants are not current iPhone product surfaces.

## Handoff files

- [component-specifications.md](component-specifications.md) — token layers, component APIs, anatomy, states, content, interaction, and accessibility rules.
- [ios-handoff.md](ios-handoff.md) — Flutter/iOS implementation constraints, system ownership, typography, symbols, accessibility, motion, haptics, and acceptance evidence.
- [coverage-gaps.md](coverage-gaps.md) — verified coverage boundary, unresolved mappings, missing states, and future validation.
- `tokens.json` — machine-readable tokens, owned by the parent task.
- `source-manifest.json` — source-frame provenance, owned by the parent task.
- `mapping.json` — authoritative 89-source-to-89-target mapping and target context, owned by the parent task.
- `component-catalog.json` — authoritative catalog of 83 independent masters, owned by the parent task.
- `qa-results.json` — final static verification and runtime ledger, owned by the parent task. Static status is `STATIC_DESIGN_COMPLETE_WITH_INHERITED_BASELINE_NOTES`; runtime fields remain `NOT RUN`.
- [Interactive gallery](index.html) — browsable handoff index.
- [All-screen contact sheet](contact-sheet.png) — overview of the 89 Dark targets.
- [Accessibility contact sheet](accessibility-contact-sheet.png) — overview of the 14 static specimens.
- [Showcase](showcase.png) — compact visual summary.

## Design QA gates

1. Use the completed 89-source-to-89-target mapping and 83-master catalog as the static inventory authority.
2. Use normalized eight-character hex comparison from `qa-results.json`: all 94 source artifacts, including the reference and original masters, are unchanged.
3. Compare source and target by IDs from `mapping.json`, not by frame name. Preserve copy, action presence, state, and surface ownership.
4. Validate the riskiest pilot set before scaling: Home, a long settings/list route, a complex sheet, a dialog, and a keyboard-open input.
5. Freeze the resulting rules, then apply them across the remaining mapped frames.
6. Produce a contact sheet of all 89 targets plus full-size captures for risky states. Measure contrast at the worst particle/glass point and run layout checks.
7. Re-read the source snapshot and reference snapshot. Current results: reference isolation `PASS`, component isolation `PASS` across 878 checked references, no foreign references, no unresolved token references, and no raw color literals in screens/component definitions.

The static artifacts prove creation and linkage of the frozen 89-frame target set and 83 independent masters. Text parity passes for all 89 frames except the two approved neutral-brand substitutions. Layout passes for added reskin changes; 10 frames retain classified baseline geometry notes. Fourteen accessibility/layout specimens pass without unexpected content clipping. This does not prove exhaustive application coverage or runtime/device acceptance.

## Data safety

Only approved display values and deterministic synthetic fixtures may appear. Never place subscription URLs, access tokens, UUIDs, real IP addresses, credentials, QR payloads, device identifiers, payment data, raw logs, signed URLs, or App Group data on the canvas. Use documentation domains and reserved IP ranges for synthetic examples.
