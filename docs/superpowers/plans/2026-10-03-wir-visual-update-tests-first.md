# Безопасное визуальное обновление WIR Baseline — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> В текущем каталоге соответствующие навыки называются `subagent-driven-development` и `executing-plans`. Исполнение начинается только после отдельного запроса пользователя на реализацию. Этот документ — план, а не разрешение менять приложение или публиковать сборку.

**Goal:** Обновить внешний вид рабочего iOS-приложения до согласованного дизайна Woman in Red, сохранив импорт, VPN, маршрутизацию, профили, настройки и данные при обновлении.

**Architecture:** Использовать работающую WIR Baseline как основу. Менять Flutter-представление существующих состояний и действий; сохранять Riverpod, репозитории, ядро, native bridge и Packet Tunnel. Переносить из старого приложения только проверенные визуальные решения, без переноса целых экранов вместе с их логикой.

**Tech Stack:** Flutter 3.38.5 / Dart 3.10.4; Riverpod; GoRouter; Drift / SharedPreferences; официальный Hiddify app 4.1.1 и core 4.1.0; существующий iOS signing / private TestFlight pipeline.

## Global Constraints

- **Все необходимые автоматические тесты, fixtures, ручные сценарии, ожидаемые результаты и команды запуска должны быть написаны до первой production-правки интерфейса.** Позднее добавление проверок не закрывает этот gate задним числом.
- Текущий запрос разрешает составление плана. В этой работе production-код, зависимости, CI, приложение на телефоне и Apple-настройки не меняются.
- Для сохраняемого поведения: characterization GREEN на baseline, проверка чувствительности теста, затем сохранение GREEN на новом UI. Для новых визуальных требований: корректный поведенческий/визуальный RED на старом UI → минимальное изменение → GREEN. Ошибка компиляции, MissingPluginException, отсутствие fixture или SDK не считаются RED требования.
- Доставка только в личный TestFlight. Публикация в App Store, приглашение тестеров, изменения сервера и чужих приложений не входят в план.
- Не удалять приложение ради проверки или отката; не сбрасывать профиль, подписку, VPN-конфигурацию или настройки без отдельной причины и разрешения.
- Никаких секретных URL, токенов, UUID, исходных IP, конфигов или полных приватных логов в тестовых артефактах. Использовать синтетические данные, локальные сравнения и безопасные метки.
- Любой соседний дефект оформлять отдельно. Начальный отказ импорта остаётся известным наблюдением с неустановленной причиной; визуальный редизайн не должен объявлять его исправленным.

---

## 1. Точка отсчёта и границы доказательств

План составлен 3 октября 2026 года по прочитанному коду и текущему диалогу.

| Параметр | Рабочий эталон |
|---|---|
| Установленная пользовательская сборка | WIR Baseline **0.0.1 (1)** |
| Source SHA выпущенной сборки | `0830294eff5b8cd86324545ed00689648c70bd23` |
| Официальная исходная база | Hiddify 4.1.1, `abbd671bf6bf05195acd4158c714bff267cada8f` |
| Канонический checkout сейчас | `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-baseline`, branch `chore/clean-hiddify-ios-baseline`, HEAD `fe6f971674787ec0ae2955ef0cba456857324810` |
| Проверенная копия опубликованного source | `/private/tmp/wir-baseline-release-publication` |
| App / extension | `com.womaninred.baseline` / `com.womaninred.baseline.HiddifyPacketTunnel` |
| App Group / Team / service channel | `group.com.womaninred.baseline` / `M9D72QQJ79` / `com.hiddify.app` |
| Core | 4.1.0; gitlink `c9d6f0f00b2eda34e4fb71863e4e0a62b3e931a0` |
| SHA256 архива core | `31a03842df31fcebd8a1d43c883acd82f437639075815029f00859fb3470164b` — это hash архива, не framework и не IPA |
| SHA256 baseline IPA | `346cd87f18e2549e79d615a897da2d304d0e65ccf0478eeb2a2f683e96b57685` |
| Подтверждённая доставка | run `37128905532`; Apple `VALID`, `IN_BETA_TESTING`, existing internal group `Test` |
| Workflow SHA выпущенной сборки | `a17fb44a4f760f1ca69c98048a10e1dad7419472` на main |
| Пользовательская проверка | После повторного импорта профиль добавился; пользователь сообщил, что VPN, блокировка/возврат и последующие проверки работают |
| Что не измерено независимо | Полная матрица TCP/UDP/DNS IPv4/IPv6, точные длительности, пять циклов и формальная deny/retry/grant-последовательность |

Пользовательский результат принимается: это работающая исходная точка для визуального обновления. Он не заменяет измерений, необходимых для сравнения конкретной следующей сборки. Не задавать повторно вопрос, действительно ли пользователь проверяет WIR Baseline.

Canonical HEAD и shipped SHA различаются по истории. До работы сравнить их деревья; эталоном поведения и release provenance считать **shipped SHA**, а не название ветки. Runtime-поддеревья уже сопоставлены по Git blobs: core interface, profile/import, HTTP, bootstrap/error presentation, Swift handlers/AppDelegate/extensions/tunnel и lockfile совпадают. Перед реализацией сохранить свежий manifest этого сравнения.

Дополнительное прямое сравнение при подготовке плана подтвердило совпадение `scripts/`, `test/ci/`, `test/brand/` и source workflow `ios-baseline.yml` между canonical HEAD и shipped source. Поэтому старт из shipped SHA не теряет текущий проверенный release tooling. Реальный main workflow имеет отдельный SHA из таблицы; его reviewed trust bindings сохраняются и заново проверяются при будущем выпуске. Если после даты плана появится новое hardening, сначала инвентаризировать и сохранить его tests-only/release change, не откатывать механически.

### Реально существующие проверки

- `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-baseline/test/brand/ios_baseline_contract_test.dart` — Apple identity, исходные entitlements, channel и export/version.
- `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-baseline/test/ci/ios_baseline_identity_inventory_test.rb`.
- `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-baseline/test/ci/ios_baseline_signed_entitlements_test.rb`.
- `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-baseline/test/ci/ios_baseline_release_test.rb`.
- `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-baseline/test/ci/ios_baseline_workflow_test.rb`.
- `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-baseline/test/security/ios_baseline_core_test.sh`.
- Parser, DB migration и IP-masking tests в `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-baseline/test/`.

Поведенческих/widget/golden-проверок мигрируемых экранов и готового `integration_test/` контура сейчас нет. `RunnerTests.swift` содержит пустой пример, а не доказательство native lifecycle. Поэтому первая работа при реализации — именно тестовый контур. В рамках составления плана эти новые тесты не написаны и не запущены.

## 2. Что должно оставаться неизменным

### Защищённая логика

| Граница | Почему защищаем |
|---|---|
| `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-baseline/lib/hiddifycore/` и `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-baseline/hiddify-core/` | Core setup, foreground validation, RPC, запуск/остановка |
| `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-baseline/ios/Runner/Handlers/`, `/ios/Runner/VPN/`, `/ios/Runner/Extensions/`, `/ios/Runner/AppDelegate.swift`, `/ios/HiddifyPacketTunnel/` | Native bridge, App Group, consent, системный VPN и Packet Tunnel; сокращённые `/ios/` пути в этой строке относятся к тому же checkout |
| `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-baseline/lib/features/connection/data/`, `/lib/features/connection/notifier/`, `/lib/features/connection/model/` | Единственный источник состояния подключения и connection actions |
| `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-baseline/lib/features/profile/data/`, `/lib/features/profile/notifier/` | Парсинг, проверка, сохранение и выбор профиля |
| `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-baseline/lib/features/settings/data/`, `/lib/features/settings/notifier/`, `/lib/core/preferences/`, `/lib/singbox/` | Значения настроек и генерируемая конфигурация |
| `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-baseline/lib/bootstrap.dart`, `/lib/features/app/widget/app.dart`, `/lib/features/connection/widget/connection_wrapper.dart` | Порядок запуска, lifecycle, подписки и восстановление состояния |
| `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-baseline/lib/core/router/go_router/`, `/lib/core/router/deep_linking/` | Shell, реальные destinations, возврат и deep links |
| Drift schema, storage keys/paths, bundle IDs, App Group, service channel, entitlements, core binaries | Совместимость установленного обновления с существующими данными |

В строках с несколькими путями сокращение `/lib/` или `/ios/` означает продолжение полного префикса `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-baseline`; это не путь от корня файловой системы.

До создания UI checkout закрепить shipped SHA `0830294eff5b8cd86324545ed00689648c70bd23` в долговременном Git remote/ref либо проверенном Git bundle вне `/private/tmp`; записать адрес/ref или путь bundle, SHA256 bundle и tree SHA в baseline manifest. Источник существует в `/private/tmp/wir-baseline-release-publication`; это временная проверенная копия, а не утраченный source. Проверить восстановление объекта и exact tree из долговременного источника. Уже проверенное совпадение runtime и release tooling с canonical checkout не означает недостающего CI-hardening delta.

Для реализации создать отдельный checkout `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-ui` **из shipped SHA**. Там те же защищённые относительные поддеревья. Существующие dirty checkout, evidence и сборки сохраняются. Отдельный checkout не означает отдельное iOS-приложение: идентификаторы оставляются прежними, чтобы установить обновление поверх baseline.

### Допустимые визуальные изменения

- Главная: `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-ui/lib/features/home/widget/home_page.dart`, `connection_button.dart` в той же директории; новые чистые визуальные компоненты рядом.
- Оформление навигации: `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-ui/lib/core/router/adaptive_layout/my_adaptive_layout.dart`; существующий `StatefulNavigationShell`, индексы и actions сохраняются.
- Внешний вид профилей и импорта: `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-ui/lib/features/profile/widget/`, `/lib/features/profile/overview/`, `/lib/features/profile/add/` — только layout, текст и оформление существующих действий. Файлы notifiers/data не входят в этот список.
- Серверы: `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-ui/lib/features/proxy/widget/`, `/lib/features/proxy/active/`, `/lib/features/proxy/overview/` — только widget-файлы; `active_proxy_notifier.dart` защищён.
- Настройки, правила и вспомогательные экраны: widget/page-файлы в `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-ui/lib/features/settings/overview/`, `/lib/features/route_rules/overview/`, `/lib/features/about/widget/`, `/lib/features/log/overview/`, `/lib/features/intro/widget/`.
- Тема: `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-ui/lib/core/theme/app_theme.dart`, `theme_extensions.dart` и новый `wir_visual_tokens.dart` в той же директории. Хранение и смысл theme preference не менять.
- Проверенные изображения/шрифты и их asset declarations. Новые runtime-зависимости для blur/анимации не добавлять.

Это кандидаты для инвентаризации, а не широкая allowlist каталогов. До тестового этапа A записать конечный список конкретных production-файлов и защищённых символов/callback mappings внутри каждого файла. Path guard дополняется поведенческими tests и review каждого callback. Текст и набор действий по умолчанию сохраняются; новые copy/error meanings или действия требуют отдельного заранее заданного контракта. Generated-файлы вручную не редактируются; новая генерация допускается только из заранее согласованного UI/assets/localization-изменения.

## 3. Задача A — зафиксировать дизайн и полную матрицу поведения

**Files:** создать в будущем UI checkout:

- `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-ui/docs/verification/ui-migration/screen-state-contract.md`;
- `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-ui/docs/verification/ui-migration/baseline-manifest.json`;
- `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-ui/docs/verification/ui-migration/acceptance-matrix.csv`;
- `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-ui/docs/verification/ui-migration/approved-visuals/`.

**Consumes:** точный shipped source, существующее поведение, актуальные согласованные макеты Woman in Red.

**Produces:** для каждого iOS-visible экрана и каждого интерактивного элемента запись `screen/state/action/provider.method/arguments/effect/test_id/visual_reference`.

- [ ] Снять source/core/dependency/storage/identity manifests и состояние старых checkout; сохранить безопасные screenshots baseline.
- [ ] Подготовить в pen.dev полный набор текущих baseline экранов/состояний, включая overlays, с двумя вкладками Home/Settings и существующими system/light/dark/black. Это реконструкция текущего продукта по source/screenshots, а не автоматически утверждённый будущий дизайн.
- [ ] До visual test authoring сохранить `docs/verification/ui-migration/design-manifest.json`: pen.dev file/revision и frame ID, source/build screenshot reference, screen/state, viewport/DPR/locale/theme, approved appearance, статус согласования и отклонения от исторических specs. Отдельно связать baseline frames и утверждённые целевые frames; незаполненное согласование оставляет Gate A открытым.
- [ ] Сопоставить актуальные визуальные референсы с экранными состояниями. Исторические specs старого fork — материал для проверки, а не автоматическое разрешение копировать их решения.
- [ ] Исторический dark-theme spec: `/LOCAL_USER_HOME/Documents/KVN/hiddify-app/docs/superpowers/specs/2026-07-14-woman-in-red-dark-theme-design.md`; tab-bar spec: `/LOCAL_USER_HOME/Documents/KVN/hiddify-app/docs/superpowers/specs/2026-07-13-nova-liquid-glass-tab-bar-design.md`. Дизайн-смысл можно использовать, текущую актуальность и поддержку функций проверить.
- [ ] Старый макет содержит четыре вкладки; рабочий mobile shell сейчас имеет Home/Settings. Механически заменять shell четырьмя вкладками нельзя. В первом визуальном этапе сохраняются текущие destinations; иное размещение существующих экранов оформляется отдельным явно заданным navigation contract с тестами до кода.
- [ ] Не переносить историческое решение «dark-only» вместе со скрытием theme picker: baseline поддерживает system/light/dark/black. Сохранить существующие варианты и записать эталоны для каждого; изменение продуктовой политики тем — отдельная задача.
- [ ] Утвердить геометрию, палитру, типографику, safe areas, состояния и поведение анимаций. До этого визуальные ожидания не считаются готовыми и production UI не начинается.
- [ ] Для каждого существующего действия указать доступный путь в новом дизайне. Новое оформление не должно скрыть импорт, выбранный профиль/сервер, диагностику или настройку, которую можно было открыть раньше.

**Gate A:** нет экранов, состояний или действий без эталона и test ID. Матрица покрывает все iOS-visible страницы, sheets/dialogs/menus и переходы, затронутые общей темой. Неподдерживаемые функции старого макета не изображаются как работающие.

## 4. Задача B — написать весь тестовый контур до UI

**Первый шаг B — техническая выполнимость:** до разворачивания полного suite написать и запустить минимальный `integration_test/ui_harness_smoke_test.dart`: один настоящий iOS экран, изолированная внешняя platform/core граница и рабочий изолированный native storage context. Проверить simulator slice либо test-only host, реальный запуск и write/read storage; затем на этом harness написать полный suite. Smoke не заменяет Gate B и не разрешает production UI: все тесты и физические сценарии по-прежнему пишутся до первой UI-правки.

**Files:** создать tests-only commit в будущем UI checkout:

| Файл относительно `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-ui/` | Ответственность |
|---|---|
| `scripts/run_ui_contract_tests.py` | Исполняемый expected-RED/all-green runner pinned Flutter JSON event stream |
| `test/ci/ui_contract_runner_test.py` | Fixture-based tests политики runner: разрешённые assertions и все отказные случаи |
| `docs/verification/ui-migration/ui-test-phases.json` | Committed stable test IDs, named assertion IDs, phases и точный pending RED список |
| `.github/workflows/ios-baseline.yml` | Явное подключение runner, его tests, обоих новых Ruby guards и integration/core jobs до signing/publish |
| `integration_test/ui_harness_smoke_test.dart` | Ранний iOS feasibility smoke реального экрана и native storage |
| `integration_test/ui_native_persistence_test.dart` | Раздельные write/read запуски настоящего изолированного native store без повторного seed |
| `test/helpers/ui_migration_harness.dart` | Riverpod overrides, fixed locale/fonts/viewport, lifecycle и recording adapters |
| `test/helpers/ui_migration_fixtures.dart` | Детерминированные synthetic profiles/settings/core events |
| `test/features/connection/connection_behavior_contract_test.dart` | Настоящие repository/notifier + записывающая внешняя граница |
| `test/features/profile/profile_import_contract_test.dart` | Импорт, реальные parser/storage, отказ и retry |
| `test/features/home/widget/home_actions_contract_test.dart` | Все действия главного экрана |
| `test/features/home/widget/connection_button_contract_test.dart` | Состояния, reconnect, single-action, ошибки |
| `test/features/profile/widget/profile_actions_contract_test.dart` | Профили, выбор, импорт, обновление, формы |
| `test/features/proxy/widget/proxy_actions_contract_test.dart` | Выбор сервера, группы, latency и ошибки |
| `test/features/settings/widget/settings_persistence_contract_test.dart` | Настройки и сохранение прежних значений |
| `test/core/router/ui_navigation_contract_test.dart` | Shell, back, route и overlays |
| `test/visual/ui_visual_contract_test.dart` | Заранее заданные цвет/геометрия/текст/семантика и golden comparisons |
| `test/visual/ui_accessibility_contract_test.dart` | Touch targets, контраст, крупный текст, reduced motion |
| `test/ci/ui_runtime_boundary_test.rb` | Protected tree/dependency/identity guard |
| `test/ci/ui_simulator_selector_test.rb` | Разрешён только однозначно выбранный available iOS Simulator; отказ при неоднозначности/physical device |
| `scripts/ui_test_simulator_id.py` | Читает CoreSimulator inventory и возвращает единственный ID заранее подготовленного simulator `WIR UI Verification`; никаких launch/install/reset по умолчанию |
| `integration_test/ui_preservation_test.dart` | Настоящие экраны, локальная БД/настройки, управляемая platform boundary |
| `docs/verification/ui-migration/physical-acceptance.md` | Все физические сценарии и критерии PASS/FAIL |
| `docs/verification/ui-migration/test-readiness.json` | Полный список test IDs, GREEN/expected RED, доказательства чувствительности |

В этой таблице пути относительные для команд из явно заданного будущего checkout; файлы ещё не существуют. Она задаёт точные будущие расположения, а не утверждает, что тесты уже реализованы.

### Правила harness

- Существующие типы: `ConnectionNotifier`, `ActiveProfile`, `ActiveProxyNotifier`, `ConfigOptionNotifier`, `ConnectionRepositoryImpl`, `ProfileEntity.local/remote`.
- Override через `connectionNotifierProvider.overrideWith`, `activeProfileProvider.overrideWith`, `activeProxyNotifierProvider.overrideWith`, `configOptionNotifierProvider.overrideWith`; `translationsProvider` получает `AsyncData(AppLocale.ru.build())` или EN.
- Для widget wiring записывающие notifier adapters допустимы. Для logic-contract tests не заменять проверяемый notifier/repository его фейком: заменяется только core/platform/HTTP граница; используются настоящие parser, DB и preferences.
- `DialogNotifier`/`BottomSheetsNotifier` записывают запросы открытия, но не имитируют проверяемую business-логику. Один тест проверяет реальный sheet/dialog через настоящий UI.
- `SharedPreferences.setMockInitialValues` используется только для unit/widget и даёт receipt `in_memory`; пересоздание provider/container не доказывает persistence. Реальная file DB создаётся в изолированной временной директории; close/open даёт только `file/native_reopen`.
- Для preferences persistence использовать настоящий platform store изолированного iOS test host: write → завершить процесс → новый запуск → read без повторного seed/fixture initialization. Такой receipt имеет уровень `process_restart`. Upgrade — отдельная установка baseline→candidate поверх данных и receipt `actual_build_upgrade`; фактические F01/F09 на устройстве обязательны. Каждый I05/S02/D01/R01 receipt указывает storage backend, границу перезапуска и один из четырёх уровней; mock, reopen и simulator restart не заменяют device upgrade/rollback proof.
- Не добавлять production API «для теста», новый `ProviderScope` или второй core. Production seam/refactor в защищённых connection/profile/core/router границах не разрешён этим визуальным этапом. Если текущий API не позволяет изолировать границу, назвать точный blocker и вынести узкую задачу с тестами и отдельной авторизацией; не менять runtime под видом подготовки harness.
- Для размеров и accessibility применять реальные `MediaQuery`/tester view, не создавать второй app/router container. Формы проверять с открытой клавиатурой.
- Test fixtures: два synthetic профиля `fixture-local-a`, `fixture-local-b`; фиксированное время; deterministic outbound data; валидный/невалидный JSON; remote content отдаётся управляемым локальным HTTP server; сценарии empty/timeout/error/cancel. Настоящая пользовательская подписка в fixtures не используется.
- Sentry/analytics/IP auto-check и внешние запросы в harness изолируются на внешней границе, с проверкой отсутствия непредусмотренных запросов. Runtime preferences пользователя не меняются.
- Golden harness: закрепить SDK/OS/fonts/locale/DPR/viewport, время и кадр анимации. Не использовать бесконечный `pumpAndSettle` для бесконечной анимации; проверять заданные кадры через bounded `pump`.

### Обязательная спецификация тестов

Каждая строка — семейство независимых test cases. Перечисленные варианты оформляются отдельными тестами с ID суффиксом, а не одним общим «smoke». Все эти cases пишутся на этапе B.

До запуска разделить assertions на **сохраняемый фактический baseline contract**, **новое визуальное/a11y требование** и **обнаруженный старый дефект**. Сохраняемый контракт должен быть GREEN без production-правок. Предлагаемый safety criterion не объявляется уже существующим фактом. Старый defect получает отдельную запись с решением о влиянии на миграцию; исправление поведения не прячется в редизайн. Критический дефект нужной для миграции границы блокирует Gate B до отдельно согласованного решения; некритический фиксируется как существующее ограничение, без молчаливого ослабления теста. Улучшение текста ошибки входит только в заранее утверждённый copy contract.

| ID | Действие/вход | Что обязательно должно сходиться |
|---|---|---|
| C01 | `CoreStopped/Starting/Started/Stopping` и stopped с alert | Точные `Disconnected/Connecting/Connected/Disconnecting`; ни UI, ни анимация не создают Connected самостоятельно |
| C02 | Connect с profile A | `setup → applyConfigOption → start`; те же profile id/path/name/options и `disableMemoryLimit` |
| C03 | Ошибка setup/config/start по отдельности | Нет последующего вызова после отказавшего этапа; конечная ошибка и обычный retry; сравнить с baseline, обнаруженную старую проблему отделить от редизайна |
| C04 | Disconnect/reconnect, profile A→B, удалён активный профиль | Прежний `stop/restart`, правильный профиль; старый профиль не остаётся выбранным тайно |
| C05 | Один tap, два быстрых tap; tap в Connecting/Disconnecting/loading | Один tap сохраняет точный callback baseline; двойной tap воспроизводит измеренный baseline throttling. Новых start/stop нет; никакие действия не вызываются из build/animation callbacks. Новая debounce policy — отдельное требование, если baseline ей не соответствует |
| C06 | Theme/locale change, возврат на экран, открытие sheet | Без нового start/stop/setup и без второго экземпляра core/notifier из-за визуального rebuild |
| C07 | AsyncError/disconnected failure, retry | Прежняя ошибка видна и прежний доступный retry сохранён; no new false success toast/state. Более понятный error copy сначала отдельно утверждается и получает собственный RED |
| C08 | Settings require reconnect true/false; latency 0, normal, >65000 | Прежние reconnect actions; отсутствие ложного «защищено» только из-за декоративного состояния |
| I01 | Clipboard: valid local, valid remote, empty, malformed, read failure | Тот же input в настоящем parser/repository; одна попытка; пустое/невалидное не создаёт профиль |
| I02 | Manual/QR: valid, cancelled, denied permission, malformed | Прежний import action; cancel/deny без phantom record или зависания |
| I03 | HTTP timeout/error/cancel; foreground validation unavailable | Проверить реальные persistence/error/retry baseline semantics и сохранить их. Если найдено сохранение недопроверенного профиля или отсутствие retry, зафиксировать отдельный дефект до Gate B; редизайн его не исправляет молча |
| I04 | Успешный импорт/повторный импорт/обновление существующего remote | Те же запись/количество/active-selection/данные; duplicate/update policy равна baseline |
| I05 | Перезапуск после добавления и выбора profile B | Реальная DB возвращает те же profile IDs/count/active selection; не требуется новая подписка |
| I06 | Native unavailable → повторный импорт по сценариям boundary | Characterize baseline как есть; тест не объявляет неизвестную первоначальную причину исправленной |
| H01 | Add/profile overview/quick settings/proxy navigation | Прежние notifier methods/route names и аргументы; один tap — один эффект |
| H02 | Нет профиля/loading/ошибка профилей/выбран A/выбран B | Доступный путь импорта и тот же выбранный профиль; нет fabricated данных |
| P01 | Выбор профиля и каждое реально существующее update/delete/export/edit действие; отмена подтверждения | Прежние write/cancel semantics; cancel не меняет storage; список и selection соответствуют реальной БД. Rename включается только если инвентаризация подтвердила существующий путь; новые функции не добавляются |
| P02 | Выбор сервера/группы, latency test, timeout/error | Прежний outbound и действующее core action; оформление не меняет route policy |
| S01 | Каждый отображаемый switch/radio/slider/text setting | UI value = stored preference = value read by runtime; boolean inversion и единицы не изменены |
| S02 | Reopen, app restart, candidate update | Те же persisted keys/values/defaults и типы; никаких reset/migration от визуального обновления |
| S03 | Cancel/invalid input/save failure | Draft/старое значение сохраняются по исходному контракту; no success before persistence |
| S04 | System/light/dark/black, язык, память/debug/logging/IP-auto-check | Прежний смысл всех существующих options; изменение appearance не меняет VPN/debug/config preferences |
| N01 | Home↔Settings; proxies/profile details/options/logs/about/intro | Прежние destinations, shell branch state, корректный back; no duplicate route/container |
| N02 | Sheet/dialog open/close; keyboard/back/gesture; scroll | Нет потерянного draft/selection/connection action; экран после возврата сохраняет состояние |
| N03 | Existing deep link и импорт внутри приложения | Та же routing policy; результат фиксировать в конкретном app, общую URL scheme не считать доказательством выбора приложения |
| V01 | Каждый state из screen-state-contract | Layout, typography, tokens, icons, texts и assets соответствуют утверждённому эталону |
| V02 | 320×568, 390×844, 430×932, 844×390; scale 1.0/1.3/2.0; RU/EN | Нет overflow/clipping/недоступных кнопок; safe-area и keyboard inset сохраняют доступ к действиям |
| V03 | System light/dark, explicit light/dark/black; длинные labels/names, empty/error/loading | Эталоны соответствуют состоянию; нет белых/нечитаемых overlays; QR-полотно остаётся сканируемым |
| A01 | Semantics и VoiceOver, error/disabled/selected | Понятные labels/roles/status; состояние различимо без одного только цвета; порядок чтения соответствует действиям |
| A02 | Контраст, hit targets, Increase Contrast/Reduce Transparency/Reduce Motion | Targets ≥44×44 logical px; обычный текст contrast ≥4.5:1; декоративное движение/blur имеют читаемый fallback |
| D01 | Импорт→выбор→connect→events→disconnect→reopen | Настоящие UI + DB + preferences + управляемый platform adapter; сравнение event/action/storage trace с baseline |
| B01 | Любая production diff вне allowlist; protected runtime change | Guard FAIL по конкретному безопасному коду; неизменные runtime tree entries |
| B02 | Identity/core/options/storage/dependency mismatch | Guard FAIL; dev test-dependency additions не изменяют версии или sources runtime packages |
| B03 | IPA: права, подпись, targets, version/build/core/provenance | Старые строгие native signing/profile/source проверки остаются обязательными |
| R01 | Обновление baseline→candidate и candidate→rollback | Сохраняются реальные профили/settings/selection и способность подключаться; same IDs/storage |
| M01 | 2 прогревочных запуска отдельно; 10 измеряемых cold starts каждого exact release build на том же iPhone | До UI записать способ измерения first interactive frame и безопасные времена; сравнить median, без p95 по малой выборке. Плановый порог регрессии median +20%, зафиксировать его в A вместе с методикой; crash/hang — отдельный FAIL |

**Полнота:** S01/P01/N01 раскрываются по каждому действию из инвентаризации A. Не считать строку S01 выполненной после теста одного произвольного переключателя. Набор вариантов V02/V03 проходит для каждого существенно отличающегося layout и каждого изменённого UI state; text/layout test и pixel golden могут иметь разные объёмы, но оба объёма фиксируются до кода.

### Что доказывает, что тесты работают

- [ ] На immutable baseline regression suite компилируется и GREEN. Старые выявленные дефекты оформлены отдельными IDs; никакого blanket skip, xfail или ослабления ожиданий.
- [ ] В **отдельной одноразовой копии** убрать connection callback, подменить profile A на B, вызвать start дважды, показать Connected до core event, потерять settings save, изменить App Group/core hash. Каждый соответствующий regression test обязан упасть по ожидаемой assertion.
- [ ] Удалить все эти подмены; исходный GREEN восстановлен, clean diff подтверждён. Эти изменения не коммитятся и не попадают на телефон.
- [ ] Все новые визуальные assertions и совместимые эталонные изображения заданы по утверждённым макетам до production UI. Старый UI даёт RED по геометрии/цвету/представлению, не из-за отсутствующего класса или broken harness.
- [ ] Golden-файл нельзя впервые получить из уже написанного нового UI и объявить test-first эталоном. Если экспорт макета не совместим с pinned Flutter rasterization, сначала подготовить согласованный deterministic visual fixture/эталон в tests-only слое и численные layout/style assertions; до готовности эталона gate остаётся закрытым.
- [ ] Сохранить actual test outputs и `test-readiness.json`: ID, command, fixture, expected result, observed result, sensitive mutation и verdict. Отдельно фиксировать ожидаемые RED visual cases; nonzero exit без сверки точных failed IDs недостаточен.

**Gate B — разрешает первую UI-правку:** A завершена; весь необходимый runnable suite и физический протокол написаны; regression GREEN; visual RED корректен; чувствительность доказана; iOS integration harness действительно запускается на заявленной среде. Для неизменяемого native кода проверяются существующие Ruby contracts и runtime source guard, затем будущий signed IPA и телефон; готовый XCTest runtime suite не заявляется. Если нужно менять native код, это отдельная задача с тестами до кода. Unavailable fixture/tooling — `BLOCKED`, а не PASS и не RED продукта; отсутствие физического измерения обозначается отдельно и не выдаётся за локальный GREEN.

## 5. Задача C — визуальная миграция по небольшим шагам

**Consumes:** готовый A/B contract и тестовый suite. **Produces:** только разрешённые UI diffs плюс GREEN receipt для каждого шага.

Порядок, чтобы не смешать причины:

1. Добавить пока неактивные семантические токены и чистые компоненты. Затем выбрать и зафиксировать до правки один путь: локальное подключение стилей к явно перечисленным поверхностям либо отдельное атомарное включение общей `AppTheme`. При глобальном включении сразу получить GREEN theme/contrast/touch-target/overlay/action-access invariants на **всех** затронутых routes, sheets/dialogs/menus и текущих темах, включая ещё не мигрированные экраны. Theme preference сохраняется. Pending RED будущей геометрии не разрешает новую нечитаемость или потерю доступного действия.
2. Главный экран и connection control: реальное состояние, профиль, сервер, быстрые действия.
3. Profiles/import/QR/manual и все связанные overlays.
4. Servers/groups/latency и существующая навигация.
5. Settings/options/rules и оставшиеся iOS-visible экраны; about/logs/intro и общие dialogs.
6. Декоративные blur/animation только после функционального GREEN и accessibility fallback.

Для **каждого** пункта:

- [ ] Запустить уже написанный целевой тест и сохранить ожидаемый visual RED.
- [ ] Сделать минимальный разрешённый production diff; сохранить существующие callback/state mapping.
- [ ] Запустить те же тесты; получить GREEN.
- [ ] Прогнать весь regression suite, goldens/a11y реализуемого и уже реализованных этапов, protected-tree guard и analyzer diff. Все тесты следующих этапов также запускаются; допустим только заранее перечисленный expected visual RED с правильной assertion, без инфраструктурных ошибок.
- [ ] Проверить diff: новый ProviderScope/router/core, lifecycle change, storage write из build, новые runtime зависимости отсутствуют.
- [ ] Провести отдельное review поведения и визуального соответствия; приложить screenshot именно этого source, не старого checkout.
- [ ] Сохранить небольшой commit и test receipt. Следующий шаг не начинается при новой регрессии.

Нельзя переносить целиком старый `HomePage`/`ConnectionButton` или глобальную тему вместе с старой connection/config/navigation-логикой. Из общего компонента извлекать только оформление; изменения его поведения требуют отдельного теста и отдельной задачи.

## 6. Команды и CI-gates

Команды ниже предназначены **для реализации**, а не заявлены как выполненные этим планом. Запускать из `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-ui` после создания tests-only контура. Проверенный текущий SDK находится в `/private/tmp/wir-baseline-tools/flutter-3.38.5`; если временная копия исчезнет, восстановить ту же pinned версию/revision, не брать latest.

```sh
export WIR_PLAN_FLUTTER=/private/tmp/wir-baseline-tools/flutter-3.38.5/bin/flutter
export WIR_PLAN_DART=/private/tmp/wir-baseline-tools/flutter-3.38.5/bin/dart
export PUB_CACHE=/private/tmp/wir-baseline-tools/pub-cache

"$WIR_PLAN_FLUTTER" --version --machine
"$WIR_PLAN_FLUTTER" pub get --enforce-lockfile
"$WIR_PLAN_DART" --suppress-analytics run build_runner build --delete-conflicting-outputs
"$WIR_PLAN_DART" --suppress-analytics run slang
git diff --exit-code -- lib pubspec.lock

python3 -m unittest discover -s test/ci -p ui_contract_runner_test.py
python3 scripts/run_ui_contract_tests.py --flutter "$WIR_PLAN_FLUTTER" \
  --manifest docs/verification/ui-migration/ui-test-phases.json --mode phase
# Перед signing/publish обязательный режим без pending RED:
python3 scripts/run_ui_contract_tests.py --flutter "$WIR_PLAN_FLUTTER" \
  --manifest docs/verification/ui-migration/ui-test-phases.json --mode all-green
"$WIR_PLAN_FLUTTER" analyze --no-pub

ruby test/ci/ui_runtime_boundary_test.rb
ruby test/ci/ui_simulator_selector_test.rb
ruby test/ci/ios_baseline_identity_inventory_test.rb
ruby test/ci/ios_baseline_signed_entitlements_test.rb
ruby test/ci/ios_baseline_release_test.rb
ruby test/ci/ios_baseline_workflow_test.rb

IOS_BASELINE_CORE_ARCHIVE=/private/tmp/wir-baseline-core-4.1.0/hiddify-lib-ios.tar.gz \
  bash test/security/ios_baseline_core_test.sh
```

Framework revision должен быть `f6ff1529fd6d8af5f706051d9251ac9231c83407`. Generated prerequisites проверяются на чистом зафиксированном tests-only/UI commit, а не во время незакоммиченного изменения lockfile. Fixture/configuration ошибки исправляются до оценки RED/GREEN.

`flutter_test`/`integration_test` — SDK test-dependencies. В текущем pubspec нет подготовленного integration контура; добавления dev dependencies и стабильный lockfile оформляются **до UI**. Сравнить полный граф runtime packages с baseline: только необходимый dev-only delta разрешён. Если resolver хочет обновить runtime packages, отклонить такой lockfile и устранить test tooling prerequisite.

Integration target после создания harness запускать на iOS Simulator, чтобы исполнялись реальные `Platform.isIOS` ветки:

```sh
export WIR_PLAN_SIMULATOR_ID="$(python3 scripts/ui_test_simulator_id.py)"
test -n "$WIR_PLAN_SIMULATOR_ID"
"$WIR_PLAN_FLUTTER" test integration_test/ui_harness_smoke_test.dart --no-pub -d "$WIR_PLAN_SIMULATOR_ID"
"$WIR_PLAN_FLUTTER" test integration_test/ui_preservation_test.dart --no-pub -d "$WIR_PLAN_SIMULATOR_ID"
```

Для `ui_native_persistence_test.dart` до Gate B записать и проверить точные команды двух отдельных запусков write/read и завершения test-host процесса между ними; read запрещает повторную initialization fixture. Один непрерывный integration run не засчитывается как process restart.

Selector — новый test-infrastructure файл этапа B. Он читает `xcrun simctl list devices available --json`, требует единственный available simulator с именем `WIR UI Verification`, проверяет iOS runtime, выводит только его UDID, при ошибке выходит nonzero без выбора физического устройства. Если simulator отсутствует, подготовить отдельный test simulator до пробного запуска; script сам его не создаёт и не запускает. Выбор/boot тестового simulator не означает изменение личного телефона.

Harness обязан изолировать startup/platform services без runtime production-правок. До Gate B проверить, что core framework содержит нужный simulator slice, либо test-only target действительно исключает загрузку/линковку device-only framework и подменяет внешнюю границу. MissingPlugin, неподходящий slice или compilation error — prerequisite blocker, не RED приложения. До успешного пробного запуска конкретной команды контур не считается готовым. macOS host допустим только как дополнительный host test, не замена iOS-веткам. Simulator не доказывает Packet Tunnel или phone upgrade; личный телефон автоматически не выбирается.

### Исполняемая политика expected RED

Runner этапа B сам запускает pinned Flutter с `test --no-pub --reporter json`, сохраняет exit code и полный JSON event stream, проверяет завершённость прогона и сопоставляет стабильные case IDs с committed phase manifest. Visual assertion выдаёт точный named assertion ID; один только failed test name или произвольный текст ошибки недостаточен. Manifest связывает ID с фазой, fixture, утверждённым visual reference и разрешённой assertion; regression и уже реализованные cases обязаны быть GREEN.

До UI тесты runner должны доказать: принятие точного pending visual assertion failure; отказ при неправильной assertion, неожиданном failure, пропущенном обязательном ID, дубликате/обрезанном JSON, compile/plugin/fixture failure и незаявленном skip. Expected failures не маскируют дополнительную ошибку в том же case. Неожиданный GREEN pending case требует review manifest/receipt; исключения не расширяются ради production diff. `--mode all-green` отвергает непустой pending список, любые failures и обязательные незавершённые cases. Зафиксировать команду/SDK/manifest hash/source SHA в receipt. Runner tests используют synthetic machine-output fixtures, включая каждый отказный случай.

CI:

- Существующий `test-source` явно перечисляет четыре Ruby suites; discovery новых guards не предполагать. В tests-only commit добавить явные steps для `python3 -m unittest discover -s test/ci -p ui_contract_runner_test.py`, `ruby test/ci/ui_runtime_boundary_test.rb` и `ruby test/ci/ui_simulator_selector_test.rb`; существующие четыре suites сохранить. Полный Flutter suite запускать через runner в phase mode, а обязательный pre-sign/pre-publish job — через `--mode all-green`; signing/publish зависит от его успешного завершения для exact source SHA.
- До UI подготовить отдельный тестовый job/документированный runner для integration target и включить core shell suite; сейчас core shell suite не входит в `test-source`.
- Guard должен сравнивать **полный список paths/blobs** защищённых tracked деревьев, включая add/delete, со shipped baseline manifest; скан одного текста или проверка наличия слова недостаточны.
- Analyzer: снять свежий результат shipped baseline в той же среде; новые diagnostics отсутствуют, в изменённых файлах нет новых errors/warnings. Исторические 370 upstream issues не подставлять как сегодняшние данные и не «чинить всё» в редизайне.
- В tests-only этапе regression job GREEN, отдельная проверка expected-RED принимает только заранее перечисленные visual assertions. До UI закрепить manifest pending visual IDs по этапам. После каждого этапа его tests и все ранее реализованные tests GREEN; expected RED допустим только для точного списка ещё не реализованных этапов, все tests продолжают запускаться. Неожиданное падение всегда блокирует работу; неожиданно прошедший будущий test рассматривается и переводится в GREEN receipt, не игнорируется. Добавлять новое исключение или ослаблять assertion ради production diff нельзя. Перед signing/publish список expected RED пуст, весь suite GREEN. Ни blanket ignore, ни автоматическое `--update-goldens` в CI не допускаются.
- Flutter generation, hash/identity guard, dependency guard, tests и native verifier должны блокировать signing/publish при ошибке. Нельзя добавлять `continue-on-error` для обязательных gates.
- Если UI использует новые strings/assets, обновление generated output делается генератором, а source drift объясняется только соответствующими входами; неизменённые inputs должны воспроизводиться без diff.

## 7. Что конкретно сравнивается до и после

| Объект | Обязательное совпадение / разрешённое отличие |
|---|---|
| Core/native/runtime деревья | Paths и blobs защищённых файлов равны baseline; framework manifest/digest тот же. Разные IPA hashes ожидаемы для разных builds |
| Идентификаторы и права | Те же app/extension/App Group/Team/service channels; реальные signed entitlements и profiles проходят существующий verifier |
| Профили | Количество, локально сравниваемые IDs/данные, active selection и сохранённые options не изменены обновлением |
| Настройки | Типы, keys, values/defaults и значение, получаемое runtime, совпадают; theme policy сохранена |
| Конфигурация/действия | На одинаковых synthetic fixtures одинаковые semantic config inputs, outbound selection, action order/arguments и конечные статусы |
| Нестабильные поля | Только заранее перечисленные время/request IDs/ephemeral paths нормализуются; routing, server, DNS, profile и option values не нормализуются |
| UI | Отличается по утверждённому дизайну; доступность всех прежних действий, error/retry и semantic state сохраняется |
| Системный VPN | Connected/Disconnected и восстановление соответствуют реальным системным событиям; декоративный статус не заменяет состояние extension |
| Сеть | Для той же fixture ожидаемая `tunnel/direct/block` policy и IPv4/IPv6 TCP/UDP/DNS outcome одинаковы; после OFF нет egress старого туннеля |
| Производительность | M01: та же модель/iOS/settings/network и release mode; 2 warmups отдельно, 10 cold starts каждого build. Сравнить median first interactive frame по записанной до UI методике и плановому порогу +20%; не делать p95-вывод по малой выборке. Нет новых crashes, зависаний или непрекращающегося декоративного таймера в background |

В отчёт по приватным данным пишется `equal/not_equal` и безопасный test ID, не значения. Сравнение только скриншотов не закрывает эти контракты.

## 8. Задача D — сборка, обновление поверх baseline и телефон

**Files:** безопасные receipts в `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-ui/docs/verification/ui-migration/`. Существующий physical protocol: `/LOCAL_USER_HOME/Documents/KVN/hiddify-ios-baseline/docs/evidence/ios-baseline/device-protocol.md` — использовать содержание сценариев, новую запись привязывать к новой сборке.

До release этапа заполнить `physical-resources.md`: доступное устройство/контекст и iOS, оператор, baseline/candidate/rollback exact builds, согласованная последовательность consent deny/retry/grant и baseline→candidate→rollback, доступные Wi-Fi/cellular и управляемые endpoints TCP/UDP/DNS IPv4/IPv6 с ожидаемой policy и безопасными receipts. Если доступен лишь один личный iPhone, заранее согласовать явную последовательность на нём; сброс consent, удаление приложения и скрытая смена builds не предполагаются. Недоступный ресурс даёт BLOCKED соответствующему обязательному gate; изменение обязательности требует отдельного явного решения и обновления контракта, не фиктивного PASS.

**Частота gates:** каждое UI-изменение — полный regression, phase runner, guards, analyzer diff и текущие/прежние visual/a11y cases; включение общей темы дополнительно требует app-wide invariants сразу. Каждый подписанный candidate — all-green и exact artifact/signature/provenance checks. Каждый физический релизный прогон — F01–F10 на закреплённых builds и resources, включая upgrade/rollback; изменение source/build после прогона требует новых exact-build receipts. Сценарии всех трёх уровней написаны заранее на B; телефонный прогон после каждого изменения отступа не требуется. Signing/upload не закрывают физическую приёмку.

**Consumes:** GREEN source, согласованные visuals, сохранённые immutable baseline/rollback артефакты. **Produces:** exact candidate provenance, обновление с сохранением данных, physical receipts.

- [ ] До signing source review и полный тестовый GREEN.
- [ ] Сохранить marketing version `0.0.1`, следующий build — **2 или выше**, строго выше последнего принятого Apple. Перед сборкой заново прочитать фактическое состояние App Store Connect; не считать, что build2 свободен спустя время.
- [ ] App и extension имеют одинаковые version/build; source SHA, workflow SHA, Flutter revision, core archive/framework manifest и SHA256 IPA связаны в provenance.
- [ ] Применить существующие native проверки фактического IPA: strict signature, signer/profile membership, сроки/profile grants, App Group/NE/VPN, source entitlement preservation и target identity. Source plist не заменяет подписанные права.
- [ ] Публикация/подписывание/установка выполняются в рамках отдельно подтверждённого запроса на реализацию и выпуск, не автоматически по этому плану.
- [ ] Доставка в существующий `Test`: точный build `VALID`, beta state `READY_FOR_BETA_TESTING` или `IN_BETA_TESTING`, финальное чтение membership assigned=true. Не добавлять/приглашать тестеров.
- [ ] Установить **обновление поверх** baseline, проверить profile/settings/active server до первого нового импорта. Повторная подписка или исчезновение данных — FAIL.

Порядок D/E: сначала архив и сборка candidate/rollback, затем upgrade/rollback проверка в согласованном тестовом контексте, только после этого обновление личного телефона. E выполняется как prerequisite пользовательского обновления, несмотря на отдельную нумерацию раздела. Если второго контекста нет, physical rollback остаётся явно непроверенным; E не закрывается автоматически, на личном телефоне не выполняется скрытая смена builds. После rollback с большим build number повторная доставка candidate требует нового большего build number и новых artifact/provenance checks; результаты exact-build приёмки не переносятся автоматически.

### Весь физический сценарий записывается на этапе B

| ID | Сценарий на exact candidate | PASS означает |
|---|---|---|
| F01 | Baseline→candidate update | Данные/selection/preferences сохранены; первая обычная попытка connect работает |
| F02 | Импорт clipboard/manual/QR; invalid, cancelled, unavailable | Только валидный профиль сохраняется; отказ конечен, retry доступен, существующий профиль не повреждён |
| F03 | Consent deny→ordinary retry→grant | После deny нет активного VPN/зависания; после grant новая попытка работает. Уже выданное разрешение на личном телефоне не сбрасывать молча; использовать отдельно согласованный свежий тестовый контекст, иначе эта часть BLOCKED |
| F04 | 5 connect/disconnect циклов; последний с быстрым reconnect | Система/UI/traffic согласованы; нет stale events, старого tunnel egress после OFF, двойного start или hang |
| F05 | TCP/UDP/DNS IPv4/IPv6, ON и OFF | Доступные управляемые endpoints дают безопасные server receipts по заранее заявленной fixture policy |
| F06 | Wi-Fi→cellular→Wi-Fi без ручного выключения VPN | Связность и заявленная routing policy восстановлены, UI согласован с системным состоянием |
| F07 | Lock 2 минуты, unlock, background, relaunch | Нет нового отказа импорта/подключения, ложного Connected или потери профиля; реальные контрольные запросы проходят |
| F08 | Крупный текст/VoiceOver/motion/transparency/contrast | Можно импортировать, выбрать профиль/сервер, подключиться, отключиться и закрыть ошибку; overlays/keyboard не перекрывают действия |
| F09 | Candidate→rollback update | Данные сохранены; рабочий старый UI и connect восстановлены без удаления приложения |
| F10 | M01 на baseline/candidate в exact release builds | Сняты записанные до UI first-interactive-frame samples; плановый median budget соблюдён, нет новых crash/hang |

Для F05 заранее записать таблицу endpoint labels, transport/family, ожидаемую ON/OFF policy и безопасную server receipt. Измерения проводить и на baseline, и на candidate при одинаковой fixture. Если endpoint отсутствует, ставить BLOCKED этой строке, а не считать Safari достаточным доказательством DNS/UDP/IPv6.

Каждая запись содержит дату, test ID, source/build/core/IPA, среду, фактический outcome и `PASS/FAIL/BLOCKED/NOT RUN`. Устройство/сеть/fixture не подменять между paired measurements без новой baseline записи. Успешная загрузка в Apple или надпись Connected не закрывают физический gate.

## 9. Задача E — готовый откат до выпуска

- [ ] Сохранить точный baseline source и воспроизводимый toolchain, core archive/framework manifest, signing metadata и baseline/новые IPA/provenance в приватном долговременном архиве. Текущий Actions retention=7 дней; его недостаточно как единственного места хранения rollback.
- [ ] Подготовить сборку **прежнего UI из immutable baseline source** с теми же bundle IDs/App Group/storage и новым монотонным build number. Замена build/version metadata допустима; runtime/layout берутся из baseline.
- [ ] В изолированном upgrade/reopen harness проверить baseline→candidate→rollback persistence до пользовательского обновления. F09 физически проверяется на согласованном тестовом устройстве/контексте; на личном телефоне не выполнять скрытую смену builds.
- [ ] Условие остановки: новый импорт/refusal, потеря данных, неверный server/config, regression behavior/a11y, новая crash/hang, signing mismatch или mismatch измеренной policy. Откат и разбор первого отличия вместо дальнейших декоративных правок.
- [ ] Старый доступный TestFlight build может быть запасным вариантом, но доступность/совместимость не предполагать. Основной вариант — воспроизводимая rollback-сборка с большим build number. Удаление/переустановка не является стратегией сохранения данных.

## 10. Финальный gate «визуальное обновление принято»

- [ ] A: актуальный дизайн и полная матрица существующих функций/состояний зафиксированы.
- [ ] B: **все проверки написаны до UI**, чувствительность и корректный RED/GREEN доказаны.
- [ ] C: UI изменён по шагам, весь regression/visual/a11y suite GREEN, runtime/dependency/storage guard GREEN.
- [ ] D: exact signed candidate доставлен и установлен поверх baseline; данные сохранились; обязательные физические сценарии прошли.
- [ ] E: rollback подготовлен и его сохранность данных подтверждена.
- [ ] Пользователь увидел финальный визуал именно новой сборки и принял его.

Локальный PASS, release PASS и device PASS записываются отдельно. Любая обязательная FAIL/BLOCKED/NOT RUN оставляет соответствующий gate открытым; нельзя писать «ничего не сломалось» только по сборке или screenshot. Текущий результат — **план готов; реализация тестов и редизайна не начиналась**.

## Официальные технические опоры

- [Flutter: уровни тестирования](https://docs.flutter.dev/testing/overview): разделять unit/widget/integration доказательства.
- [Flutter: integration tests](https://docs.flutter.dev/testing/integration-tests): отдельный harness и SDK test dependencies.
- [Flutter: matchesGoldenFile](https://api.flutter.dev/flutter/flutter_test/matchesGoldenFile.html): фиксировать графические эталоны и среду; [autoUpdateGoldenFiles](https://api.flutter.dev/flutter/flutter_test/autoUpdateGoldenFiles.html) объясняет, почему автоматическое обновление превращает comparison в принятие текущего результата.
- [Flutter: accessibility](https://docs.flutter.dev/ui/accessibility): автоматические guidelines дополняются реальной проверкой VoiceOver.
- [Apple: NEVPNStatus.reasserting](https://developer.apple.com/documentation/networkextension/nevpnstatus/reasserting): reconnect является реальным системным состоянием, его нельзя выводить из визуальной анимации.
