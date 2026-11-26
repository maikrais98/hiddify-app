# Subscription routing region

A subscription may send this response header:

```http
profile-routing-region: ru
```

The header requests the core's existing Russia preset for this subscription:
The .ru domain suffix and the core's RU geosite/geoip rule sets use direct;
the remaining traffic uses the selected proxy. Rule-set availability and actual
network paths must be checked on the target build. This extension does not
import a Happ routing profile or promise identical domain lists across clients.

The value is stored with the subscription metadata and applied when its runtime
options are built. It does not change the global region preference, replace
custom routing rules, change configured DNS server addresses, or enable raw
configuration execution. The preset resolves matching RU domains through the
existing direct resolver.
Without this header, the existing behavior is preserved. Removing it on the next
successful subscription update restores the locally configured region.

Only `ru` is accepted, case-insensitively with surrounding whitespace ignored.
Unknown values and non-string/multiple values are ignored. HTTP metadata takes
precedence over an embedded metadata comment. Plain or Base64 subscriptions can
also include `# profile-routing-region: ru` among the first ten decoded lines.
The response body and server links do not need to change.

## Compatibility and rollout

Wrabbit 2.1.0 does not recognize this extension. It can continue using the
unchanged server-list format and server-side routing, but client-side RU bypass
requires a build containing this change. Upstream Hiddify is not claimed to
support the extension. Do not switch old clients to a raw sing-box configuration.

Publish the header to a dedicated test subscription first. Validate initial
import, update without re-adding, a second unrelated subscription, header removal,
restart, PL/FI, Wi-Fi/mobile DNS, and geo downloads on the actual iOS build.
Confirm RU connections leave from the device network and do not reach the VPN
ingress; confirm foreign connections use the chosen exit. HTTP success alone
does not prove the route.

The header uses the core's existing preset and does not add a runtime preference,
schema migration, native-core patch, or a forced app-wide routing-profile import.
Only add it to production subscriptions after the target-client checks pass.

Run the parser regression tests with:

```sh
flutter test test/features/profile/data/profile_routing_region_test.dart
flutter test test/features/profile/data/profile_parser_test.dart
```
