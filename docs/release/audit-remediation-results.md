# Audit remediation verification

Date: 2026-09-16. Baseline: `884ce69fc8dcc1e0468ceb4bae931c9036f03cc9`.
Plan: [audit remediation](../plans/2026-09-16-audit-remediation-lfg.md).

Status: superseded integration baseline. All ten fixes were integrated against 884ce69f, but user review identified that this branch omits the current dark UI and startup work. Flutter386/analyzer228 results apply only to this baseline. Both native builds pass; the integrated packaged RPC replay hangs and remains FAIL. Do not ship or use this branch as current visual evidence; integration with checkpoint/current-ui-snapshot is required.

## Unit evidence

| Finding | Integrated commit | Verified result | Remaining boundary |
|---|---|---|---|
| F01 native core/build | `dd95f076`, `4d1946ed` | Source rebuild, full Simulator build, unsigned device Release, Go race and packaged auth lifecycle pass in F01; copied source/artifact identity rechecked by parent | Final integration native replay |
| F02 clean bootstrap | `5d3ef920`, `01e3034c` | Real public HTTPS bootstrap repeated successfully; Go targets pass; parent release gate replay passes | Final PR CI |
| F03 credential lifecycle | `220d8167` | 17 focused Dart tests, executable Swift/Kotlin lifecycle harnesses and scoped Simulator build pass | Android SDK compile and signed device replay |
| F04 responsive import UI | `eabf64a0` | Production hero/modal regressions, 39/39 targeted tests pass | Native typography and assistive technology |
| F05 shared deadline | `fdb160f4`, `dfc94277` | Parser/policy regressions, 69/69 pass, including late DNS completion after deadline | Full suite passed; final review pending |
| F06 accessible import action | `1599b811` | English/Russian semantics action returns to import options; combined F06/F10 replay 22/22 pass | Native VoiceOver traversal |
| F07 reduced motion | `f116757e` | Navigator push/pop regressions, 3/3 pass | Native OS accessibility replay |
| F08 design reconciliation | `9a96e81a` | 11 CSS/Nova mappings pass; four pen.dev states updated, reread and visually checked | Native runtime screenshot and pixel parity |
| F09 safe import logging | `d35879b6` | Real clipboard/file handler and diagnostic sink tests, 22/22 pass | Full suite passed; final review pending |
| F10 truthful tray state | `5c302e7a` | Platform-channel menu tests; combined F06/F10 replay 22/22 pass | Native desktop tray smoke |

Detailed local logs are retained outside Git under `/Users/stasyudkin/Documents/KVN/.audit-remediation/`. Passing targeted tests is not a substitute for the final integrated gates.

## Findings outside this remediation scope

- Config-options import can report success after an existing update failure. F09 preserves this behavior while preventing sensitive exception logging. A follow-up should define failure propagation and user feedback.
- Per-app file import contains an existing double JSON conversion. F09 preserves this parsing behavior; a separate reproduction and correction are needed.

## Physical device boundary

Fresh local signing check on 2026-09-16 reports `0 valid identities found`.

Widget tests and Simulator builds do not verify VPN traffic, Keychain sharing between signed targets, On Demand, or device lifecycle behavior. The signed candidate must pass the physical VPN gate in the plan before these claims can be made.
