# D5 read-only specialist preparation

Inspection only; no repository edits/commits. Current shared source inspected after D3 handoff; parent owns exact native provenance.

## Findings and narrow proposed visual diff

1. **Local Material color omissions are source-confirmed.** `BlizzardTheme.from` copies ColorScheme/scaffold/cardTheme but leaves `ThemeData.canvasColor` and `cardColor` from the legacy theme. Pinned Flutter `material.dart:460-461` resolves uncolored MaterialType.canvas/card using those two fields. Settings reset VPN row is an uncolored default `Material(child: ListTile(...))` at settings_page.dart around180, so a legacy rectangular backing can remain visible around the rounded eligible ListTile. Narrow fix: add `canvasColor: material.content` and `cardColor: material.content` to the LOCAL BlizzardTheme factory only. Keep global AppTheme unchanged. If native capture still shows a shape mismatch with the quiet scene, use eligible-only matching radius12/clip on this existing Material; no callback/row/tree replacement. Prefer testing the color correction before adding clipping.

2. **Profile card/inset ripple radii disagree.** Eligible Card is radius20, while content InkWell and ProfileActionButton's start/end radii still use ProfileTileConst radius16. This affects pressed/hover ink geometry, not payload/state. Narrow fix: derive eligible start/end `BorderRadiusDirectional` with radius20 and resolve against existing Directionality; preserve source radius16 outside eligibility. Apply only to the three existing interaction surfaces, retaining exact callbacks/showActionButton branch semantics and hit width48. Avoid globally changing ProfileTileConst, adding extra GestureDetectors, or clipping entire card before verifying why clip is necessary. Other new BlizzardSurface is purely DecoratedBox, so do not infer it clips descendant ink.

3. **Default gate is deliberately false and currently consistent.** Production `const blizzardVisuals = bool.fromEnvironment('BLIZZARD_VISUALS', defaultValue:false)`; home/visual fixtures use same environment key with implicit false. Native harness documents explicit `BLIZZARD_VISUALS=true` plus separate `BLIZZARD_VISUAL_CHECKS=true`. Approved plan line232 explicitly permits a separate default-true activation AFTER all relevant ON gates. Keep defaultfalse through those gates, then update fixture defaults and release provenance together with the intentional defaulttrue step; rerun explicitOFF, explicitON and ordinary flutter test and produce a new exact candidate. Current host tests on macOS remain ineligible even with true define; host green alone cannot prove iOS Blizzard rendering.

4. **D4 completeness cannot be claimed yet.** Explicit boundaries exist for General/WARP and already migrated inputs/confirmation, while source search did not find own boundaries for Routing/DNS/Inbound/TLS/Logs/About/Intro and remaining dialog family. Some may inherit a migrated ancestor; absence of explicit boundary is not proof of missing style. Before D5, inspect actual route/modal ancestry and run source-backed fixtures for these surfaces, especially root navigator dialog/theme-capture paths. Do not solve unverified D4 ownership by changing global AppTheme or bottom-sheet/dialog orchestrators.

## Required tests BEFORE production D5

- Add local-theme unit/style RED asserting eligible canvasColor/cardColor equal opaque material.content at normal/high contrast. Preserve `AppTheme.darkTheme` and ineligible theme identity/color fields for Light, Black, system-light, >=600 width, Android/macOS and default/false flag. Include Dark/system-dark narrow iOS as true cases on native runner.
- Mount actual SettingsPage reset VPN row; assert backing Material effective color matches eligible surface, inspect 393 and320 RU1.3 native captures for square corner exposure and contrast. Tap actual row with notifier spy and assert the same single reset action; do not execute real VPN reset.
- Mount actual ProfileTile active/inactive/main/menu in LTR/RTL; assert Card20 and content/action start/end ink20 only eligible, legacy16 otherwise. Capture pressed ink near outer corners. Verify same hit target bounds and source callbacks, selection immediate/late result behavior, share/delete/update menu order. Use existing fixtures/AST49 binding gate rather than inventing alternate UI.
- After any local BlizzardTheme factory change, run all previously prepared UI/visual/overlay invariants in OFF and ON variants, protected guard6/615, AST49/651 (or current parent-authoritative exact manifest count), analyzer delta; actual iOS native eligible subset is required. No new controller/schema/dependency/native tests or code are implied.
- Finish D4 explicit screen/transient inventory first; distinguish inherited styling proof, own local boundary proof and NOT RUN cases. Settings child routes and root overlays need fresh screenshots, not generic theme equality alone.

## Risks and limits

- Setting canvasColor affects every uncolored Material under a local boundary, including custom dialogs/menu content. Its wider *scoped* reach is why all overlay invariants are required; do not call this a one-row-only effect.
- Card radius20 correction can differ for RTL start/end halves; changing only entire Card clipping can hide ripples and produce separator artifacts.
- Normal and high-contrast material.content differ; tests should assert semantic material values, not one unconditional color.
- D5 should remain static. No animation/blur/timers/haptics are necessary to fix these omissions. Actual performance/VoiceOver/physical camera remain separately measured or NOT RUN.
- Native provenance must be frozen before capture. Do not use host platform overrides as equivalent to actual iOS execution.

No production changes made by this inspection.

## Additional actual-native search strip finding

Parent actual native D3 capture r2/016 shows the editor black search strip. Source `_SearchField` reads `searchBarTheme.backgroundColor?.resolve({}) ?? Colors.black`. Add only LOCAL `searchBarTheme: base.searchBarTheme.copyWith(backgroundColor: WidgetStatePropertyAll(material.control))`; legacy fallback stays in JsonEditor unchanged. The editor outer border derives `_themeColor` from ThemeData.primaryColor, which still retains the legacy alias under copyWith(ColorScheme). Proposed LOCAL `primaryColor: BlizzardPalette.accent` aligns that visual alias without touching editor business/controllers. Tests mount the actual editor under derived local Theme and independently assert observed strip color and outer border accent, normal/highContrast.
