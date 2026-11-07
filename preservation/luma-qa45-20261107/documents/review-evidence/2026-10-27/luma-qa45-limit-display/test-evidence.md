# Luma subscription-limit evidence — 2026-10-27

## Confirmed device evidence

QA44 screenshot showed:

- `My`: `217.14 GiB / 857.03 GiB`, expiration shown as infinite;
- `Akonit`: `0 GiB / 857.03 GiB`, expiration shown as 145 days.

`857.03 GiB` matches the app's stable `920233720369`-byte sentinel exactly. This is a synthetic parser value, not evidence that the two profiles share traffic.

The parser assigns the sentinel when `total` is present but zero or non-numeric. If the `total` key is wholly absent, the current map pattern returns no `SubscriptionInfo`; this behavior remains unchanged.

Because zero and non-numeric values are conflated, the UI does not claim “unlimited”. It preserves actual consumption and displays a neutral unknown limit: `consumption / —`. Accessibility semantics reuse the localized `Not set` value.

## RED

Command:

```text
fvm flutter test test/visual/luma_subscription_limit_test.dart
```

Exit: `1`.

Expected failures confirmed that the old UI:

- had no neutral `217.14GiB / —` representation and exposed the synthetic `857.03GiB` total;
- rendered a finite percentage indicator and could report `no traffic` for the sentinel;
- converted a real finite `12 TiB` limit to `∞ GiB`.

Parser characterizations already passed during RED:

- zero or invalid `total` maps to the sentinel;
- a missing `total` key does not invent subscription info.

## GREEN

Focused command:

```text
fvm flutter test test/visual/luma_subscription_limit_test.dart
```

Exit: `0` — `6/6` passed.

Final regression command:

```text
fvm flutter test test/visual/luma_subscription_limit_test.dart test/features/profile/data/profile_parser_test.dart test/ui_preservation/profile_tile_contract_test.dart test/visual/blizzard_aurora_profile_states_test.dart test/visual/blizzard_v3_design_parity_test.dart
```

Exit: `0` — `31/31` passed. The v3 suite emitted one pre-existing non-fatal tap hit-test warning.

## Scope

- Added a model-only computed finite-limit predicate; no schema or generated-file change.
- Reused the existing parser sentinel through a named model constant.
- Changed only the active `ProfileSubscriptionInfo` rendering and its finite percentage indicator.
- Preserved real consumption and expiration.
- Preserved all real finite limits, including totals above `10 TiB`.
- No build, install, device mutation, network access, user URLs, raw profiles, logs, environment values, or secrets.
