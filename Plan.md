# Клиент U3 — закрытая debug-интеграция Luma

27.10.2026. Изолированная локальная копия maikrais98/hiddify-app от main 5b3d62165b782ba7ba2c44784681f52cc59b61a7, ветка dev без remote. Точная ветка сборки на Mac ещё уточняется. Этот файл — план текущей реализации; продуктовые решения остаются в docs/plans/2026-10-27-luma-personal-account-auth-and-devices.md и исходном плане направления.

Учёт этапа: Plan.md, todo.md, docs/u3-client/history.md. Корневой HISTORY.md — существующий release changelog; из-за нечувствительности Windows к регистру отдельный history.md в корне пересёкся бы с ним, поэтому журнал этапа расположен в docs/u3-client.

Цель: debug-клиент email/session API U3 на Hermes, с Keychain на iPhone, клиентскими тестами и воспроизводимым запуском на пользовательском Mac. Только example.test; публичный доступ, релиз, production и рабочий VPN исключены.

1. Проверить клиентские seams; переиспользовать Dio, Riverpod и существующий native channel. Отдельный HTTP client необходим: текущий общий client автоматически повторяет запросы и допускает VPN proxy fallback, что несовместимо с одноразовым refresh.
2. Реализовать строгие U2 DTO, client-bound email challenge, session repository с single-flight refresh без retry, восстановлением через защищённый refresh, отзывом и защитой от поздних ответов.
3. Подключить отдельный debug-only экран аккаунта к существующему профилю. Для первого device smoke использовать main_account_lab.dart, без обычного запуска core/telemetry/VPN. Local profile/manual import остаются отдельными; VPN grants и аватар не синхронизируются этим API.
4. Добавить debug-only iOS Keychain bridge и отдельные bundle/app-group настройки для тестовой сборки. Только Debug получает .u3debug и Manual signing; автоматическая регистрация Apple identifiers исключена. Release/profile build не включает доступ к тестовому API. Подходящие development profiles и entitlement verification остаются Mac gate.
5. Подготовить Mac SSH + TLS relay для физического iPhone в той же Wi-Fi сети, с явным доверием единственному тестовому сертификату и без публичного endpoint Гермеса.
6. Проверить клиент автоматически, провести synthetic HTTP integration, подготовить переносимый Git bundle и Mac checklist. После отдельного разрешения пользователя опубликовать очищенный текущий snapshot в feat/luma-u3-account-debug существующего GitHub-репозитория; отдельный ACCOUNT-PROJECT-STATUS.md объясняет цель и выполненное. Прежние локальные коммиты с конкретными infrastructure settings не публикуются. Native build, signing, Keychain на устройстве и соединение iPhone проверяет пользователь на Mac — согласованная альтернатива отсутствующему здесь Xcode.

Критерии: token/OTP/verifier не попадают в preferences/logs/URL; release feature off; параллельный refresh один; потерянный результат refresh не повторяется; logout и смена аккаунта исключают поздние ответы; storage failure закрывает доступ; endpoint private HTTPS и сертификат проверены; клиент не делает panel/VPN writes.
