# Telemetry volume check — 2026-10-24

Read-only live Better Stack account verification was explicitly authorized by the user. No purchase, plan change, or account-setting mutation was performed.

- Billing page: current **Free** plan; **3 GB logs per month retained for 3 days**.
- Usage / Logs, Last 30 days (visible table Sep 24–Oct 23): **109.55 kB** ingested for WIR Baseline. The visible complete-day values are 70.54 kB and 39.01 kB.
- Source pages: https://betterstack.com/settings/billing/features and https://betterstack.com/settings/usage/logs?rf=now-30d&rt=now&res=day.

The proposed local cap is 5 MiB per installation per UTC day, retaining failed/retry attempt accounting. Complete consumption for 31 days is 155 MiB per installation (162,529,280 bytes); ten installations attempt 1,550 MiB, about 1.63 decimal GB. That model alone is about 54 percent of a 3 GB monthly allowance. It is an upper bound on attempted serialized log volume, not a measurement or guarantee of Better Stack billing. Other sources and differences in ingestion accounting must retain headroom. No paid tariff is required by the patch itself; current observed use is far below the external allowance.
