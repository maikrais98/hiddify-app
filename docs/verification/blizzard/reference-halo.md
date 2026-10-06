# Blizzard Home — reference halo and soft blue glass

Local visual iteration from `a2485fb40d410882a291f2cb648824cf7c87830c`,
on `codex/blizzard-reference-halo`. The user's screenshot is the visual target:
a contained cyan particle cloth around a deep blue rounded-square control,
with the existing Hiddify mark. No release, signing, upload or phone installation
was performed. TestFlight remains unchanged.

## Visible result and preserved behavior

- The oversized pale cloth becomes a contained cyan halo, roughly 74% of the
  scene width. Its section tapers smoothly toward both ends, reducing sharp
  protrusions. A brighter upper-left fold supplies the reference's light accent.
- A cached 216 × 96 point field uses small dots with local crest emphasis.
  A 24 × 12 mesh deforms it; its broad swell has a 16-second period. Cloth,
  opposing numeral streams and snow retain the same shared 48-second clock.
- The 96 decorative numerals become quieter and remain secondary to the cloth
  and control. The atlas contains all digits 0–9. These are decoration, not
  traffic, addresses, connection status or measured latency.
- The button uses a 40% deep blue tint, a soft diagonal highlight, 3.5-point
  backdrop blur, the existing 1.055 background magnification, and one soft
  0.75-point edge. The dock retains its existing clear material.
- The existing `assets/images/logo.svg` replaces the Blizzard power icon. The
  148 × 148-point hit target, 44-point corner radius, padding, state semantics,
  enabled state and callback stay unchanged. The seasonal image branch stays
  unchanged. No new asset, font or dependency was introduced.
- `_BlizzardSnowPainter` is byte-identical to the parent. Profile, connection
  caption, latency, footer, navigation, settings and theme eligibility retain
  their current layout and behavior.

## Verification

- The initial native reference contract failed on both widths because the
  existing Hiddify SVG was absent. The final native cases verify that exact asset.
- The dense-cyan crest test was checked against the exact parent scene in a
  temporary test-only copy: **0** qualifying cyan pixels versus a required
  >1,000. It passes with the new scene. Temporary comparison files were removed.
- Visual review found pointed cloth ends and a weak upper-left light accent.
  Before correcting these, the added bright-crest assertion failed with
  **63** pixels versus >150. The final tapered shape and brighter fold pass.
- The 55% tint / 6-point blur review version suppressed changes in the native
  button-face sample below its required contrast. The final 40% / 3.5 material
  passes the original **>120 moving pixels** assertion on both widths; that
  threshold and sample region were not weakened.
- **375/375 Flutter tests pass.** Focused verification passes **32/32**:
  16 scene contracts, six glass contracts and ten binding guards. Rendered color
  transmission, unchanged target size, lifecycle pauses, cached resource reuse
  and disposal, and exact 48-second rendered loop closure are covered.
- Preservation guard: **49 files / 651 exact state/action bindings**. Runtime,
  native identity, dependencies and pipeline boundary: **6 tests / 615 assertions**.
- Changed decoration and tests analyze without issues. The connection source
  retains the same eight pre-existing diagnostics as the parent; the comparison
  is saved in the receipt folder. No neighboring warning cleanup was performed.
- Final native iOS Simulator cases pass at **393 points**, and **320 points with
  130% text**. They check SVG identity, visible moving light through the face,
  unchanged geometry, exactly one toggle, Settings pause, Home resume and
  fixture disposal, using synthetic VPN/profile data.
- During each 12-second native debug-simulator observation: **719 / 720 frames**;
  build p95 **1.460 / 1.264 ms**, raster p95 **3.194 / 3.046 ms**. These are local
  simulator samples, not physical-device smoothness, battery or VPN evidence.
- Independent code review checked cache/resource lifetimes, periodicity and
  snow preservation. Its numeral tangent observation was corrected. Independent
  visual review passed the final ordinary/compact captures: the right edge is
  softer, the upper-left accent is stronger, and no new overlap, mesh seam or
  clipping was found. The crest remains softer than the static reference.

The narrower reference halo is tested at the actual 614-point Home scene height
and 2× capture scale with an opaque control present. Its broad-coverage minimum
is >260 logical columns, reflecting the reference's contained width; the
>1,200 bright-pixel requirement is retained across three phases.

## Material and delivery limits

This is a **custom Flutter glass treatment**, not native UIKit Liquid Glass.
It filters the moving scene behind the control and adds tint and an edge;
it does not claim Apple's native optical behavior. High contrast, accessible
navigation and disabled animations retain the opaque, unfiltered fallback.
These Flutter signals do not prove iOS Reduce Transparency support. Native
material adaptivity and physical-phone performance remain unverified.

The updated source, exact hashes, snow preservation, analyzer comparison and
native receipt are in [reference-halo](reference-halo/). Native verification
ran from the reviewed working tree; its parent and exact content hashes identify
the source independently of the subsequent local checkpoint commit.

The sibling workspace folder `blizzard-reference-halo` contains a **9.65-second
native MP4**, a **142-frame / 15-fps GIF** review copy, full-resolution frames at
1/3/6 seconds, and native before/after captures. The GIF repeats a short excerpt,
not the entire 48-second animation period. Test fixtures label their data as
synthetic. Earlier RED, glass and contour review outputs remain separately
archived; none is presented as the final result.
