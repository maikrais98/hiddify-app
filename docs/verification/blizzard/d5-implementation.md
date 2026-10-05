# D5 opaque materials and ink geometry implementation

Base a78d39ab; changes only three assigned production files, 25 insertions / 4 deletions. No tests/index/commits/dependencies/native/controller changes. Production source FROZEN.

## Exact changes

- `lib/core/theme/blizzard_theme.dart`: LOCAL copied ThemeData canvasColor/cardColor=semantic opaque content; primaryColor=accent; searchBarTheme.backgroundColor=semantic opaque control. Preserves base/global AppTheme and compile-time defaultfalse. JsonEditor existing fallback and callbacks are untouched; its actual consumers now receive correct local aliases.
- `lib/features/profile/widget/profile_tile.dart`: eligible existing InkWell content full radius20 or directional end20; existing remote-update/menu action directional start20. Existing source radius16 outside eligibility. Same widgets, callbacks, provider reads, branches, semantics, positions and hit widths.
- `lib/features/settings/overview/settings_page.dart`: existing iOS reset row Material receives eligible radius12 and antiAlias clip. Legacy null radius/Clip.none preserved. Color inherits corrected local canvasColor. Original reset callback exactly unchanged.

## Evidence and gates

Before production, prepared D5 tests saw host19PASS/8expectedRED and parent native27cases10PASS/17expectedRED; source provenance a78d39ab and parent manifest unchanged.

Focused analyzer on current three files: **No issues found** (`/private/tmp/d5-analyze.log`). Exact a78d39ab three-file baseline extracted read-only with resolved package config: **No issues found** (`/private/tmp/d5-analyze-baseline.log`). Analyzer delta0. `git diff --check` PASS. Reviewed diff contains only requested material/border properties plus one token import.

Parent requested to execute targeted27 OFF/ON plus binding suite using root local-loopback permission; result pending at report creation. Parent owns full shared-theme regressions, native actual-iOS GREEN capture and freeze/commit provenance. No host result is represented as eligible iOS proof.

## Remaining boundaries

Defaultfalse remains unchanged. Plan232 separate defaulttrue activation is parent-owned only after relevant gates, followed by explicitOFF/ON/ordinary tests and new exact artifact provenance. Physical camera/traffic acceptance and release remain separate; none performed here.

Parent focusedON37/37PASS (27materials+10AST); nativebefore27cases10PASS/17expectedRED. FullOFF/ON and strengthenedactualviewports/all6Settingsa11y underway.
