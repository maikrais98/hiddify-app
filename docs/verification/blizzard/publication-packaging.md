# Publication-safe Blizzard source packaging

The release source is a fresh single-commit export on public baseline `0830294eff5b8cd86324545ed00689648c70bd23` of reviewed migration tree `aab1503bfbbab5219035a2383b0904b9dd48d4af`.

All production, test, native, dependency, script and workflow files and all PNG pixels match that reviewed tree byte-for-byte. Only 12 documentary text artifacts replace local home-directory paths with `/LOCAL_USER_HOME`; this note records the packaging. Private migration history is not an ancestor of the publication commit and is not published. Original raw evidence remains preserved locally.

Existing evidence SHAs/checksums retain their original historical meaning. They are not relabelled as runs against the publication commit, and documentary placeholders are not runnable paths. Release CI must verify the exact newly selected source independently before signing.

Blizzard applies to iOS mobile Dark and System-dark using existing layout eligibility; other themes keep their original rendering. This package adds no tester, app record, group or public App Store release. Physical VPN traffic, lifecycle, upgrade, accessibility and performance validation remain separate device work after private TestFlight delivery.
