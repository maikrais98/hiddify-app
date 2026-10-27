# История клиентского этапа U3

## 27.10.2026 — подготовка

Создана отдельная локальная копия исходников Luma на dev от main 5b3d621. Исходная release-копия не использовалась. Автоматическая promisor remote-настройка fetch удалена после загрузки; публикаций нет. В исходниках не найден secure account token store; iOS уже имеет Flutter platform channel, который можно расширить отдельными debug-only методами Keychain.

Пользователь подтвердил физический iPhone, общую доверенную Wi-Fi сеть с Mac и согласовал: автоматические клиентские проверки здесь, сборка и native Keychain/connection проверки на его Mac. Точная ветка Mac пока неизвестна. На C: меньше 1 GiB, поэтому временные SDK/cache размещаются в F:/CodexU3Tooling. Рабочий VPN и серверные сервисы не изменялись.

## 27.10.2026 — клиент U3 и проверка с Hermes

Реализованы [клиентский протокол](../../lib/features/account_lab/account_protocol.dart), отдельный Dio transport и platform token store, [репозиторий сессий](../../lib/features/account_lab/account_repository.dart) и [debug UI](../../lib/features/account_lab/account_lab_page.dart): email PKCE, me, sessions/pagination, refresh, logout, cancel, email reauth и revoke/revoke-all. Токены не передаются общему retry/proxy client; refresh одноразовый и перед HTTP блокируется в persistent store. Поздние ответы ограждены поколением состояния, storage операции упорядочены. Ошибка удаления Keychain больше не отменяет серверный logout — добавлен отдельный регрессионный тест. Неоднозначные IPv4 с ведущими нулями запрещены.

iOS platform channel расширен в #if DEBUG. Refresh/UUID записываются отдельно в Keychain WhenUnlockedThisDeviceOnly без sharing/synchronization. UserDefaults хранит только несекретный rotation tombstone. Debug Runner и extension имеют отдельный BASE_BUNDLE_IDENTIFIER com.womaninred.app.u3debug и Manual signing; Info-U3Debug.plist содержит разрешение LAN и не перехватывает рабочие URL schemes. Release/Profile configuration, оригинальные Info.plist/entitlements/Base.xcconfig и HISTORY.md проверены на неизменность.

Подготовлены [Mac инструкция](MAC.md), private TLS relay tools/u3_lab.py и отдельный main_account_lab.dart без обычной Dart инициализации core/telemetry/VPN. Сертификат встраивается единственным trust anchor; IP SAN проверяется, DER используется на iOS, PEM — на desktop. Нет публичного сервиса, изменений firewall/VPN, новых remotes или внешних авторизаций.

Проверки:

- TDD: зафиксированы ожидаемые падения до реализации PKCE/URI/DTO, репозитория, транспорта/native protocol, UI, relay validators и debug entrypoint. Для обнаруженных отказа удаления storage и неоднозначного IPv4 тесты сначала упали, затем прошли.
- Flutter 3.38.5 / Dart 3.10.4: **47 тестов passed**, включая 23 существующих проверки identity. Live Hermes test в обычном наборе намеренно skipped.
- Python: **7 тестов passed**, включая настоящий TLS relay, фильтрацию, неизвестный CA/неверный IP и неизменность Release configuration. Отдельный Dart transport также проверяет настоящий TLS.
- Targeted Dart analyzer: **No issues found**; dart format без изменений, git diff --check без ошибок. build_runner завершён успешно; прежние предупреждения circle_flags/analyzer/drift не потребовали изменения зависимостей. crypto 3.0.6 переведён из transitive в direct, версия сохранена.
- Opt-in live Hermes: synthetic Alice login → /me/sessions → dispose/recreate repository → refresh restore → email reauth → revoke-all → старый refresh получает **401**. Созданная проверкой сессия отозвана; токены/OTP не печатались. Первоначальная попытка с несуществующей synthetic фикстурой получила account_blocked; использованы две штатные fixture-учётки, серверные правила не ослаблялись.

Ограничения: на этой Windows-машине нет Xcode/iPhone; native Swift build, фактический Keychain, отдельная подпись и LAN-доступ iPhone не проверены. Согласованный следующий шаг — Mac checklist. Windows pub get дошёл до ограничения native plugin symlinks при выключенном Developer Mode; глобальные настройки не менялись, тесты выполнены с --no-pub после успешного разрешения зависимостей. SDK/cache/build остаются на F: вне пакета поставки.

## 27.10.2026 — перенос на Mac

Реализация сохранена локальным коммитом `26f09dd feat: add isolated U3 account debug client` на dev. Создан Git bundle в соседнем `../luma-u3-client-delivery/`; `git bundle verify` подтвердил корректность и единственный prerequisite `5b3d62165b782ba7ba2c44784681f52cc59b61a7`. В пакете — bundle, MAC.md и контрольные суммы; SDK, секреты, private сертификаты и native frameworks не включены. После этого документационного коммита bundle обновляется до dev и повторно проверяется. Push, публикаций и переноса в release-ветку не было.

## 27.10.2026 — уточнение безопасного запуска на Mac

При подготовке пошаговой инструкции проверен исходник установленного Flutter 3.38.5: packages/flutter_tools/lib/src/ios/mac.dart добавляет allowProvisioningUpdates и allowProvisioningDeviceRegistration при codesign=true. Прежняя рекомендация подписанного flutter run была неточной. В MAC.md заменена на Flutter build --no-codesign → Xcode workspace отдельной копии → ручные Debug profiles → Build/Run; автоматические регистрации исключены. Реализация клиента не менялась. Native проверка по-прежнему ожидает Mac пользователя.

## 27.10.2026 — отдельная GitHub-ветка и сводный документ

Пользователь явно разрешил загрузить работу в дополнительную ветку существующего репозитория и отдельно попросил документ о цели и выполненном. Подготовлен ACCOUNT-PROJECT-STATUS.md: цель продукта, результат U0–U3, границы Minishop/backend, проверки и следующие U4–U10. MAC.md дополнен получением feat/luma-u3-account-debug в соседнюю worktree без изменения текущей ветки Mac.

Репозиторий проверен как публичный, поэтому конкретные SSH settings/mailbox paths вынесены из текущих файлов в локальные параметры. Параметры live smoke обязательны и проверяются до SSH: две новые проверки сначала упали, затем прошли. Перед публикацией: 49 локальных Flutter tests passed, live test default skipped, 7 Python tests passed, targeted Dart analyzer без замечаний. Новый live прогон ради публикации не выполнялся; предыдущий подтверждённый synthetic smoke остаётся историческим результатом.

Для публикации выбран новый чистый commit от исходного 5b3d621 с текущим проверенным tree: старые локальные коммиты с infrastructure defaults в GitHub не передаются. Main/stable/dev сервера, теги, PR, release workflows и production не входят в разрешённую запись. Ветка публикуется через существующее подключение GitHub, новые remotes/авторизации не создаются; успешность записи подтверждается отдельной проверкой branch head и tree.

Публикация подтверждена: [feat/luma-u3-account-debug](https://github.com/maikrais98/hiddify-app/tree/feat/luma-u3-account-debug), первоначальный source commit [b6e6545](https://github.com/maikrais98/hiddify-app/commit/b6e6545fc7f517e30d0ab3a789d7cf22f1557515). Повторное получение ветки через Git подтвердило tree 7c6b562974c4c536752f3752cf0612062e539ff9, полностью совпадающий с локально проверенным. Его единственный parent — исходный 5b3d621. Main осталась на 5b3d621; старые локальные коммиты не входят в ancestry публикации. Сводный документ находится в корне ветки: ACCOUNT-PROJECT-STATUS.md. Эта запись публикуется отдельным документационным продолжением поверх проверенного source commit.
