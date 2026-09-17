# Activation and support baseline

Status: **measurement contract ready; observed baseline unavailable** (2026-09-16).
Acceptance for Analytics-baseline is definitions, denominators and owners without sensitive payloads.
This delivers a usable manual aggregate worksheet, not deployed product instrumentation.

## Evidence and scope

The 2026-09-14 audit, Product Understanding and measurement sections, defines a private-issued-access
client and reports no factual activation, support or cost data. Current
`lib/core/analytics/analytics_controller.dart` enables Sentry only after opt-in;
`analytics_logger.dart` sends diagnostics, not a validated activation funnel.
`docs/privacy-data-inventory.md` forbids transmitting the local installation ID.
No new telemetry, SDK, network transmission or identity linkage is introduced here.
Crash reports must not be reused as a denominator for all users.

Use `baseline-template.json` for one **manual, observed pilot cohort**: one
observation per installation enrolled during a complete UTC calendar week, on one
platform. QA separately keeps the tested build and secure execution evidence in
its existing release protocol. Do not put identity, access material, raw errors,
server labels, links, addresses, or free text in this worksheet. The worksheet
accepts only dates, numbers and fixed enums; it cannot hold a link to evidence.
Do not combine different builds or recruitment methods in one cohort. The secure
source ledger remains under its existing access and retention policy. Product
owner must designate the actual human for each role before collecting pilot data.

## Funnel definitions

Source for every funnel event: QA's directly observed pilot tally, recorded at
the transition below; never inferred from an earlier transition. QA owns the
tally; Product owns interpretation and denominators. Collection is manual and
local. No event described here is currently emitted by the app.

| Event / count | Definition | Denominator / reporting |
|---|---|---|
| `enrolled` | Distinct pilot installations first observed opening the client in the cohort week | Recruitment count; not MAU or all downloads |
| `access_available` | Participant confirms already-issued usable access, without recording its value | `enrolled`; `enrolled - access_available` is missing/unknown access, not import failure |
| `onboarding_completed` | Eligible installation finishes onboarding, or QA verifies it was already completed | `access_available` |
| `import_started` | Eligible installation begins first observed import after onboarding | `onboarding_completed` |
| `import_succeeded` | That access is successfully persisted and available for use within 24 hours of first opening | `import_started`; count once despite retries |
| `connect_started` | Connection requested after successful import | `import_succeeded` |
| `permission_ready` | OS permission granted, or already granted and verified | `connect_started` |
| `core_connected` | Native/core connection status observed after permission | `permission_ready`; status alone does not prove traffic |
| `working_session` | QA confirms agreed harmless test traffic works through the selected tunnel on physical hardware within 24 hours of first opening | `core_connected` step rate; `access_available` primary activation rate |
| `repeat_working_session` | A later distinct connection with verified traffic, after disconnecting the first session, within 7 days of first opening | `working_session` |

All counts are unique installations within this ordered cohort, not attempt totals.
Count a stage only when its preceding stages were observed. Exclude pre-imported
returning users from this first-import cohort; measure them separately. Report
each denominator alongside its numerator. A zero or unavailable denominator yields
**N/A**, never 0% or 100%. Retries can recover within the stated window. Failures
after that window do not retroactively alter the completed cohort.

Time to first working session: `activation_elapsed_seconds_sum / working_session`;
elapsed starts at first observed opening and ends at the first verified traffic
success. It is the mean for successes only (survivorship bias); publish activation
rate alongside it. Do not interpret this aggregate as p50/p90.

## Support reasons and cost

Support owner classifies **one primary reason per case** into `missing_access`,
`import`, `permission`, `connection`, `routing`, `metadata`, `editing`, `crash`,
or `other`. The latter means unknown/unclassified too; review its share weekly.
Case = one support request about one problem; follow-ups/reopening the same problem
remain one case, a distinct problem is a new case. Keep deduplication in the secure
source system, export counts only. In this worksheet include only cases opened by
cohort participants within 7 days of first opening; this is not company-wide support.

| Metric / field | Definition and denominator | Owner | Source | Lag |
|---|---|---|---|---|
| `support_contacted` | Cohort installations with at least one case / `enrolled` | Support | Manual case tally with source-side deduplication | 7-day observation + 1 day reconciliation |
| `support_cases` | Number of cases; reason count / all cases | Support | Case ledger, only aggregate taxonomy exported | Same |
| `resolved_cases` | Cases resolved by cohort close / `support_cases` | Support | Case resolution tally | Same; pending cases remain in denominator |
| `resolution_elapsed_seconds_sum` | Sum of wall-clock open-to-resolution for resolved cases / `resolved_cases` | Support | Case timestamps aggregated at source | Same; excludes unresolved cases, report their count |
| `handling_minutes` | Sum of actual agent work minutes on included cases through cohort close, including unresolved cases | Support | Time ledger, no case text exported | Same; exclude waiting time |
| `loaded_hourly_cost_minor` | Actual attributable staffing cost / recorded available work hours, in minor currency units per hour | Finance | Payroll/vendor cost ledger, aggregated at source | After accounting close; otherwise null |
| `allocated_infrastructure_cost_minor` | Actual invoiced pilot-attributable infrastructure cost, using documented cohort allocation at source | Finance / Infrastructure | Invoice ledger and allocation, no provider details exported | After accounting close; otherwise null |
| Support cost | `handling_minutes / 60 × loaded_hourly_cost_minor` | Finance | Above measured inputs | Slowest input; **cost estimate from actual time and allocated rate**, not booked payment |
| Total allocated cost | Support cost + allocated infrastructure cost | Finance | Above inputs | Same; not revenue, profit, or cash flow |
| Cost per activated installation | Total allocated cost / `working_session` | Product / Finance | Same cohort only | Same; N/A for zero or missing denominator |

Currency is a fixed enum; never sum different currencies. Cost is a cohort-window
allocation, not a monthly run-rate. Missing invoices, labor rates or allocation
evidence stay null. Revenue and forecasts are deliberately absent: profile metadata,
imports and connections do not establish payments. A future forecast must be a
separate artifact with explicit assumptions, never entered as `observed` here.

## Collection and data checks

1. Product fixes recruitment/build/platform and assigns QA, Support and Finance owners.
2. QA records stage transitions and timings in its controlled source workflow;
   Support exports classified case totals and actual work time. QA simulation belongs
   to `synthetic`, never `observed`, and cannot establish physical tunnel readiness.
3. Close observation 8 days after the cohort's exclusive end date (7 days for the
   last enrollee plus 1 day reconciliation). Activation itself has a 24-hour window;
   do not publish immature cohorts. Accounting fields may still be null at close.
4. Fill only aggregate allowlisted fields and run
   `python3 scripts/check_analytics_baseline.py docs/analytics/baseline-template.json`.
   The template intentionally contains null facts; a valid template is not evidence.
5. Validate with `--require-observed` before accepting a measured baseline. The
   checker rejects unknown fields, wrong types, unsafe strings, impossible ordered
   counts, reason totals, denominators, inconsistent timing and immature cohorts.
   It does not certify source truth, consent, build comparability, source-side
   deduplication or invoice allocation: owners reconcile these before acceptance.

Raw pilot notes follow their existing secure retention policy; this contract does
not authorize retaining new participant identifiers. Keep aggregates only as long
as needed for the pilot review. No automated collection is enabled by this task.
