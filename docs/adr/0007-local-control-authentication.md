# ADR 0007: authenticated local control channel

Status: implemented; Apple framework and Simulator runtime verified, physical device VPN verification required.
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

Derive a P-256 server key with SHA-256 over a domain separator and the random
session credential. Standard Go RFC 6979 signing produces a deterministic self-signed localhost certificate that lets
separate Runner/PacketTunnel processes derive the same TLS identity from native
launch options. Fixed certificate dates are solely a reproducible encoding;
actual key lifetime is the app session, not the certificate validity period.
The client obtains its certificate pin exclusively through FFI/MethodChannel,
never through the loopback endpoint. It uses a trust context without system roots.
Where platform PKI verification rejects the deterministic certificate, the only
fallback is constant-time equality with that exact certificate's DER bytes; a
different self-signed or system-trusted certificate remains rejected.
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

### Apple native artifact contract

The Apple artifact is built from `hiddify-core` commit
`f2034de743b1ad775dba026f4e6e3c44cf7d9790`, nested `hiddify-sing-box`
`170d8315cab7a8695fd80469073ed2f1d07d63af`, and the approved compressed patch
whose SHA-256 is `66ec1612e13ffc9516baa325696935e954e4410b6832f828ffcacab42821c8e1`.
The source-build gate creates an expected Git tree from that commit plus patch
in a temporary index and rejects extra tracked, untracked, ignored Go, or dirty
nested-submodule sources. The XCFramework carries `provenance.json` with these
pins, the exact expected source-tree object, toolchain versions, and both slice
digests. CI initializes the same submodule and uses this source build; iOS no
longer downloads a separately versioned core archive.

For the iOS foreground core, Runner currently selects setup mode 4 even though
the Dart caller passes mode 3. Consequently lifecycle owners must close mode 4.
`Setup(mode: 4, sameSecret)` is idempotent and returns the same deterministic
certificate. `Setup(mode: 4, differentSecret)` fails with
`control API session changed; restart native core`; live secret rotation is not
supported. `Close(mode: 4)` stops the listener before its RPC response is
necessarily flushed, so callers must verify listener shutdown rather than
requiring a clean response. Only after full server/process stop may a new secret
be set up, yielding a new certificate. A surviving PacketTunnel must receive the
same in-memory secret through trusted start options to derive the same pin;
otherwise reconnect/restart both ends. `MobileGetServerPublicKey` is meaningful
only after successful native setup.

The Simulator-only `_test_setup_packaged_core` method directly exercises the
linked XCFramework without writing NetworkExtension preferences. It is removed
from device builds by `targetEnvironment(simulator)` and is not a production VPN
bypass. The packaged probe verifies correct pin/bearer success, missing and wrong
bearer rejection, wrong and stale pin rejection, same-secret idempotence,
different-secret live rejection, listener shutdown, fresh-secret setup, and
post-rotation rejection of old credentials. Simulator evidence does not prove
packet-tunnel operation; that remains a physical-device signing/runtime gate.

### Recorded checks (2026-09-16)

- `go test -race ./v2/localauth ./v2/hcore`: PASS for the exact patched source.
- Source-provenance regression: PASS; extra tracked edits and untracked Go files
  are both rejected without modifying the source checkout.
- Pinned-source Apple XCFramework build: PASS for device and Simulator slices;
  digests and toolchain are recorded in its provenance manifest.
- Packaged Simulator auth/TLS lifecycle probe: PASS, including rotation and
  stale-credential rejection. This validates local control only, not VPN traffic.
- Focused Dart analysis, release gates, archive integrity, and app/core
  whitespace checks: PASS. Physical-device VPN and signed distribution remain
  separate gates and are not claimed by this ADR.
