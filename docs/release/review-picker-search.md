# Review-picker: server search and quick repeat selection

## Evidence

- [Audit: Search country/city/server](../../../audit-2026-09-14/report.md#92-все-58-рекомендаций) found no search in the production picker and required an explicit search-empty state.
- [Audit: Recent locations](../../../audit-2026-09-14/report.md#92-все-58-рекомендаций) recommended keeping 3–5 recent manual choices ahead of the full catalog.
- [Audit backlog: Review-picker](../../../audit-2026-09-14/report.md#12-приоритизированный-backlog) requires search, reset, empty, selected, and a measured large-list scenario.
- The underlying market pattern comes from the [VPN competitive UX benchmark](../../../vpn_competitive_ux_research_2026-09-14.md).

The audit is product evidence and a recommendation, not proof of user demand or revenue impact. This change keeps the existing Servers IA, sorting, latency test, tile design, and selection behavior.

## Resulting contract

- Search matches server tag/display name, type, host, group selection, country, region, city, and organization without reordering the source list.
- The engine-reported selected tag remains visible above filtered results. If the selected tag is absent from the current catalog, the tag is still shown as the current selection instead of inventing a matching item.
- Search with no matches has its own message and clear action. Clearing returns the full current list.
- Up to three unique manual choices are kept newest-first for the current app session. The current selection and tags no longer present in the catalog are excluded from repeat-selection chips.
- Reopening Servers starts with an empty query. The production shell route listener observes Servers becoming active again even though `StatefulShellRoute.indexedStack` keeps the page mounted; selected/recent shortcuts remain available for the current session.

## Automated before/after measurement

The deterministic regression fixture contains 100 nodes and targets `Node 099`.

| Scenario | Before | After | Automated evidence |
|---|---:|---:|---|
| Candidate set for `Node 099` | 100 visible catalog candidates; no query control | 1 matching candidate | `large-list search reduces one hundred candidates to one exact result` |
| Repeat a previous manual choice | Scan/scroll the catalog again | 1 recent chip tap | `recent node is a one-tap repeat choice and stale tags stay hidden` |
| Reopen after a search | No search state existed | Query resets; selected and valid recent shortcuts remain | `production shell resets search after Servers to Settings to Servers while preserving shortcuts` |

This measures deterministic candidate count and required UI actions, not human elapsed time. A real time-to-selection claim still needs production analytics or a moderated usability run with a representative large subscription.

## Verification

```text
/Users/stasyudkin/fvm/versions/3.38.5/bin/flutter test \
  test/features/proxy/overview/proxy_picker_content_test.dart \
  test/features/proxy/overview/proxy_picker_state_test.dart \
  test/features/proxy/overview/proxies_overview_page_test.dart \
  test/features/proxy/widget/proxy_tile_test.dart

29 tests passed
```

Focused coverage includes search fields, 100-to-1 filtering, selected visibility, no-results/reset, bounded recent state, stale-tag removal, reopen behavior, the existing recovery states, Auto Mode feedback, and selected-tile styling.

## Remaining boundary

Recent shortcuts are session-scoped and deliberately add no new persisted history. If repeat selection across a full app restart is required, persistence needs a separate privacy review because server tags can reveal provider or location information.
