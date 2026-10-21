# WIR Baseline telemetry on Better Stack Free

The main application sends its existing closed-schema diagnostic events to Better Stack Logs and
classified error events through `sentry_flutter` to Better Stack Errors. A Sentry
account is not required. The same `session_id` / `operation_id`, version and build
identify related events. Raw VPN output, subscription URLs, addresses, tokens,
native error messages, stack traces and arbitrary logger messages stay local.
The contract in [observability.md](observability.md) still applies.

## Baseline source selection

The shipped WIR Baseline application uses `fix/baseline-vpn-reliability`, which
is a separate application tree from `main`. Its integration follows new typed
`SafeDiagnosticJournal` events directly, excludes restored history and raw logs,
and keeps the native safe Sentry transport. See source PR #50 and its
`docs/betterstack.md` for that implementation and the device acceptance steps.
The protected controller must pin the tested Baseline source, never main's app.
The three ingestion settings have been installed in `release-signing`.

## One-time setup

The initial resources have been created in team `620118`:

- [WIR Baseline logs](https://telemetry.betterstack.com/team/t620118/sources/2805644)
- [WIR Baseline errors](https://errors.betterstack.com/team/t620118/applications/2805645/data-ingestion)

Install GitHub CLI and run `gh auth login` with access to repository/environment
secrets. Obtain a team-scoped Telemetry API token from Better Stack API tokens.
Run this command from the reviewed checkout:

```sh
python3 scripts/setup_betterstack.py \
  --team-id 620118 --team-name 'Your team' \
  --repository maikrais98/hiddify-app --environment release-signing
```

It prompts privately for the API token and performs a read-only dry run. Repeat
with `--apply` to reuse/create the resources and set three ingestion secrets in
the existing GitHub `release-signing` environment:

- `SENTRY_DSN`
- `BETTERSTACK_LOGS_URL`
- `BETTERSTACK_SOURCE_TOKEN`

The management API token is not stored in GitHub or embedded in the application.
Do not paste it into chat or commit it. The ingestion credential is embedded in
the distributed client and can be extracted; it grants ingestion, not account
administration. This first integration is for the controlled Baseline beta.

An existing resource with a different platform/correlation is rejected rather
than silently replaced. Setup preserves the account's default retention and
does not select a paid plan, enable AI SRE, or alter billing settings.

## Build integration

Both `.github/workflows/ios-baseline.yml` and `testflight.yml` validate these
settings using `scripts/prepare_telemetry.py`. The script writes a mode-0600 file
in `RUNNER_TEMP`, passed to Flutter with `--dart-define-from-file`. Its values are
never printed or included in workflow artifacts. No dependency was added.

Baseline requires all three settings and telemetry-capable reviewed source. The
general TestFlight workflow still allows a completely unconfigured local-only
build, or its existing Sentry-only mode. Partial Better Stack settings fail before
compilation. Beta enables technical telemetry; production remains opt-in; debug
builds do not transmit by default. Both SDK tracing and interaction tracing are off.

The Baseline workflow deliberately pins `TRUSTED_RELEASE_SOURCE_SHA`. This PR
does not move that release pin or dispatch signing/upload. Before releasing these
changes, the reviewed telemetry-capable source commit must be approved through
the existing release process and that pin updated in a separate release change.
The `TELEMETRY_SOURCE_MISSING` guard prevents claiming logs are enabled when
building an older source that cannot send them.

## Free-tier controls

- Logs retain the plan default (currently 3 days); account allowance is 3 GB/month.
- Each installation reserves at most 256 KiB of JSON log bodies per UTC day,
  including retries, and 50 error events per UTC day. Counters persist across
  restarts. Failed storage writes prevent transmission. Clock rollback grants no
  new allowance.
- Only INFO and above from the `observability` logger are eligible. Unknown fields
  are removed again at the HTTP boundary. Repeated warning/error signatures are
  limited to one per minute.
- The memory-only queue holds at most 100 events, each at most 2 KiB. A request
  sends up to 20 events after 10 seconds; app backgrounding attempts a flush.
- Requests time out after 5 seconds. Transient failures have at most three attempts
  per batch with backoff. HTTP 402, 401 and 403 stop this exporter for the session.
  No redirects are followed with the ingestion token.
- Successful operation terminals go to Logs rather than consuming the Errors
  allowance. Error grouping and privacy filtering are preserved.

Per-installation caps cannot guarantee an account-wide free allowance for an
unlimited number of installations, and client credentials can be abused. Keep
the account on Free with no paid overage allowance. Check aggregate usage in
Better Stack during beta. The demonstration flight source is separate and should
be paused/deleted in the UI if it consumes unwanted quota. This change does not
automatically delete existing account resources.

## Validation and first device check

The narrowly scoped `Free-tier telemetry checks` workflow runs Python setup tests
and Flutter telemetry, consent, privacy and cleanup tests. It has read-only repo
permissions, uses no service credentials and does not run scheduled builds.

After the reviewed build is installed on a physical iPhone:

1. Open Safe Diagnostics and tap **Send test event** once. Creating the event in
   the UI is not proof of delivery.
2. Confirm `test_event` in Better Stack Logs with the installed version, build
   and beta environment. Baseline Errors keeps its existing fixed severity codes;
   the explicit device test targets Logs. Allow a few seconds for ingestion.
3. Exercise connect, reconnect, disconnect and an expected failure; inspect the
   corresponding typed events and operation IDs.
4. Verify a period without network does not block startup or VPN operation.

MCP provides on-demand investigation from chat. Continuous AI analysis, external
LLM API calls, paid incident features and automatic TestFlight publishing are not
part of this integration.
