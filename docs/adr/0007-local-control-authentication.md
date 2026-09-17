# ADR 0007: authenticated local control channel

Status: implemented in source; native binary rebuild and device verification required.
Date: 2026-09-16. Audit: T-07.

## Evidence and threat

Before this change desktop/mobile selected modes 3/4, which created a plain
`grpc.NewServer()` and ignored SetupRequest.Secret. Desktop and Flutter mobile
accepted an arbitrary `Hello` response before calling their trusted native setup.
Any process able to connect to the fixed loopback ports could invoke unary or
streaming control methods; a process occupying the port could impersonate core.

Scope: an unprivileged local process outside the app sandbox, without access to
app memory, debugger privileges, or root. Protect every RPC including Hello and
streams. Root, injected code, and denial of service by binding the port are outside
this boundary. This does not change the separate proxy/Clash API.

## Decision

Retain TCP loopback for Flutter, Go, Android Wire, and iOS extension compatibility.
For historical setup modes 3/4, require an app-generated 256-bit CSPRNG session
credential, TLS 1.2 or newer, and bearer authentication on every unary/streaming RPC.
Missing, malformed, duplicate, or wrong authorization metadata is rejected before
the handler. No insecure compatibility fallback is allowed. These enum names are
legacy wire values, no longer a statement about transport security.

Derive an P-256 server key with SHA-256 over a domain separator and the random
session credential. Standard Go RFC 6979 signing produces a deterministic self-signed localhost certificate lets
separate Runner/PacketTunnel processes derive the same TLS identity from native
launch options. Fixed certificate dates are solely a reproducible encoding;
actual key lifetime is the app session, not the certificate validity period.
The client obtains its certificate pin exclusively through FFI/MethodChannel,
never through the loopback endpoint. It trusts only this certificate, performs
normal hostname verification, and never accepts bad certificates or system roots.
The bearer credential is sent only after TLS verifies this native identity.

Native setup happens before Hello. Existing in-process setup can be reused only
with the same credential. Port collisions fail closed, rather than trusting the
occupying process. Empty credentials fail before a server can start. Invalid or
legacy native builds cannot produce a matching authenticated channel.

## Lifecycle and platforms

- Desktop: generate once per Dart process with Random.secure; pass through FFI;
  keep only in memory. A second application process cannot adopt the first one's
  listener. Restart the app/core together to rotate.
- Android: foreground setup receives the credential via Flutter MethodChannel;
  VPN service receives it via app-process memory (services use the app process).
  P-256 and TLS 1.2 preserve compatibility with older Android TLS providers.
  Notification RPC uses the active native certificate and token. No preference,
  settings export, command-line argument, or log contains the credential.
- iOS: Runner gets the credential through MethodChannel; PacketTunnel receives it
  in NETunnelProviderSession start options, not shared preferences or a file.
  Both derive the same pin independently. Automatic extension startup without
  authenticated app launch options fails closed. After an app-process restart,
  reconnect the tunnel to establish the new session before control RPC is used.
- Existing mTLS modes 1/2 retain their original behavior; app entry points no
  longer select them. Standalone callers using legacy modes must supply a valid
  credential and use TLS or will fail. No silent insecure downgrade is supported.

OS-native IPC was considered but needs a separate Windows named-pipe transport,
Unix socket permission lifecycle, Flutter gRPC adapters, and iOS extension IPC.
A pinned TLS channel provides a single auditable minimum across these platforms.

## Verification and deployment boundary

`go test ./v2/localauth -count=1` starts an actual TLS gRPC listener and checks
that a separate OS process without the session credential cannot execute unary
or streaming RPC; missing/wrong credentials cannot reach handlers, valid ones can,
and a different server identity cannot reach the handler. It also verifies native
processes derive an identical pin and malformed credentials are rejected.

Rebuild and package Go desktop, Android, and Apple native libraries from this
modified core submodule. Source tests alone do not establish that a bundled
prebuilt framework enforces authentication. Before shipping: run the unauthorized
RPC probe against each packaged target, verify notification traffic, connect /
disconnect / relaunch, and test an iPhone tunnel. Keep T-07 in verification until
those packaged-runtime checks pass. No physical VPN validation is claimed here.

### Current native build blocker

The isolated authentication package passes its TLS integration tests. A full
`go test ./v2/hcore -run '^$'` is blocked by existing nested-submodule drift:

- `hiddify-sing-box/protocol/{socks,mixed,tor}` calls the older
  `socks.HandleConnectionEx` signature; the selected `sing` version now requires
  a UDP timeout. Its TLS wrappers also lack `HandshakeTimeout` setters/getters.
- A bounded compatibility trial passed those points, then exposed a second
  mismatch in `ray2sing/ray2sing/{awg,warp}.go`: `AwgEndpointOptions.Awg`,
  `T.AwgOptions`, and `T.WARPEndpointOptions` no longer exist in selected sing-box.
  The trial was reverted to avoid an unverified cross-submodule migration.

Resolve/pin a compatible sing + sing-box + ray2sing dependency set, rebuild all
native artifacts, then run the packaged-target checks above. Current source
integration is not a shippable native build and must not be marked Done.

### Recorded checks (2026-09-16)

- `GOMODCACHE=/private/tmp/t07-gomod GOCACHE=/private/tmp/t07-gocache go test ./v2/localauth -race -count=1` from `hiddify-core`: PASS (2.737s), including the separate untrusted process. The test needs permission to bind an ephemeral loopback port; the sandbox denied that bind, so the successful run used reviewed escalation.
- Dart analysis of the three changed control-interface files: no errors; the existing mobile unused `_logger` warning and two redundant `maxTry` argument infos remain.
- `xcrun swiftc -frontend -parse` of MethodHandler, VPNManager, and ExtensionProvider: PASS. This is syntax checking, not native linking or iPhone execution.
- App `git diff --check`: PASS. Core `git -c core.whitespace=cr-at-eol diff --check`: PASS (preserves its original CRLF file).
- Full hcore compilation: BLOCKED as described above. Android compilation and signed Apple packaged-runtime tests are not claimed.
