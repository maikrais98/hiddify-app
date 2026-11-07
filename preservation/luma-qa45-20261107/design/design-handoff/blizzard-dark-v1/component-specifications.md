# Blizzard Dark v1 — component specifications

This specification defines the independent component library created for the approved iPhone Dark v1 reskin. `component-catalog.json` contains 83 unique master IDs: 75 structural masters and 8 shared masters. `mapping.json` records their target-frame references and is authoritative for linkage; this document defines their behavioral and accessibility contract.

Unmapped states and future acceptance remain tracked in [coverage-gaps.md](coverage-gaps.md); absence from this component catalog is not evidence that a source state does not exist.

## Token model

Use three token levels. Canvas components consume semantic `blz-v1-color-*`, material, typography, layout, and state roles directly where shared meaning is required, plus component aliases for component-specific decisions. Primitive values remain centralized in `tokens.json` and are not repeated as arbitrary local literals.

### 1. Primitive tokens

The canonical color primitives are `#06121D`, `#102235`, `#19374C`, `#72D1FF`, `#EFF7FD`, `#BACDDB`, `#9BB3C5`, `#F7AAAA`, and `#EAC586`. Opacity, blur, radius, spacing, stroke, shadow, type size, and motion primitives belong in `tokens.json`; canvas measurements come from the mapping/catalog rather than prose approximations.

### 2. Semantic tokens

| Family | Required roles |
|---|---|
| Color | `background`, `surface`, `surfaceElevated`, `accent`, `textPrimary`, `textSecondary`, `textMuted`, `statusError`, `statusWarning`, `separator`, `focusRing`, `scrim` |
| Material | `scene`, `content`, `control`, `opaqueFallback` |
| Particle | `hero`, `quiet`, `off`, plus text/control exclusion masks |
| Typography | `display`, `title`, `headline`, `body`, `bodyEmphasis`, `label`, `caption`, `code` |
| Layout | safe-area insets, content margins, vertical rhythm, list density, control minimum target |
| State | `default`, `pressed`, `focused`, `selected`, `disabled`, `loading`, `success`, `warning`, `error` |

Status colors carry status meaning. Decorative red/blue particles must never reuse an error token or become the only status cue.

### 3. Component tokens

Each master owns aliases such as `button.primary.fill.default`, `dialog.surface`, or `connectionControl.ring.reconnect`. A component state may map to semantic tokens; it must not hard-code a primitive. Unsupported combinations should be absent instead of generated as a full Cartesian product.

## Shared implementation contract

The future implementation for each visual component family must expose or document the following. These are implementation requirements, not claims that every field exists in `component-catalog.json`:

- `state`: only states demonstrated by source or required for platform interaction;
- `content`: label, supporting text, leading/trailing semantic icon, badge/value, and optional status;
- `interaction`: tap, long press, selection, dismissal, validation, and loading behavior already present in source;
- `availability`: enabled/disabled/hidden based on the source condition;
- `direction`: LTR/RTL-safe leading/trailing behavior;
- `density`: baseline geometry plus large-text layout when required;
- `particlePreset`: `hero|quiet|off` only where the component owns a scene;
- `surfaceOwner`: `app|system|unknown`;
- `interactionContract`: the source-backed action semantics that a future implementation must preserve; `mapping.json` does not contain executable callback bindings, so provider/callback methods and arguments must be rechecked against source during implementation;
- `testId`: stable identifier for later widget, golden, and semantics checks;
- `accessibility`: semantic role, label, value, hint, selected/disabled/busy state, and logical focus order.

Visible state, semantic state, and action availability must agree. Color, blur, glow, vibration, or animation cannot be the only carrier of meaning.

Static QA measured 403 action targets; the smallest measured target is 44×44 pt. Thin slider/switch visuals depend on an enclosing 44 pt interaction region defined by this contract and still require runtime semantics verification. Listed static text/material pairs pass WCAG AA; the lowest recorded text ratio is 4.66:1. Unknown runtime backdrops must be measured again in the build.

## Scene and material components

### `BlizzardScene`

**API:** `preset`, `decorativeSeed`, `exclusionMask`, `reduceMotion`, `reduceTransparency`, `increaseContrast`.

**Anatomy:** base background → optional gradient/wave → decorative particles → content exclusion mask. The brand mark is a separate slot and must not be baked into the scene raster.

**Rules:**

- `hero` is reserved for Home and other explicitly approved hero compositions.
- `quiet` is the default for lists, settings, sheets, and dialogs.
- `off` is required behind QR, dense input, critical feedback, or when decoration harms readability.
- Reduce Motion freezes the scene or uses a simple crossfade. Reduce Transparency and Increase Contrast select an opaque, high-contrast surface.
- Decoration is ignored by assistive technology and must not suggest connectivity or security.

### `BlizzardSurface`

**API:** `layer=content|control`, `elevation`, `state`, `isScrollable`, `particleMask`, `opaqueFallback`.

**Anatomy:** fill/material → border/separator → optional shadow/highlight → content. Avoid glass-on-glass. Nested cards should use hierarchy through fill, spacing, and separators rather than another blur layer.

## Navigation and shell

### `MobileAppShell`

**API:** `activeTab=home|settings`, `title`, `leadingAction`, `trailingActions`, `body`, `bottomNavigation`, `safeArea`, `scrollBehavior`.

It exposes exactly two persistent destinations: **«Главная»** and **«Настройки»**. Profiles remain a modal sheet; Logs and About remain settings children. Back, edge-swipe, scroll position, and route transitions stay aligned with the existing app.

### `BottomTabDock`

**States:** Home selected, Settings selected, pressed, focused, disabled only if the source can disable it. Selected state uses icon, label, and material/fill differences; do not rely on color alone.

**Symbols:** Home → `house`; Settings → `gearshape`. Use `fill` variants only for selected state when optical weight remains balanced.

## Brand slots

### `BrandMarkSlot` and `BrandNameSlot`

**API:** `asset`, `accessibleName`, `sizeClass`, `placement`, `isPlaceholder`.

The slot is intentionally neutral until final brand assets are approved. Background wave/particles, luminous container, and mark must remain separable. If an existing raster cannot be separated, reconstruct the decorative layer rather than copying embedded Hiddify/WIR branding into the new master.

App icon and splash use the same replaceable-slot rule. About/legal source fields that depend on final branding are content dependencies, not permission to invent copy or URLs.

## Controls

### `PrimaryButton` / `SecondaryButton` / `DestructiveButton`

**API:** `label`, `semanticIcon`, `state`, `isFullWidth`, `onPress`, `busyLabel`.

**States:** default, pressed, focused, disabled, loading; destructive only where the current action is destructive. Preserve the source action label and availability. A loading button keeps its size and exposes a busy semantic state.

### `IconButton`

**API:** `semanticIcon`, `accessibilityLabel`, `state`, `badge`, `onPress`.

The visual glyph may be smaller, but the hit target should be at least 44×44 pt. Existing baseline conflicts are logged individually; they are not silently solved by changing composition.

### `ConnectionControl`

**API:** `modelStatus`, `latencyState`, `needsReconnect`, `warpSecureEligible`, `enabled`, `label`, `supportingLabel`, `action`.

**Allowed model states:** disconnected, connecting, connected, disconnecting. `needsReconnect` and unknown/invalid latency are rendering conditions, not new connection-model states.

**Rendering priority:**

1. `connected && needsReconnect` → reconnect treatment and «Переподключить».
2. `connected && latency unknown/invalid` → connecting treatment and «Подключение...».
3. `connected && latency valid` → connected treatment and «Подключено».
4. other model states → their source-backed labels.

Async loading is disabled; disconnected and async error retain the source retry/connect action behavior. Do not attach a protected/safe claim to a connected state. A secure sublabel appears only under the existing WARP condition and valid latency rule.

### `SwitchRow`, `SegmentedControl`, `RadioPicker`, `SliderControl`

**API:** source label/value, optional supporting text, current selection/value, enabled state, reset availability, and source callback.

`RadioPicker` preserves selected, reset, and cancel behavior. `SliderControl` preserves min/max/divisions and the generated label when present. Disabled dependent settings remain visible only where the current source does so.

### `TextInput`

**API:** `label`, `value`, `keyboardType`, `textDirection`, `validator`, `errorText`, `possibleValues`, `optionalAction`, `reset`, `cancel`, `confirm`, `enabled`, `isSecure`.

**States:** default, focused, populated, invalid, disabled, suggestion list, keyboard open, submitting where source-backed. Technical values such as addresses remain LTR inside RTL layouts. Preserve OS keyboard appearance and autocomplete ownership; Blizzard styles only the app-owned field and surrounding surface.

The current generic input closes without inline error copy when its validator rejects a value. Do not invent validation text for the seven source frames. Record this behavior as source parity and treat any future inline error as a separate product change.

## Content rows and cards

### `SettingsRow`

**API:** `title`, `subtitle`, `value`, `semanticIcon`, `controlType`, `enabled`, `platformGate`, `onPress`.

Variants: navigation, toggle, value/editor, information, destructive action. Long titles wrap without truncating the control or changing action semantics.

### `ProfileCard`

**API:** `name`, `subscriptionSummary`, `expiryState`, `selected`, `updating`, `error`, `menuAvailability`, `onSelect`, `onOpen`, `onMenu`.

Content uses only approved display values or deterministic fixtures. Update/share/edit/delete actions remain in their existing menu hierarchy.

### `ProxyRow`

**API:** `name`, `delayState`, `delayValue`, `selected`, `testing`, `availability`, `onSelect`, `onInfo`.

Delay states are normal, timeout, testing, unknown, and error only when source-backed. Latency is a fixture on canvas and does not prove throughput, stability, or route protection.

### `StatusPanel`, `EmptyState`, `InlineError`, `ProgressState`

**API:** source title/body, semantic status, optional existing action. Keep each route’s source-backed empty/loading/error behavior; do not normalize distinct product states into invented universal actions.

## Overlays

### `BottomSheet`

**API:** `title`, `content`, `primaryAction`, `secondaryActions`, `dismissibility`, `scrollMode`, `keyboardInset`, `state`.

Applies to S01–S03. Preserve rounded top presentation, root-navigator modality, keyboard inset, and the source’s close behavior. A grabber is permitted only if present in the approved composition or added without changing interaction expectations.

S01’s current navigation is not five equal actions: QR, Clipboard, and Manual are primary buttons; Free is a switch and Help is a chip. Preserve those roles and triggers during the reskin.

### `AppDialog`

**API:** `type`, `title`, `message`, `icon`, `actions`, `defaultAction`, `destructiveAction`, `state`, `scrollMode`.

Applies to app-owned D01–D13 and source-backed editor instances. Action order, cancelability, conditional actions, URLs displayed as content, and loading/permission variants must match source. System permission prompts and package-owned alerts use `surfaceOwner=system|unknown` and are not converted into this master without proof of ownership.

**D11 documented exception:** all three existing actions remain in one horizontal row. To preserve the action set without changing composition, the static target reduces horizontal action padding from 18 to 4 and action-label size from 14 to 12. This is an approved typography/form reskin exception, not permission to remove, rename, stack, or reprioritize actions. Runtime Dynamic Type and VoiceOver acceptance remain outstanding.

### `Menu` and `Toast`

Menus preserve the source hierarchy, including nested Profile Share actions. Toast variants are success, error, and information when source-backed. Toasts need a text/icon cue and accessible announcement; they cannot be the only persistent record of a critical error.

### `QRScanner` / `QRDisplay`

Scanner variants preserve camera view, guide, close, loading, and permission-denied behavior. The OS permission prompt remains system-owned. QR display uses an opaque white quiet zone and synthetic payload only; particles and translucency are `off` behind the code.

## SF Symbols semantic mapping

Use symbols by meaning and preserve the existing accessible label. Confirm availability against the eventual minimum iOS target; provide a bundled/vector fallback where necessary.

| Meaning | Preferred symbol |
|---|---|
| Home | `house` |
| Settings | `gearshape` |
| Back | `chevron.backward` (direction-aware) |
| More actions | `ellipsis` / `ellipsis.circle` |
| Add profile | `plus` |
| Scan QR | `qrcode.viewfinder` |
| Clipboard import | `doc.on.clipboard` |
| File import/export | `doc` / `square.and.arrow.up` |
| Refresh/update | `arrow.clockwise` |
| Sort | `arrow.up.arrow.down` |
| Share | `square.and.arrow.up` |
| Edit | `pencil` |
| Delete/reset destructive | `trash` |
| Logs | `doc.text` |
| About | `info.circle` |
| Warning | `exclamationmark.triangle` |
| Error | `xmark.octagon` |
| Success | `checkmark.circle` |
| Network/proxy | `network` |
| WARP/privacy setting | `shield` without a verified-protection claim |

## Content and localization rules

- Preserve source strings and punctuation; do not “improve” product copy during the reskin.
- Design in Russian and English, verify RTL mirroring in Arabic and Persian, and test long strings in French/Spanish. Include CJK line-height checks for Simplified and Traditional Chinese.
- Arabic/Persian layouts mirror spatial order; numeric addresses, ports, URLs, JSON, and code remain LTR.
- Use leading/trailing alignment rather than hard-coded left/right. Symbols with inherent direction must mirror; brand marks and QR codes must not.
- Avoid fixed-height text containers. Large text can reflow controls vertically while preserving the same action grouping.

## Accessibility contract

- Target 44×44 pt for interactive controls. Record any existing composition conflict in the gap log before changing layout.
- Measure text/control contrast over the worst visible particle and translucent-material point, including pressed, disabled, selected, warning, and error states.
- Define VoiceOver role, label, value, hint, and order for every interactive component. Decorative particles and redundant visual labels are excluded.
- Provide visible focus, selected, disabled, busy, error, and expanded/collapsed cues beyond color.
- Specify large-text layouts and safe truncation rules. Canvas review is design evidence only; runtime Dynamic Type and VoiceOver remain future implementation acceptance.

Fourteen static specimens now cover compact/baseline/large Home, 320 pt and 150% text settings, long strings, corrected Arabic RTL, Reduce Transparency, Increase Contrast, static Reduce Motion, 320 pt form errors, WARP large text, 430 pt server list, and a keyboard-inset system-zone fixture. They pass static layout checks with no unexpected content clipping. They do not convert VoiceOver, Dynamic Type, native semantics, system keyboard, or device behavior into runtime proof.
