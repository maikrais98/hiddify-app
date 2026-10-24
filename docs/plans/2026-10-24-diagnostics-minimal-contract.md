# Minimal diagnostics integration contract — 2026-10-24

Implementation boundary for the approved `../2026-10-24-diagnostics-integration-handoff.md` (authoritative copy is `/Users/stasyudkin/Documents/KVN/docs/2026-10-24-diagnostics-integration-handoff.md`). This is a contract, not evidence of implemented behavior. No production changes in this contract task.

## Ownership

- Schema/delivery integrator: `lib/features/diagnostics/safe_diagnostic_event.dart`, `safe_diagnostic_journal.dart`, `remote_diagnostic_subscription.dart`, new `native_diagnostic_importer.dart`, `lib/core/observability/better_stack_log_printer.dart`, analytics wiring, SafeDiagnosticsPage, matching tests. Sole owner of shared enums and serialization.
- Dart subscription implementer: profile repository/parser/data source, DioHttpClient, subscription action callers, matching tests. Consume the schema below; do not edit schema/delivery files. Parent owns connection notifier/core-interface integration with the existing UI patch; coordinate any shared-file edits before touching them.
- Native implementer: `ios/HiddifyPacketTunnel/Logger.swift`, ExtensionProvider, platform interface, `ios/Runner/VPN/VPNManager.swift`, `ios/Runner/Handlers/MethodHandler.swift`, Swift tests and necessary target membership. Logger.swift is already compiled into both targets. No Dart production edits.

## Preserve v1; only add optional typed attributes

Existing required fields and names remain unchanged: sequence, operation_id, operation, stage, code, duration_ms, reachability=`not_checked`. Existing persisted events parse without changes. Unknown keys/enum names, invalid numeric types/ranges and arbitrary strings are rejected. Absent optional fields are omitted, not serialized as null. Equality/hash/restore include new fields.

Extend DiagnosticOperation with `subscriptionImport`, `subscriptionUpdate`, `native`.
Extend DiagnosticStage with `skipped` (existing requested/accepted/failed/state retain meaning).
Extend DiagnosticCode with `unknown`, `cancelled`, `partialFailure`, `storageFailure`, `overflow`, `unsupported`, `noError`, `noProfile`, `stale`, `notConnected`, `busy` (existing codes remain).

Add these optional constructor/record parameters and corresponding snake_case JSON keys, all strictly typed:

| Dart parameter / JSON key | Type / allowed values |
|---|---|
| phase / phase | DiagnosticPhase enum below |
| trigger / trigger | DiagnosticTrigger: manual, automatic, importAction |
| parentOperationId / parent_operation_id | int 1..maxCounter; update→reconnect only |
| httpOutcome / http_outcome | DiagnosticHttpOutcome: success, connectionTimeout, sendTimeout, receiveTimeout, badCertificate, badResponse, cancel, connectionError, unknown |
| httpStatus / http_status | int 100..599, only actual response status |
| selectedMode / selected_mode | DiagnosticHttpMode: direct, proxy, both |
| retryCount / retry_count | int 0..3, only observed retries; absent if unavailable |
| nestedTotal / nested_total | int 0..65535, saturated aggregate |
| nestedFailed / nested_failed | int 0..65535, <=nestedTotal when both present |
| nativeStatus / native_status | DiagnosticNativeStatus: invalid, disconnected, connecting, connected, reasserting, disconnecting, unknown |
| errorDomain / error_domain | DiagnosticErrorDomain: neVpn, neProvider, posix, url, cocoa, unknown |
| errorCode / error_code | signed 32-bit int; only with allowlisted non-unknown errorDomain |
| stopReason / stop_reason | int 0..255, directly from NEProviderStopReason; unknown/out-of-range omitted with code unknown |

DiagnosticPhase: action, download, nestedDownload, metadataParse, changeOptions, validateAndCommitConfig, dbPersist, reconnectDecision, reconnectResult, foregroundReady, optionsReady, backgroundStart, preferencesLoad, preferencesSave, preferencesReload, networkSettings, tunDescriptor, sleep, wake, lastDisconnectError.

Use stage requested before an awaited operation and accepted after actual completion; failed only on actual failure. `accepted` does not assert network reachability. `nestedDownload` emits one aggregate result per parent attempt, not one event per URL. For descriptor observation, accepted means obtained; skipped/unknown means unavailable. No descriptor value/branch string. Native state has nativeStatus; foreign connection notifications are ignored before recording. For callbacks unsupported/nil/stale use DiagnosticCode and omit fabricated NSError fields.

`operationId=0` additionally allowed for DiagnosticOperation.native: autonomous native observations have no fabricated Dart correlation. Native disconnect-error correlation is maintained inside VPNManager using a monotonically incrementing local disconnect generation; reject completion if generation or connection identity changed. Do not claim association with a connect attempt when no actual ID was passed through existing start options. Existing tunnel/state zero rule remains.

## Dart instrumentation signatures and semantics

`DioHttpClient.get/download` gain optional `void Function(DiagnosticHttpResult result)? onDiagnostic`; result is a closed typed value with `outcome`, `selectedMode`, optional `httpStatus`, optional `retryCount`. Define this result alongside DioHttpClient (not in schema). Mapping to event occurs at caller. Callback exceptions cannot change HTTP result/error. Catch DioException only to inspect `.type` and `.response?.statusCode`, then rethrow the same object. Other errors map unknown; never inspect text. The callback fires once per logical request after Dio's existing retry interceptor. Count retries only if actual interceptor metadata is verified; otherwise omit retryCount rather than assume zero.

Pass one optional `int? diagnosticOperationId` and `DiagnosticTrigger? diagnosticTrigger` through subscription entry methods and internal parser/downloader paths as needed. Allocate the operation ID inside each TaskEither execution, not when constructing the task. Re-running a TaskEither creates a fresh attempt. Callers needing update→reconnect allocate inside their own execution and pass the same ID; reconnect gets its own ID and parentOperationId. Keep public old call sites source-compatible through named optional parameters.

Do not move existing eager operations or otherwise change existing laziness/order; newly added diagnostics are lazy. Preserve returns, Left values, thrown exception identity, cancellation, nested partial-failure business behavior, and reconnect conditions. Never split validateConfigByPath into imaginary validation and commit successes.

## Native journal and existing bridge

Reuse NativeDiagnosticLog, preserving its safe legacy text log API. Add a bounded structured typed sidecar through the same class, NOT another sender. One file per writer (`runner`, `extension`) under the shared app-group directory avoids cross-process append races. Each is bounded to 64 KiB / 128 records; preserve previous episode on start, no reset of structured records. Atomic replacement with retained suffix. A local generation value changes only when journal is re-created; monotonic sequence survives restart. Generation is random 16 lowercase hex characters, local-only and unrelated to profile/device/account IDs. Read snapshots atomically; malformed snapshots produce closed failure, never raw content.

Existing method channel: native `MethodHandler.name` / Dart `CoreInterfaceMobile.methodChannel`; add method `read_safe_diagnostics`, no arguments. Return closed map:

```
{version: 1, sources: [
 {source: 'runner'|'extension', generation: <16 hex>,
  first_sequence: <positive int or 0 if empty>, last_sequence: <nonnegative int>,
  dropped_count: <nonnegative bounded int>, storage_failed: <bool>,
  records: [{source_sequence: <positive int>, event: <v1 event map>}, ...]}
]}
```

Maximum two sources / 128 records each. Events have operation=native, operation_id=0; event.sequence equals source_sequence on wire. Dart replaces sequence with its own journal sequence when recording. No path, timestamps from log text, UUID, domain string, description, userInfo, URL, bytes, config, profile identity or FD crosses the bridge. Generation/source_sequence are import metadata, never remote payload fields. Native writer emits exactly the Dart enum spellings above, mapping NSError domains by equality against constants. Existing string classifier can remain legacy-only and cannot supply typed root-cause claims.

Read is non-destructive: no ACK method and no deleting records after read. Recording diagnostics must not change native callback count/order/error behavior. Availability-guard fetchLastDisconnectError at iOS 16; compare disconnect generation in callback. Record sleep/wake receipt and MobileWake completion separately using requested/accepted with phase wake; neither means traffic recovery.

## Durable handoff in existing outbox

Add minimal local-only source checkpoint data to existing `blizzard-remote-outbox/v1` document as optional `source_cursors`: list of at most two `{source, generation, sequence}` with closed source and validation above. Old six-key documents remain valid. Checkpoints survive dequeue/HTTP receipts so rereads do not re-enqueue delivered native events. New event payload keys are optional and validated by SafeDiagnosticEvent, not arbitrary extension maps.

Public API:

```
enum DiagnosticEnqueueResult { persisted, alreadyPersisted, disabled, storageFailed, rejected }
Future<DiagnosticEnqueueResult> addImportedDiagnostic(
  SafeDiagnosticEvent event, {
  required String source, required String generation, required int sourceSequence,
});
```

Strings here are validated closed-source / strict generation-format metadata at boundary. Source key is `(source,generation,sourceSequence)`. Stable remote event_id must derive from that key using existing stable hashing mechanism, not current app session or new Dart sequence. Do not upload source key. Stable ID permits downstream deduplication, does not prove exactly-once.

Required transaction: serialize importer calls; stage event plus cursor in one outbox snapshot; persist successfully before considering cursor committed or allowing the staged event to send. A failed write returns storageFailed; leave durable and in-memory committed cursor unchanged and block unpersisted staging from send. Retrying same key must retry persistence, not report alreadyPersisted. Existing null writer may be acceptable for ephemeral ordinary telemetry, but MUST NOT return persisted for imported durable events. Ensure bound-fitting has retained the exact imported event before cursor commit; rejected/evicted-before-persist does not advance cursor. Disabling while persistence is pending must not schedule/send after disabled.

Ordinary RemoteDiagnosticSubscription must not double-forward native import events: importer records locally through a dedicated journal import method / notification distinction, and owns the explicit awaitable remote enqueue path. On repeated bridge read, local dedupe can be volatile; remote checkpoint is authoritative. Local journal-only display must continue when analytics OFF. OFF performs no outbox enqueue/persist/network and must not cause later upload of observations collected while OFF: on enable take a native snapshot baseline, persist only cursor baselines without event payloads, then import newer events. If baseline persistence fails, block remote import and expose storage failure. Keep local display cursor and remote checkpoint separate.

On restart with analytics already enabled, resume existing persisted remote cursor; do not baseline away pending native events. Source rotation/first_sequence beyond expected cursor indicates an explicit gap; show bounded dropped count / overflow, then process retained suffix. If native storage fails, display storage failure; cannot promise recovery of absent records. Existing TTL/queue eviction/daily budget remain and expose their existing drop counters. No capacity or 5 MiB budget increase.

## Acceptance gates before integration

1. RED then GREEN: legacy event/journal/outbox restore; every optional field valid/invalid; privacy canaries rejected; queue keeps unknown strings out.
2. Subscription: no event before TaskEither.run; repeated runs new IDs; unchanged call order/result/exception; nested partial failure observed once; requested and actual reconnect result linked; no extra reconnect.
3. Dio: all DioExceptionType values; real status; mode selected not asserted actual route; callback cannot change result; no secret-bearing properties read or emitted.
4. Native: all six statuses distinct; foreign observer ignored; stop reason/settings/TUN/preferences/sleep/wake observations; nil/stale/unsupported disconnect error; callback semantics unchanged; both Runner and PacketTunnel targets compile.
5. Import: crash after source read; failed outbox write; retry same key after failure; crash after successful persist before next read; restart after delivered dequeue; concurrent flush; saturation; source generation rotation; corrupt bridge payload; no writer; OFF and OFF→ON baseline. No cursor may suppress an event absent from persisted queue unless it is the explicit OFF baseline or already-committed prior delivery/drop lifecycle.
6. Measure a normal update+reconnect and a failure episode against 128 records/64 KiB; report overflow rather than silently increase limits. Unit/build results do not imply device traffic acceptance or release authorization.

Implementation clarifications: parent approved foregroundReady and noProfile for distinct existing connection outcomes. Journal v1 additionally persists optional bounded dropped_count to expose capacity loss. Native importer reuses existing accepted delivery notifications to resume a capacity-blocked backlog; no timer or additional network monitor. OFF-to-ON baseline requirement is persisted before analytics enable and retained across restart until native cursor baselines are durable. Native source storage_failed blocks baseline establishment.

Final failed-write clarification: never retain an uncommitted native event payload for a later successful write: it could cross an analytics OFF-to-ON snapshot taken from the older on-disk journal. Restore the previous records and sequence on failure, latch storage_failed and increment bounded dropped_count. The next observation reuses the never-committed sequence, so retained records remain contiguous. A source-scoped categorical failure marker reuses the existing shared app-group UserDefaults suite; init and bridge reads merge it, and it is cleared only after the journal has atomically persisted storage_failed=true. This is best-effort partial-storage-failure visibility, not a durable acknowledgement from UserDefaults. If both shared storage paths fail or the marker is not yet visible cross-process, immediate Runner detection is unavailable; the failed event payload is still never retried. Exact failed-event count across a writer crash is not guaranteed. No new transport, schema or core is added.
