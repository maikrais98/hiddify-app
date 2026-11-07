# Personal account design

## Direction

The cabinet follows **Operate** and inherits the visual language of **Blizzard v2**.
This direction applies only to the personal VPN account cabinet.

- Canvas: `393×852 pt`; stale state: `393×940 pt`.
- System bar: `62 pt`; navigation: `56 pt`.
- Field height: `56 pt`; button height: `52 pt`; every hit region: at least `44 pt`.
- Side inset: `20 pt`; field radius: `12 pt`; action radius: `14 pt`.
- Typeface: `Inter`.

## Color tokens

`bg #06121D` · `surface #102235` · `elevated #19374C` · `accent #72D1FF` · `onAccent #092638`

`primary #EFF7FD` · `secondary #BACDDB` · `muted #9BB3C5` · `warning #EAC586` · `warningSurface #302B1E`

`error #F7AAAA` · `errorSurface #2B2025` · `border #55758B`

## Composition and states

- Entry is one field, «Телефон или логин», with no SMS, password, or method switchers.
- Visual hierarchy: status and expiry first, traffic second, bound devices third.
- Do not wrap every row in a separate card; do not add charts or decorative glass effects.
- Missing values read «Нет данных».
- Unlimited traffic uses no zero values and no progress bar.
- A stale response keeps its timestamp and shows a warning.
- Expired subscription copy: «Свободных мест: 1».
- Stale subscription copy: «Было свободно мест: 1».
- All numbers, dates, and states are demo content: they are not real `akonit` parameters.
- The design has no live backend and does not implement authentication code.

## Pen source and exports

Pen source: `[LOCAL_PATH]`.
The cabinet block starts below Blizzard v2 at `x=23033, y=12145`.
PNG exports are in `previews/` as specified by the source flow.
Shared scheme and components: `NVo6N`; row labels: `AQEIS`, `hVrNO`.

| State | Screen ID |
|---|---|
| Empty entry | `er8r9` |
| Phone entry | `BvKom` |
| Login entry | `aoVcZ` |
| Subscription not found | `c7batd` |
| Network error | `xDWHe` |
| Active subscription | `TzIU7` |
| Unlimited | `iBog7` |
| Expired subscription | `zvueD` |
| Limits exhausted | `u6ub8` |
| Saved data after failure | `ISFsk` |
| Device data unavailable | `dyOhK` |
| Load error without cache | `n8R3u` |
