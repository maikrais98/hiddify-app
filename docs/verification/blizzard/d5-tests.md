# D5 tests-only preparation

Owned added file: `test/visual/blizzard_material_contract_test.dart`.
Registration: `registerBlizzardMaterialContracts()`; parent owns integration runner registration.
27 tests prepared before D5 production changes. No production files edited by this task. Test source FROZEN.

## Coverage

- Four host-executable actual physical paint cases: uncolored MaterialType.canvas/card under LOCAL BlizzardTheme.from, normal/highContrast; assert resolved PhysicalModel/PhysicalShape color equals opaque semantic content. Original AppTheme object remains separate.
- Two actual JsonEditor search-strip cases: nearest real ColoredBox around search icon must equal semantic control, normal/highContrast. Existing source fallback currently paints black.
- Two actual JsonEditor outline cases: real outer DecoratedBox border must use accent, normal/highContrast. Source reads ThemeData.primaryColor; proposed local alias fix is tested at actual consumer.
- Twelve actual ProfileTile cases: active/inactive, LTR/RTL, Dark/Light/Black; Card radius and both split InkWell radii align20 eligible,16 legacy; action width48, no VPN events.
- Three actual SettingsPage cases: Dark/Light/Black. On real iOS, reset row's nearest backing Material has eligible radius12 and clipping, semantic content, then a tap calls overridden reset notifier exactly once. Host asserts source-gated reset is absent and spy calls0. No real tunnel operation can occur in this fixture.
- Four actual main ProfileTile cases: local full-card InkWell and remote split update InkWell, LTR/RTL; radius20 eligible/16 legacy; remote tap invokes exact ID once via existing TileUpdateSpy.

## Observed RED and checks

Parent first targeted run of original20 tests: **12 PASS / 8 expected RED** (`/private/tmp/blizzard-d5-material-red.log`). All8 failures are actual color mismatches, not compilation/harness errors:
- canvas/card legacy backing #121318 vs content #102235 (normal) or #06121D (highContrast);
- editor search strip #000000 vs semantic control #19374C (normal) or #102235 (highContrast);
- editor outline #121318 vs accent #72D1FF.

Added7 cases await parent's fresh targeted run and actual iOS runner. Native eligible card radii/reset cases are deliberately conditional on real PlatformUtils.isIOS/fixture eligibility; passing macOS cases is not claimed as native proof.

Final analyzer: **No issues found** (`/private/tmp/d5-test-analyze.log`). Format and diff-check clean. Duplicate escalated test request was canceled before launch after parent confirmed its authoritative run.

## Production proposal these tests precede

Only local BlizzardTheme fields canvasColor/cardColor=material.content; primaryColor=accent; searchBarTheme backgroundColor=material.control. Eligible ProfileTile content/action start/end radius20 and Settings reset backing radius12/clip preserve legacy branches. No controllers/providers/schema/native/dependencies modified.

Plan232 default activation remains authorized as a distinct step AFTER relevantON gates: keep defaultfalse during this RED/GREEN slice, then intentional defaulttrue plus fixture consistency, explicitOFF/ON/ordinary tests and new exact artifact provenance. No default activation is implemented in this tests-only work.

Parent final27 host19PASS/8expectedRED; actualiOS a78d39ab27 cases10PASS/17expectedRED, source unchanged during run. All failures map to real material/search/outline/ink/reset differences; no harness/compiler failures. Production correction starts only after this receipt.
