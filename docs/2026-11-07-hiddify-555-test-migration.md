# Proposed replacement of obsolete regression tests

Status: user explicitly approved this exact replacement on2026-11-07 after separately choosing official Hiddify diagnostics. Rejected commands made no changes; the approved scope was then applied.

## Scope

These test files exercise removed QA45 custom iOS ping/status owners, rather than the current official Hiddify5.5.5 implementation:

- test/features/proxy/active/ios_active_proxy_measurement_test.dart
- test/features/proxy/active/ios_active_proxy_provider_test.dart
- test/features/proxy/active/ios_delay_refresh_feedback_test.dart
- test/features/proxy/active/ios_ping_lifecycle_integration_test.dart
- test/features/proxy/active/ios_ping_lifecycle_presentation_test.dart
- test/features/proxy/active/ios_ping_refresh_diagnostics_test.dart
- test/features/proxy/active/ios_url_test_deadline_test.dart
- test/features/proxy/active/legacy_active_proxy_preservation_test.dart
- test/ui_preservation/ios_latency_wait_test.dart

The proposed removal deliberately relinquishes custom ping deadlines, treating unavailable ping as connection readiness, and custom diagnostic correlation. Official status/health semantics replace those policies. It does not claim the old behaviors still exist.

## Replacement evidence

A combined run of these official suites passed42 tests:

- test/features/proxy/active_proxy_card_data_test.dart: main/hop selection, untested/timed-out/available ping, status precedence, stale IP, chain health.
- test/features/proxy/connection_health_test.dart: pending/failed hops, dead selection and fastest selection action, no degraded state before connection.
- test/features/proxy/proxies_overview_notifier_test.dart: failed selection notification, active-row ordering, selected-only ping, upload action, failed proxy label.
- test/hiddifycore/core_interface/start_once_stopped_test.dart: managed start waits for stop, bounded failure remains visible.

Luma connection/button/status-route tests are being adapted, including Waiting, NoAvailableProxies and HotReloading. Route visibility coverage remains. No replacement of authentication tests, archive validation, app identity or release approval gates is proposed.

## CI changes

In .github/workflows/baseline-telemetry.yml:

1. Replace analysis of removed custom telemetry sources with analysis of the complete application.
2. Keep full Flutter test invocation.
3. Keep test/ios/vpn_manager_manual_policy_test.sh. Its updated suite compiles the actual official VPNConfig/Stored and current patched VPNManager and passes exact-provider lookup, serialized preferences, bounded stale retry/reset, manual default and explicit always-on opt-in checks.
4. Stop invoking test/ios/foreground_setup_mode_test.sh, which extracts the obsolete QA45 setup contract and expects the old unencrypted foreground mode. Current official setup/mTLS tests and full native compilation replace that contract.
5. Stop invoking test/security/native_diagnostics_privacy_test.sh, which requires the removed bespoke NativeDiagnosticLog and read_safe_diagnostics bridge. User explicitly chose complete official diagnostics, including raw errors in local/system logs.
6. Keep all release/identity/signed-entitlements and archive security gates.

Risk: original custom ping timing and privacy assertions intentionally no longer apply. This does not authorize publication, merge or upload, and does not prove physical-device traffic or signed-artifact validity.

## Historical binding audit disposition

After the user delegated remaining decisions on 2026-11-07, the unchanged `presentation_binding_contract_test.dart` was moved to `tool/qa45_audit/`. It compares all presentation provider/action expressions and predicates with `0830294eff5b8cd86324545ed00689648c70bd23`; the full run failed before loading because the official migration replaces `warp_license_dialog.dart` with `chain_license_dialog.dart`. Changing its baseline or adding exceptions would conceal the approved technical replacement. The original QA45 audit remains reproducible against preserved `d59ee70b`; it is not counted as a passing 5.5.5 test.

Literal identity with old bindings is intentionally relinquished. Observable behavior remains covered at these existing boundaries:

| Historical audit concern | Current executable coverage |
|---|---|
| Connection state/action and server selection | `test/ui_preservation/connection_contract_test.dart`, official connection/health/proxy suites, `test/visual/blizzard_server_parity_test.dart` |
| Profile import, editor, updates, sharing and deletion | `test/ui_preservation/profile_import_contract_test.dart`, `editor_import_async_contract_test.dart`, `profile_tile_contract_test.dart` |
| Settings persistence, reset and actions | `test/ui_preservation/proxy_settings_contract_test.dart`, `remaining_surface_actions_contract_test.dart`, `theme_contract_test.dart` |
| Dialogs, navigation and preserved branches | `test/ui_preservation/navigation_overlay_contract_test.dart`, `test/visual/blizzard_surface_coverage_test.dart` |
| Native control, motion/accessibility and layout | `test/visual/blizzard_native_connection_control_test.dart`, `blizzard_accessibility_contract_test.dart`, native integration suites |
| Profile drag, quota and responsive layout | `test/visual/luma_profiles_sheet_gesture_test.dart`, `luma_subscription_limit_test.dart`, `blizzard_native_sheets_parity_test.dart` |
| Intro and official Chain legal links | `test/visual/blizzard_aurora_remaining_states_test.dart`, `blizzard_luma_remaining_surfaces_test.dart` |

The separately frozen `test/ci/blizzard_runtime_boundary_test.rb` also remains a historical QA45 audit; it is not a 5.5.5 release approval. Publication trusted-SHA and signed-artifact gates are unchanged. Frozen `preservation/**` evidence and `tool/qa45_audit/**` are excluded from live source analysis; active application and test sources remain analyzed.
