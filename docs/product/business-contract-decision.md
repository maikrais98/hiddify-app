# Account, recovery, and billing decision

Date: 2026-09-16. Decision owner: Product owner. Status: **NO-GO for implementation**; reopen only after the gates below have evidence.

## Decision

Keep Woman in Red as a local client for importing and using access supplied by an external provider. Do not add signup, password reset, billing, StoreKit, prices, trials, purchases, or upgrades in the current product loop.

This is a product decision, not a claim that these capabilities have no value. The current repository has no authenticated entitlement API, backend owner, payment contract, verified recovery identity, or observed revenue/support baseline. Adding account-shaped UI before those exist would create an unsupported promise and expand the privacy and support surface.

## Evidence boundary

### Facts

- Access is granted by imported profile URL, QR/deep link, or local file. Optional email and avatar are stored locally and do not authorize access.
- The application has no route for registration, login, password reset, paywall, trial, purchase, or subscription management.
- The accepted iOS MVP scope explicitly excludes billing, StoreKit, prices, trials, purchases, and upgrades.
- No factual MAU, paid renewal, ticket rate, support time, infrastructure cost, or retention baseline is available yet.

### Estimates

These are planning ranges, not commitments. One person-day means one fully loaded engineering/product day; let its monetary cost be `R`.

| Workstream | P50 person-days | P90 person-days |
|---|---:|---:|
| Authenticated identity and entitlement backend | 15 | 30 |
| Recovery policy, privacy, abuse controls, and operations | 7 | 15 |
| Client account and entitlement integration | 8 | 15 |
| Store billing, receipt lifecycle, and compliance | 10 | 20 |
| **Total** | **40** | **80** |

Estimated build cost is therefore `40 × R` at P50 and `80 × R` at P90, before payment fees, taxes, legal review, backend hosting, monitoring, and ongoing support.

For a 12-month payback, the minimum monthly incremental contribution is:

- P50: `(40 × R + fixed external cost) / 12 + monthly operating cost`
- P90: `(80 × R + fixed external cost) / 12 + monthly operating cost`

Required additional paid renewals are that value divided by verified marginal contribution per renewal. Imported profiles, access metadata, activation, and conversion events are not payments and cannot be used as revenue substitutes.

### Unknowns

- Number of users who need cross-device recovery rather than re-import.
- Lost paid renewals attributable to missing account or billing flows.
- Actual support minutes saved by self-service recovery.
- Provider identity and entitlement API shape, uptime, fraud controls, and owner.
- Store policy, legal entity, refund, tax, privacy, deletion, and data-retention obligations.

## Reopen gates

Implementation can move to GO only when all gates are satisfied:

1. **Demand:** pilot evidence shows the account/recovery/billing JTBD and its denominator; the problem is not inferred from optional local email.
2. **Economics:** the observed 12-month incremental contribution exceeds the P90 cost threshold and includes payment, infrastructure, support, and compliance costs.
3. **Contract:** a named backend owner provides an authenticated API for identity, entitlement, recovery, revocation, and deletion, with failure behavior and SLOs.
4. **Operations:** named owners cover support, refunds, abuse, privacy requests, incident response, and reconciliation.
5. **Architecture:** secrets and payment data stay out of logs and client persistence; the client never treats profile metadata as entitlement.

If any gate is missing, the decision remains NO-GO. The next allowed step is evidence collection using the privacy-safe analytics baseline, not account UI implementation.

## Sources

- Audit report sections 2, 5, 11, 13 and 14: `/Users/stasyudkin/Documents/KVN/audit-2026-09-14/report.md`
- Current MVP scope: `docs/superpowers/plans/2026-07-14-woman-in-red-ios-mvp.md`
- Local data boundary: `docs/privacy-data-inventory.md`
- Measurement contract: `docs/analytics/baseline.md`
