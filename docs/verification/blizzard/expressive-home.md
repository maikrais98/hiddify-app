# Blizzard Home — expressive ribbon and blizzard

This visual variant replaces the previous subtle translation with an actual
deforming particle cloth, flowing icy highlights, a diffuse moving glow, and
450 irregularly distributed snow particles in three depths. UI structure,
texts, control geometry, routes, action bindings, preferences and VPN code are
unchanged. The gentle revision remains on `codex/blizzard-home-snowfall` at
`4712fd976283625a9a2b81ea04a4b357bbb30a25`; this variant is on the separate local
branch `codex/blizzard-expressive-home`.

## Motion and rendering

- A single 48-second phase drives periodic effects: a main 12-second cloth
  swell (up to 22 points with a quieter center), a counter-fold every 6 seconds
  (8 points), and 11-point lateral undulation. The surface changes shape rather
  than moving as a rigid picture.
- A broad 8-second light crest and a softer counter-light modulate the dots
  through icy blue, pale periwinkle and near-white. Glow fades naturally into
  the background. A discovered straight glow cutoff was removed and covered
  by a RED/GREEN pixel-continuity regression.
- The existing 144 × 72 particle cloth is rasterized once per size/DPR into a
  transparent, cropped image. A 24 × 12 textured triangle mesh provides motion.
  Mesh topology and texture coordinates are prepared once. Each frame updates
  325 vertices and their colors; it does not recalculate 10,368 dots. DPR is
  capped at 3 for the decoration. Picture, image, image shader, gradient shader
  and vertices have explicit resource lifetimes.
- 300 far, 120 middle and 30 near flakes share stable irregular seeds. Their
  vertical speeds at an 852-point scene are approximately 11 / 23 / 34 points
  per second, with smooth 8-second gusts. Near flakes have faint halos and
  short trails. Horizontal/vertical wraps fade out; status and latency retain
  their central quiet zone. No flashing, connection-state promises or moving
  readable data were introduced.
- Existing accessibility/lifecycle rules are preserved: quiet/off are static;
  disableAnimations, accessibleNavigation and highContrast use the existing
  opaque off fallback. TickerMode=false and lifecycle other than resumed stop
  motion. Resume retains phase without a background time jump. Decoration is
  IgnorePointer and ExcludeSemantics.

## Acceptance evidence

- Before implementation, the luminance/flow test failed on the gentle source:
  ribbon light score 375 versus the required >3,000. The enhanced rendered
  ribbon passes; the light distribution moves between surface regions within
  two seconds. The separate glow-edge regression failed at a 1.90-level blue
  discontinuity, then passed after the glow was moved outside the mesh clip.
- **366/366 local Flutter tests pass**, including thirteen scene motion tests.
  The cache test verifies the actual ribbon image identity across frames, a
  smaller cropped allocation, Size/DPR invalidation, old-image disposal and
  accessibility/disposal cleanup. The prior test that selected the static
  background was replaced, as requested by independent review.
- Changed-file Dart analysis: **no issues**. Existing source preservation:
  **49 files / 651 exact state/action bindings**. Runtime/native/dependency
  boundary: **6 tests / 615 assertions**, all passed.
- Final native iOS Simulator run passed both real Home cases: 393 points at
  normal text size and 320 points at 130% text size. Rendered motion is visible,
  control bounds stay fixed, one tap issues exactly one toggle, Settings stops
  the clock, returning to Home resumes it, and fixture cleanup passes.
- Debug-simulator measurements during each 12-second observation: 716 frames
  per case; build p95 **2.335 / 2.313 ms**, raster p95 **1.727 / 1.877 ms**.
  These are simulator samples, not a physical-phone battery/performance claim.
- Independent code review found coherent resource disposal and loop phases.
  Its cache-test and immutable-topology findings were addressed. Independent
  visual review of native frames confirmed deformation/light movement and
  readability, including the compact enlarged-text case. Root review then
  identified and removed the faint glow cutoff described above.

Receipts and exact source-file hashes are in [expressive-home](expressive-home/).
The sibling workspace folder `blizzard-expressive-home` contains the final
full-resolution native MP4, GIF preview, phase snapshots and native before/after
captures. All VPN/profile data in these artifacts are synthetic. GIF is a
15-fps review copy; the original native recording preserves the capture frames.

This variant is local and has not been pushed, signed or uploaded. TestFlight
0.0.1 (2) remains unchanged. Physical iPhone smoothness and battery cost are
pending the next installed build. No VPN traffic or physical device was used
for this visual verification.
