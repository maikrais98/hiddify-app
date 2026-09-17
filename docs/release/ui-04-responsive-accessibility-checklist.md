# UI-04 responsive and accessibility verification checklist

Owner: Designer + QA

Scope: Woman in Red mobile shell, Home, Servers, Rules, Settings, profile/import surfaces, dialogs and sheets
Required result for every row: `PASS`, `FAIL`, or `BLOCKED`

This is the execution manual for backlog item UI-04. It is a release evidence record, not a design proposal. Run the matrix against the exact build under review and record the build SHA, toolchain, device, OS, settings, evidence path, result, and defect ID before signing off.

## Evidence boundary

The 14 September 2026 audit recorded UI-04 as `Needs validation`: server-card labels were one line, stats used a fixed grid, and the dock used a fixed 64 px height with an 11 px label. Its requested validation set was 320/393/600/1024 px, 100/150/200% text scale, landscape, and RTL. The audit did not run a native screen reader. See the [UI audit finding](/Users/stasyudkin/Documents/KVN/audit-2026-09-14/report.md:369) and the [audit limitations](/Users/stasyudkin/Documents/KVN/audit-2026-09-14/report.md:378).

The audit was performed at branch `checkpoint/mvp-before-dark-theme`, SHA `47b3fdbea1ffc2bfbcc0b4382dbfa6c19061438d`. That SHA, its saved screenshots, and its test output are historical evidence only. They must not be copied into a later build's result column. A screenshot proves what is visible in that capture; it does not prove the build SHA, native semantics, VoiceOver, or TalkBack unless those facts are recorded with it.

Automated Flutter tests and semantics assertions are marked `AUTO`. They establish deterministic widget behavior in the test environment. They do not establish that the operating system's VoiceOver or TalkBack speaks the same tree, announces state changes, or allows a user to complete the flow. Those checks are marked `NATIVE-SR` and require a separate native-device or native-OS evidence item.

## 1. Run record

Create one run record for each build and keep it beside the evidence. Do not leave a value inferred from a branch name, screenshot filename, or an old report.

| Field | Record exactly | Capture method / release note |
|---|---|---|
| Run ID and UTC timestamp | `UI04-YYYYMMDD-HHMM-<short-sha>` | Use one ID across logs, screenshots, and native recordings. |
| Build SHA | Full 40-character commit SHA; also record dirty state | `git rev-parse HEAD` and `git status --short --branch`. If the checkout is dirty, include the changed-file list and mark the build as locally modified. |
| Flutter / Dart | Full versions and channel | Run the pinned Flutter executable's `--version`; record the Dart version shown there. The audit used Flutter 3.38.5 / Dart 3.10.4; do not assume those are current. |
| Build variant | Debug/profile/release, target, signing state | Record the installed artifact name and whether it is simulator/emulator, unsigned, or signed Release. |
| Device / OS | Model, architecture, OS version, API level where applicable | Record iPhone/iPad/Android/desktop separately. A simulator or emulator must be labeled as such. |
| Locale and direction | Locale, script, `ltr`/`rtl` | Minimum set: `ru`, `en`, and an RTL locale such as `ar`. Record the actual system locale and app locale if they differ. |
| Viewport and orientation | Logical width × height, orientation, pixel ratio | Use the viewport set in section 2. Record window size for desktop/tablet, not only the physical display size. |
| Text scale | Actual Dynamic Type / font scale and Flutter text scale | Run 1.0, 1.5, and 2.0. Record the OS setting and the resulting Flutter `MediaQuery.textScaler`. |
| Safe area | Top/bottom/leading/trailing insets | Record home-indicator or navigation-bar inset and whether an IME is visible. The iPhone stress case uses top 59 and bottom 34 logical px where available. |
| Accessibility settings | Reduce Motion, Reduce Transparency, Increase Contrast, Bold Text if used | Record each toggle as enabled or disabled. A Flutter `MediaQuery` override is automated evidence only; an OS toggle check is native evidence. |

## 2. Required viewport and setting set

Use the same content fixtures in every applicable size: a long server name and subtitle, long stats labels/values, the four navigation destinations, a scrollable list with a final actionable row, and the representative loading, error, empty, and success states. Use synthetic content only; never capture a subscription URL, token, or full user configuration.

| Profile | Logical viewport | Orientation | Text scale | Locale / direction | Safe-area setup |
|---|---:|---|---|---|---|
| Compact stress | 320 × 568 | Portrait | 1.0, 1.5, 2.0 | `ru` / `ltr` and `en` / `ltr` | Record device insets; include a no-inset automated fixture. |
| Primary phone | 393 × 852 | Portrait | 1.0, 1.5, 2.0 | `ru` / `ltr` and `en` / `ltr` | Include top 59 and bottom 34 logical px when the device has those insets. |
| Phone landscape | 852 × 393 | Landscape | 1.0, 1.5, 2.0 | `ru` / `ltr` and `ar` / `rtl` | Verify rotation recalculates insets and content clearance. |
| Tablet | 600 × 1024 | Portrait | 1.0, 1.5, 2.0 | `ru` / `ltr` and `ar` / `rtl` | Record split-view/window insets if applicable. |
| Desktop | 1024 × 768 | Landscape | 1.0, 1.5, 2.0 | `en` / `ltr` and `ar` / `rtl` | Record window chrome and keyboard inset if present. |

At widths below 600 px, verify the floating bottom dock. At tablet and desktop widths, verify the adaptive navigation rail or other production navigation chosen by the breakpoint. Do not treat a dock-only fixture as evidence for the rail.

## 3. Automated matrix

Evidence class `AUTO` means a command output or deterministic Flutter test result saved with this run. A row is `PASS` only when the named assertion was actually run against the recorded SHA. If the command or required test fixture was not run, use `BLOCKED` and state why.

| ID | Evidence class | Setup and procedure | Pass condition | Evidence path | Result | Defect ID |
|---|---|---|---|---|---|---|
| A-01 | `AUTO` | Record SHA, dirty state, Flutter/Dart versions, target, and test command before running UI checks. | All run-record fields are present and identify the exact build under test. | `artifacts/ui-04/<sha>/meta/run-record.txt` | `BLOCKED` until captured | `—` |
| A-02 | `AUTO` | Run `test/core/ui_04_responsive_assistive_smoke_test.dart` breakpoint cases at 320×568, 393×852, 600×1024, 1024×768, and 852×393. | Each size resolves to the intended mobile, tablet, or desktop breakpoint; no Flutter exception occurs. | `artifacts/ui-04/<sha>/automated/ui-04-smoke-test.txt` | `BLOCKED` until run | `—` |
| A-03 | `AUTO` | On 320×568 and 393×852, render Home with a long server name and subtitle at text scales 1.0, 1.5, and 2.0. | Essential server identity and transport text wraps or expands; it is not silently ellipsized, clipped, or replaced by an exception. | `artifacts/ui-04/<sha>/automated/home-server-card-<viewport>-<scale>.txt` | `BLOCKED` until run | `—` |
| A-04 | `AUTO` | Render the four dock destinations at 320×568 and 393×852 at text scales 1.0, 1.5, and 2.0. | `Главная`, `Серверы`, `Правила`, and `Настройки` (or the recorded locale equivalents) remain visible, readable, and within their item bounds. | `artifacts/ui-04/<sha>/automated/dock-labels-<viewport>-<scale>.txt` | `BLOCKED` until run | `—` |
| A-05 | `AUTO` | Render the stats section with long labels and values at 320×568 and 393×852 at text scale 2.0 inside a scrollable parent. | Labels and values remain readable; no overflow, `RenderFlex` exception, or fixed two-column collision occurs; the final stat remains reachable by scroll. | `artifacts/ui-04/<sha>/automated/stats-large-text.txt` | `BLOCKED` until run | `—` |
| A-06 | `AUTO` | Run the production shell at 393×852 with a 34 px bottom safe area and text scales 1.0, 1.5, and 2.0. Inspect the dock, FAB/primary action, snackbar, and the last scrollable content rect. | Dock clears the home indicator; primary actions and transient messages do not overlap the dock; the last content item can be scrolled above both overlays. | `artifacts/ui-04/<sha>/automated/shell-clearance-<scale>.txt` | `BLOCKED` until run | `—` |
| A-07 | `AUTO` | Apply a 300 px bottom `viewInsets` fixture, focus a text field, show the keyboard, and repeat after dismissing it. | Dock and page actions move above the IME, consume the inset once, remain non-overlapping, and return to their original safe-area positions after dismissal. | `artifacts/ui-04/<sha>/automated/ime-inset.txt` | `BLOCKED` until run | `—` |
| A-08 | `AUTO` | Render the dock and rail with semantics enabled. Inspect each destination's semantics node and selected state. | Every destination has one actionable, non-empty label; the selected destination exposes selected state; decorative icon semantics are not duplicated. | `artifacts/ui-04/<sha>/automated/navigation-semantics.txt` | `BLOCKED` until run | `—` |
| A-09 | `AUTO` | Pump the dock under `TextDirection.rtl` with `ar`-like labels; send Tab and, where supported by the shell, directional key events. | Every destination remains actionable; logical reading order is deterministic; focus does not disappear or become trapped. | `artifacts/ui-04/<sha>/automated/rtl-semantics-focus.txt` | `BLOCKED` until run | `—` |
| A-10 | `AUTO` | Review the widget tree and geometry for all directional padding around dock, rail, cards, dialogs, and sheets; run the RTL fixture. | Leading/trailing relationships mirror with direction; no critical control uses an accidental left/right inset; content and focus order remain logical. | `artifacts/ui-04/<sha>/automated/rtl-padding-review.txt` | `BLOCKED` until run | `—` |
| A-11 | `AUTO` | At 600×1024 and 1024×768, open Home, Servers, Rules, and Settings and exercise the rail destinations. | The rail, labels, selected state, content column, and any trailing stats remain inside the window; no mobile dock is stretched across the desktop layout. | `artifacts/ui-04/<sha>/automated/rail-shell.txt` | `BLOCKED` until run | `—` |
| A-12 | `AUTO` | Set `disableAnimations` and `accessibleNavigation`; set `highContrast`; render the dock and connection control. | Non-essential movement is disabled; dock treatment becomes opaque or otherwise readable; selected and inactive states remain distinguishable without color alone. | `artifacts/ui-04/<sha>/automated/reduced-effects-high-contrast.txt` | `BLOCKED` until run | `—` |
| A-13 | `AUTO` | Exercise the same states at 200% text scale: no access, loading, data error, empty server group, connected/checking, and connection error. | State copy and its next action remain visible and reachable; no state is communicated only by color or by a clipped icon. | `artifacts/ui-04/<sha>/automated/state-copy-reachability.txt` | `BLOCKED` until run | `—` |
| A-14 | `AUTO` | Run the focused UI suite with the repository's pinned Flutter executable: `test/core/ui_04_responsive_assistive_smoke_test.dart`, `test/core/nova_tab_route_test.dart`, and `test/core/widget/nova_glass_tab_bar_test.dart`. | The command exits 0 and the saved output identifies the same SHA and toolchain as A-01. A green test result is recorded as automated evidence only. | `artifacts/ui-04/<sha>/automated/focused-suite.txt` | `BLOCKED` until run | `—` |

Suggested invocation (replace the executable only if the run record documents a different, approved toolchain):

```sh
/Users/stasyudkin/fvm/versions/3.38.5/bin/flutter test --no-pub \
  test/core/ui_04_responsive_assistive_smoke_test.dart \
  test/core/nova_tab_route_test.dart \
  test/core/widget/nova_glass_tab_bar_test.dart
```

The current repository test names cover server-card wrapping, large-text dock labels, large-text stats, RTL semantics, keyboard focus, keyboard insets, breakpoint selection, shell clearance, and reduced-effects flags. A test name or source assertion alone is not a result; attach the output from the exact run.

## 4. Native visual and interaction matrix

These rows require the installed app or an equivalent native build and a visual inspection. A Flutter test or screenshot from a different SHA cannot close them. Record screenshots or a short screen recording for each failing or release-critical state; redact private access data.

| ID | Evidence class | Setup and procedure | Pass condition | Evidence path | Result | Defect ID |
|---|---|---|---|---|---|---|
| V-01 | `NATIVE` | On compact phone profiles, rotate through portrait and landscape at 100/150/200% text. | No clipped text, clipped control, unreachable final row, or overlay collision; orientation preserves the current route and selected navigation destination. | `artifacts/ui-04/<sha>/screens/<device>-<viewport>-<orientation>-<scale>.png` | `BLOCKED` until inspected | `—` |
| V-02 | `NATIVE` | On tablet and desktop profiles, open every top-level destination and one nested route/sheet. | Rail and content hierarchy fit the window; the dock is not used as an edge-to-edge desktop bar; nested back/close actions remain visible. | `artifacts/ui-04/<sha>/screens/<device>-rail-<locale>.png` | `BLOCKED` until inspected | `—` |
| V-03 | `NATIVE` | Use long server names, long status text, no-data/loading/error content, and a list with a final action. Scroll with touch, mouse, or trackpad. | Every essential string can be read and every required action can be reached without relying on a hidden overflow gesture. | `artifacts/ui-04/<sha>/screens/<state>-scroll-reachability.mp4` | `BLOCKED` until inspected | `—` |
| V-04 | `NATIVE` | Use an RTL locale and inspect dock/rail order, cards, dialogs, sheets, directional icons, and leading/trailing padding. | Reading order and directional spacing follow the locale; the connection and back affordances point in the expected direction; no text or action is stranded at a stale LTR edge. | `artifacts/ui-04/<sha>/screens/<device>-rtl-<state>.png` | `BLOCKED` until inspected | `—` |
| V-05 | `NATIVE` | Focus a text field, open the native IME, move through the form, submit/cancel, dismiss the IME, and repeat on a narrow viewport. | Focused content and primary actions remain above the IME; the dock/rail does not steal focus; dismissal restores layout and scroll position. | `artifacts/ui-04/<sha>/screens/<device>-ime-<state>.mp4` | `BLOCKED` until inspected | `—` |

## 5. Native screen-reader matrix

`NATIVE-SR` is a separate evidence class. Run the checks with the platform screen reader enabled and record the device/emulator, OS version, build SHA, locale, and exact spoken output or a screen recording. A semantics tree dump, `find.bySemanticsLabel`, or a Flutter test result cannot be entered as VoiceOver or TalkBack evidence.

| ID | Evidence class | Setup and procedure | Pass condition | Evidence path | Result | Defect ID |
|---|---|---|---|---|---|---|
| SR-01 | `NATIVE-SR` | Enable VoiceOver on iOS. Swipe through Home, the four dock tabs, Servers, Rules, Settings, a profile/import surface, and one dialog or sheet. Use the rotor to check headings/actions where present. | Each actionable control has one concise spoken name and role; the selected dock tab announces selected state; decorative icons do not create duplicate stops; focus order follows the visual/logical order. | `artifacts/ui-04/<sha>/native/ios/voiceover/navigation-<locale>.mp4` plus `transcript.txt` | `BLOCKED` until VoiceOver run | `—` |
| SR-02 | `NATIVE-SR` | With VoiceOver enabled, trigger loading, data error, empty server group, connect/checking, connected, and connection error. | The user can identify the state and available recovery action from speech; an update is not hidden behind a visual-only color or an unlabeled icon. | `artifacts/ui-04/<sha>/native/ios/voiceover/state-announcements.mp4` plus `transcript.txt` | `BLOCKED` until VoiceOver run | `—` |
| SR-03 | `NATIVE-SR` | With VoiceOver enabled, set the largest tested text size, open the IME, enter/exit a dialog, and return from a nested route. | All controls remain reachable; focus moves into a modal and returns predictably; no clipped label prevents identifying or activating an action. | `artifacts/ui-04/<sha>/native/ios/voiceover/large-text-ime-modal.mp4` plus `transcript.txt` | `BLOCKED` until VoiceOver run | `—` |
| SR-04 | `NATIVE-SR` | Enable TalkBack on Android. Repeat navigation, selected-state, modal, and nested-route traversal. | Each actionable control has one spoken name and role; selected state is announced; focus order is logical in both LTR and RTL locales. | `artifacts/ui-04/<sha>/native/android/talkback/navigation-<locale>.mp4` plus `transcript.txt` | `BLOCKED` until TalkBack run | `—` |
| SR-05 | `NATIVE-SR` | With TalkBack enabled, repeat the loading/error/empty/connected/checking states and the IME flow. | Status and recovery actions are discoverable by speech; focus remains reachable above the IME; no action depends on color or a gesture with no spoken affordance. | `artifacts/ui-04/<sha>/native/android/talkback/state-announcements.mp4` plus `transcript.txt` | `BLOCKED` until TalkBack run | `—` |

If a simulator/emulator is used for exploratory screen-reader work, label it in the run record and keep it separate from signed-device release evidence. The 14 September audit's statement that native screen readers were not run remains true until SR-01 through SR-05 have fresh evidence.

## 6. Native accessibility-settings matrix

The automated reduced-effects tests cover the Flutter flags that are available in the test environment. They do not prove the OS setting changed the installed app. Run each native toggle and capture the before/after state.

| ID | Evidence class | Setup and procedure | Pass condition | Evidence path | Result | Defect ID |
|---|---|---|---|---|---|---|
| OS-01 | `NATIVE-SETTING` | Enable Reduce Motion (or the platform equivalent); revisit dock selection, connection control, radar, loading, and sheets. | Non-essential movement is removed or reduced; no looping dock animation remains; the connection state and action stay understandable. | `artifacts/ui-04/<sha>/native/<platform>/reduce-motion.mp4` | `BLOCKED` until OS toggle run | `—` |
| OS-02 | `NATIVE-SETTING` | Enable Reduce Transparency / Remove animations or transparency according to the platform; inspect the dock, sheets, and dialogs over bright and dark content. | The dock and overlays switch to an opaque/readable treatment; text and icons do not lose their background or become unreadable. | `artifacts/ui-04/<sha>/native/<platform>/reduce-transparency-<state>.png` | `BLOCKED` until OS toggle run | `—` |
| OS-03 | `NATIVE-SETTING` | Enable Increase Contrast / high-contrast mode; inspect inactive labels, borders, selected lens, buttons, error states, and focus indicators. | Contrast and focus cues strengthen as intended; selected, error, disabled, and ordinary interactive states remain distinguishable without color alone. | `artifacts/ui-04/<sha>/native/<platform>/increase-contrast-<state>.png` | `BLOCKED` until OS toggle run | `—` |
| OS-04 | `NATIVE-SETTING` | At 200% text or the platform's largest supported accessibility size, repeat the compact, tablet, RTL, and modal cases. | Text reflows, scroll remains possible, and every primary action remains visible and screen-reader reachable. | `artifacts/ui-04/<sha>/native/<platform>/large-text-matrix/` | `BLOCKED` until OS toggle run | `—` |

## 7. Result and defect rules

Use these exact status meanings in the matrix:

- `PASS`: the procedure ran against the recorded build and every pass condition was met. Attach the evidence path.
- `FAIL`: the procedure ran and at least one pass condition failed. Attach the smallest useful repro evidence and a real tracker defect ID, for example `UI-04-01`; do not hide a failure in prose.
- `BLOCKED`: the procedure could not be run because a prerequisite is unavailable, or it has not yet been run. State the concrete reason in the evidence record, such as `no signed device`, `native screen reader not enabled`, or `focused suite not executed`. `BLOCKED` is not evidence of accessibility and does not close UI-04.

Use `—` for defect ID on a passing row. For a blocked environment prerequisite, record the owning release/environment issue ID if one exists; do not invent a product defect. A newly observed product failure should retain the parent scope `UI-04` and receive a distinct tracker ID.

## 8. Evidence package and sign-off

Store the following under one SHA-scoped directory:

```text
artifacts/ui-04/<full-sha>/
  meta/run-record.txt
  automated/
  screens/
  native/ios/voiceover/
  native/android/talkback/
  native/<platform>/
  sign-off.md
```

`sign-off.md` must reproduce the final matrix results and list every `FAIL` and `BLOCKED` row with its reason and defect or environment ID. Remove private access URLs, QR contents, tokens, provider values, and full configuration from screenshots, recordings, transcripts, and logs.

UI-04 is ready for release sign-off only when all required `AUTO`, `NATIVE`, `NATIVE-SR`, and `NATIVE-SETTING` rows have fresh evidence for the same build SHA, every executed row is `PASS`, and no required row remains `BLOCKED`. The earlier audit's green Flutter suite, saved screenshots, and the fact that native screen readers were not run cannot substitute for this package.
