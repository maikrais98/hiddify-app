# D5 focused re-review — a87da1e9

Verdict: SOURCE/FОCUSED-FIX PASS. Important typography mismatch is resolved by the reviewed two-field role fix and supplied38/38 OFF/ON consumer tests. Full native B-IOS transition and broad suite remain required before default activation/final completion.

## Typography

Production diff only adds inherit:false and textBaseline:TextBaseline.alphabetic to the complete role constructor. False fixes actual TextStyle.lerp inheritance mismatch. Alphabetic is necessary once roles no longer merge missing baseline from inherited Material text styles; matches pinned Flutter Typography and satisfies ListTile/InputDecorator baseline contracts. All chosen fonts/sizes/weights/heights/colors, codeStyle, global theme and defaultfalse are unchanged. No state, callback or runtime migration.

New test mounts actual Material/ListTile/TextField/TextButton and switches the same Theme subtree both ways, samples five50ms frames after each change, checks exceptions and retains draft/controller/focus identity. It reproduces the real consumer class of failure without platform spoofing or remounting, and is registered natively. Source is strong narrow regression coverage; one reporting correction: the fixture initializes AppTheme.dark and darkTheme, so this host test proves legacy DARK↔scoped Blizzard typography, not LIGHT↔Dark as the worker report says. The actual B-IOS test is still the required light→dark root-animation evidence. Selection offset and explicit final style assertions would strengthen the isolated test, but their absence does not negate current exception regression or existing draft tests.

## Fixture corrections

The main ProfileTile test now adds56px top padding only around its isolated child. Pinned scaffold.dart1276–1278 places statusBar hit area at y0 with minInsets.top height, and3160–3164 gives it an opaque GestureDetector on iOS/macOS. A standalone card's tap center near local24 was inside native top62; after padding it is near80, below the intercepted region. Production Home already has an AppBar and is untouched. Radius/RTL/action-count expectations remain unchanged. This is legitimate isolation-fixture placement, not evidence of production Home card y geometry; retain separate fullHome actual action coverage.

Two profile-import cleanup pumps occur only after all preservation assertions, removal of app subtree and toastification.dismissAll. They advance package teardown timers without changing actions, return values, callbacks or assertion timing inside tested user flows. No exceptions are swallowed and no product behavior assertions removed. This does not repair or disguise a production import callback failure.

Read exact13760336..a87da1e9 diff, worker report and pinned SDK evidence. Accepted supplied38OFF/ON PASS and analyzer0; did not rerun suites. Pending full native results must remain honestly pending. No repository/device/Apple/production edits; wrote only this report.
