# D2 suggestion material correction

Changed only `lib/core/router/dialog/widgets/setting_input_dialog.dart` after parent GO confirmed actual-iOS RED in `docs/verification/blizzard/d2-suggestions-red.log`: expected explicit 0xFF102235 material color, actual null.

## Change and self-review

Added tokens import and TypeAheadField.decorationBuilder. Central BlizzardPresentation.isActive controls eligibility. Active Material preserves package type card/elevation4 while explicitly selecting computed themeOf(builder context).colorScheme.surface, transparent tint and BlizzardRadii.row (12). Inactive builder is null, so flutter_typeahead 5.2.0 executes its exact unmodified default decoration. Computed surface supports existing high-contrast palette. No global theme or dependency changes.

All existing input builder, focus management, controller, suggestions mapping/filter/fallback, row builder, selection, mapTo, validation, reset, optional action and route return callbacks remain literally untouched. Only new callback is a pure presentation wrapper. Reviewed full assigned-file diff, and git diff --check passes.

## Verification

Pinned Flutter: `/private/tmp/wir-baseline-tools/flutter-3.38.5/bin/flutter --suppress-analytics`; PUB_CACHE `/private/tmp/wir-baseline-tools/pub-cache`.

Command for each FLAG=true,false:

```
PUB_CACHE=/private/tmp/wir-baseline-tools/pub-cache /private/tmp/wir-baseline-tools/flutter-3.38.5/bin/flutter --suppress-analytics test --no-pub --dart-define=BLIZZARD_VISUALS=FLAG test/visual/blizzard_surface_coverage_test.dart test/ui_preservation/remaining_surface_actions_contract_test.dart test/ui_preservation/navigation_overlay_contract_test.dart test/ui_preservation/presentation_binding_contract_test.dart
```

Both modes PASS 63 tests. Logs `/private/tmp/blizzard-d2-fixes-host-on.log` and `/private/tmp/blizzard-d2-fixes-host-off.log`. Initial sandbox invocation could not open loopback server; approved escalation resolved it. Host runs exercise inactive actual-platform branch, input behavior and AST callback preservation; active native branch remains parent verification.

Requested theme_navigation_contract_test.dart does not exist; navigation_overlay_contract_test.dart covers real dialog results, cancellation, validation, reset, draft and focus.

`ruby test/ci/blizzard_runtime_boundary_test.rb`: PASS 6 tests / 615 assertions (log `/private/tmp/blizzard-d2-fixes-boundary.log`). Existing Ruby deprecation notice only.

Native GREEN, pixel acceptance and physical VPN proof are not claimed by this report. No git index, commit, dependency, global theme, native or test modifications made by this worker.
