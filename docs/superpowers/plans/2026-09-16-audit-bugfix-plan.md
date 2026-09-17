# Woman in Red — Audit Bugfix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** устранить F01–F10 аудита и получить воспроизводимый кандидат для проверки VPN на физическом iPhone.

**Architecture:** Сначала восстановить воспроизводимость native dependencies и сборки. Затем закрепить native ownership control credentials, исправить privacy/UI regressions и проверить один и тот же исходный SHA, собранный framework и установленный кандидат. Разделять code/test completion, Simulator UI и фактический tunnel runtime.

**Tech Stack:** Flutter 3.38.5, Dart, Swift/Network Extension, Kotlin, Go/Libbox, GitHub Actions.

## Global Constraints

- Репозиторий: `/Users/stasyudkin/Documents/KVN/hiddify-app`; GitHub fork: `maikrais98/hiddify-app`.
- План опирается на аудит HEAD `884ce69fc8dcc1e0468ceb4bae931c9036f03cc9` от 2026-09-16. Это не повторный аудит нового кода.
- Live GitHub read при составлении плана: PR #1 открыт, branch `checkpoint/mvp-before-dark-theme`, remote SHA `6ce4a7e1ed4ed4f109963be77f955a5a452c46b7`. Локальный HEAD содержит ещё один коммит.
- Исходный отчёт: `/tmp/wir-audit-20260916/report.md`; временное хранение не считать долговременным архивом.
- В исходной рабочей папке уже изменены Xcode project и core submodule. Не делать reset/clean/stash и не включать эти изменения автоматически.
- Зафиксированный Flutter: `/Users/stasyudkin/fvm/versions/3.38.5/bin/flutter`. Native audit использовал Xcode 26.6; исторический pin 16.x требует решения в задаче 2.
- Не логировать подписки, JSON-конфигурации, credentials; тестовые canary только синтетические.
- Не отключать auth, TLS, pinning, deadlines или On Demand для получения зелёного теста.
- Здесь создан только план. Исполнение, push, merge, публикация и изменение Miro этим документом не выполнены.

## 0. Git и доказательства — до правок

Владелец: основной Sol High; механическая подготовка — Sol Medium.

- [ ] Повторно проверить HEAD, dirty diff и PR с явным `--repo maikrais98/hiddify-app`. При изменившемся HEAD сопоставить новые коммиты с F01–F10.
- [ ] Создать отдельный worktree от локального `884ce69f`, а не от отстающего origin; предполагаемое имя ветки `fix/audit-native-readiness`. Существующую ветку с этим именем не перезаписывать.
- [ ] Сохранить краткий обезличенный audit baseline и критерии приёмки в Git. Большие build logs, frameworks, DerivedData и device identifiers в Git не добавлять; хранить как ограниченные CI/local artifacts.
- [ ] Вести один исправляющий PR в пользовательском fork. Практичный вариант — stacked PR в `checkpoint/mvp-before-dark-theme`, чтобы не смешать исправления со всей историей PR #1. Перед публикацией проверить фактические base/head и включение локального `884ce69f`.
- [ ] Каждый независимый fix — отдельный тематический коммит вместе с regression test. Не смешивать CI, credentials и UI в одном коммите; не менять соседний код.

Проверка исходного состояния:

```bash
git status --short --untracked-files=no
git rev-parse HEAD
git log --oneline origin/checkpoint/mvp-before-dark-theme..HEAD
gh pr view 1 --repo maikrais98/hiddify-app --json url,headRefName,headRefOid,state
```

Приёмка: изменения пользователя сохранены, известны исходный SHA и remote PR; diff исправлений можно рассмотреть отдельно.

## 1. F02 — чистый bootstrap dependencies

Модель: Sol High. Предшествует окончательной приёмке F01.

Файлы: `scripts/apply_hiddify_core_patch.sh`, `test/ci/release_gate_test.sh`, `.github/workflows/build.yml`; nested `.gitmodules` обрабатывать воспроизводимо в patch/bootstrap, не только в локальном checkout.

- [ ] Воспроизвести проблему из пустого checkout без SSH agent/keys и заранее заполненных submodules.
- [ ] Для публичных nested dependencies использовать repository-scoped HTTPS transport. Не менять глобальный Git config; сохранить pinned revisions и остановку при неверном SHA.
- [ ] Проверить повторное применение bootstrap: уже применённый patch не должен дублироваться, другой исходный SHA должен отклоняться.
- [ ] Выполнить реальный bootstrap в CI/чистом окружении; проверка наличия строки `recursive` в shell script недостаточна.

Приёмка: clone/init/patch/dependency resolution проходят без пользовательских SSH credentials; Go тесты запускаются из полученных исходников.

## 2. F01 — один native source/artifact contract и успешная сборка

Модель: Sol High. Astra Low — один сфокусированный review решения о source/artifact provenance, если остаётся неоднозначность.

Файлы: `ios/HiddifyPacketTunnel/SingBox/ExtensionPlatformInterface.swift`, `Makefile`, `dependencies.properties`, `.github/workflows/build.yml`, `scripts/download_core_archive.sh`, `docs/adr/0007-local-control-authentication.md`.

- [ ] Выбрать точные core/sing-box revisions + patch и поддерживаемую версию Xcode; записать решение. Не лечить несовместимость случайным откатом SDK.
- [ ] Сверить реальный Libbox protocol и предоставить осмысленные реализации `closeNeighborMonitor`, `registerMyInterface`, `startNeighborMonitor`; адаптировать DNS iterator. Пустые заглушки без обоснования не принимаются.
- [ ] Связать native build и packaging с теми же patched sources, что проходят Go tests. Зафиксировать source SHA, patch digest, toolchain и artifact digest. Если нужны опубликованные immutable artifacts, сначала получить проверенные локальные artifacts; публикация отдельный шаг исполнения.
- [ ] Собрать Simulator и unsigned iOS Release с нуля. Убедиться, что подхвачен проверенный framework, а не старый из рабочей папки.
- [ ] На packaged core проверить: корректный credential допускает RPC; отсутствующий/неверный отклоняется; TLS/pinning проверяются. Package marker в binary не заменяет эти сценарии.

Приёмка: обе native сборки PASS; происхождение binary доказано; auth-проба использует именно собранный core. Возможные device-only проверки явно остаются в задаче 7.

## 3. F03 — credentials переживают процессы приложения и tunnel

Модель: Astra Medium для ограниченного архитектурного решения; Sol High для реализации; Astra Low для review diff и lifecycle matrix.

Файлы: `lib/hiddifycore/core_interface/core_interface_mobile.dart`, `ios/Runner/VPN/VPNManager.swift`, `ios/HiddifyPacketTunnel/SingBox/ExtensionProvider.swift`, Android `Settings.kt`, `MethodHandler.kt`, `bg/TileService.kt`, `bg/BoxService.kt`; ADR 0007. Точные Android пути взять из checkout перед правкой.

- [ ] Описать владельца credential, доступ из app/extension, поведение при locked device, generation/rotation/cleanup и восстановление при surviving tunnel. Выбрать native protected storage после проверки доступных entitlements; App Group сам по себе не доказывает общий Keychain access.
- [ ] Добавить воспроизведение iOS `options == nil`, Flutter process restart при живом tunnel и Android tile/service start без предварительного Flutter initialization.
- [ ] Перенести ownership в native lifecycle: Flutter получает согласованные connection materials, а не генерирует независимый secret при каждом запуске.
- [ ] Проверить гонку одновременных стартов/rotation и отказ при недоступном защищённом хранилище. Не использовать plaintext fallback и не продолжать запуск без auth.
- [ ] Запустить unit/integration cases; подписанный device replay завершить в задаче 7.

Приёмка: lifecycle contract реализован и покрыт тестами; system-driven launch не зависит от transient Flutter options; старый/неверный credential не принимается после предусмотренной rotation. До device replay статус Partial.

## 4. F09 — удалить конфигурации из error/log/telemetry

Модель: Sol Medium; поднять до High только при изменении общего logging contract. Может выполняться независимо от задач 1–3.

Файлы: `lib/features/settings/notifier/config_option/config_option_notifier.dart`, `lib/features/per_app_proxy/overview/per_app_proxy_notifier.dart`; проверить sinks `lib/core/logger/custom_logger.dart`, `lib/core/analytics/analytics_logger.dart`. Добавить `test/security/config_import_logging_test.dart`.

- [ ] Перенести синтетический canary из аудита в regression test, вызывающий реальные import handlers: clipboard/file и parse/update failures. Сначала подтвердить leak.
- [ ] Заменить raw exceptions/source на ограниченные failure codes в этих путях; сохранить понятное пользовательское сообщение об ошибке.
- [ ] Проверить одновременно LogRecord, file printer и Sentry breadcrumb conversion; marker отсутствует во всех sinks. Отправка реальных данных в Sentry не нужна.
- [ ] Перезапустить существующие privacy/security tests, чтобы не сломать safe diagnostics.

Приёмка: исходная регрессия воспроизводится до fix и отсутствует после; тест проверяет production path, а не копию выражения jsonDecode.

## 5. F04/F06/F07 — форма, крупный текст, semantics и motion

Модель: Sol Medium; Sol High только для сложного конфликта layout/route lifecycle. Один отдельный UI commit допустим для связанных F04/F06, F07 — отдельный.

Файлы: `lib/features/home/widget/nova_ritual_hero.dart`, `lib/features/profile/add/add_profile_modal.dart`, `lib/core/router/go_router/helper/custom_transition.dart`, локализации en/ru. Tests: расширить import/UI smoke coverage и добавить route-motion regression.

- [ ] Воспроизвести реальный modal route при 320×568, text scale 2× и при 568×320 с keyboard inset 180; hero — с production provider wiring. Сохранить baseline 1×.
- [ ] Сделать форму scrollable и keyboard-safe, hero — адаптивным. Проверять доступность и нажатие primary action, а не только отсутствие overflow.
- [ ] Добавить локализованное доступное имя кнопке возврата к вариантам импорта; проверить semantics.
- [ ] Учитывать Reduce Motion в общем route helper; тестировать включённый и выключенный режим, сохраняя переходы и навигацию.
- [ ] После задачи 2 снять fresh Simulator screenshots с нативной типографикой; позже проверить VoiceOver/Dynamic Type на iPhone.

Приёмка: целевые layouts и actions PASS; обычный размер не ухудшен; Reduce Motion соблюдается. Widget fixture не объявлять native accessibility sign-off.

## 6. F05/F10/F08 — оставшиеся независимые исправления

Модель: Sol Medium. Luna Xhigh допустима для сверки документации F08 после выбора canonical design, не для выбора UX за пользователя.

- [ ] F05: `test/features/profile/data/profile_parser_test.dart` и при необходимости clock seam в parser. Сделать deadline/shared-budget проверку управляемой clock/barrier. Отдельно проверить exhausted budget и передачу остатка второму запросу; не требовать второй запрос после истечения срока и не ограничиваться увеличением timeout. Приёмка: focused test устойчив в обычном parallel suite.
- [ ] F10: `lib/features/system_tray/notifier/system_tray_notifier.dart`. Connected сохраняется при delay 0/65000/timeout; Disconnect доступен. Отдельная regression для mapper/menu + desktop smoke. Это не блокер именно iPhone, но обязательная часть закрытия всех F01–F10.
- [ ] F08: `lib/features/proxy/overview/proxies_overview_page.dart`, `design/tokens/colors.css`, `lib/core/theme/nova_tokens.dart`. Составить точный список различий с Pencil; выбрать canonical Auto Mode presentation и tokens, затем синхронизировать соответствующие представления. Нового редизайна не проводить. До согласования варианта — явно Deferred, не Done.

## 7. Интеграция, GitHub CI и физический iPhone

Модель: Sol Medium для запуска/сбора evidence; Sol High для устранения новых содержательных failures. Astra Low — один заключительный review F01/F03/F09.

- [ ] После отдельных targeted checks собрать изменения в ветке исправлений; `git diff --check`, review diff, full Flutter suite и analyzer ratchet. Baseline 357 tests — историческая опора, число после новых регрессий должно увеличиться.
- [ ] Выполнить Go hcore/localauth и race tests, archive integrity/release gates, Simulator build и unsigned Release. Нагрузочную native сборку не запускать одновременно с расследованием timing failures.
- [ ] После публикации ветки проверить CI по точному PR head SHA: tests и iOS build не должны быть SKIPPED. Если merge/rebase меняет SHA, повторить необходимые проверки итоговой точки.
- [ ] Проверить реальные identity/provisioning/Network Extension и App Group у Runner и tunnel target. Отдельно учесть новое secure-storage решение F03; наличие Team ID в project не является проверкой signing.
- [ ] Установить подписанный кандидат и проверить connect/disconnect/reconnect, On Demand, app kill при surviving tunnel, restart, background/foreground, Wi-Fi/cellular, ошибки доступа. Подтвердить реальный traffic, DNS/IPv6 и ожидаемое поведение при сбоях.
- [ ] Зафиксировать evidence с app SHA, core digest, toolchain, типом устройства и результатом каждого сценария. Удалить конфиденциальные параметры из evidence.
- [ ] Обновить PR description и repository checklist фактическими PASS/FAIL/SKIP. Miro закрывать лишь после соответствующей приёмки, с ссылкой на commit/PR/evidence.

Общие локальные проверки, из корня worktree:

```bash
/Users/stasyudkin/fvm/versions/3.38.5/bin/flutter test --no-pub --reporter expanded
bash scripts/check_analyzer_ratchet.sh
bash test/ci/release_gate_test.sh
bash test/security/core_archive_integrity_test.sh
/Users/stasyudkin/fvm/versions/3.38.5/bin/flutter build ios --release --no-codesign --no-pub
git diff --check
```

Зелёный кодовый этап = необходимые tests/builds PASS и проверенный packaged auth. Готовность к iPhone = подписываемый кандидат. VPN verified = отдельные успешные device сценарии. TestFlight/Store publish и release-environment administration — отдельный release scope.

## Модели и расход

Рекомендуемый простой вариант: один основной Sol High для этапов 1–3 и интеграции. Более экономный режим: Sol Medium для задач 4–6 и обычных проверок; Astra Medium только на архитектуру F03, Astra Low на ограниченный security/native review. Luna Xhigh — механические проверки документации/путей, только если делегирование окупает передачу контекста.

Это инженерная рекомендация по риску задач, не измеренный benchmark или гарантированная экономия. High обычно увеличивает reasoning budget; сравнивать итоговый расход на принятую задачу с учётом повторных попыток, а не только tokens/minute или название модели.

- Передавать исполнителю F-ID, файлы, критерий PASS и релевантный фрагмент отчёта; не копировать полный 516-строчный аудит в каждого агента.
- Не поднимать совет из нескольких агентов для мелкой правки. Максимум два независимых потока: native/CI и privacy/UI, с непересекающимися файлами.
- Сначала targeted check, полный suite на интеграционной границе. Повторять широкий аудит только при новой информации.
- Вести краткую запись model/effort, input/output/reasoning tokens если доступны, результат и число переделок. Codex account limits не являются измерением расхода конкретной подзадачи.
- Не оценивать заранее экономию в процентах без таких замеров.

Общий принцип effort подтверждён [OpenAI API reference](https://developers.openai.com/api/reference/resources/chat): снижение reasoning effort может уменьшать reasoning tokens и задержку. Тарифы API не переносить автоматически на расход лимитов текущей подписки Codex.
