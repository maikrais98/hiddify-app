# Luma on Hiddify 5.5.5 — integration report

**2026-11-07.** The stable foundation is integrated, reviewed and committed. The checks below distinguish source, simulator and packaging evidence from the outstanding physical-device release gates. This document does not approve a release.

Implementation contract: [approved plan](plans/2026-11-07-1619-refactor-luma-hiddify-555-plan.md). Historical-test decisions and current coverage: [test migration record](2026-11-07-hiddify-555-test-migration.md).

## Foundation and release accounting

The preserved source is `d59ee70b`, containing QA45 `3ed0a966`. Its common upstream base is `abbd671bf6bf05195acd4158c714bff267cada8f`. The integration uses the actual stable app tag `upstream/v5.5.5`, commit `7804cadac01419f31b1ec7802d9e1be599e66de2`, rather than a version-only change or a transplant without ancestry. Merge commit `a2298c6bc7ff3b1cb9cd8a6a468ee23d10654bfa` has parents `0b64127b` and the exact stable tag `7804cada`; no index conflicts remain. Review fixes are committed separately in `3fc6361e`. No pull request has been merged and no upload or publication has been performed.

The app manifest and `dependencies.properties` select app/core **5.5.5**, using Flutter **3.38.5** and Dart **3.10.4**. The official iOS archive is [hiddify-lib-ios.tar.gz](https://github.com/hiddify/hiddify-core/releases/download/v5.5.5/hiddify-lib-ios.tar.gz):

- Size: **111,283,683 bytes**.
- SHA-256: `7b14e3a657a000d0200bb40f30b3d6796854219bb0b5b72c38e3f4d456601a8b`.
- Existing extraction, size/digest and framework-manifest checks remain in `scripts/prepare_ios_baseline_core.sh` and the iOS baseline workflow. Preparation and upload-side provenance expectations agree; upload was not dispatched.

The following inventory covers **all 610 changed paths**, including both endpoints of renames, between the common base and the stable tag (`git diff --name-only --no-renames abbd671 upstream/v5.5.5`). It accounts for the whole released change, including platforms that were not exercised locally.

| Stable release area | Paths | Integration disposition |
|---|---:|---|
| Bridge, core and configuration models | 81 | Official managed lifecycle, mTLS credentials/channels, generated RPC protocols and models adopted together. |
| Connection, proxies, health and traffic | 29 | Official start/stop/reconnect, Waiting/NoAvailableProxies/HotReloading, main/chain proxy selection, latency and speed tests retained. |
| Settings, chains, routing and preferences | 66 | Official extra-security/unblocker chains, WARP/Psiphon options, built-in rules, per-app routing, preference migrations and LAN/local proxy controls retained. |
| Profiles, storage, parser/import and HTTP | 34 | Official repositories, title/header parsing, nested subscription imports, phone import, asynchronous editor configuration, pinned profiles and schema migrations retained. |
| Logging, analytics and crash reporting | 28 | Complete official diagnostics adopted by explicit user decision; obsolete custom owners removed as described below. |
| Application/shared UI, utilities, updates and bootstrap | 71 | Stable functionality retained; mixed widgets rebound to official providers/actions beneath luma presentation. |
| iOS | 56 | Stable native bridge, packet tunnel and minimum iOS 15.5 adopted; retained identity and bounded VPN preference corrections described below. |
| Android | 27 | Stable platform, service, notification, routing and mTLS changes retained; Android execution remains unverified here. |
| macOS | 57 | Stable extension, admin service, platform and packaging changes retained; macOS application packaging remains unverified here. |
| Windows/Linux | 13 | Stable service, updater, signing/Store and distribution changes retained; platform execution remains unverified here. |
| Assets and translations | 20 | Official entries retained alongside luma assets and existing product wording. |
| Official tests and migration fixtures | 45 | Released regressions retained; fork tests adapted to observable official behavior. |
| Build/release tooling, vendored dependency and documentation | 83 | Stable build/release changes retained with existing fork publication safeguards and verified core provenance. |

Direct comparison with the tag finds no fork edits in the critical Dart runtime units: `lib/hiddifycore`, `lib/singbox`, connection repositories/notifiers, profile parsing/repositories, preference providers, proxy repository/state and routing/configuration repositories. The sole preference-migration addition is the saved-global-WARP bridge below. Presentation changes do not recreate the removed runtime behind compatibility providers.

## Deliberate fork adaptations

| Area | Retained behavior and reason |
|---|---|
| Luma presentation | Existing Blizzard artwork, native glass/control/dock, grouped settings, profile gestures and simplified import/server/connection journeys remain. Widgets use the official state/actions. New chain/routing screens reuse existing panels; confirmed narrow-screen/large-text overflow and undersized touch targets were corrected without changing actions. Legal-link focus styling remains readable under luma. |
| Product metadata | `Constants.appName` remains `luma`; the existing version-with-build display is retained. User-agent/runtime version semantics remain official. |
| Installed iOS identity | App `com.womaninred.baseline`, extension `com.womaninred.baseline.HiddifyPacketTunnel`, AppGroup `group.com.womaninred.baseline`, service identifier `com.hiddify.app` and existing signing-team selection are retained. Application and service identity remain distinct. |
| Saved profiles | Official conditional v5→v6 `profile_override` removal and v6→v7 `pinned=false` remain. A small one-time v5 header bridge maps stored `enable-warp=true` to `extra-security=warp`, and stored `enable-fragment=true` to supported TLS-tricks headers. Existing explicit current-format headers take precedence. It runs before the old cache column is dropped and does not broaden the parser policy for new downloads. |
| Saved global WARP | One version-5 step in the official preference migration preserves enabled QA45 WARP: default/`warpOverProxy` becomes extra security, `proxyOverWarp` becomes unblocker. Supported license/endpoint/noise fields carry to the relevant hop; modern settings win. Retired credentials remain untouched. No runtime adapter is added. |
| Release configuration validation | The official validator accepts the existing Flutter version references through the generated-config include and automatic signing. Manual or explicitly supplied provisioning maps still require both correct identities; team, plist and privacy checks remain. Negative fixture tests cover invalid configurations. |
| Subscription limits | A presentation predicate recognizes the historical QA unlimited sentinel and the official parser sentinel, while preserving finite limits. Stored traffic amounts and the official parser remain unchanged. |
| VPN preferences | The tag still selects the first saved manager. The fork selects the exact provider and serializes preference operations across suspension points. One stale-save reload/reapply retry targets the same manager. Reset removes only that provider, waits a bounded interval for stop and preserves an active profile on timeout. Start/save failures propagate through the official flow. |
| Manual connection policy | Always-on stays an explicit official opt-in. Disconnect clears on-demand policy; changing the setting while disconnected does not silently initiate a connection. Default/manual behavior remains covered by native policy tests. |

The minimum supported iOS version changes to **15.5**, matching the stable native foundation. This is a supported-OS change, not merely a build setting.

## Diagnostics and historical test contracts

The user explicitly chose complete official diagnostics. The integration therefore removes the displaced custom startup/status owners, bespoke iOS ping deadlines/readiness policies, diagnostic journal/import bridge and custom Better Stack delivery path. Official local/system logging, ring buffers, crash reporting and analytics behavior replace them. In particular, previous custom redaction/correlation guarantees are not claimed: official diagnostics can include raw errors in local/system logs.

Tests that assert those removed custom implementations were replaced within the approved scope, rather than retaining fake legacy APIs. The unchanged 2,018-line AST binding audit was moved to `tool/qa45_audit/`: it freezes callback/provider expressions and predicates against `0830294eff5b8cd86324545ed00689648c70bd23`, which conflicts with the approved technical replacement. It is preserved as historical QA45 evidence and is not counted as a passing 5.5.5 runtime test. The separate frozen QA45 runtime-boundary audit has the same historical disposition. Current action, persistence, migration, native-control and visual coverage is mapped in the test migration record.

Frozen `preservation/**` and `tool/qa45_audit/**` evidence is excluded from live source analysis. Active application and test sources remain analyzed. Trusted publication-source SHAs, archive security and signed-artifact gates were not changed to bypass approval checks.

## Post-tag changes deliberately deferred

| Change after 5.5.5 | Affected files | Decision |
|---|---|---|
| `ea08fb5b`, WARP/Psiphon display-name update | `test.configs/warp` | Defer: outside the chosen stable baseline. |
| `4cc86c4e`, accept unpadded base64 profile title | `lib/features/profile/data/profile_parser.dart`, its parser test | Defer: keep the tagged parser and tests. `0d6eb882` is the merge of this fix, not a third independent change. |

## Verification receipts

Results below are completed focused checks unless explicitly marked pending. Native compilation, simulator mTLS and UI rendering establish different boundaries; none is treated as proof of physical-device VPN traffic.

| Gate | Recorded result | What it establishes |
|---|---|---|
| Dependency/generated consistency | Dependencies resolved and code generation/translations completed with the pinned toolchain; tracked-output review completed; no incidental generation changes remain. | Official inputs can generate the integrated application. |
| Data upgrade/parser/override compatibility | **109 tests passed**. | Synthetic v5 with/without legacy cache column, v6/fresh v7, saved IDs/active selection/headers, current overrides and compatibility bridge. No user database used as a fixture. |
| Official proxy/health/start-stop suites | **42 tests passed**. | Official proxy/card/chain health, selection and bounded start-after-stop behavior. |
| Runtime/mTLS/model checks | **29 tests passed**. | Current credentials, channel/RPC and state/model contracts. |
| Settings/action/visual preservation pack | **120 tests passed**. Additional visual/accessibility pack plus 320 pt/2× readability: **110 passed**. | Preserved observable journeys, focus/semantics, responsive layout and official chain/routing behavior. These overlapping focused runs are not summed into a whole-suite total. |
| Native VPN policy | Passed. | Actual patched VPNManager/VPNConfig policy: exact provider, serialization, bounded stale/reset handling, manual defaults and explicit always-on. |
| Archive security | **9 checks passed**. | Verified core preparation and existing rejection paths for invalid archive inputs. |
| Ruby workflow/release/identity/entitlement gates | **31/457**, **28/309**, **15/154**, **39/250**, **8/48** runs/assertions; no failures. The 39-run group has **one artifact-dependent skip**. | Workflow, publication protections, source identities and available entitlement/packaging checks. The skip is not signed-artifact verification. |
| iOS release compilation | Final no-codesign release archive passed after review fixes; **435.8 MB** (`/private/tmp/luma555-final-release-build.log`). App/extension Info.plists confirm retained bundle IDs, version **5.5.5 (50505)** and iOS **15.5**. | Real app and packet-tunnel compile/link against the prepared core, using the existing `flutter build ipa --release --no-codesign --target lib/main_prod.dart` path. It is not a signed distributable. |
| Simulator real-core mTLS | **One handshake test passed**. | Actual simulator client/core authentication and linkage; no physical tunnel/traffic claim. |
| Whole Flutter suite | **918 passed, 5 skipped**, including a complete rerun after the final native layout fixes (`/private/tmp/luma555-full-tests-verified.log`). | All active Flutter tests pass. Five iOS-only visual cases do not run in the host lane; four were subsequently exercised in the native geometry run below. The desktop mTLS smoke also returns early without its desktop library and is not credited as a handshake; actual simulator-core mTLS was tested separately. |
| Native visual integration | Complete native run: **178 passed, 7 failed**. Two confirmed UI layout defects were fixed; the subsequent **17/17 affected and adjacent native cases passed** (`/private/tmp/luma555-native-layout-final.log`). | Real iOS rendering, luma native component registration, actions, accessibility, scrolling and appearance. Native action fixture callbacks are not physical touch or traffic evidence. WARP content also passes its previously failing 1×/1.8× text reproduction. |
| Global WARP upgrade | **10 tests passed**; all three enabled legacy variants first failed without the migration. Final run together with the existing WARP-hop suite: **18/18 passed**. | Actual preference migration from QA45 version 1 and emitted official configuration, both detours/default, modern precedence, disabled state and replay. |
| Native preferences/process restart | Write and read phases each passed in separate app processes, with native SharedPreferences receipts. | Settings survive a process restart without uninstalling/resetting the app; synthetic fixtures, not an installed QA45 upgrade. |
| Native geometry/motion | **10 tests passed**. | iOS-only geometry, cached layers, native control, tab/modal visibility, scroll reachability and frame timings. |
| Native screen capture | **10 screenshots and 2 videos**, capture receipt PASS. | Main app iOS project, 393×852 simulator, synthetic profiles. Home/settings/servers/profiles/import/quick settings visually inspected. Local evidence: `review-evidence/2026-11-07/hiddify-555/` under the KVN workspace. |
| Browser applicability | Not applicable to the scoped iOS integration. | Native UI evidence above exercises the changed product. Inherited `web/` assets are untouched; no browser result or web support is claimed. |
| Complete application analysis | **No issues found** in final full `flutter analyze --no-pub` after review fixes (`/private/tmp/luma555-final-analysis.log`). | Application and active tests analyzed with the pinned SDK; historical archives excluded explicitly. |

## Independent review

Full review covered correctness, project standards, testing, maintainability, security, migration, reliability, adversarial behavior, Swift/iOS and deployment verification. Both confirmed P2 findings (legacy global WARP and release validator compatibility) were fixed and independently rechecked; no actionable findings remain. Review run: `20261107-173943-2e71b359`. A different-provider review did not run under the allowed-model constraint; the adversarial lens used the available local reviewer.

## Remaining gates before release

- Run a physical iPhone upgrade from QA45: retain saved profiles/selection, authenticate runtime RPC, manually connect/disconnect, switch servers and verify actual traffic. Record foreground/reconnect behavior separately. **Not verified.**
- Inspect a signed app/extension artifact and entitlements with the preserved identity/signing inventory. **Not verified.**

No TestFlight/App Store upload, publication or pull-request merge is authorized by this report. The local successful build and simulator handshake do not close the physical-upgrade, traffic or signed-artifact gates.
