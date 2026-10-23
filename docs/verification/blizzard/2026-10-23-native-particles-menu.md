# Native particles and interactive menu

Scope: the Home vortex and full-screen snowfall requested after build 23, plus the native Apple tab-bar interaction shown in the Tihasloy reference. Settings group/row spacing stays intact; its scroll inset now protects the final action while content paints behind the floating menu.

## Implementation and observed checks

- The vortex uses independently flowing procedural particles rather than rigidly moving a PNG with a button-shaped cutout. Snowfall belongs to the full-screen shell and pauses outside Home.
- A dedicated interactive `UITabBar` platform view owns iOS touches, native accessibility, and the selection lens. The existing decorative glass component is unchanged. Flutter/GoRouter remains the navigation authority, including selected-tab reactivation.
- Measured native layout needs an 88-point platform-view slot plus a 12-point external bottom inset. The former 64-point slot caused overlapping icons and titles. No overflow or clipping workaround is used. The non-iOS dock retains its previous geometry.
- Exact copied candidate control/bridge sources passed 10 native XCTest cases and a real UIKit gesture test with five asserted events: selection, reselection, return, drag, reverse drag. Evidence and SHA256 bindings are preserved outside the repository in `review-evidence/2026-10-23/blizzard-native-menu-gestures`.
- iOS integration: 8 tests passed, including screen-edge snowfall, stable Home controls, compact/large screens, large text, Settings painting beneath the dock, scrolling the final Settings action above the dock, and the actual footer background pixel color on nested Home routes. The Settings-under-dock assertion first failed at 752 = 752 before the scoped `extendBody` change, then passed. Native pixels also reproduced a new card-blue footer band before explicitly setting the shell Material to the dark background; that regression is now green.
- Full Flutter suite: 900 passed, 5 platform skips. Changed-file analysis found no issues. The capture adapter tests pass with separate exact production and QA registration contexts.

## Capture and evidence boundaries

Capture uses a regular QA host without VPN, with the exact candidate Swift source and separately hashed QA registration adapter. Fixture metadata, navigation callbacks, and lifecycle input remain synthetic. Real UIKit gesture evidence is recorded separately. Capture completion does not itself constitute visual approval, TestFlight delivery, or physical-device VPN traffic proof.

The prior failed capture at source `266df33f` remains failed and unmodified. The new two-phase acknowledgement protocol waits for native screenshot completion, aborts on a terminal failure, and defers video decoding until the UI driver exits. A fresh clean-source compositor capture and independent visual review are required for release.

The subsequent `b1c3dc0f` capture produced all images/videos with Flutter exit 0 but failed strict frame timing (1.011 seconds between Home I/O starts). It is not release evidence. A tested two-worker scheduler now starts the second native screenshot request at the measured 600 ms deadline without waiting for the first file to finish saving; terminal acknowledgement still requires both captures to succeed. The strict 0.55–0.75-second validator is unchanged. Python capture contracts: 31 passed, including delayed-first-capture and failed-capture cases.

## Existing legacy gate debt

The old runtime-boundary suite compares against `0830294e` and already has stale diagnostics/telemetry fingerprints and additions from released build-23 source `19092ea5`. The affected production files were compared byte-for-byte with that released source and are unchanged by this work. Only the three reviewed native UI fingerprints were updated here; the focused native-boundary contract passes (17 assertions). No blanket fingerprint refresh or unrelated diagnostics/VPN edit was made. This legacy full gate is not reported as passing.
