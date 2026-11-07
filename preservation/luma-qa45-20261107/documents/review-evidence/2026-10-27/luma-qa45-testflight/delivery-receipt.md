# luma 0.1.0 (45) — TestFlight delivery

Apple API receipt: TESTFLIGHT_READY; processingState=VALID; betaState=IN_BETA_TESTING; assigned=true. Existing internal tester group: Test. Bundle: com.womaninred.baseline.

Exact source: 3ed0a966f13a4ee7a84819d80b34e956d6b4ca19, branch release/luma-qa45-testflight. QA45 lib tree matches release source; followups change only tests. Controller PR73 is merged at 2e5f5f0a0a2f8a66d8ed8ece326b2a19d4b8f0ad.

Workflow: [REDACTED] — completed successfully. Exact signed artifact identity, app/extension version, entitlements and digests verified before upload. Signing readiness confirmed false after completion.

Validation: clean full Flutter run 1149 passed, 5 platform skips; runtime boundary 55 tests/2054 assertions; presentation binding 117 tests. Cloud source tests passed. QA45 foreground and video measurements each had Nominal thermal state for all300 analyzed seconds; user reported no heat on main and slight warmth during uninterrupted video.

Remaining device validation: the actual TestFlight distribution build has not been installed or run on the phone by this release task. Existing phone installation was not changed. Disable QA VPN before connecting production luma because the two installations share fixed local service ports. Known selected-server bottom-edge cosmetic issue remains.

Only existing TestFlight app/group used. No App Store production submission, GitHub Release, Android artifact, or tester creation.
