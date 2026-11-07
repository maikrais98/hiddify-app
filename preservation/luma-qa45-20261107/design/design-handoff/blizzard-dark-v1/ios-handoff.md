# Blizzard Dark v1 — iOS and Flutter handoff

Read [coverage-gaps.md](coverage-gaps.md) before implementation. It is the authority for unresolved source/target mappings and evidence that remains `FUTURE_ACCEPTANCE`.

## Runtime baseline

The inspected app uses Flutter Material 3 through `MaterialApp.router`, `ThemeData(useMaterial3: true)`, adaptive navigation, and Material dialogs/sheets. It derives optional dynamic color schemes and otherwise falls back to a seeded Material scheme. This handoff therefore specifies a Blizzard visual layer for Flutter. It does not claim native Apple Liquid Glass or a Cupertino application shell.

The current iPhone breakpoint is below 600 logical pixels and exposes exactly two persistent destinations: Home and Settings. Profiles open as a sheet; Logs and About are Settings children. The repository also contains tablet/desktop navigation and iPad target settings, but Dark v1’s approved frame set is iPhone-focused. Do not apply the two-tab assumption to iPad without a separate adaptive-layout design pass.

The repository contains conflicting iOS floor declarations (15.0 in project/framework settings and 15.5 in the Podfile). Resolve the effective deployment target from the built artifact/configuration during implementation. Dark v1 must not require an API newer than the verified minimum.

## Theme and typography

- Implement a dedicated Dark target theme mapped from primitive → semantic → component tokens.
- Existing runtime preferences include System, Light, Dark, and Black. Dark v1 designs only the Dark result. Keep theme controls and actions for copy/action parity, but do not treat the reskinned source copies as designed Light/System/Black outcomes.
- Use the iOS system font family at runtime so SF Pro resolves through the platform. The pen.dev check confirmed that `SF Pro Text` is unavailable, so the static canvas uses Inter as its recorded fallback. The fallback is not runtime guidance.
- Persian currently has a Shabnam preference in the source. Do not remove locale-specific font behavior silently. Confirm the final type fallback chain with localization and licensing before implementation.
- Use monospaced system styling only for app-owned JSON/log/code content. Never place raw private logs or configuration on design or test artifacts.

## Concrete token implementation map

The following is a recommended implementation map, not generated application code. Resolve aliases recursively from `tokens.json`; keep the exact canvas IDs for traceability. Store Blizzard-specific values in a typed theme extension, with `copyWith` and `lerp`, rather than scattering local literals. This follows Flutter's documented [ThemeExtension]([REDACTED]) mechanism.

| Actual token / role | Flutter target | Native iOS pattern or equivalent |
|---|---|---|
| `blz-v1-color-background` | Shell/scaffold background; keep separate from card fill | Custom dark page background |
| `blz-v1-color-surface`, `blz-v1-color-elevated` | Explicit content/container fills; corresponding Material surface roles where appropriate | Opaque grouped content and raised app-owned surfaces |
| `blz-v1-color-accent`, `blz-v1-color-on-accent` | Primary/on-primary pair and source-backed active control styling | Tint and readable foreground for primary controls |
| `blz-v1-color-text-primary`, `-secondary`, `-tertiary`, `-disabled` | Explicit semantic text roles; primary maps to on-surface | App text hierarchy, with separate disabled treatment |
| `blz-v1-color-status-error`, `-warning` | Error maps to the Material error role; warning remains a custom role | Error/warning text plus a semantic icon or label |
| `blz-v1-color-selected`, `-separator`, `-border` | Selected-row fill, divider, and field/control outlines | Selection indication, separators, and app-owned boundaries |
| `blz-v1-component-button-background`, `-foreground` | Primary button state styling | Primary button appearance; action semantics unchanged |
| `blz-v1-component-field-background`, `-border` | Input surface and border styling | App-owned input field appearance |
| `blz-v1-component-dock-background`, `blz-v1-color-glass-edge` | Dock fill/edge; opaque fallback under Reduce Transparency | Floating navigation material reference; native Liquid Glass is not implied |
| `blz-v1-space-*`, `blz-v1-radius-*`, `blz-v1-target-min` | Logical-pixel spacing/radii and a minimum 44 logical-pixel interaction region | Point-based geometry and at least 44×44 pt interaction regions |
| `blz-v1-hero-opacity`, `-quiet-opacity`, `blz-v1-decor-off` | Decorative preset strength; no semantic data | Decorative scene layer, excluded from VoiceOver |

Material roles describe compatible meanings; custom Blizzard roles remain explicit when one-to-one mapping would change the appearance. Do not regenerate this fixed Dark palette from a seed or wallpaper. Flutter supports configuring both component themes and a custom [ColorScheme]([REDACTED]).

Color strings in this package are `#RRGGBB` or `#RRGGBBAA`. Flutter's integer [Color]([REDACTED]) representation is ARGB: for example, `#163C51D9` becomes `0xD9163C51`. Preserve alpha during conversion; do not copy the RGBA byte order into the integer constructor.

| Typography role in `tokens.json` | Base canvas treatment | Flutter target | Native iOS text style |
|---|---|---|---|
| `title` | 22 / 600 / 1.25 | Role-specific `TextStyle` with platform text scaling | `title2` |
| `body` | 17 / 400 / 1.3 | Body role with platform text scaling | `body` |
| `callout` | 16 / 400 / 1.3 | Callout role with platform text scaling | `callout` |
| `label` | 14 / 500 / 1.3 | Source-compatible control label, scaled and allowed to wrap | Custom control style, scaled using appropriate text metrics |
| `caption` | 12 / 400 / 1.3 | Caption role with platform text scaling | `caption1` |
| `code` | 13 / 400 / 1.4 | System monospace, LTR technical content | System monospace with scalable text metrics |

Base sizes describe the design reference, not a maximum user text size. Preserve the recorded source-specific size variants, including the D11 exception; do not force every existing label to the generic body size. Use the platform font scaling strategy rather than a fixed global multiplier. Flutter exposes `textScaler`, safe-area padding, and keyboard `viewInsets` through [MediaQueryData]([REDACTED]). Native text-style correspondence uses Apple's [UIFont.TextStyle](https://developer.apple.com/documentation/uikit/uifont/textstyle); custom sizes require scalable [UIFontMetrics](https://developer.apple.com/documentation/uikit/uifontmetrics).

## Concrete component implementation map

IDs below are representative masters, not the complete state list; `component-catalog.json` supplies all 83 masters. Flutter bindings are recommendations for the inspected Material application. Native entries describe the matching iOS interaction pattern, not a requirement to replace the current Flutter shell.

| Canvas family and representative IDs | Flutter implementation responsibility | Native iOS pattern |
|---|---|---|
| Navigation `Pncjt`, `zS0W1` | Style the existing two destinations and preserve their selection/routing callbacks | Two-item tab navigation with selected semantics |
| Header `g2mz6F`; IconButton `IffME` | Style the existing app bar/actions; keep back behavior and ≥44 interaction regions | Navigation bar and labelled toolbar buttons |
| ConnectionControl `gV44U`, `oC0vk`, `ItpJH`, `NprjB`, `t5MA0` | Render model/latency/reconnect priority; retain source enabled conditions and actions | Custom accessible primary button, with a separate status value |
| ProfileCard `Slurc`; ServerRow `PJogE`; ActiveServer `AroE3` | Restyle existing list/card content, selection, menus, and delay values | Grouped content rows with selection and contextual actions |
| SettingsRow `sl64v`; Toggle `YqHKU`, `N5r42` | Keep source preference bindings; disabled controls remain disabled | Settings row and switch semantics |
| Segment `Zmylv`; RadioOption `tyjop`; Slider `F0ZGo` | Preserve selection/value/range/reset callbacks and ≥44 interaction regions | Segmented selection, choice list, and adjustable slider |
| TextField `KbBxH`; SettingInput `P5HaK4` | Restyle existing inputs and validators; maintain LTR technical values and keyboard insets | Editable field with system keyboard |
| Sheet `UYIaz`, `h8smZ`, `sYyTx`; Alert `G05Zb`, `rHydA` | Restyle current app-owned modal presentations; preserve dismissal, action order, scroll, and focus return | Modal sheet and app alert patterns |
| CodeEditor `bxmrG`, `c5kHn`; LogRow `lAW1b` | Opaque, scrollable technical content; preserve edit/read-only behavior | Monospaced editor or readable log list |
| Scanner `JYowI`; QR `w94UYW` | Keep existing camera/code behavior and system permission ownership; opaque QR quiet zone | Camera scanner and QR presentation |
| Feedback `XdenY` | Preserve the route's real loading/empty/error state and available actions | Progress or status presentation with accessible text |
| Decor `VdsoR`, `QBuOy`; Brand slots `ghARu`, `AwuMD`, `NF1dc` | Separate decorative layer and replaceable brand assets; decoration receives no pointer or semantic actions | Noninteractive background decoration and replaceable identity |
| StatusBar `JyMB9` | Canvas illustration only; use platform status bar styling and real safe areas | System-owned status bar |

## VoiceOver labels and reading order

Bind labels to localized source content and real model values. The table is an accessibility specification; it does not assert working runtime bindings. Flutter's [Semantics]([REDACTED]) provides role/label/value/state annotations and supports excluding purely decorative subtrees.

| Family | Label, value, and state | Reading order / grouping |
|---|---|---|
| Tab navigation | «Главная» / «Настройки»; selected state from the current destination | Each tab is one item, in source order |
| Header/action | Title marked as a heading; icon action uses its existing localized action name | Back, title, then source trailing actions |
| Connection control | Existing visible status label; actual busy/disabled state; use the source action name when actionable | One control, followed by nonredundant supporting status |
| Profile card | Profile name, source subscription summary, expiry/update state | Summary grouped; menu and other actions remain distinct |
| Server row | Server name, displayed delay or delay-state text, selected state | Row content grouped; separate info action only where present |
| Settings row | Source title, current value; toggle on/off or disabled state | Title/value together; one actionable control per source action |
| Input/editor | Source field label and current value; existing error text when present | Label, editable value, supporting/error text, then existing actions |
| Slider/choice | Source label and current formatted value; selected/adjustable/disabled state | Preserve source option order and adjustable actions |
| Sheet/dialog | Source heading, message, options, then unchanged action labels | Focus moves into modal; dismiss restores the invoking control |
| QR/scanner | Existing localized purpose and close action; never announce a raw private payload | Purpose then existing scanner/display actions; code artwork is not read cell by cell |
| Log/feedback | Visible source severity/status and readable event content | Follow source chronological/content order; announce meaningful state changes once |
| Scene/brand | Exclude particles, wave, redundant mark/title artwork | Keep a meaningful brand name only once if required by the screen |

WARP dependent controls expose their actual disabled state and existing explanatory text. Do not invent a VoiceOver protection claim. System keyboard and permission-prompt reading order remain platform-owned.

## Materials and particles

`layer.scene`, `layer.content`, and `layer.control` are functional layers, not three stacked blur effects.

- Scene: static color/gradient/wave and decorative particles.
- Content: cards, lists, forms, sheets, and dialogs with stable readability.
- Control: navigation and important actions with the strongest separation and focus treatment.

Use a Flutter-compatible opaque/translucent surface implementation. Native Liquid Glass remains unproven. Avoid glass-on-glass, large live blur regions, and particles under text/input. `hero`, `quiet`, and `off` are the only v1 particle presets.

For accessibility fallbacks:

- Reduce Motion: freeze particles; allow a simple short crossfade only if it does not convey state.
- Reduce Transparency: use the opaque surface fallback.
- Increase Contrast: strengthen text, separators, focus, and control boundaries without changing semantics.

These are implementation requirements to validate later, not verified runtime behavior.

## System-owned surfaces

Every overlay must declare `surfaceOwner=app|system|unknown`.

- App-owned Flutter dialogs, sheets, menus, fields, and cards receive Blizzard styling.
- iOS permission prompts, keyboard, text selection, camera permission, share sheet, document picker, and system alerts remain platform-owned.
- Package/runtime-dependent overlays such as global upgrade alerts remain `unknown` until captured and attributed. Do not substitute the app’s custom update dialog for an OS/package alert.
- Status/navigation bars, safe areas, home indicator, keyboard insets, and edge-swipe behavior are environmental constraints, not decorative canvas elements.

## Layout and interaction

- Preserve source route structure, action placement, modal behavior, dismissal rules, and enabled/disabled conditions.
- Use safe-area-aware layout in portrait. Record landscape/iPad adaptations as gaps unless represented in the verified manifest.
- Maintain at least 44×44 pt hit targets. When the current composition conflicts, log the exact component/frame and resolve it in implementation review; do not silently move semantic blocks in the design handoff.
- Sheets retain keyboard inset handling and scrolling. Long routes must keep reachable controls at large text sizes.
- Preserve platform back behavior and logical leading/trailing alignment. The iOS edge-swipe back gesture must not be blocked by full-width decorative gesture layers.
- Keep OS keyboards and permissions visually unchanged. Show them only as environmental context with system ownership metadata.
- Preserve D11’s three source actions in one horizontal row. The approved static reskin uses horizontal action padding 4 instead of 18 and label size 12 instead of 14. Revalidate this exception with localized copy, Dynamic Type, VoiceOver, and supported iPhone widths in the implementation; the static frame is not accessibility proof.

## Localization and bidirectionality

The source currently declares `en`, `ar`, `es`, `fa`, `fr`, `id`, `pt-BR`, `ru`, `tr`, `zh-CN`, and `zh-TW`.

Required design review set:

- Russian and English for primary copy parity;
- Arabic and Persian for RTL order, mirrored navigation, and mixed-direction values;
- French or Spanish for long Latin strings;
- Simplified and Traditional Chinese for line height and compact labels.

Technical values such as IP addresses, domains, ports, URLs, JSON, and identifiers stay LTR inside RTL pages. Localize semantic text, not fixture payloads. Do not hard-code left/right padding or direction-dependent chevrons.

## Accessibility handoff

For each component/frame, annotate:

- VoiceOver order and grouping;
- role, label, value, hint, selected/disabled/busy state;
- decorative elements excluded from the accessibility tree;
- large-text reflow and truncation behavior;
- focus position after opening/closing sheets, dialogs, menus, and validation errors;
- contrast measurement at the worst particle/transparency location;
- Reduce Motion, Reduce Transparency, and Increase Contrast fallback.

Canvas annotations do not prove VoiceOver, Dynamic Type, Switch Control, keyboard navigation, or runtime contrast. Those checks belong to future implementation acceptance on the exact build.

## Motion recommendations

Motion may explain an existing transition or state change; it must not introduce a new interaction.

- Route transitions keep the current semantics: fade for Proxy/Profile details and slide for Settings children.
- Connection-state changes may use a restrained color/material crossfade. Busy state may use a progress treatment with an accessible busy value.
- Particle movement, if implemented, is subtle, non-directional, and optional. A static Blizzard scene is a valid v1 implementation.
- Avoid continuous scale/pulse on resting connected or disconnected controls. Do not use motion as proof of VPN activity.
- Canvas timings remain prototype recommendations; static presentation cannot prove runtime smoothness, interruption, or cancellation behavior.

The library’s `Press 120 ms`, `Transition 200 ms`, and `Sheet 280 ms` values are initial prototype recommendations. They are not final runtime tokens until implementation profiling, interruption behavior, and Reduce Motion validation pass.

## Haptic recommendations

Haptics are optional implementation guidance, not current behavior evidence:

- selection feedback for source-backed picker/segmented changes;
- light impact for a completed primary tap when it does not duplicate a system control;
- notification success/warning/error only after the corresponding model result is known;
- no repeated haptic during connecting, particle animation, loading, or disabled taps.

Respect the user’s system settings. Haptics must never be the sole state cue.

## Icons and assets

Use the semantic SF Symbols mapping in [component-specifications.md](component-specifications.md). Verify each symbol against the effective minimum iOS version. Provide an approved vector fallback when unavailable; do not replace meaning with a merely similar decorative glyph.

Keep background wave/particles, glowing container, and brand mark as separate assets/layers. `BrandMarkSlot`, `BrandNameSlot`, app icon, and splash remain placeholders. Do not copy a logo embedded in the reference raster.

## Connection truthfulness

Implementation must preserve the source distinction between the model and its displayed latency-dependent label. A connected model can still render «Подключение...» when latency is absent or invalid, and `needsReconnect` has priority. Do not add “protected”, “secure”, external-IP, country, throughput, or route-quality claims from connection state alone.

The approved WARP-specific secure label is conditional content. It cannot be generalized to the whole app or used as physical-device traffic evidence.

## Future implementation acceptance

Bind evidence to the exact source SHA, build, device/OS, locale, theme, viewport, and fixture. Record `PASS`, `FAIL`, `BLOCKED`, or `NOT RUN`.

1. Token/component implementation maps to the approved IDs and preserves source actions/states.
2. Golden/screenshot checks cover the mapped risk set and all 89 manifest frames where technically practical.
3. Layout is checked at supported iPhone widths, safe areas, keyboard open, and large Dynamic Type.
4. VoiceOver reads labels, values, state, and action order correctly; focus returns predictably after overlays.
5. RTL, long Latin strings, and CJK are checked with real localized resources.
6. Reduce Motion, Reduce Transparency, and Increase Contrast fallbacks are exercised.
7. Performance profiling checks frame pacing, memory, battery, shader compilation, overdraw, and blur/particle cost on representative supported hardware.
8. OS permission prompts, keyboard, scanner, document/share surfaces, and edge-swipe behavior remain functional and system-owned.
9. VPN/device/traffic acceptance is a separate product test. Visual completion cannot satisfy it.

Until these checks run, motion, haptics, VoiceOver, hardware performance, and device behavior remain recommendations or `NOT RUN`.

Static acceptance already completed: 94/94 source artifacts are immutable after normalized hash comparison; 89/89 source-to-target text checks pass with the two documented neutral-brand exceptions; reference and component isolation pass; 14 accessibility/layout specimens pass; and 89 screen, 89 source-screen, 94 source-artifact, 14 specimen, and 6 library-board exports are recorded. The keyboard-inset specimen uses a 304 pt system-zone fixture; it is not an iOS keyboard capture or system-keyboard proof. These results do not replace the runtime acceptance list above.
