# luma QA45: foreground main-screen measurement

27 October 2026. iPhone 16 Pro Max, Xcode Activity Monitor. User confirmed main screen open without auto-lock at start, VPN enabled. Charging was confirmed in preceding run; no change reported. Brightness unchanged, exact level unmeasured. YouTube excluded. User confirmed after completion: main screen remained open throughout; no noticeable heating.

Recording 360s; analyzed 60–360s, excluding the first minute. Full 300s metric coverage for the app and VPN. Thermal state Nominal for all 300s; no induced states or missing thermal coverage. No temperature in degrees, GPU power or watts measured.

| Target | Mean CPU (% of one core) | Median | p95 | Maximum | Peak physical memory (MiB) |
|---|---:|---:|---:|---:|---:|
| app | 0.232 | 0.058 | 0.107 | 28.076 | 637.96 |
| vpnExtension | 0.955 | 0.041 | 5.468 | 34.333 | 27.63 |

Whole-device mean CPU 87.547% on the one-core scale includes OS, profiler and other apps; cannot attribute it to luma. Screen observer samples reported active backlight; this alone does not prove which app was visible. User foreground confirmation and final observation are separate evidence.

App PID unchanged at the delayed post-recording check. VPN target had complete coverage throughout the analyzed window but was absent at that later exact bundle-path check. Do not claim continuous VPN operation after the trace or a confirmed absence of restart. User subsequently confirmed disconnecting VPN or switching luma after recording; the delayed absence is consistent with that action and does not establish an unexpected VPN failure. Generic Runner name matches cannot establish a restart.

Conclusion: no thermal pressure during this short measured interval. This does not establish thermal equilibrium, long-session behavior, or performance under video load. Retained files contain only allowlisted app/VPN and global numerical metrics.
