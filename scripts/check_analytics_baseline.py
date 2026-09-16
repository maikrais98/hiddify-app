#!/usr/bin/env python3
"""Validate privacy-allowlisted manual aggregates; does not read source ledgers."""
import argparse
from datetime import date, timedelta
import json
from pathlib import Path

STAGES = ('enrolled', 'access_available', 'onboarding_completed', 'import_started',
          'import_succeeded', 'connect_started', 'permission_ready', 'core_connected',
          'working_session', 'repeat_working_session')
REASONS = ('missing_access', 'import', 'permission', 'connection', 'routing',
           'metadata', 'editing', 'crash', 'other')
OTHER = ('activation_elapsed_seconds_sum', 'support_contacted', 'support_cases',
         'resolved_cases', 'resolution_elapsed_seconds_sum', 'handling_minutes',
         'loaded_hourly_cost_minor', 'allocated_infrastructure_cost_minor')
META = {'schema_version', 'kind', 'cohort_start', 'cohort_end_exclusive', 'as_of',
        'platform', 'currency', 'owners', 'source', 'reasons'}


def check(data, require_observed=False):
    def need(ok, message):
        if not ok:
            raise ValueError(message)

    need(type(data) is dict and set(data) == META | set(STAGES + OTHER), 'Unexpected or missing fields')
    need(type(data['schema_version']) is int and data['schema_version'] == 1, 'Schema version')
    need(data['kind'] in ('template', 'synthetic', 'observed'), 'Kind')
    need(not require_observed or data['kind'] == 'observed', 'Observed data required')
    need(data['platform'] in ('ios', 'android', 'desktop'), 'Platform')
    need(data['currency'] in ('RUB', 'USD', 'EUR'), 'Currency')
    need(data['source'] == 'manual_pilot_tally', 'Source')
    need(data['owners'] == ['product', 'qa', 'support', 'finance'], 'Owner roles')
    need(type(data['reasons']) is dict and set(data['reasons']) == set(REASONS), 'Reason taxonomy')
    values = {k: data[k] for k in STAGES + OTHER} | {f'reason_{k}': v for k, v in data['reasons'].items()}
    for key, value in values.items():
        need(value is None or (type(value) is int and 0 <= value <= 10**12), f'Invalid number: {key}')
    if data['kind'] == 'template':
        need(all(v is None for v in values.values()), 'Template must not contain measurements')
        need(all(data[k] is None for k in ('cohort_start', 'cohort_end_exclusive', 'as_of')), 'Template dates must be null')
        return
    dates = []
    for key in ('cohort_start', 'cohort_end_exclusive', 'as_of'):
        value = data[key]
        need(type(value) is str, f'Missing date: {key}')
        parsed = date.fromisoformat(value)
        need(parsed.isoformat() == value, 'Canonical date required')
        dates.append(parsed)
    start, end, as_of = dates
    need(start.weekday() == 0 and end - start == timedelta(days=7), 'Complete UTC calendar week required')
    need(as_of >= end + timedelta(days=8), 'Cohort not mature')
    if data['kind'] == 'observed':
        need(as_of <= date.today(), 'Observed date is in the future')
    for key in STAGES:
        need(data[key] is not None, f'Missing funnel observation: {key}')
    for before, after in zip(STAGES, STAGES[1:]):
        need(data[after] <= data[before], f'Invalid denominator: {after}')
    total = data['activation_elapsed_seconds_sum']
    if total is not None:
        need(total <= data['working_session'] * 86400, 'Activation time outside 24-hour window')
    contacted, cases, resolved = (data[k] for k in ('support_contacted', 'support_cases', 'resolved_cases'))
    if contacted is not None:
        need(contacted <= data['enrolled'], 'Support contact denominator')
    if cases is not None:
        need(contacted is not None and contacted <= cases and (cases == 0 or contacted > 0), 'Case/contact mismatch')
        need(all(v is not None for v in data['reasons'].values()), 'Missing reasons')
        need(sum(data['reasons'].values()) == cases, 'Reason totals do not match cases')
        if cases == 0:
            need(data['handling_minutes'] in (None, 0), 'Handling time without cases')
    else:
        need(all(v is None for v in data['reasons'].values()), 'Reasons without case denominator')
    if resolved is not None:
        need(cases is not None and resolved <= cases, 'Resolved-case denominator')
    elapsed = data['resolution_elapsed_seconds_sum']
    if elapsed is not None:
        need(resolved is not None, 'Resolution time without denominator')
        need(elapsed <= resolved * (as_of - start).days * 86400, 'Impossible resolution time')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path', type=Path)
    parser.add_argument('--require-observed', action='store_true')
    args = parser.parse_args()
    try:
        data = json.loads(args.path.read_text())
        check(data, args.require_observed)
    except (ValueError, TypeError, OSError) as exc:
        parser.exit(1, f'INVALID: {exc}\n')
    print(f"VALID {data['kind']}; source evidence and owner reconciliation still required")


if __name__ == '__main__':
    main()
