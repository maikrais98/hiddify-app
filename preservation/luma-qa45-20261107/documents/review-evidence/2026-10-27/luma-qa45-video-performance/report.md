# luma QA45: YouTube video measurement

27 October 2026. iPhone 16 Pro Max, Xcode Activity Monitor. User confirmed ready after instructions to run YouTube at maximum brightness with fixed 1080p, QA45 VPN enabled and charging unchanged. Video settings were not independently verified. User confirmed after completion: video played throughout and the phone felt slightly warm.

Recording 360s; analysis 60–360s excludes first minute. App and VPN metric coverage complete for all 300s. Thermal state Nominal throughout, no induced intervals. Exact app/VPN PIDs match start/end. No degrees C, GPU power, watts, packet contents or video history collected.

| Target | Mean CPU (% of one core) | Median | p95 | Maximum | Peak physical memory (MiB) |
|---|---:|---:|---:|---:|---:|
| app | 0.0 | 0.0 | 0.0 | 0.0 | 262.17 |
| vpnExtension | 5.172 | 4.284 | 14.387 | 38.631 | 26.0 |

App UI was backgrounded while video ran; its zero CPU does not measure foreground UI performance. VPN mean CPU was 5.172% of one core, p95 14.387%, maximum 38.631%, peak memory 26.00 MiB. Whole-device mean 93.323% of one core includes OS, video playback, profiler and other apps; cannot attribute global load or heat to luma.

No thermal pressure observed during this short interval. This does not establish thermal equilibrium or long-session battery use. Prior main-screen run VPN mean 0.955% is descriptive context only; video changes multiple conditions, so it is not a controlled efficiency comparison. Traffic routing of every YouTube request was not independently verified by this process-counter recording.

Only allowlisted app/VPN and global numeric metrics retained. Generic Runner name matches do not establish a restart.
