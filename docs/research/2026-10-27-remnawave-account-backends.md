# Основа личного кабинета luma: проверка четырёх решений

Дата: 27 октября 2026. Цель: вход через email и Telegram в нативной luma и веб-кабинете, получение существующей подписки Remnawave. Проверка документации и выбранных участков исходников; установка, запуск и проверка на живой панели не выполнялись. Это не полный аудит безопасности.

## Вывод

Первый кандидат для прототипа — Minishop Core. Есть самостоятельное MIT-ядро, пользовательский API, email-код и Telegram OAuth/Mini App, документированная совместимость с Remnawave 3.4.3. Для нативной luma нужен отдельный безопасный обмен результата браузерного входа на пользовательскую сессию. Оценка объёма этой доработки требует прототипа.

Bedolaga ближе к желаемому входу с подтверждением в чате бота технически, но содержит Commons Clause. Нельзя считать его обычным MIT-проектом для коммерческого использования без уточнения условий у правообладателя.

## 1. Jolymmiels/remnawave-telegram-shop (RWP)

Публичный код: `958a0bb6e7abe2fb324008dc44d423d4a9c8681b`, публичный релиз 5.2.0. Go-бот и PostgreSQL 17. Есть продажи, выдача ссылок, уведомления, платёжные webhooks и healthcheck. В изученном HTTP router отсутствуют пользовательские login/session API.

Синхронизация импортирует записи с Telegram ID, пропускает записи без него. При нескольких подписках с одним Telegram ID выбирает одну, предпочитая username с соответствующим суффиксом. Sync также удаляет локальных клиентов, которых нет в наборе Telegram ID панели: это операция изменения данных, не безопасный предварительный просмотр.

Публичная лицензия объявлена AGPL-3.0; её условия нужно учитывать при модификации и сетевом использовании. Приватная версия — отдельный продукт: документация заявляет кабинет, Mini App API, email/внешние провайдеры, Telegram OIDC и OAuth-диплинк для нативных приложений. Код этой версии не проверен. Поставка — Docker-образ, обязательный платный ключ с привязкой к серверу; PostgreSQL 18.

Источники:
- https://github.com/Jolymmiels/remnawave-telegram-shop/blob/958a0bb6e7abe2fb324008dc44d423d4a9c8681b/cmd/app/main.go
- https://github.com/Jolymmiels/remnawave-telegram-shop/blob/958a0bb6e7abe2fb324008dc44d423d4a9c8681b/internal/sync/sync.go
- https://github.com/Jolymmiels/remnawave-telegram-shop/blob/main/LICENCE.txt
- https://docs.rwp.rw/ru/private/overview
- https://docs.rwp.rw/ru/private/installation

## 2. Fr1ngg/remnawave-bedolaga-telegram-bot

Старая ссылка перенаправляет в BEDOLAGA-DEV. Изученный код: `46e644c52b562bc55c06ab15ebdf2b3031b21a41`.

Есть Cabinet API с пользовательскими JWT: профиль, подписка, трафик, устройства и другие функции. Реальный Telegram approval flow: запрос одноразового токена, открытие бота, явное подтверждение, опрос результата и выдача JWT. Подтверждение работает для уже зарегистрированного активного пользователя бота. Есть также web widget, Mini App и OIDC.

Есть email-вход и проверка email. Sync сопоставляет записи по panel ID, Telegram ID и подтверждённому email; записи без Telegram ID и email пропускаются. Стек: FastAPI/Python, PostgreSQL 18, Redis, Docker Compose.

Важное ограничение: фактический LICENSE — MIT плюс Commons Clause с ограничением Sell, включающим некоторые платные сервисы, существенно основанные на функциональности ПО. Применимость к платному VPN-сервису нужно выяснить до выбора. Это не заключение, что любая коммерческая эксплуатация автоматически запрещена.

Дополнительные пункты для проверки перед внедрением: deep-link bearer challenge без привязки через PKCE, длительное допустимое окно Mini App initData, отдельный JWT secret вместо fallback на bot token, отсутствие стабильного версионированного mobile API.

Источники:
- https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot/blob/46e644c52b562bc55c06ab15ebdf2b3031b21a41/LICENSE
- https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot/blob/46e644c52b562bc55c06ab15ebdf2b3031b21a41/app/cabinet/routes/auth.py#L2531
- https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot/blob/46e644c52b562bc55c06ab15ebdf2b3031b21a41/app/services/remnawave_service.py

## 3. snoups/remnashop

Изученный релиз main/v0.8.2: `06350c6cb3e1f13b4da316852f102bee6bf26949`. Backend MIT. Кабинет — отдельный репозиторий remnashop/cabinet; лицензию backend нельзя автоматически переносить на его интерфейс.

В релизе есть пользовательский REST API `/api/v1/public`: профиль, подписка, устройства, платежные операции. Есть Telegram widget/Mini App, email и привязка Telegram. Сессии cookie-based; готовой передачи сессии из внешнего браузера в native iOS не найдено. Готового bot approval flow не найдено.

Sync поддерживает Remnawave UUID/Telegram ID. При отсутствии Telegram ID импортированная запись может остаться отдельно от нового Telegram-аккаунта; нужна контролируемая привязка. В текущих константах версии указаны 2.7.0–2.8.0: совместимость с 3.4.3 не подтверждена. Это не доказательство, что все операции сломаны.

В текущем релизе операции покупки/trial требуют подтверждённый email и для Telegram-входа. Исправление PR143 при проверке оставалось открытым и неслитым. Backend/worker/scheduler, PostgreSQL 17 и Valkey; frontend разворачивается отдельно. Документированный быстрый запуск не включает полностью настроенный веб-кабинет.

Источники:
- https://github.com/snoups/remnashop/blob/06350c6cb3e1f13b4da316852f102bee6bf26949/src/web/endpoints/public/auth.py
- https://github.com/snoups/remnashop/blob/06350c6cb3e1f13b4da316852f102bee6bf26949/src/web/endpoints/public/_common.py
- https://github.com/snoups/remnashop/blob/06350c6cb3e1f13b4da316852f102bee6bf26949/src/core/constants.py
- https://github.com/snoups/remnashop/pull/143
- https://github.com/snoups/remnashop/blob/06350c6cb3e1f13b4da316852f102bee6bf26949/LICENSE

## 4. Minishop

Проверены официальные docs и выбранные участки GitHub-зеркала 3252a8/remnawave-minishop. Наблюдаемый main: `c10936489f83c844c8aea15e06629e1b4e49a77c`; сайт документации может обновляться отдельно от зеркала.

Core — самостоятельный MIT-продукт с ботом, кабинетом, подписками, оплатой и синхронизацией. PRO — отдельное proprietary-расширение аналитики и автоматизаций, не обязательное для нашего кабинета.

Есть email-код/magic link, пароль после подтверждения email, Telegram Mini App и браузерный OAuth/OIDC. Пользовательский JSON API отделён от admin API; поддерживает UserBearer. Браузерный Telegram OAuth заканчивается веб-сессией. Готовый native code-to-session handoff и подтверждение входа кнопкой в чате бота не найдены; потребуется расширение авторизации.

Sync импортирует пользователей с Telegram ID или email и разрешает идентичности по нескольким признакам; неоднозначные случаи требуют разбора. Email из панели сам по себе не подтверждает владение. Есть отдельные миграторы трёх других ботов. Документация включает Remnawave 3.4.3 в проверенную матрицу; на нашей панели это пока не запускалось.

Стек: backend/worker, frontend/nginx, PostgreSQL, Redis, migrate-service; HTTPS и ключи Remnawave только на сервере.

Источники:
- https://github.com/3252a8/remnawave-minishop/blob/main/LICENSE
- https://minishop.minidoc.cc/features/login-methods/
- https://minishop.minidoc.cc/architecture/http-api/
- https://minishop.minidoc.cc/architecture/remnawave-api-compatibility/
- https://minishop.minidoc.cc/features/minishop-pro/
- https://minishop.minidoc.cc/migrations/
- https://github.com/3252a8/remnawave-minishop/blob/main/backend/bot/handlers/admin/sync_admin_identity.py

## Предлагаемая схема luma

Два способа входа в один аккаунт: email с одноразовым кодом и Telegram. Оба доступны в приложении и веб-кабинете. Веб — поверхность, а не отдельный способ подтверждения личности.

Общий backend хранит пользователя и связанные подтверждённые identity; сервер обращается к Remnawave, клиент получает только свои данные. Добавление второго метода выполняется из действующей сессии с подтверждением нового метода. Уже существующие отдельные аккаунты нельзя объединять только по совпадению строки email/username.

Прототип проверки до выбора: вход email, вход Telegram на реальном iPhone с возвратом в luma, корректное отображение одной существующей подписки обоими методами, отсутствие дублей и изоляция данных двух тестовых пользователей. Использовать тестовые данные и изолированную среду; не запускать массовый sync на рабочей панели до предварительного отчёта о привязках.
