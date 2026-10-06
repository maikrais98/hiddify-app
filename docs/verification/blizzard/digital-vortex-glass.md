# Blizzard Home — digital vortex and clear optical controls

Local visual iteration from `ce091607c93b34840a1c55abecd8c302db709273`,
on `codex/blizzard-digital-vortex`. The accepted expressive snow revision stays
on its existing branch. No build was signed, uploaded or installed on a phone.

## Visible result

- The cloth center rises from 36% to 28% of the Home scene height. Its main
  width grows from 80% to 96%, and cross-section from 19% to 28%. Larger folds
  expose a broad luminous surface above and beside the unchanged control.
  Soft top/bottom fades replace the former rectangular mesh clip.
- Two opposing curved streams carry 96 rotating decorative numerals. They are
  independent of connection status, addresses, traffic or measured latency.
  A tiny atlas is rasterized with the cloth cache; one atlas draw call moves
  the glyphs without per-frame text layout. All layers share the original
  48-second clock and its lifecycle/accessibility gates.
- The accepted `_BlizzardSnowPainter` is byte-identical to the parent. Existing
  profile, status, latency, footer and navigation layout remain in place.
- The connection control and dock use a new clear optical treatment. The old
  opaque button gradient is removed. A 1.6-point backdrop blur, 1.055 background
  magnification on the button, low tint, and two specular edges show the scene
  through the control. Its old cyan halo drops from 20% to 8% opacity. The
  action remains 148 × 148 points with the same icon, semantics and callback.

## Material interpretation and limits

This is a **custom Flutter optical material, not UIKit's native Liquid Glass**.
It follows the [Apple Materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials)
on using highly translucent Clear material over rich visual backgrounds and
keeping content surfaces readable. Dense content cards, forms and lists retain
their existing opaque materials. Glass adds no gestures, provider reads or
ambient ticker; background motion supplies its changing light.

The dock keeps the original Scaffold layout and safe areas. Its background is
flat, so it has a clear surface and specular outline but does not reveal the
moving Home scene underneath. No body expansion or content repositioning was
introduced to produce that effect.

High contrast, accessible navigation and disabled animations use a conservative
opaque, unfiltered fallback. These are Flutter signals, **not proof of reading
iOS Reduce Transparency**; the pinned MediaQuery API exposes no dedicated flag
for that setting. Native Apple material adaptivity, curved refraction, system
Reduce Transparency, phone smoothness and battery cost remain unverified.

## Verification

- Before changing the cloth, the new rendered upper-area test failed: only
  43 bright pixels versus a required >1,200. It now passes at three phases,
  including broad visible coverage, with an opaque 148-point control present.
- Before changing the button, both native cases failed the transparency test:
  material alpha was 1.0. Final native tests verify a translucent material and
  >120 changed pixels of moving light on its face, away from the icon.
- **373 local Flutter tests pass**, including 15 scene-motion contracts and
  five glass contracts. Color transmission is measured from rendered pixels;
  opaque fallback, legacy bypass, unchanged hit size, one tap, cached image
  identity/disposal, paused phases and exact 48-second rendered-loop closure
  are covered.
- Preservation guard: **49 files / 651 exact state/action bindings**. Runtime,
  native identity, pipeline and dependency boundary: **6 tests / 615 assertions**.
- New/changed decoration and tests analyze without issues. The connection
  source retains the same eight pre-existing diagnostics as `ce091607`: two
  unused imports and duplicate unreachable switch cases. They were left
  unchanged; the diagnostic comparison is saved in the receipt folder.
- Final native iOS Simulator cases pass at **393 points** and **320 points with
  130% text**. Exact button size, single toggle, stationary geometry, Settings
  pause, Home resume and fixture disposal pass using synthetic VPN/profile data.
- During each 12-second debug-simulator observation: **720 / 721 frames**;
  build p95 **1.435 / 1.424 ms**, raster p95 **3.079 / 3.145 ms**. These are local
  simulator samples, not physical-device or VPN-traffic evidence.
- Independent code review checked cache/resource lifetimes, periodic phases
  and snow preservation. Its Stack sizing and effective halo observations
  were addressed. Independent native-frame review passed five phase/compact
  captures: the larger cloth and numerals are visible, glass is clearer, and
  no new text overlaps, mesh seams or straight glow cutoffs were found.

Exact source hashes, native result, analysis parity and snow preservation are
in [digital-vortex-glass](digital-vortex-glass/). Local logs are alongside this
document. The sibling workspace folder `blizzard-digital-glass` contains the
final 9.78-second native MP4, 15-fps GIF review copy, full-size phase frames and
native before/after captures. The GIF loops a short review excerpt, not the
entire 48-second animation period. Earlier review/RED captures are retained
separately. TestFlight **0.0.1 (2)** remains unchanged.
