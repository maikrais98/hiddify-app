# Observability contract

The application emits only versioned, closed-vocabulary diagnostic events. Raw VPN-core output remains local and is never forwarded to Sentry. AppMetrica is intentionally not part of this technical-error pipeline.

## Event envelope

Every event is created through `ObservabilityClient` and contains only allowlisted fields:

`schema_version`, `timestamp`, `environment`, `app_version`, `build_number`, `platform`, `session_id`, `operation_id`, `request_id`, `module`, `operation`, `event`, `status`, `duration_ms`, `error_code`, `endpoint_class`, `status_class`, `retry_count`, `count`.

URLs, profile names and IDs, server addresses, configuration, headers, tokens, receipts, native error text, stack traces and absolute paths are forbidden. The console, file and Sentry boundaries apply redaction again. Automatic Sentry transactions are dropped until a typed transaction exporter exists.

Automatic Cocoa/NDK crash capture is also disabled because native events bypass the Dart sanitizer. Packet Tunnel failures use the typed App Group bridge instead. Native crash capture may be restored only after a native exporter enforces the same closed schema.

## Environment and consent

- `dev`: local/development diagnostics.
- `beta`: selected by the TestFlight workflow with `telemetry_beta=true`; technical telemetry is enabled for the beta build.
- `prod`: telemetry remains user opt-in.

Sentry release and distribution identify the exact app version and build. The Safe Diagnostics screen has an explicit test-event action; test events are never sent automatically.

## Initial Sentry views and alerts

Create views grouped by `module`, `operation`, `error_code`, `release` and `dist`.

- Alert immediately for a new classified fatal event. Native crash alerts remain unavailable until the native typed exporter exists.
- Alert on five identical `error_code + operation + dist` events in 15 minutes.
- Alert when failed `connect` terminal events exceed 10% over 30 minutes with at least 20 attempts.
- Track p95 from the numeric `observability.duration_ms` context; alert above 20 seconds for `connect`.
- Keep dedicated views for `permission_denied`, `invalid_configuration`, `core_initialization_failed`, `tunnel_start_failed`, `connection_timeout` and `status_stream_unavailable`.

Revisit thresholds after two beta builds. Do not enable raw attachments, screenshots, request bodies or automatic transaction export.

## Confirmed physical-device cases

### XHTTP configuration rejection

The observed `xPaddingBytes cannot be disabled` failure is classified as `invalid_configuration` during VPN configuration/startup. The raw message and subscription contents stay local. This observability change does not alter the converter.

The separate product fix should add a non-zero default XHTTP padding range (for example `100..1000`) in the converter and/or normalize missing legacy values, with a regression test for an XHTTP URI without `extra`.

### Local foreground import

Local and remote imports now share one operation ID across parsing, validation and persistence stages. Known invalid configuration and unknown import failures remain distinct, while URI, profile name/ID, configuration and underlying error are excluded.

## Release acceptance

Before a beta is accepted:

1. Run the privacy canary through Flutter logging, local file output, Sentry filtering and the native Packet Tunnel bridge.
2. Trigger an explicit Safe Diagnostics test event and confirm its `environment`, `release` and `dist` in Sentry.
3. Exercise permission denial, invalid configuration, tunnel start failure, timeout, reconnect and disconnect on a physical iPhone.
4. Confirm the native failure event reaches Flutter with the same operation ID and an allowlisted error code.
5. Inspect the exported Safe Diagnostics JSON and confirm it contains no raw logs or user/service identifiers.

TestFlight processing or installation alone is not proof that Packet Tunnel traffic works.
