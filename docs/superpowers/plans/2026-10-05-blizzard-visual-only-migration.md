# Blizzard Dark v1 — Visual-only Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> В установленном каталоге навыки называются `subagent-driven-development` и `executing-plans`. Этот запрос разрешает планирование: production-код, зависимости, CI, сборки, телефон и Apple-настройки сейчас не меняются.

**Goal:** Перенести утверждённый Blizzard Dark v1 в существующее iPhone-приложение, сохранив функции, маршруты, данные, условия доступности действий и поведение VPN.

**Architecture:** Постепенно менять Flutter-представление на существующих экранах. Сохранить текущие Riverpod-провайдеры, обработчики, GoRouter, repositories, core и native lifecycle. Новые компоненты получают уже вычисленные значения и существующие callbacks; оформление не становится новым источником состояния.

**Tech Stack:** Существующий Flutter / Dart / Material 3, hooks_riverpod, GoRouter, Drift и SharedPreferences. В `pubspec.yaml` объявлены Dart `^3.10.4` и Flutter `^3.38.5`; фактический SDK/revision закрепить в baseline manifest перед реализацией. Обновление SDK или runtime packages в этот этап не входит.

**Дата:** 5 октября 2026. **Статус:** план; новые тесты и runtime-приёмка `NOT RUN`.

## Global Constraints

- Только визуальное обновление существующей мобильной ветки iOS. Две существующие вкладки: «Главная» и «Настройки».
- Сохраняем тексты, действия, порядок смысловых блоков, группировку, route/result semantics, validation, enabled/disabled и состояния.
- Исключение визуального бренда уже утверждено в макетах: заменяемый power glyph и нейтральное «VPN» в экранном brand slot. Bundle/display identity, юридические тексты, About URLs, глобальные Constants, app icon и splash этим не переименовываются; финальный бренд отложен.
- Dark получает Blizzard. Light и Black сохраняют существующее оформление. System сохраняет следование системной яркости: светлая ветка прежняя, тёмная — Blizzard. Default, reset, выбранное значение и ключ `theme_mode` не меняются.
- Охват — существующая мобильная ветка iOS с исходным breakpoint ширины <600 logical px. Это presentation scope, а не новый детектор физического iPhone. Android/desktop и широкая tablet-ветка сохраняют legacy оформление. Узкое окно iPad уже использует мобильную ветку: оно получает тот же mobile skin и отдельную regression-проверку; полноценный iPad redesign не входит в этап. Breakpoints, branch mapping и функциональное поведение всех платформ неизменны.
- Все необходимые тесты, fixtures, ожидаемые результаты и физический протокол готовятся до первой production-правки UI. Сохраняемое поведение: baseline GREEN → чувствительность теста → новый UI GREEN. Новые визуальные требования: корректный visual RED → минимальная правка → GREEN.
- Не меняем ядро VPN, native bridge, Packet Tunnel, providers/notifiers/repositories/models, параметры конфигурации, storage keys/schema, bundle IDs/App Group/service channel/entitlements и разрешения.
- Не меняем версии runtime-зависимостей, Flutter/Dart/iOS minimum target, server, signing и release pipeline. Необходимые SDK test dependencies — отдельный tests-only шаг с проверкой неизменности runtime dependency graph.
- Новые частицы и материалы не перехватывают tap/long press/scroll/back/VoiceOver. Начинаем со статичной сцены. Существующие haptics сохраняем; новые haptics в visual-only этап не добавляем.
- Удаление функций, исправление соседних багов, переписывание архитектуры, новое поведение импорта и изменение текста ошибок в этот этап не входят.
- План не разрешает публикацию/установку/сброс данных. При будущем выпуске — существующий private TestFlight путь и обновление поверх установленной версии; действия на личном телефоне и Apple выполняются в рамках явного запроса на реализацию/выпуск.
- Используем синтетические fixtures. Приватные URL, токены, credentials, payload QR и raw logs не попадают в макеты, тестовые отчёты и screenshots.

---

## 1. Проверенная основа и методика

Live read-only аудит подтвердил checkout `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-baseline`, ветку `chore/clean-hiddify-ios-baseline` и HEAD `fe6f971674787ec0ae2955ef0cba456857324810`. Изменённых `lib/` файлов в текущем git status нет; evidence/docs/framework checksum содержат локальные изменения. Не очищать и не включать их в UI commits.

Документация установленного WIR Baseline 0.0.1 (1) указывает source `0830294eff5b8cd86324545ed00689648c70bd23`. История HEAD и shipped source различается. Перед началом заново сравнить runtime trees и закрепить долговременный источник shipped SHA; название ветки не определяет эталон. Ранее сообщённый пользователем рабочий baseline принимается. Для сравнения следующей сборки нужны свежие результаты на закреплённой паре builds.

Дизайн-источник: `/LOCAL_USER_HOME/Documents/KVN/design-handoff/blizzard-dark-v1/` — 89 пар в `mapping.json`, 83 masters в `component-catalog.json`, 106 variables в `tokens.json` и 14 статических QA specimens. Статическая готовность не означает исчерпывающий список runtime-состояний.

Подходы:

| Подход | Результат и ограничения |
|---|---|
| Только заменить общую тему | Быстро меняет палитру, но не переносит характерный контрол, сцену и навигацию Blizzard. Глобальная тема сразу затрагивает ещё не проверенные overlays. |
| **Тема + поэтапное оформление существующих компонентов** | **Рекомендуется.** Сохраняет текущую orchestration; каждая небольшая порция имеет проверяемый diff и собственный откат. |
| Одновременно заменить экранные деревья целиком | Сложнее сохранить listeners, controller lifetime, callbacks, фокус и route state; для этого этапа не выбираем. |

Применяем:
- **Characterization tests:** фиксируем фактическое поведение старой версии, включая ошибки, отмену и асинхронные ветки.
- **Дифференциальная проверка:** подаём одинаковые события старому и новому UI и сравниваем последовательность actions, аргументы, маршруты и изменения хранилища.
- **Контрактные проверки:** защищаем state-to-label, callback binding, persistence и границы неизменяемых файлов.
- **Visual regression:** фиксируем эталоны изображения/геометрии и обнаруживаем обрезание, исчезновение действий и непреднамеренные изменения.
- **Маленькие reviewable commits:** отдельно tests, основа оформления, семейство компонентов и декор.

Flutter разделяет unit, widget и integration tests; эти уровни имеют разную область доказательств. [Flutter testing overview](https://docs.flutter.dev/testing/overview). Golden сравнивает изображение и требует стабильной среды/шрифтов. [matchesGoldenFile](https://api.flutter.dev/flutter/flutter_test/matchesGoldenFile.html). Стандартный `integration_test` не управляет native permission UI; разрешения проверяем отдельным заранее записанным физическим сценарием. [Flutter integration testing](https://docs.flutter.dev/cookbook/testing/integration/introduction).

## 2. Карта файлов и защищённые границы

Во всех задачах ниже полный корень приложения — `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-baseline`. Реализация выполняется в отдельном checkout от зафиксированного источника; пути `lib/` и `test/` в таблицах переносятся в него без изменения структуры.

| Разрешённая поверхность | Ответственность и ограничение |
|---|---|
| `lib/core/theme/app_theme.dart`, `theme_extensions.dart` | Добавление неактивных presentation tokens/eligibility extension; глобальные legacy ColorScheme/фон/типографика и Light/Black остаются прежними. |
| Будущие `lib/core/theme/blizzard_tokens.dart`, `blizzard_theme.dart` | Типизированные цвета/размеры/материалы и политика только визуального включения. Без persistent setting. |
| Будущие `lib/core/widget/blizzard/blizzard_presentation.dart`, `blizzard_scene.dart`, `blizzard_surface.dart` | Локальная Theme boundary и чистые декоративные/контентные поверхности; игнорируют ввод и semantics декора. |
| `lib/core/router/adaptive_layout/my_adaptive_layout.dart` | Только внешний вид существующей navigation surface. Не менять `goBranch`, branch indices, breakpoints, focus hooks. |
| `lib/features/home/widget/home_page.dart`, `connection_button.dart` | Только representation и artwork. Не менять provider watches, callback switch, label predicates, async sequence. |
| `lib/features/profile/widget/profile_tile.dart`; `lib/features/proxy/widget/proxy_tile.dart`; `lib/features/proxy/active/active_proxy_card.dart` | Карточки, строки, выбранность и отображение реальных значений. |
| `lib/features/settings/widget/preference_tile.dart`; `lib/features/common/general_pref_tiles.dart` | Только визуальная anatomy; setter, ключ, default/reset, тип значения и platform gate неизменны. |
| `lib/core/router/dialog/widgets/`; `lib/features/profile/add/add_profile_modal.dart`; `lib/features/profile/overview/profiles_modal.dart`; `lib/core/router/bottom_sheets/widgets/quick_settings_modal.dart` | App-owned presentation. Не менять результат закрытия, navigator, dismissal, callback и keyboard inset. |
| `lib/features/profile/details/profile_details_page.dart`, `json_editor.dart`; `lib/features/settings/overview/`; `lib/features/log/overview/logs_page.dart`; `lib/features/about/widget/about_page.dart`; `lib/features/intro/widget/intro_page.dart` | Только оформление существующего содержимого, без смены editor/controller lifecycle. |
| `pubspec.yaml`, `pubspec.lock`, assets | Только заранее перечисленные декоративные assets и необходимые dev test dependencies; runtime resolved graph сохраняется. |

Защищённые от runtime-правок:
`lib/hiddifycore/`, `hiddify-core/`, `lib/singbox/`, `lib/core/preferences/`, `lib/core/directories/`, `lib/core/router/go_router/`, `lib/core/router/deep_linking/`, `lib/features/*/data/`, `lib/features/*/notifier/`, `lib/features/*/model/`, persistence schema, `lib/bootstrap.dart`, `lib/features/app/widget/app.dart`, `lib/features/connection/widget/connection_wrapper.dart`, `lib/core/theme/app_theme_mode.dart`, `lib/core/theme/theme_preferences.dart`, dialog/sheet notifier orchestration, native iOS code/identity/core artifacts.

UI-файл не считается целиком разрешённым: внутри него обработчики, hooks, listeners, controllers и side effects защищены. Git guard обнаруживает изменения файлов/зависимостей; semantic review и behavioral tests отдельно обнаруживают изменение callback внутри разрешённого UI-файла.

## 3. Задача A — зафиксировать baseline и контракт сохранения

**Files:** создать `docs/verification/blizzard/baseline-manifest.json` и `screen-action-contract.json`; использовать `docs/superpowers/plans/2026-10-03-wir-visual-update-tests-first.md` как подробный baseline/device протокол, сохранив его safety gates. Этот новый план заменяет прежнее визуальное направление на Blizzard и закрепляет согласованную политику тем.

Переиспользуем из старого плана source/identity/protected-tree checks, test readiness, строгий simulator selector, физические сценарии и update/rollback constraints. Его предложения новых CI steps, pre-sign/pre-publish jobs и глобального включения AppTheme здесь **не действуют**. Новые guards запускаются обязательным локальным validation-прогоном по разделу 8 и сохраняют receipts для exact source. Существующий release workflow не переписывается; интеграция дополнительных автоматических CI gates — отдельная задача, если она будет запрошена. Наличие ручного gate не выдаём за автоматически enforced CI protection.

**Consumes:** shipped source/build provenance, утверждённый mapping, реальный код. **Produces:** полная матрица «экран/состояние → действие/gesture → callback/аргументы → результат/хранилище».

- [ ] Сохранить исходный dirty status и текущие материалы; выбрать отдельный implementation checkout, не переносить старый UI вместе с его business logic.
- [ ] Сверить shipped SHA и выбранный source; сохранить core/dependency/identity/protected-tree fingerprints.
- [ ] Связать 89 дизайн-состояний с настоящими widgets и predicates. Использовать настоящие названия notifier methods и route names из source.
- [ ] Для каждого доступного действия записать normal, busy, disabled, cancel, error и async completion, если такие ветки существуют. Включить long press, overflow/share menus, keyboard и back.
- [ ] Для source-backed состояний без макета сохранить функцию и оформить через существующее семейство Blizzard, без выдуманного текста/полей. Зафиксировать визуальный вариант до изменения этого участка. В частности: Clash API port input, меню профиля/настроек, proxy sort/info, Logs/About menus, toast и editor keyboard states.
- [ ] Системные permission prompts, keyboard, share/document picker и text selection оставить системными. Package-owned upgrade alert сначала атрибутировать, не заменять его D11.
- [ ] Зафиксировать существующие seasonal artwork predicates и haptics. Не удалять их условие/вызов под видом оформления; artwork меняется только в согласованной визуальной области.

**Gate A:** каждое существующее iPhone действие сохранено в контракте; отсутствие отдельного макета не скрывает функцию. Immutable baseline воспроизводим; известные исходные дефекты отделены от возможных новых регрессий.

## 4. Задача B — тесты до UI

**Current readiness:** `flutter_test` закомментирован в `pubspec.yaml`; готового widget/golden harness и `integration_test/` нет. Существующие parser/DB/IP/identity/Ruby/core guards есть, но в этом планировании не запускались.

**Create:**
- `test/ui_preservation/connection_contract_test.dart`
- `test/ui_preservation/profile_import_contract_test.dart`
- `test/ui_preservation/proxy_settings_contract_test.dart`
- `test/ui_preservation/navigation_overlay_contract_test.dart`
- `test/ui_preservation/theme_contract_test.dart`
- `test/visual/blizzard_visual_contract_test.dart`
- `test/visual/blizzard_accessibility_contract_test.dart`
- `test/support/blizzard_fixture_app.dart`
- `test/support/blizzard_action_trace.dart`
- `test/ci/blizzard_runtime_boundary_test.rb`
- `integration_test/blizzard_preservation_test.dart`
- `docs/verification/blizzard/test-readiness.json`
- `docs/verification/blizzard/device-acceptance.md`

**Interfaces:** fixture app создаёт настоящие проверяемые screens с существующими provider overrides на внешних границах. Action trace записывает ordered method name, безопасные fixture arguments, count, route/result и состояние synthetic storage. Не заменять проверяемый notifier/repository фейком в тесте его собственного поведения.

| Семейство | Заранее заданные cases / ожидаемый результат |
|---|---|
| Подключение | OFF/connecting/ON/disconnecting/loading/error/no-profile/reconnect; задержка 0, 1, 64999, 65000, 65001; WARP условие. Label, enabled и callback соответствуют исходнику; один разрешённый tap вызывает ровно исходный эффект. Никаких новых «защищено» обещаний. |
| No-profile flow | Диалог → add sheet → исходный experimental notice flow в прежнем порядке; cancel и retry не меняют профиль произвольно. |
| Профили/импорт | Валидный/невалидный/отменённый clipboard/manual/QR; select/update/edit/share/delete; повторный выбор текущего профиля; late async completion после закрытия. Те же данные и результаты; не добавляем ошибки валидации, которых нет в source. |
| Серверы | Выбор, test delay, pending/timeout/error, sort/info/long press. Тот же outbound ID, args и selection. |
| Настройки | Каждый отображаемый switch/radio/slider/input/reset раскрыт в отдельные cases. Те же keys/values/types/units/defaults и зависимые disabled controls; отмена сохраняет старый результат по исходному контракту. |
| Навигация | Home/Settings, повторное нажатие текущей вкладки, child routes, sheet/dialog/back/close/gesture, import deep link, scroll/focus/controller state. `goBranch(index, initialLocation: index == currentIndex)` и исходный порядок действий сохранены. |
| Темы и область | Dark→Blizzard только в iOS mobile presentation; Light/Black→legacy; System brightness light/dark; выбор/reset в System; restart с сохранённым `theme_mode`. Ширины 599/600/840 pt, iPad full-width/узкое окно и phone rotation сохраняют исходные branch indices/navigation. Android/desktop legacy. Перестроение темы/размера не запускает VPN или сохранение профиля. |
| Данные | Real synthetic file DB close/open; отдельный process restart для platform preferences; update-over-existing-data на устройстве. Mock preferences не выдаём за persistence/upgrade proof. |
| Visual | Все 89 mapped states; недостающие transient состояния из A; размеры 320, исходный 393 и большой 430 pt; исходный full-scroll viewport; длинные строки, RU/EN, RTL и увеличенный текст. |
| Доступность | ≥44×44 hit regions, readable contrast, non-color state cues, modal focus, VoiceOver labels/order, Reduce Motion/Transparency/Increase Contrast, keyboard-safe actions. |
| Границы | Protected tree/identity/core hash/runtime dependency graph неизменны; dev-only и asset changes явно разрешены. |

- [ ] Подключить SDK test tooling без runtime upgrades и подготовить детерминированные fixtures/шрифты/время/viewport/DPR.
- [ ] Написать весь необходимый runnable suite, action inventory и device protocol перед первой UI production-правкой.
- [ ] Запустить characterization suite на baseline: GREEN по фактическим assertions. Исходный defect — отдельный ID и исходный результат, без blanket skip/ослабления ожидаемых действий.
- [ ] В одноразовой tests-only копии удалить callback, подменить profile ID, удвоить start, изменить settings save и protected-tree entry. Соответствующие tests обязаны упасть по ожидаемой assertion. Удалить все fault injections, восстановить GREEN.
- [ ] Задать visual assertions по tokens/geometry/design до UI; старый интерфейс даёт RED именно по новому визуальному требованию. Missing class/SDK/plugin/fixture и отсутствие golden файла не считаются visual RED.
- [ ] Экспорт pen.dev с Inter не считать pixel-perfect эталоном Flutter/SF Pro. До production правок закрепить визуальные критерии и совместимые test-only reference fixtures; после визуальной приёмки Flutter render становится одобренным golden для дальнейших regression comparisons. Не делать автоматическое `--update-goldens` ответом на каждый failure.
- [ ] Визуально значимые fonts закрепить в harness. На устройстве отдельно проверить системную iOS typography и Persian Shabnam fallback. Ahem-квадраты не являются проверкой читаемости.
- [ ] Бесконечные анимации проверять фиксированным bounded `pump`, без неограниченного `pumpAndSettle`.
- [ ] Записать команды/fixture/verdict/sensitivity proof в `test-readiness.json`; integration harness запускается на явно выбранном изолированном iOS Simulator. Simulator UI не доказывает работающий VPN.

**Gate B:** regression GREEN, чувствительность доказана, целевые visual RED осмысленны, harness работоспособен. Все необходимые сценарии написаны заранее. До этого gate новая тема не включается в production.

## 5. Задача C — оформить основу без включения на всех экранах

**Files:** `blizzard_tokens.dart`, `blizzard_theme.dart`, `app_theme.dart`, `theme_extensions.dart`; `blizzard_presentation.dart` и scene/surface widgets; перечисленные assets; тесты B.

**Consumes:** `tokens.json`, typography/component contracts, Gate B. **Produces:** typed presentation data и чистые visual primitives.

- [ ] Добавить неактивные semantic tokens и component aliases без смены глобальных цветов legacy интерфейса.
- [ ] Добавить внутренний compile-time switch `BLIZZARD_VISUALS`, default false; он выбирает только оформление в одном существующем app/router tree. Не добавлять пользовательскую настройку, persisted key, второй router/ProviderScope/core.
- [ ] Добавить в существующую AppTheme только presentation eligibility/tokens extension, без смены global ColorScheme, шрифта и фона. Eligibility учитывает compile switch, iOS и mode Dark/System, исключая Black/Light; существующий MaterialApp выбирает effective brightness. Никакие listeners/hooks или аргументы router в `app.dart` не меняются.
- [ ] В `BlizzardPresentation` использовать уже существующий `Breakpoint(context).isMobile()` и effective theme brightness. Активность требует iOS + mobile + Dark/System dark + включённый switch. Этот механизм не определяет физическую модель устройства, не вводит device-info/native query и не зависит от позднего post-frame breakpoint provider. При размере >=600 оформление legacy; в узком iPad окне — согласованная мобильная ветка.
- [ ] Для переноса RGBA tokens учитывать Flutter ARGB; сохранить alpha/opaque fallbacks.
- [ ] Подключать общую Blizzard ThemeData через локальную presentation boundary у существующих мобильных root surfaces и app-owned modal content. Фабрика глобальной темы остаётся legacy. Не менять navigator/theme-capture/dismissal: root-navigator sheets/dialogs получают оформление внутри своих существующих content widgets, сохраняя viewInsets и результат закрытия.
- [ ] Theme boundary остаётся в стабильном месте дерева при смене mode/ширины; меняются только её данные. Не переставлять Stateful child/controller/focus/keys и не создавать вторую ветвь app state. Проверить, что вложенная boundary не применяется повторно. Overlay/action-access invariants должны PASS при каждом изменении общей Blizzard ThemeData.
- [ ] Не создавать новую business-state enum для ConnectionControl: дизайн-варианты являются отображением существующего model/latency/reconnect.
- [ ] Реализовать статичную hero/quiet/off сцену отдельным неинтерактивным слоем. QR, input, logs и critical feedback получают off/opaque.
- [ ] Системный iOS font является runtime целью; canvas Inter — только fallback макетов. Locale-specific font behavior сохраняется.

**Gate C:** legacy build с выключенным switch сохраняет визуальность и поведение. Включённые primitives проходят целевые visual/style/semantics tests. Никакой вызов core/repository не появляется в новом декоративном компоненте.

## 6. Задачи D1–D5 — перенос небольшими порциями

Каждая строка — самостоятельная порция review/commit. State variants оформляются параметрами подходящего общего компонента: 89 frames и 83 canvas masters не требуют 89 новых экранов или 83 новых business classes.

| Порция | Что переносим | Особая проверка |
|---|---|---|
| D1 — пилот | Home OFF/connecting/ON/unknown delay/error + navigation + header | Reconnect priority, busy semantics, no-profile async order; selected tab и реальный active profile/server. |
| D2 — плотный пилот | Все 10 серверов, Settings/General, manual validation, confirmation, WARP disabled | Списки/scroll, длинный текст, sheet keyboard, все действия диалога, зависимые контролы. |
| D3 — профили и импорт | Profile card/overview/add/import/QR/детали/редакторы/menus | Сохранение draft, cancel, focus/controllers, source validation и share/delete/update order. |
| D4 — остальные существующие поверхности | Routing/DNS/Inbound/TLS/WARP, Logs/About/Intro, все picker/input/slider и app-owned dialogs/toasts | Каждый исходный setter/route/action; debug/platform gates; missing-frame варианты из A. |
| D5 — общий вид и декор | Общие scoped Dark правила на полном mobile охвате; навигационный material, тихие эффекты | App-wide contrast/readability/actions, Light/Black/широкая tablet-ветка/другие platforms legacy; narrow-iPad mobile case, reduced fallbacks и performance. |

Для каждой порции:

- [ ] Запустить уже подготовленный целевой visual RED и behavioral baseline GREEN.
- [ ] Изменить только оформление и размеры/материалы по утверждённым правилам, сохранив callbacks, predicate order и component/controller lifetime.
- [ ] Проверить один tap/long press → тот же effect, те же аргументы и количество вызовов; асинхронные результаты/late completion дают исходный результат.
- [ ] Выполнить relevant regression + ранее пройденные UI/visual cases + boundary guard. При правке общей scoped Blizzard ThemeData — invariants всех её surfaces сразу.
- [ ] Сравнить screenshot и запись действия с эталоном, проверить keyboard/back/focus/scroll и исходные overlays.
- [ ] Записать source SHA, test IDs, fixture, visual acceptance и результаты; сделать небольшой тематический commit. Пока порция не GREEN, следующая не начинается.

**Особые условия исходника:** connected label при delay `>=65000` и secure-label при delay `>65000` имеют разные границы. Сохраняем точные исходные predicates и тестируем 65000 отдельно. `profile_tile.dart` содержит immediate close и late success/mounted/canPop sequence — сохраняем её. Native/frontend pause/resume listeners в `app.dart` не перемещаем.

Анимации — отдельная последняя visual порция после функционального GREEN; статичная Blizzard сцена уже удовлетворяет v1. Motion не задерживает бизнес-команду, не создаёт таймерный источник VPN-статуса и не меняет доступность действий. Новые haptics не добавляем. Стоимость blur/particles измеряем на exact build; Flutter material не выдаём за native Liquid Glass.

## 7. Задача E — итоговый regression и физическая приёмка

**Files:** `docs/verification/blizzard/device-acceptance.md`, `acceptance-results.json`; существующий baseline/release tooling без его переписывания.

**Consumes:** D1–D5 GREEN, visual review 89/89 и transient coverage, exact source/build/core manifest. **Produces:** доказательства одинакового поведения baseline/candidate и сохранения данных.

- [ ] Полный тестовый GREEN, protected trees/runtime dependencies/identity неизменны. Analyzer diagnostics сравнить с baseline; новые относящиеся к изменению ошибки запрещены.
- [ ] Designer review полного охвата 89/89, новых source-backed transient вариантов и 14 risk specimens; проверить actual SF Pro и физическую клавиатуру.
- [ ] Сравнить заранее записанный baseline/candidate protocol на том же устройстве/OS/сети с контролируемыми условиями.
- [ ] Установить candidate поверх существующих данных в согласованном тестовом контексте. Profile IDs/count, active profile/server, preferences, theme/locale и drafts должны сохраняться; fresh install не заменяет upgrade.
- [ ] Импорт всех существующих способов: success, cancel, invalid и retry; no profile path; dialogs/sheets/back/deep links.
- [ ] Пять connect/disconnect циклов, reconnect и server/profile switch при разрешённых исходных условиях. Согласовать model/UI/system tunnel и реальные контрольные запросы.
- [ ] Проверить Wi-Fi→cellular→Wi-Fi, background, lock/unlock и relaunch. Для core/DNS/TCP/UDP/IPv4/IPv6 использовать baseline fixture policy и доступные endpoints, сохраняя конкретную routing policy.
- [ ] Native VPN/camera permission deny/retry/grant проверяется в отдельно согласованном тестовом контексте; личное разрешение не сбрасывать. `integration_test` не закрывает этот пункт.
- [ ] VoiceOver, Dynamic Type, Increase Contrast, Reduce Transparency/Motion и modal focus проверяются на устройстве.
- [ ] Измерить холодный запуск, прокрутку, memory/frames и scene cost на одной и той же паре release builds. Методика и budget фиксируются до UI; первоначальный ориентир cold-start median +20% из baseline протокола не является уже измеренным результатом. Crashes/hangs/inaccessible actions — FAIL.
- [ ] Подтвердить возможность отката оформления отдельным UI revert или проверенной rollback сборкой поверх сохранённых данных. Нельзя обещать downgrade через обычную установку старого TestFlight build; доставка rollback имеет свои version/build/provenance ограничения.
- [ ] Только после приёмки и отдельного запроса на выпуск использовать текущий private TestFlight процесс. Не добавлять testers, новый app record, App Store objective или серверные изменения.

Недоступный device/fixture/tooling получает `BLOCKED/NOT RUN`, а не PASS. Новые exact builds требуют соответствующих новых receipts; signing/upload/Connected screen не заменяют traffic proof.

## 8. Команды и правила выполнения

Команды ниже — для будущего isolated implementation checkout, из его корня, с закреплённым существующим SDK. Они не запускались при написании этого плана.

```sh
flutter analyze
flutter test --dart-define=BLIZZARD_VISUALS=false test/ui_preservation
flutter test --dart-define=BLIZZARD_VISUALS=false test/visual
flutter test --dart-define=BLIZZARD_VISUALS=true test/ui_preservation
flutter test --dart-define=BLIZZARD_VISUALS=true test/visual
flutter test --dart-define=BLIZZARD_VISUALS=true
ruby test/ci/blizzard_runtime_boundary_test.rb
ruby test/ci/ios_baseline_identity_inventory_test.rb
ruby test/ci/ios_baseline_signed_entitlements_test.rb
ruby test/ci/ios_baseline_release_test.rb
ruby test/ci/ios_baseline_workflow_test.rb
bash test/security/ios_baseline_core_test.sh
```

Две именованные конфигурации: **legacy/switch-off** и **candidate/switch-on**. Test fixture selection и expectations следуют конфигурации: off сверяется с baseline, on — с Blizzard; не запускать Blizzard-only ожидания как обязательный GREEN на legacy. Финальная visual/device/performance приёмка относится к on candidate. Каждый receipt включает boolean define, source SHA и режим. Дополнительно полный suite запускается с false для проверки сохранения legacy результата.

Для локального simulator artifact после B — `flutter build ios --simulator --no-codesign --target lib/main_prod.dart --dart-define=BLIZZARD_VISUALS=true`; receipt также записывает target/SDK/artifact hash и не является release/device/VPN proof. `lib/main_prod.dart` совпадает с текущим baseline release entrypoint; перед запуском проверяются его существующие environment/core prerequisites, без чтения или вывода секретных значений. Невыполненные prerequisites дают tooling blocker. Signing и upload этим действием не подразумеваются.

До D5 default остаётся false. После всех relevant gates на on-конфигурации отдельная **только визуальная** правка в `blizzard_theme.dart` меняет default на true для release candidate; явный false сохраняет legacy путь. Это позволяет существующему release workflow собрать включённый skin без добавления новых pipeline steps/arguments. После смены default заново выполнить suite с обеими explicit конфигурациями и обычный `flutter test`, собрать новый exact candidate и записать define/default в provenance. Итоговая физическая приёмка выполняется на этом новом exact artifact, а не переносится со старого SHA. Откат default сам по себе не обновляет уже установленный бинарник.

Ожидаемый финальный результат tests/guards: exit 0, все утверждённые cases PASS; analyzer не добавляет diagnostics к зафиксированному baseline. Core shell suite использует существующие подготовленные prerequisites; их отсутствие — tooling blocker.

Integration command задаётся только после подтверждения явно выбранного изолированного Simulator, target и test-host configuration на B. Для этого использовать уже описанный strict selector/protocol в плане от 3 октября. Не подставлять произвольный device ID и не запускать физическую установку по умолчанию. Предварительные visual RED фиксируются целевыми cases отдельно и не смешиваются с обязательным final all-GREEN.

После relevant GREEN проверки не повторять полный дорогой цикл без новой правки, failure или unresolved concern. Физическая матрица выполняется на релизном candidate; после каждой правки отступа телефонный прогон не требуется.

## 9. Готовность и условия остановки

Работа принята, когда:
1. Все 89 target frames сопоставлены с реализованными состояниями; существующие дополнительные actions/menus/editors не потеряны.
2. Runtime predicate/callback/action/storage/route contract совпадает с baseline; protected logic и identities неизменны.
3. Dark соответствует Blizzard; Light/Black и выбор System/locale сохраняют согласованное поведение.
4. Нет новых crashes, overflow, inaccessible actions, повторных commands, повреждённых drafts или потери данных после update.
5. Behavioral/integration/visual/a11y gates и обязательная exact-build device матрица имеют реальные результаты.
6. Есть reviewable source diff, complete provenance и проверенный путь отката; декоративная производительность укладывается в заранее принятый budget.

Если для визуального изменения требуется тронуть защищённый controller/provider/router/native API, production seam или storage, остановить именно этот участок, назвать concrete blocker и вынести его отдельной задачей. Не чинить посторонний баг незаметно. Ни одна такая правка не маскируется именем «reskin».

## 10. Ревью плана

Self-review: покрыты точный visual-only scope, Dark/System/Black policy, исходная provenance, тесты до UI, защита бизнес-логики внутри UI-файлов, gaps 89-frame набора, app/system surfaces, async/lifecycle/controller lifetime, accessibility, performance, update-over-data и rollback.

Независимый read-only аудит source выполнен Astra low после недоступности первого Sol medium ревьюера. Финальное независимое ревью документа — **PASS**: первоначальные замечания об области темы, старых CI-инструкциях и проверке включённого switch закрыты. Проверены scope, существующие пути и непротиворечивость gates. Production tests/build/device проверки в этом ходе `NOT RUN`.
