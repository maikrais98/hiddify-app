# D3 independent source review — 85c67a08

Verdict: CHANGES REQUIRED. Critical: none. Important: one concrete legacy-layout regression.

## Important — Restore tight legacy toolbar spacer

`lib/features/profile/details/json_editor.dart:811` replaces original `Spacer()` with `Flexible(flex: blizzard ? 0 : 1, child: const SizedBox.shrink())`. Flexible defaults to FlexFit.loose, whereas Spacer uses Expanded/tight. On an ineligible bounded toolbar with spare width, the zero-size child consumes none of that space. Format/Copy/search/custom actions therefore move left instead of retaining their original right alignment. This affects Light/Black/flag-off/desktop and violates explicit legacy preservation. The fixed-width legacy ConstrainedBox does not correct the loose child's width.

Keep stable wrapper and eligible zero-flex approach, but restore tight fit for the positive legacy flex (e.g. explicit FlexFit.tight; zero-flex eligible is still laid out as a non-flex child). Verify real control x positions in a wide ineligible toolbar before/after, not merely callback equality or absence of overflow. No production/test edits made by reviewer.

## Other inspected changes

- Six production files only in scoped package. Whitespace-insensitive source comparison shows original profile async mutation/onFailure/onSuccess, immediate pop and late mounted/canPop sequences retained. Action, share/update/delete, field validation and route callbacks preserved.
- Theme wrappers are structurally unconditional. Hooks/controllers remain owned by their original widgets; editor toolbar ScrollView/LayoutBuilder likewise stays mounted across eligibility changes. Existing UniqueKey choices are unchanged rather than introduced. New draft test meaningfully checks controller/focus identity, selection, content and event count across dark→light; real native results remain pending.
- JSON tree/code style13, row48/legacy30 and minimum44 controls are explicitly eligible. Original checkbox/dropdown scale and visual density retained outside scope. Search offset uses the same row metric, captured before the pre-existing delayed callback; no new asynchronous context read. `_themeColor` getter is paint derivation, not controller replacement.
- Output QR data, width, backgroundColor default white and optional-message predicate preserved. Scanner first.rawValue extraction, nonnull pop, permission/error text and close callback unchanged; camera lifecycle is not modified. This is not physical camera proof.
- ProfilesModal retains controller, listener, initial/min sizes, list/footer order and actions; bounded backdrop uses existing input/semantics-isolated scene. ProfileDetails retains provider branches, form hooks, fields, raw content updates; AnimatedSize zero is scoped to eligible disableAnimations.
- No test expectations removed or weakened in reviewed patch. New JSON test is additive.

## Evidence and limits

Read GlobalConstraints/D3, exact `.superpowers/sdd/review-bc392c30..85c67a08.diff`, six-file source and worker report. Accepted parent-reported baseline/current analyzer48/48 delta0 and boundary6/615 as supplied; did not rerun suites. Full host and native D3 gates/captures were still parent-owned/in progress at review time. Therefore no new pixel-level D3 visual acceptance is claimed here. After fixing spacer, native JSON overflow/controller checks and actual profile/QR screenshots still need their reported outcomes reviewed before marking D3 complete.

Only `/private/tmp/blizzard-d3-review.md` written. No repository, device, Apple or production mutations.
