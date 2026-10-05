# D5 independent source review — 13760336

Verdict: SOURCE PASS. No Critical/Important finding identified in a78d39ab..13760336. This source verdict alone does not authorize declaring final native/shared-theme acceptance or default-on verification complete; current native/full host results remain parent-owned gates.

## Production review

Exactly three production files, limited to material aliases and ink/clip properties. BlizzardTheme.from now copies opaque content into canvasColor/cardColor, accent into primaryColor and opaque control into searchBarTheme.backgroundColor. These updates are confined to the existing local factory; AppTheme/global legacy and defaultfalse remain unchanged. Existing eligibility still excludes Light/Black/wide/non-iOS. High-contrast aliases use the same semantic opaque materials as colorScheme, avoiding a split between old Material consumers and newer themed widgets. No state/provider/storage/router/action changes.

Profile content ink now matches the20 card with full radius when no action, directional end radius with action; update/menu ink gets directional start radius. BorderRadiusDirectional.resolve correctly reverses edges in RTL, matching Row's original action placement. Every ineligible branch retains the exact prior16-radius helper. Widgets, predicates, callbacks, hook positions, semantics and48 action width are unchanged.

Existing iOS reset Material gets eligible radius12+antiAlias clipping only. Inactive null/Clip.none is literal; onTap/provider call remains exact. Clipping affects paint around an already rounded row, not route/results or enabled state.

## D4 dropdown minor closure

Source closure confirmed for the material-color mismatch: pinned SDK dropdown.dart:331–332 paints DropdownButton popup from dropdownColor ?? Theme.of(context).canvasColor. Logs specifies no dropdownColor; the newly copied scoped canvasColor therefore makes its popup opaque Blizzard content. The original small4 radius remains; this is a minor surviving visual detail, not a blocking functional/readability issue. Actual updated menu pixels should be included in final D5 visual evidence before claiming full pixel closure.

## Tests and fixtures

Reviewed prepared material contracts: actual resolved Material paint, JSON strip/outline consumers, profile ink in LTR/RTL and Dark/Light/Black, main local/remote profile geometry and reset one-call spy. These are meaningful consumer/behavior checks rather than merely token equality. Supplied RED provenance19PASS/8RED host and10PASS/17RED native supports sensitivity; supplied focused37PASS includes AST. No reruns here.

Both fixture helpers now set real renderer width and assert captured canvas Size(width,852); requested width can no longer be satisfied only by MediaQuery while its rendered frame is clipped. Surface reset is registered for teardown. Existing geometry/action expectations are retained. Accessibility expansion adds four settings families to the prior two over the same3 widths×3 locales; it strengthens coverage. Exact viewport changes can reveal previously hidden failures, so pending full results remain necessary.

Defaultfalse is unchanged. If parent proceeds with separately authorized defaulttrue after relevant GREEN gates, explicitOFF/ON/default runs and source/artifact provenance need the activation commit, not this earlier source SHA. Physical camera/VPN lifecycle/performance/release remain separate and unproved by these widget tests.

Read-only: inspected exact diff, worker report, existing material tests and pinned SDK dropdown source. Wrote only this temporary review. No repository/device/Apple/production mutation.
