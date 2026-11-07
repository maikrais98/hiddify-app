# Blizzard Aurora settings inventory

Read-only source audit for a settings/profile prototype. Audited checkout: `/workspace/user/Documents/KVN/blizzard-aurora-optimization`, branch `fix/keep-vpn-connected-on-resume`, on 2026-10-25. Existing modified and untracked source files were left untouched.

The prototype contract is the current runtime structure and current Russian localization. It must preserve labels, order, conditions, navigation, and touch ownership. It must not expose actual profile URLs, configuration JSON, WARP license/access values, local IP addresses, or imported/exported payloads.

The machine-readable companion is `screens.json`. It contains 15 surfaces and uses only these row types: `navigation`, `toggle`, `choice`, `action`, `input`, `info`.

## Scope and evidence boundary

Included:

- Settings root, its grouped Blizzard layout, legacy ordering, overflow menu, and all six setting sections.
- Quick Settings bottom sheet.
- Android per-app proxy route and its Auto Selection bottom sheet.
- Profile list sheet/page behaviors, profile action menu, profile details settings, sort dialog, and Add Profile sheet/manual form.
- Mobile/desktop/iOS/Android/Linux/macOS conditions, disabled/loading/error/empty states, and navigation targets.
- Exact Russian labels from `assets/translations/ru.i18n.json` plus three Russian-only Blizzard group headings hardcoded in Dart.

Not asserted:

- Visual parity on a running device, native Liquid Glass optics, VoiceOver, Dynamic Type, animation smoothness, or actual VPN behavior.
- Real current preference values. Values in the JSON are semantic placeholders/default/range descriptions, not user data.
- Logs/About inner content. They are inventory targets because Settings navigates to them, but they are not setting-control screens.
- Route Rules, which has translation resources but is not reachable from the current `RouteOptionsPage` or settings route tree.

## Route and sheet hierarchy

```text
/home
├─ /proxies
├─ /profile-details/:id                 mobile only; route name profileDetails
├─ QuickSettingsModal                   root modal sheet, no GoRoute
├─ ProfilesModal                        mobile modal sheet, no GoRoute
│  ├─ ProfileActionsMenu                adaptive menu
│  ├─ SortProfilesDialog                alert dialog
│  └─ /profile-details/:id              after closing sheet
└─ AddProfileModal                      root modal sheet, no GoRoute

/profiles                               desktop only, only when at least one profile exists
└─ /profiles/:id                        route name profileDetails

/settings
├─ /general                             name general
├─ /route-options                       name routeOptions
│  └─ /per-app-proxy                    name perAppProxy; UI entry only on Android
│     └─ AutoAppsSelectionModal          root modal sheet, no GoRoute
├─ /dns-options                         name dnsOptions
├─ /inbound-options                     name inboundOptions
├─ /tls-tricks                          name tlsTricks
├─ /warp-options                        name warpOptions
├─ /logs                                mobile child only
└─ /about                               mobile child only

/logs                                  desktop branch
/about                                 desktop branch
```

Evidence: `lib/core/router/go_router/routing_config_notifier.dart:95-249`, `lib/core/router/bottom_sheets/bottom_sheets_notifier.dart:19-52`, `lib/features/profile/widget/profile_tile.dart:114-131,361-367`.

Settings itself cannot pop normally: its `PopScope` redirects back to `home` (`routing_config_notifier.dart:154-163`). Child setting screens use the shared Blizzard toolbar leading control (`lib/features/settings/widget/blizzard_settings_leading.dart:1-4`).

## Settings root: exact hierarchy and order

The current Blizzard path is selected at `settings_page.dart:156-159`. Its order is:

1. **Приложение**
   1. **Общие** → `general`
   2. **О программе** → `about`
2. **Подключение**
   1. **Маршрутизация** → `routeOptions`
   2. **DNS** → `dnsOptions`
   3. **Входящие** → `inboundOptions`
   4. **Трюки TLS** → `tlsTricks`
   5. **WARP** → `warpOptions`
3. **Диагностика**
   1. **Логи** → `logs`
4. **Сбросить профиль VPN** → immediate reset action

Evidence: `lib/features/settings/overview/settings_page.dart:226-327`. The group headings **Приложение**, **Подключение**, **Диагностика** are hardcoded only for Russian at `:235-237`, `:254-257`, `:291-294`; the row labels come from localization.

Legacy Settings uses the same six setting sections first, adds **Сбросить профиль VPN** only on iOS, and adds **Логи** / **О программе** only at the mobile breakpoint (`settings_page.dart:159-219`). The Blizzard root differs materially: it always renders the reset row and always includes About/Logs inside groups.

### Settings overflow menu

The app-bar menu order is:

1. **Импорт**
   - **Импортировать настройки из буфера обмена**
   - **Импортировать настройки из файла**
2. **Экспорт**
   - **Копировать анонимные настройки в буфер обмена**
   - **Экспортировать анонимные настройки в файл**
   - divider
   - **Копировать все настройки в буфер обмена**
   - **Экспортировать все настройки в файл**
3. divider
4. **Сбросить настройки**

Both import actions show the same overwrite confirmation first. The two “all settings” exports may contain private configuration and therefore must be represented only as inert prototype actions. Evidence: `settings_page.dart:72-137`; Russian strings: `assets/translations/ru.i18n.json:200-215,543-547`.

## Section row order and conditions

The full row-by-row data is in `screens.json`. This section calls out the structural rules a visual prototype can easily miss.

### Общие

Blizzard groups and source ordering (`general_page.dart:32-178`):

- **Оформление:** Язык; Тема оформления.
- **Приватность:** Включить аналитику; Автоматически проверять IP-адрес; Android-only notification speed and haptics; desktop-only closing action, auto-start, minimized start; Android battery-optimization action only while the OS restriction is still active.
- **Подключение:** Ограничение памяти; Режим отладки; Уровень логирования; URL для теста соединения; Интервал теста URL; Порт Clash API; Использовать xray-core, если возможно.

The memory-limit UI is intentionally inverted against storage: the switch value is `!disableMemoryLimit` (`general_page.dart:74-80`). Turning on debug shows an informational dialog before the stored update (`:82-92`). URL interval is a 1–60 minute slider (`:111-129`). Choices for locale/theme and their Reset behavior are implemented in `lib/features/common/general_pref_tiles.dart:14-119`.

### Маршрутизация

Order: Android-only **Прокси для приложений**; **Регион**; **Стратегия Balancer**; **Блокировать рекламу**; **Обход LAN**; **Определять адрес назначения**; **Маршрут IPv6** (`route_options_page.dart:35-115`).

The per-app row is both a toggle and navigation row. Opening it while off first switches to `exclude` (“В обход”). Region change resets direct DNS and, on Android, can show a notice and clear auto-selected apps (`:41-79`).

### DNS

Order: **Удаленный DNS**; remote domain strategy; fake DNS toggle; direct DNS resolver; direct domain strategy (`dns_options_page.dart:27-60`). **Включить маршрутизацию DNS** exists only as commented code and must not appear (`:61-66`).

### Входящие

Order: service mode; strict routing; TUN implementation; mixed port; Linux tproxy port; Linux/macOS redirect port; direct port; LAN sharing (`inbound_options_page.dart:31-107`).

The TUN picker currently renders the enum values `mixed`, `system`, `gvisor`, not the available Russian translations, because `presentChoice` is `value.name` (`:45-52`). LAN sharing can open a QR containing a live local SOCKS address; keep that data out of design artifacts (`:91-105`).

### Трюки TLS

The first switch **Включить фрагментацию** controls the enabled state of every following row. Those rows remain visible but disabled: packet selection, fragment size, delay, mixed SNI case, padding toggle, padding size (`tls_tricks_page.dart:28-95`). Padding size does not separately depend on the padding toggle in current code.

### WARP

The first switch controls all following inputs. Enabling it immediately requests config generation (`warp_options_page.dart:33-40`). Generate has three visual states: ready, loading indicator, and error subtitle **Отсутствует конфигурация WARP** (`:42-61`). Remaining order: detour mode, license key, clean IP, port, noise count, noise mode, noise size, noise delay (`:63-133`). Never put a real license key in a prototype.

## Quick Settings

Quick Settings is opened from the Home app-bar glass button with semantic label **Быстрые настройки** (`home_page.dart:79-91`). It is not a route; it is a non-scroll-controlled root modal sheet (`bottom_sheets_notifier.dart:50`).

Actual content (`quick_settings_modal.dart:31-117`):

1. Blizzard-only heading **Быстрые настройки**.
2. Service-mode segmented control.
3. WARP row whose title is dynamic:
   - **Разблокировать прокси с помощью WARP**, or
   - **Дополнительная безопасность с WARP**.

On mobile the service choices are **Прокси** and **VPN**; desktop also exposes **Системный прокси** (`lib/singbox/model/singbox_config_enum.dart:21-30,45-50`). Tap anywhere on the WARP row toggles; the switch toggles; long press closes the sheet and navigates to WARP settings. The commented TLS block at `quick_settings_modal.dart:104-116` is not part of the current UI. Unlike the full WARP screen, quick toggle does not trigger config generation itself.

## Per-app proxy and auto-selection

The per-app route is nested under Routing but only linked on Android. Its app bar can enter search mode. Under it are:

- mode popup: **Все**, **Прокси**, **В обход**;
- chip **Скрыть системные приложения**;
- tristate app rows with app name/package and optional forced-deselection dot;
- conditional **Автовыбор** FAB;
- overflow import/export/share/clear actions.

Evidence: `lib/features/per_app_proxy/overview/per_app_proxy_page.dart:122-340`. The Auto Selection FAB exists only when region is not **Другой**; once scrolled beyond 300 px it is replaced by Scroll to Top (`:106-120,283-300`).

The Auto Selection sheet starts applying selection automatically on first open when not already enabled. It swaps its switch for progress while loading. Interval/actions appear only in enabled state; interval is 1–7 days; disabling clears auto-selected apps and closes the sheet (`lib/core/router/bottom_sheets/widgets/auto_apps_selection_modal.dart:24-160`).

## Profile-related settings

### Profile list sheet/page

Mobile opens `ProfilesModal`; desktop navigates to `/profiles` (`profile_tile.dart:114-120`). The sheet exposes **Сортировать** and **Обновить подписки**, then profile cards (`profiles_modal.dart:102-167`). In Blizzard list mode each card is at least 96 pt high and its action strip is 48 pt wide (`profile_tile.dart:83-95`). Tap on the card body selects the active profile and closes/navigates home (`:114-131`).

Loading, error, and empty transitions must be prototyped: spinner; localized error; and sheet-close when the list becomes empty (`profiles_modal.dart:34-38,49-83`).

### Profile action menu

Actual order (`profile_tile.dart:314-383`): remote-only **Обновить**; **Поделиться** submenu; remote-only URL clipboard and URL QR; JSON clipboard; **Изменить**; **Удалить** with confirmation. Do not include URL/QR/JSON payloads.

### Profile details

Order (`profile_details_page.dart:68-295`): Save action; name; remote-only read-only URL; remote-only Disable Auto Update; conditional interval; last updated; optional subscription values; configuration editor.

- Save is disabled while loading or unchanged (`:74-89`).
- Interval is visible only when auto-update is enabled, and runs from Auto/0 through 96 hours (`:137-200`).
- Subscription data appears only for remote profiles with `subInfo` (`:209-259`).
- Valid JSON uses `JsonEditor`; other content uses a multiline text editor (`:264-294`). Both are sensitive and must be blank/masked in prototypes.
- Loading and error are separate full-screen states (`:300-316`).

### Add Profile

This is another root modal sheet, not a route (`bottom_sheets_notifier.dart:45-46`). Options are **Сканировать QR**, **Буфер обмена**, **Вручную**, **Бесплатно**, **Справка** (`lib/features/profile/add/widgets/fix_btns.dart:46-87`, `widgets/nav_bar.dart:20-56`). QR is omitted only for desktop legacy, not Blizzard presentation.

Manual form order: **Имя**, **URL**, **Отключить автообновление**, conditional interval, **Добавить** (`add_profile_modal.dart:157-283`). The interval is Auto/0–96 hours. While adding, the sheet replaces content with a loading view and closes after a successful result (`:23-54`).

### Sort dialog: current label/enum mismatch

The visible row order is **По алфавиту**, then **Последнему обновлению**. However current code maps `ProfilesSort.lastUpdate` to the first label and `ProfilesSort.name` to the second (`lib/features/profile/model/profile_sort_enum.dart:5-13`). This looks inverted, but this audit does not fix it. A faithful prototype should show the visible labels/order and preserve the existing behavior unless separately authorized.

## Hit-area contract

- Blizzard settings groups apply `minTileHeight: 48` and wrap every child in a `ConstrainedBox(minHeight: 48)`. Dividers start at x=46 rather than splitting the leading icon area (`lib/features/settings/widget/blizzard_settings_group.dart:27-55`).
- Settings navigation uses a full `ListTile` hit area; the chevron is visual only (`settings_page.dart:329-361`).
- Generic `ValuePreferenceWidget` and `ChoicePreferenceWidget` open their dialog from the whole ListTile (`lib/features/settings/widget/preference_tile.dart:36-66,96-120`). Switch rows retain standard `SwitchListTile.adaptive` row and switch interaction.
- Quick Settings service segments are explicitly 44 pt high in Blizzard mode; WARP row is 66 pt when scaled 16 pt text is at most 20 pt (`quick_settings_modal.dart:39-100`).
- Profile list cards are minimum 96 pt in Blizzard list mode / 76 pt in Blizzard main-card mode, with a separate 48 pt action strip (`profile_tile.dart:83-95`).
- Picker choices are whole `RadioListTile` rows. Input/slider dialogs expose Reset, Cancel, and OK actions (`setting_picker_dialog.dart:31-60`, `setting_input_dialog.dart:57-172`, `setting_slider_dialog.dart:49-76`).

Do not shrink these targets when applying Liquid Glass. Cosmetic glass/background work should remain behind the existing hit geometry.

## Russian localization sources

- Home/Profile/Quick Settings: `assets/translations/ru.i18n.json:97-172`.
- Settings root/General/Routing: `:200-406`.
- DNS/Inbound/TLS/WARP: `:407-493`.
- Subscription labels: `:496-522`.
- Sort/confirmation labels: `:524-569`.
- Closing-action label **Спрашивать каждый раз**: `:608-611`; common **Скрыть** / **Выйти**: `:41-42`.

All localized labels in `screens.json` were sourced from those keys. The only directly hardcoded Russian UI labels found in scope are the three Blizzard Settings group headings plus General group headings **Оформление**, **Приватность**, **Подключение** (`settings_page.dart:235-294`; `general_page.dart:160-175`).

## State coverage checklist for the prototype

- Settings root: Blizzard grouped layout; legacy layout; overflow open; import confirmation.
- General: Android, desktop, iOS/mobile; battery loading/hidden/action; debug warning; pickers/input/slider.
- Routing: Android per-app row on/off; region change notice; non-Android absence.
- DNS: normal rows; commented DNS-routing row absent.
- Inbound: mobile, Linux, macOS conditional rows; LAN-share QR redacted.
- TLS: master off with disabled dependents; master on.
- WARP: off/disabled; on/ready; generating; generation error.
- Quick Settings: mobile vs desktop segments; WARP on/off; both detour-mode titles; long-press route.
- Per-app: loading/error/data; search open; modes; system-app filter; scrolled-to-top FAB substitution; auto-selection sheet off/enabling/on/loading.
- Profiles: loading/error/data/empty; active/non-active; remote/local; subscription absent/present/expired/exhausted; actions menu; delete confirmation.
- Profile details: loading/error/unchanged/changed; local/remote; auto-update on/off; subscription absent/present; JSON/non-JSON editor.
- Add Profile: options/manual/loading/success-close; free off/on; mobile/desktop legacy/Blizzard.
- Sort: both visible labels and both directions, preserving current inverted enum mapping.

## Source index

| Surface | Source |
|---|---|
| Route tree | `lib/core/router/go_router/routing_config_notifier.dart:95-249` |
| Bottom sheet registration | `lib/core/router/bottom_sheets/bottom_sheets_notifier.dart:19-52` |
| Settings root + overflow | `lib/features/settings/overview/settings_page.dart:67-363` |
| Blizzard group geometry | `lib/features/settings/widget/blizzard_settings_group.dart:5-64` |
| General | `lib/features/settings/overview/sections/general_page.dart:23-183` |
| Shared locale/theme/analytics rows | `lib/features/common/general_pref_tiles.dart:14-143` |
| Shared choice/input rows | `lib/features/settings/widget/preference_tile.dart:10-153` |
| Routing | `lib/features/settings/overview/sections/route_options_page.dart:19-120` |
| DNS | `lib/features/settings/overview/sections/dns_options_page.dart:12-73` |
| Inbound | `lib/features/settings/overview/sections/inbound_options_page.dart:15-114` |
| TLS | `lib/features/settings/overview/sections/tls_tricks_page.dart:12-102` |
| WARP | `lib/features/settings/overview/sections/warp_options_page.dart:15-140` |
| Quick Settings | `lib/core/router/bottom_sheets/widgets/quick_settings_modal.dart:12-125` |
| Per-app proxy | `lib/features/per_app_proxy/overview/per_app_proxy_page.dart:22-343` |
| Auto Selection sheet | `lib/core/router/bottom_sheets/widgets/auto_apps_selection_modal.dart:14-162` |
| Profile sheet | `lib/features/profile/overview/profiles_modal.dart:20-169` |
| Profile card/menu | `lib/features/profile/widget/profile_tile.dart:28-453` |
| Profile details | `lib/features/profile/details/profile_details_page.dart:23-338` |
| Add Profile | `lib/features/profile/add/add_profile_modal.dart:18-289` |
| Profile sort dialog | `lib/core/router/dialog/widgets/sort_profiles_dialog.dart:10-65` |
| Russian localization | `assets/translations/ru.i18n.json:1-612` |
