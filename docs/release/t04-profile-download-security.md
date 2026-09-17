# T-04: bounded profile downloads

Implemented from audit-2026-09-14/report.md, finding T-04.

Root remote profiles and explicit standalone HTTP(S) lines in local/remote profiles
use the same transport policy. HTTPS is required. Every hop resolves the hostname,
rejects any non-public result, and passes a selected validated InternetAddress to
Socket.startConnect. SecureSocket.secure then verifies the original hostname using
the platform trust store. The transport does not re-resolve the selected address,
disable certificate validation, or forward credentials across origins.

Limits:

- 8 MiB decoded response bytes, enforced while streaming (including chunked bodies).
- Five redirects and 30 seconds per download, including DNS and response streaming.
- Sixteen explicit nested URLs, four workers, one expansion level, 32 MiB aggregate
  content, and a shared 30-second budget for the complete expansion stage. Each nested
  download receives only the remaining budget; cancellation interrupts DNS waiting
  and a late DNS completion cannot start a connection.
- Any nested failure rejects the expansion, cancels siblings, preserves the source,
  and removes temporary files. It no longer silently drops failed nested content.

Compatibility and remaining boundaries:

- Profile downloads are direct-only. The former HTTP proxy can resolve a different
  address; routing through it cannot enforce this client's IP pin. Subscriptions
  reachable only through the app's proxy need a separate authenticated transport
  that preserves pinned destinations. OS-level VPN routing is still applicable.
- The first public DNS result is used; no alternate-address retry is attempted.
- Private/local subscriptions and IP transition ranges are deliberately rejected.
- The 30-second root download and 30-second expansion are separate stages, not a
  single 30-second import SLA. DNS work already issued to the OS cannot be aborted,
  but its late result cannot initiate a connection after cancellation.
- The byte ceilings bound downloaded content, not exact peak process memory; text
  decoding, splitting and four in-flight downloads add bounded overhead. This is
  not the separate Perf-import performance benchmark.
- Native core config features that fetch resources independently are outside this
  Dart import expansion policy; this change does not claim to sandbox the VPN core.

Policy rejections carry typed URL/address/redirect/size/depth/deadline reasons.
The parser maps address/URL/redirect rejection to invalid URL and limits/deadlines
to invalid config. Only cancellation of the external caller token is user cancel.

Verification (2026-09-16): 76 focused tests passed across policy, parser and existing
HTTPS transport suites. Coverage includes IPv4/IPv6, mixed DNS, redirect downgrade,
private redirect, same-host DNS rebinding, loop hops, chunked/declared byte limits,
stalled stream/DNS deadlines, URL count, depth, aggregate bytes and temp cleanup. Security-review regression
tests cover public addresses adjoining special-use IPv4 prefixes, a near-deadline
first URL followed by stalled DNS, and root/nested error classification.
A real direct GET to https://example.com/ returned HTTP 200 / 559 bytes using the
pinned TCP + hostname-verified TLS path; no user subscription or secret was used.
