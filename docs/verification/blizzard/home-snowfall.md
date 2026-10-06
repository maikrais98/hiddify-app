# Gentle snowfall on Blizzard Home

Historical gentle revision `4712fd976283625a9a2b81ea04a4b357bbb30a25`.
The current expressive variant is documented in [expressive-home.md](expressive-home.md).

The Dark iOS Home now has slow ambient snow and a slight sway of the existing
particle wave. Connection controls, text, profile content, routes, callbacks,
preferences, VPN runtime, native identities and release configuration are unchanged.
The existing Blizzard eligibility gate still controls which themes/platforms use
this scene. Quiet and off presets remain static.

## Motion specification

- A single 48-second linear controller drives two particle depths. Far flakes
  travel once per cycle, near flakes twice; their approximate vertical speeds
  at an 852-point scene are 11 and 23 points per second.
- 130 deterministic particle seeds, radius 0.55 / 1.05 points, maximum opacity
  0.12 / 0.24. Vertical wrapping fades to zero. Status/latency retain their quiet
  central zone; text and actionable content stay stationary.
- The original 10,368-dot wave is an independent RepaintBoundary, retained as
  AnimatedBuilder.child. Only its transform changes: up to 5 points horizontally
  and 2 vertically, on smooth 24 / 12-second sine cycles. Snow has its own
  repaint-listenable painter. No shaders, blur, dependencies or application
  providers were added.
- TickerMode=false and any lifecycle other than resumed stop the controller.
  Resuming preserves its phase, excluding elapsed background time.
- disableAnimations, accessibleNavigation and highContrast preserve the
  existing opaque off fallback, with no ambient clock. Decoration retains
  IgnorePointer and ExcludeSemantics. Disposal releases the ticker.

## Verification

Tests preceded production changes. The static source failed all eight tests
that required motion/resumption; quiet and off passed. Final verification:

- **364/364** local Flutter tests passed, including eleven new pixel, pause,
  resume, disposal, hit-test and paint-layer tests. During ten moving frames,
  the wave retains the same recorded Picture and does not repaint with its parent.
- Changed-file Dart analysis: **no issues**.
- Existing preservation checks: **49 files / 651 exact state/action bindings**;
  runtime/native/dependency boundary: **6 tests / 615 assertions**, all passed.
- Real iOS Simulator renderer, separate disposable host without a VPN extension:
  Home at 393 points with normal text, and 320 points with 130% text. Rendered
  frames differ, control geometry remains fixed, one tap issues one toggle,
  Settings stops the clock, returning to Home resumes it. Both cases passed.
- Independent source review found no critical or important issue. Its cache
  verification request is covered by the retained-Picture test above.

The first fully-live native test received an iOS-owned semantics handle after
the test's initial snapshot. The optional fixture now renders a blank app in
setUpAll before the snapshot; its diagnostic confirms platform_semantics=true
and one platform handle. Normal end-of-test leak checks remain enabled. The
native rerun passed; production accessibility code was unchanged.

Logs and source file hashes are in [home-snowfall](home-snowfall/). Source starts
from exported TestFlight commit `6aa9477e98f84757b22451a12890bed898d89b84` on
`codex/blizzard-home-snowfall`. All motion changes are local; no new upload or
release was performed. The existing 0.0.1 (2) TestFlight build remains static.

The sibling workspace folder `blizzard-home-snowfall` contains full-size native
before/after frames and `home-snowfall-native.mp4`, a 6.87-second screen recording
at 1206 × 2622. All displayed VPN/profile data are synthetic. The video and its
poster were inspected; this is UI proof, not proof of VPN traffic. Physical
iPhone smoothness, battery cost and device lifecycle remain to be checked with
the next installed build. No quantitative CPU or battery claim is made.
