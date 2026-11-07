# Blizzard Dark v1 — coverage and gaps

This log prevents the 89-frame reskin from being mistaken for exhaustive product, platform, or runtime coverage. Status terms:

- `SOURCE_VERIFIED` — behavior/reachability confirmed from the inspected Flutter source.
- `CANVAS_PRESENT` — included in the current 89-frame source set, according to the parent’s live verification.
- `STATIC_LINKED` — exact source/target IDs and master references are recorded in `mapping.json` and `component-catalog.json`.
- `STATIC_PASS_WITH_NOTES` — static QA passed for added reskin work while named baseline-derived limitations remain documented.
- `GAP` — current source behavior exists or a required acceptance variant is known, but the approved frame set does not yet prove complete visual coverage.
- `OUT_OF_SCOPE` — explicitly excluded from Dark v1.
- `FUTURE_ACCEPTANCE` — can be proven only in an implementation/build/device pass.

## Current approved boundary

| Family | Status | Dark v1 handling |
|---|---|---|
| 89 source stateframes | `CANVAS_PRESENT`, `STATIC_LINKED` | `mapping.json` records 89 unique source IDs and 89 unique target IDs; every target has master references and `targetTheme=Dark`. |
| R01–R13 routes | `SOURCE_VERIFIED`, `CANVAS_PRESENT` | Preserve current route, state, copy, action, and iPhone reachability. |
| S01–S03 sheets | `SOURCE_VERIFIED`, `CANVAS_PRESENT` | Preserve modal, dismissal, keyboard inset, and state behavior. |
| D01–D13 dialog families | `CANVAS_PRESENT`, `STATIC_LINKED` | D01–D08 and D10–D13 have current triggers. D09 is implemented but its only caller is dormant, so it is not current iPhone reachability. Preserve that distinction. |
| Seven final settings/dialog frames | `SOURCE_VERIFIED`, `CANVAS_PRESENT`, `STATIC_LINKED` | R05-D01 import confirmation; R06-D01 Language picker; R06-D02 Theme picker; R06-D03 debug/restart info dialog; R06-D04 Log level picker; R06-D05 URL input; R06-D06 interval slider. Exact IDs are in `mapping.json`. |
| `ijVeD` Blizzard reference | `CANVAS_PRESENT`, `STATIC_PASS_WITH_NOTES` | Reference isolation and normalized immutability checks pass. It remains a visual reference, not runtime behavior evidence. |
| New Blizzard masters | `STATIC_LINKED` | 83 unique independent master IDs exist: 75 structural and 8 shared. All 89 targets contain master references. |

The older local inventory documents an earlier live receipt of 82 frames and unknown outcomes for its first seven setting-editor creations. The completed `mapping.json` now supersedes that receipt for static inventory: it contains all 89 source/target pairs. The historical receipt remains provenance, not current count authority.

## Static QA status

- `mapping.json`: 89 source frames, 89 target frames, 83 masters; all source and target IDs are populated and unique; all targets have master references.
- `component-catalog.json`: 83 unique master IDs, comprising 75 structural masters and 8 shared masters.
- pen.dev Copy/Update retains copied source metadata. Target-root context plus `mapping.json` is the provenance authority.
- `qa-results.json`: `STATIC_DESIGN_COMPLETE_WITH_INHERITED_BASELINE_NOTES`. Normalized hash comparison confirms 94/94 source artifacts unchanged; the earlier six differences were only unpadded versus padded hex representations.
- Text parity: 89/89 `PASS`, with only the approved `Hiddify → VPN` title/name and source artwork → replaceable power-glyph substitutions.
- Component/reference isolation: `PASS`; 878 references checked, no foreign references, zero unresolved token references, and zero raw color literals in screens/component definitions.
- Static accessibility evidence: 403 measured action targets with a 44×44 pt minimum; 14 specimens with zero unexpected content clipping; listed contrast pairs pass text AA with a 4.66:1 minimum. The keyboard-inset specimen contains a 304 pt system-zone fixture, not an OS keyboard capture.
- Layout: `PASS_FOR_ADDED_CHANGES`. Ten frames retain `INHERITED_BASELINE_GEOMETRY`: R04 editor/scroll and slider-thumb protrusions, plus R06-D02…D06 modal-underlay/navigation and slider-thumb clipping. Runtime scrolling remains `NOT RUN`.
- Export verification: all 89 target-image dimensions are verified. The gallery, both contact sheets, showcase, 89 screen exports, 94 source-artifact exports, 14 specimen exports, and 6 library-board exports are present.
- Correction review: `PASS`; Language (11 options), Log level, Profile editor, QR, and WARP samples added no blocking defect after the recorded corrections.
- Inherited visual notes: a DE flag appears beside the Finland server; a disconnected-background label is partly visible behind QR; the WARP missing-config notice remains aligned to the source left edge. These are documented baseline-derived notes, not new reskin behavior.
- Runtime ledger: VoiceOver, Dynamic Type, native Liquid Glass, motion, haptics, performance, system keyboard, and VPN traffic are all `NOT RUN`.

## Route/state gaps

| Surface | Known gap | Required disposition |
|---|---|---|
| R01 Intro | Busy action, long legal/source copy, locale/region/analytics combinations may exceed represented variants. | Map only existing 89-frame states now; log unrepresented combinations and long-text acceptance. |
| R02 Home | True model states are disconnected/connecting/connected/disconnecting; `needsReconnect`, unknown latency, no profile, subscription edges, async/error are rendering/data conditions. | Audit labels and action availability frame by frame. Do not create new model states or protected claims. |
| R03 Proxies | Loading, populated/selected, empty, error, normal/timeout/testing latency combinations may not all be separate frames. | Record exact covered variants in `mapping.json`; leave absent combinations as gaps. |
| R04 Profile details | JSON/plain-text editor, dirty/save-enabled, saving, remote/local, error, menus, and keyboard states are not proven exhaustive by the 89 count. | Do not invent editor screens; add only after source-to-frame evidence. |
| R05 Settings | R05-D01 covers import-settings confirmation. The complete overflow import/export/reset hierarchy is not thereby proven as separate transient coverage. It has no current setting picker/input. | Keep menus as `GAP` unless mapped elsewhere in the 89 set. |
| R06 General | The seven-frame tail covers Language, Theme, debug/restart info, Log level, connection-test URL, and URL-test interval. It does not include the source-backed numeric Clash API port input or every selected/reset/cancel/keyboard condition. | Keep Clash API port and unrepresented interaction variants as `GAP`. Do not add inline validation copy: current rejection closes without it. |
| R07–R11 settings children | Dependent on/off controls, disabled states, long scrolling continuation, value editors, QR action, WARP generation/license/error states may be only partially represented. | Preserve only mapped combinations; log all missing source-backed combinations. |
| R12 Logs | Live/paused/filter/empty/error and debug-only share menu are not proven exhaustive; raw logs are prohibited. | Use closed synthetic messages. `GAP` for unmapped menu/filter/empty/error variants. |
| R13 About | Update checking, latest toast, update/error dialog, update menu states may be partial. | Distinguish app-owned D11 from package/system upgrade overlays. |

## Overlay and transient gaps

| Item | Status | Notes |
|---|---|---|
| Generic setting picker/radio family (inventory D14) | `GAP` | Language, Theme, and Log level instances do not prove the complete reusable family, all reset/cancel/selected states, RTL, or large-text behavior. |
| Generic setting input/slider family (inventory D15) | `GAP` | Text/numeric input, suggestions, validation, optional action, reset/cancel/OK, interval slider, and keyboard-open variants need instance-level mapping. Dormant `SettingTextDialog` is not current iPhone reachability. |
| Clash API port input | `GAP` | Source-backed numeric editor is not one of the seven live-identified final settings/dialog frames; do not claim coverage unless another mapped frame proves it. |
| Settings overflow menu | `GAP` | Import/export/reset hierarchy requires explicit frame and trigger mapping. |
| Profile action menu/share submenu | `GAP` | Update/share URL/share QR/share JSON/edit/delete hierarchy must stay source-faithful. |
| Proxy sort and info trigger | `GAP` | Default/alphabet/delay menu and long-press/tap D08 trigger need mapping. |
| About menu / Logs debug menu | `GAP` | Logs share remains conditional on debug mode on iOS. |
| Keyboard-open forms/editors | `GAP` | OS keyboard remains system-owned; app surface must preserve insets, focus, validation, and reachable actions. |
| Toasts: success/error/info | `GAP` | Preserve source messages and accessible announcements; do not invent durable outcomes. |
| D11 three-action layout | `STATIC_PASS_WITH_NOTES` | Static target keeps all three actions in one row with padding 18→4 and label size 14→12; shortest button measures 44 pt. Validate localized labels, Dynamic Type, VoiceOver, and supported widths at runtime. |
| Global upgrade alert | `GAP`, `surfaceOwner=unknown` | Package/runtime presentation needs a capture and attribution. Do not substitute D11. |
| D09 unknown-domain warning | `GAP`, dormant source | The component exists, but its only caller is in unused `ProfileTileMain`. Keep as dormant provenance unless a live trigger is proven. |
| OS permission prompts, share/document pickers, text selection | `GAP`, `surfaceOwner=system` | Keep native; environmental captures do not become Blizzard masters. |

## Theme, viewport, and localization gaps

- Dark is the only designed v1 outcome. System, Light, and Black remain `OUT_OF_SCOPE` as visual themes even when their source actions are preserved.
- Current source includes iPad/tablet/desktop adaptive branches and landscape declarations. The approved handoff is iPhone-focused; iPad navigation rail, desktop stats/navigation, and complete landscape behavior are `OUT_OF_SCOPE` until separately approved.
- The static mapping records the canvas coordinates and source viewport metadata used for the 89 targets. Safe-area behavior and runtime status-bar rendering remain `FUTURE_ACCEPTANCE`.
- A corrected Arabic RTL specimen and general long-string/150% text specimens pass static layout. Persian, locale-specific French/Spanish expansion, Simplified/Traditional Chinese, and runtime bidirectional behavior remain `GAP` or `FUTURE_ACCEPTANCE`.
- Runtime SF Pro rendering and the Persian Shabnam fallback chain require implementation validation. pen.dev does not support `SF Pro Text`; Inter is the verified canvas-only fallback.

## Accessibility gaps

- Static QA measured 403 actions at a minimum 44×44 pt. Thin slider/switch visuals still depend on an enclosing runtime hit region and native semantics remain unverified.
- Listed semantic and worst linear glass/highlight composites pass text AA with a minimum 4.66:1. Unknown runtime backdrops still require build measurement.
- VoiceOver order, labels, values, hints, grouping, modal focus, and announcements are handoff annotations only until tested in a build.
- Dynamic Type, Switch Control, keyboard navigation, Reduce Motion, Reduce Transparency, and Increase Contrast are `FUTURE_ACCEPTANCE` unless represented and then verified at runtime.

## Brand and asset gaps

- Final brand mark, brand name, icon, splash, legal/source URLs, and About metadata are not approved. Use neutral slots.
- Static text/reference/component checks confirm the neutral power-glyph substitution and isolated new library. Final brand assets remain unapproved and must stay replaceable.
- Asset formats, export scales, color profiles, and final licensing/provenance remain `GAP`; static master IDs do not close export/runtime asset acceptance.

## Implementation and device gaps

All items below are `FUTURE_ACCEPTANCE`, not design completion evidence:

- Flutter token/component implementation and source SHA linkage;
- effective minimum iOS version and SF Symbol availability;
- shader/blur/particle performance, frame pacing, memory, battery, thermal behavior, and first-frame shader compilation;
- real Dynamic Type, VoiceOver, Switch Control, Reduce Motion/Transparency, and Increase Contrast;
- haptic behavior and system-settings compliance;
- keyboard, camera, QR scan, permission, file/share, safe-area, rotation, and edge-swipe behavior;
- physical-device VPN lifecycle, protected reachability, external routing, DNS, network handoff, background/lock, reconnect, and failure recovery.

## Explicitly excluded surfaces

- Android per-app proxy and installed-app selection;
- unreachable route-rules pages/editors and Android apps page;
- tablet/desktop Profiles page and desktop-only navigation/settings/dialogs;
- commented or dormant widgets such as alternate connection buttons and the unused empty-profile body;
- historical Woman in Red mockups as runtime evidence;
- new accounts, billing, onboarding steps, server metrics, protection claims, or other product features.

## Completion checklist for this documentation package

- [x] Scope, evidence boundary, and exact-reskin rule documented.
- [x] Three visual layers and three particle presets documented.
- [x] Component anatomy/API/state/content/a11y/interaction/material rules documented.
- [x] iOS system ownership, font fallback, symbols, RTL/locales, motion, haptics, and future acceptance documented.
- [x] Known source/canvas coverage and missing editors/menus/states documented without inventing them.
- [x] Exact 89 source/target pairs recorded in authoritative mapping.
- [x] 83 unique independent masters recorded in component catalog.
- [x] 94/94 source artifacts pass normalized immutability comparison.
- [x] 89/89 text parity, reference isolation, and component isolation pass.
- [x] 14 static accessibility/layout specimens pass with no unexpected clipping.
- [x] R04 and R06-D02…D06 clipping classified as inherited baseline geometry; added reskin changes pass layout QA.
- [ ] Future implementation/device acceptance runs against an exact build.
