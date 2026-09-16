# Safe diagnostic summary

The Logs screen now has a Safe diagnostics action. Opening it captures one
snapshot, presents a translated category and stage, and previews the complete
JSON. Create file writes `safe-diagnostics.json` to a dedicated temporary
directory. Share file is a separate action opening the OS recipient/save picker.
Closing the page removes the temporary copy (OS cache cleanup is the fallback if
deletion fails or the process is killed). No automatic upload is performed.

The exporter serializes create, share and discard internally. Concurrent creates
reuse one owned file; discard waits for earlier operations and removes their
directory before completing. This guarantee does not depend on disabled UI buttons.

## Source and scope

This implements **Safe-diagnostics / Создать безопасную диагностическую сводку**:

- [Audit: preview/redaction gap](../../audit-2026-09-14/report.md) (line 438), with the original competitive benchmark evidence.
- [Audit: summary contract](../../audit-2026-09-14/report.md) (line 535).
- [Audit: Safe-diagnostics acceptance](../../audit-2026-09-14/report.md) (line 580).
- [Privacy inventory](privacy-data-inventory.md).

## Collection boundary

`SafeDiagnosticSummary.capture` observes only the structural type of
`ConnectionStatus` and `ConnectionFailure`, plus the OS platform enum. The result
stores four enums. It never stores the source status/failure object. The JSON
contains schema version, category, stage, safe code, platform, and the explicit
`reachability: not_checked` marker. Connected means tunnel status only.

Raw logs, provider values, failure messages/objects/stacks, email, profile names,
server tags, URLs, configuration and tokens are not read or copied into the
summary. There is no regex redaction or hashing of secrets. Arbitrary app version
and build metadata are intentionally omitted from this minimal schema; a future
version field needs a separately reviewed bounded build-source contract.

The exporter never passes exceptions, paths or native share results to logging
or analytics. It exposes only closed result enums. The UI displays the fixed
filename, not a user-directory path. The OS sharing API necessarily receives a
local temporary path; no source credentials are used to derive it. The exported
file contains exactly the preview bytes. Cancelling or an unavailable result is
not reported as successful delivery.

## Verification and limits

Run `flutter test --no-pub test/security/safe_diagnostics_test.dart`.

The tests cover every current failure variant and connection stage, a hostile
URL/email/config payload, an object whose `toString` throws, IO failure, native
share failure and cancellation. The six-sink test exercises the actual screen,
file creation and sharing service. It inspects:

| Sink | Evidence |
| --- | --- |
| Logs | Real LoggerController fanout and FileLogPrinter disk output; positive marker proves the sinks were attached |
| Breadcrumbs | Production LogRecord breadcrumb and Sentry-event serialization |
| Diagnostic state | Closed-enum snapshot and its complete serialization |
| Preview | Actual SelectableText in the widget |
| File | Bytes from the actual temporary JSON file, equal to preview |
| Export | Native shareFiles MethodChannel arguments and the file read at dispatch |

The canary is absent from all six. A hostile native share response and exception
are also discarded. Widget assertions prove no file exists before Create file,
no share occurs during creation, and closing the page deletes the temporary file.
Completer-controlled race tests overlap two creates, and discard while directory
resolution is blocked; after discard neither files nor directories remain.

This proof covers the new summary pipeline. It does not establish that unrelated
historical/raw core logs, profile editor state or all app crash paths are free of
secrets. Existing raw-log export remains separate. Native OS share-sheet behavior,
recipient delivery and recipient retention require device validation; the test
intercepts the native plugin boundary. A user-saved/shared copy is outside the
app's temporary-file deletion lifecycle. The summary is a snapshot and does not
claim current internet reachability or automatically infer a recovery action.
