# Audit remediation baseline — 2026-09-16

Source SHA: `884ce69fc8dcc1e0468ceb4bae931c9036f03cc9`.
Existing PR: https://github.com/maikrais98/hiddify-app/pull/1 (remote head at intake: `6ce4a7e1ed4ed4f109963be77f955a5a452c46b7`).

This is the pre-fix evidence summary. It is not a claim that the issues are fixed.

| Finding | Baseline evidence | Required closure |
|---|---|---|
| F01 | Simulator and unsigned device build fail: three Libbox protocol methods missing; DNS iterator API mismatch | Reproducible matched sources/framework, both builds, packaged auth proof |
| F02 | Clean SSH probe fails without user keys; nested replacements use SSH | Real clean bootstrap without private credentials |
| F03 | iOS nil launch options omit required secret; mobile secret lives in Flutter/process memory | Native credential ownership, restart/system-launch coverage, separate device replay |
| F04 | Widget fixtures overflow at large text/landscape keyboard | Reachable primary actions through real route; native screenshots |
| F05 | Concurrent suite: 356 pass/1 deadline-test failure; sequential repeat: 357 pass | Deterministic shared-budget/deadline regression |
| F06 | Manual import return control lacks accessible name | Localized action name and semantics regression |
| F07 | Shared route transition ignores Reduce Motion | Reduced and normal navigation regression |
| F08 | pen.dev Auto Mode sheets and legacy tokens differ from implementation | Reconcile affected design representations against verified UI |
| F09 | Synthetic malformed JSON marker reaches LogRecord.error and Sentry breadcrumb conversion | Production import handlers exclude source-bearing exceptions from every sink |
| F10 | Tray maps connected to connecting on invalid latency, disabling disconnect | Lifecycle preserved and disconnect available |

Analyzer ratchet passed with 228 existing diagnostic signatures; this is not zero analyzer debt. Go hcore/localauth, localauth race, release-gate and archive-integrity checks passed in the recorded audit environment. These results do not replace checks on the remediation SHA.

Physical iPhone was discoverable; zero valid signing identities were found. No native VPN runtime was validated. Signing availability must be checked again when attempting installation. Simulator screenshots and widget tests do not prove traffic protection.

Full local audit evidence was produced under `/tmp/wir-audit-20260916/`. Raw logs, local device metadata, DerivedData, and framework binaries are deliberately excluded from Git. Retain red/green evidence for each remediation unit in the execution record and cite exact commands, SHA and any remaining boundary in the final PR.
