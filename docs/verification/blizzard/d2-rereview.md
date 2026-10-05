# D2 independent re-review — 5b86ad93 plus test-only working diff

Reviewed .superpowers/sdd/review-15fec6f9..5b86ad93.diff, worker report, current test-only translations import/format correction, motion contract implementation, ten-server fixture and source notifier inheritance. No production edits and no suites rerun.

## Findings

Critical: none.
Important: previous TypeAhead decoration finding is closed at source level. Eligible suggestions explicitly set computed scoped surface, transparent tint and row radius12. Inactive decorationBuilder remains null, preserving the installed package's original Material/card/elevation4/radius8 defaults. All input/controller/focus/filter/selection/validator/route callbacks are unchanged. The actual-iOS RED receipt supplied by parent is consistent with the prior source diagnosis. Final native GREEN is not yet claimed.

Minor — Settings reset row retains a visible legacy rectangular backing. Native d2-pilot/031-SettingsPage-dark-en-393-0-1-0-ltr-false.png shows darker square corners around Reset VPN profile whereas adjacent rounded rows reveal the page background. settings_page.dart retains Material(child: ListTile(...)) around that row; the bare Material resolves canvasColor, which scoped BlizzardTheme does not replace. Its opaque square backing therefore remains legacy below the rounded tile ink. This does not affect behavior/hit regions but is a small visual polish inconsistency. If corrected, make only eligible Material backing transparent or match page background; preserve inactive exact old Material. Do not alter callbacks.

## Evidence assessment

- Motion replacement is sound: the removed assertion over every ImplicitlyAnimatedWidget conflated framework-owned color/text transitions with app-owned spatial motion. New tests inspect real connection Animate/AnimatedText/Tween durations and actual scale geometry, and NavigationIndicator transform progress. Non-reduced mode is an explicit sensitivity control, reduced mode requires immediate settled geometry. Fixture event assertions retain connection callback/no-op behavior.
- Ten-server test is materially stronger than empty group screenshots. It constructs ten actual ProxyTile children, scrolls all labels into hit-testable positions at320/393 and scale1.3, taps row10, verifies native-boundary fake selection tuple and selected notifier state, then checks the real test-delay forwarding. SurfaceProxies overrides only build; original action methods execute through real ProxyRepositoryImpl. This does not establish long-press/sort or >1.3 accessibility scaling; those remain separate coverage.
- Final working diff only adds missing translations import and formatter wrapping. No test expectation weakened there.
- Viewed actual Settings031, WARP003 (320/en/1.3/highContrast) and Confirmation030 PNGs. Content is readable in these frames, WARP disabled state remains visibly distinct, dialog actions fit. WARP screenshot is a partial scrolled-list viewport, not evidence that every lower row is reachable; the navigation selected state in synthetic screenshots is fixture state, not proof of production routing correctness.
- The only inspected corrections manifest currently has source5b86ad93, unchanged tree hash, testExit1 and no frames. Parent said final targeted native run is in progress. This review must not be described as a native all-pass result.

## Remaining gates and verdict

No remaining Important source defect in the correction. Code is acceptable for the next implementation stage conditional on successful final targeted actual-iOS corrections and D2 acceptance recorded by parent. The minor reset-row backing is noted separately; it need not trigger unrelated theme refactoring.

Do not declare blanket D2 visual/native PASS from this review. Original 34PASS/1FAIL receipt was a failing motion assertion before test correction; host63/63 off/on proves inactive-host behavior, not eligible native pixels. Retain pending native suggestion material, non-reduced/reduced motion sensitivity and nonempty ten-server acceptance. Larger text with both delay/download marker remains an explicitly unverified ListTile trailing-height edge from the first report; physical VPN/performance/release evidence is outside this review.
