# Historical QA45 presentation audit

This unchanged test freezes provider/action AST bindings against `0830294eff5b8cd86324545ed00689648c70bd23`. Its last application is the preserved QA45 tree `d59ee70b602386b8d7da4d367f4294a91e55c963`; it is not an acceptance test for the authorized Hiddify 5.5.5 runtime replacement.

For a historical rerun, use an isolated checkout of `d59ee70b` with its pinned Flutter toolchain and generated prerequisites, then run:

```sh
flutter test test/ui_preservation/presentation_binding_contract_test.dart
```

Do not repoint its baseline at a new implementation or add broad exceptions to make it green. The 5.5.5 migration intentionally changes provider/action contracts. Current behavioral coverage and the boundary of the replaced guarantee are recorded in `docs/2026-11-07-hiddify-555-test-migration.md`.
