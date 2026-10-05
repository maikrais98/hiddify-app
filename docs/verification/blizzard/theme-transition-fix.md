# Theme transition correction — GREEN and frozen

Only production edit: lib/core/theme/blizzard_theme.dart role constructor now has inherit:false and textBaseline:TextBaseline.alphabetic. All SF/Shabnam fonts, role sizes/weights/heights/colors unchanged. codeStyle, global theme, defaultfalse, every other production file, tests, index and commits untouched by this worker.

## Evidence-led change

Read independent review and supplied failing host RED before edit. Initial authorized inherit:false removed TextStyle.lerp inheritance mismatch but exposed missing resolved baseline. OFF targeted suite33PASS/5FAIL: InputDecorator2318 dereferences labelStyle.textBaseline, ListTile1017 expects resolved title/subtitle baseline. Pinned MaterialTypography source defines alphabetic baseline. After parent explicitly authorized minimal second field, added textBaseline:TextBaseline.alphabetic; no broader copyWith/refactor or arbitrary interpolated fields.

## Final validation

Both FLAG=false and FLAG=true:

PUB_CACHE=/private/tmp/wir-baseline-tools/pub-cache /private/tmp/wir-baseline-tools/flutter-3.38.5/bin/flutter --suppress-analytics test --no-pub --dart-define=BLIZZARD_VISUALS=FLAG test/visual/blizzard_theme_transition_test.dart test/visual/blizzard_material_contract_test.dart test/ui_preservation/presentation_binding_contract_test.dart

**PASS38/38 each**, including actual Material light→Blizzard→light transition consumer/controller preservation, material geometry and full source binding/sensitivity guard.

Logs:
- /private/tmp/blizzard-transition-fix-off-green.log
- /private/tmp/blizzard-transition-fix-on-green.log
- Initial secondary RED retained /private/tmp/blizzard-transition-fix-off.log

Focused analyzer blizzard_theme.dart: No issues found. /private/tmp/blizzard-transition-fix-analyzer.log. git diff --check PASS. Exact diff is two added role-constructor arguments only.

Production FROZEN. Parent owns native B-IOS/full corrected fixture smoke, independent re-review and commit. No native GREEN or final default-on acceptance claimed by this host report.
