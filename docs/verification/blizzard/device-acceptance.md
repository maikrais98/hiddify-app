# Blizzard — заранее подготовленная физическая приёмка

Статус: NOT RUN. Этот протокол не разрешает установку, сброс разрешений, удаление данных или публикацию. Проверки выполняются после готовности конкретного candidate и согласованного действия на устройстве.

## Контекст и доказательства

Baseline: WIR 0.0.1 (1), source0830294eff5b8cd86324545ed00689648c70bd23. Candidate SHA/build/artifact/core/SDK fingerprints заполняются перед испытанием. Каждая запись указывает конфигурацию skin, устройство/OS, сеть, время, результат и безопасный evidence; приватные URL, профили, credentials, IP и raw logs не сохраняются.

На той же паре baseline/candidate и одном устройстве используются одинаковые доступные контрольные endpoints и routing policy. Симулированные состояния из макетов не заменяют runtime-наблюдения. Не сбрасывать личное разрешение VPN/camera; deny/retry/grant проверять только в выделенном согласованном контексте.

## Сценарии и ожидаемые результаты

| ID | Действие | Проверяемый результат |
|---|---|---|
| F01 | Зафиксировать профиль count/IDs/active, выбранный сервер, preferences/theme/locale и drafts; обновить поверх данных | Те же значения, схема и IDs. Fresh install не считается upgrade |
| F02 | Пять connect/disconnect циклов, reconnect, разрешённый source profile/server switch | Один tap — прежняя команда и args/count; UI/model/system tunnel согласованы; реальный трафик работает |
| F03 | Wi-Fi→cellular→Wi-Fi, background, lock/unlock, relaunch | Поведение совпадает с baseline; нет подвисаний, повторных start, ложных Connected |
| F04 | Импорт clipboard/manual/QR/deep link: valid/invalid/cancel/retry | Прежние validation/результаты/данные; no-profile dialog→sheet→notice в исходном порядке |
| F05 | Profile select/update/edit/share/delete; late success после закрытия, overflow, sort/info и long press | Прежний профиль/route/result, сохранённый draft; source mounted/canPop и immediate-close sequence |
| F06 | Каждая настройка из screen-action-contract: switch/radio/slider/input/reset/cancel; WARP зависимости | Те же keys/types/defaults/units, disabled и platform gates; отмена как в baseline |
| F07 | Home/Settings, повторное нажатие, дочерние routes, sheet/dialog/back/edge-swipe, keyboard/focus/scroll | Прежняя branch/route семантика, сохранённые controllers/позиции, доступные действия |
| F08 | Dark, Light, Black, System light/dark; 599/600/840, rotation, narrow iPad | Blizzard только в согласованном iOS mobile Dark/System-dark; остальные legacy. Смена оформления не вызывает VPN/storage команд |
| F09 | Process restart native preferences; реальные file DB reopen; upgrade и rollback отдельно | Уровни mock/native_reopen/process_restart/actual_build_upgrade не смешиваются; storage сохраняется |
| F10 | TCP/UDP/DNS, IPv4/IPv6 при наличии policy/endpoints | Конкретные запросы проходят согласно тому же baseline. Отсутствующий endpoint — NOT RUN с причиной |
| F11 | VoiceOver labels/order/modal focus, Dynamic Type, длинные RU/EN, RTL, high contrast/reduced motion/transparency | Все прежние действия доступны; ≥44pt targets; статус читается без цвета; decor не перехватывает ввод |
| F12 | Native VPN/camera prompts deny/retry/grant, document/share picker/text selection | Системные поверхности и source permission/result semantics сохранены |
| F13 | Logs pause/filter/export/copy/clear, About update/changelog/licenses/URLs и Intro busy/start | Все source gates/actions/texts сохранены; package-owned alert не выдаётся за app-owned |
| F14 | Откат оформления отдельной новой rollback сборкой поверх данных | Проверенная доставка и сохранение данных; обещание downgrade старым TestFlight build недопустимо |

## Визуальная и performance-приёмка

89 mapped states и 17 transient groups из screen-action-contract сопоставляются с actual Flutter/iOS render. Макеты Inter являются дизайн-спецификацией; реальные SF Pro/Shabnam проверяются отдельно. Убедиться, что QR/logs/input/critical feedback имеют opaque/off decor. Навигационные материалы Flutter не называем native Liquid Glass.

До UI приняты budgets: cold-start median не более +20% от baseline (5 измерений на каждой версии в одинаковых условиях); любой crash/hang/недоступное действие — FAIL. Прокрутка и control interaction: фиксированный сценарий 30сек, сравнить raster/UI p95, dropped frames и peak memory; исходные измерения и причины разброса записать до вывода. Декор v1 статичен: таймеров/новых haptics нет; отдельно сравнить scene on/off в release/profile build. Непомерную стоимость decor сначала устранять оформлением, сохраняя бизнес-команду.

## Известные исходные особенности

ConnectionButton AsyncError+latency1..65000 падает при чтении secure label; ошибка+delay0 доступна для retry. Границы connected >=65000 и secure >65000 различаются. Generic input validator=false закрывает dialog без inline error. Source D11 About caller canIgnore:false. Эти факты фиксируются отдельно, не исправляются скрыто в reskin.

## Release gate

Все receipts относятся к exact source/artifact. Simulator/сборка/upload не доказывают VPN. Private TestFlight выполняется только после отдельного запроса на выпуск и этой приёмки; новые testers/app record/servers не входят в задачу.
