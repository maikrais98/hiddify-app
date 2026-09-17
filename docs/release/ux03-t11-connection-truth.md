# UX-03 / T-11: connection state and native failures

Source: [audit T-11](../../../audit-2026-09-14/report.md#t-11-ios-vpnmanager-подавляет-первопричину-setupsavestart-failure), [audit UX-03](../../../audit-2026-09-14/report.md) (rows UX-03, T-11; source trace at report line 735).

## Changed contract

- VPN preference load/save/enable and synchronous tunnel start errors propagate to MethodHandler. A thrown native operation cannot return `true`. Elapsed connection time starts on the `.connected` status notification, not on a start request.
- MethodChannel failure carries operation (`SETUP` / `SETUP_CONNECTION`) and native NSError domain/code. Raw localized descriptions are excluded from these responses because they can contain configuration information.
- Dart converts platform errors to a small `NativeConnectionError` value and an existing typed `BackgroundCoreNotAvailable` failure. Setup preserves that failure through the repository; start returns Left and publishes Stopped immediately instead of leaking an exception while remaining Starting. The existing notifier displays the failure presentation.
- Connected always offers Disconnect (or Reconnect when options require it). Latency is a separate proxy reachability observation and cannot relabel a connected tunnel as Connecting. An accepted native start is not evidence of working VPN traffic.

## Local checks (2026-09-16)

- Targeted Flutter regression suite: native MethodChannel errors and safe UI presentation; service start failure and Starting→Stopped; repository setup failure identity and blocked start; production connection control with unknown reachability; existing connection repository/home scenarios.
- Swift frontend parsing: `xcrun swiftc -frontend -parse ios/Runner/VPN/VPNManager.swift ios/Runner/Handlers/MethodHandler.swift` passed.
- Scoped Dart analyzer: no errors; existing warnings in HiddifyCoreService (unused imports/variable, unreachable switch) remain. This is not a clean project-wide analyzer gate.

## Signed-device smoke remains required

No signed physical-device tunnel run or native fault-injection XCTest was performed here. Swift parsing and mocked Dart channel tests do not prove NetworkExtension runtime behavior. Before release record build, device/iOS, signing/entitlements, network and evidence for permission deny/allow, preference load/save failure, start failure, successful traffic, stop, reconnect and network change. Verify failure text contains operation/domain/code, failures do not remain Connecting, and Connected with unknown/failed URL-test still offers Disconnect. Asynchronous extension failures continue through the existing status/alerts stream and need device verification separately from synchronous NSError propagation.

## Initialization-path regression follow-up

The production iOS notifier now stops initialization on setup Left and exposes the original typed failure as AsyncError before subscribing to connection status. The connection control displays its safe presentation and a Retry action, including when no profile exists. Retry rebuilds initialization; another failure remains retryable, and only successful setup subscribes to native status. This prevents a late-uninitialized native client from replacing the original error.

`native_initialization_failure_test.dart` exercises the actual ConnectionNotifier build and production ConnectionButton with iOS initialization enabled: initial failure, repeated failure, visible native code, no status watch after either failure, successful retry and exactly one watch subscription. The combined targeted suite passes 20 tests.
