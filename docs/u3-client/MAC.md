# U3 на Mac и физическом iPhone

Статус: клиент и серверный обмен проверены автоматически на Windows. Подпись iOS, запуск на устройстве, Keychain и соединение iPhone ещё требуют проверки на вашем Mac. Пользователь согласовал это разделение проверок. Исходная база: `maikrais98/hiddify-app`, `main` `5b3d62165b782ba7ba2c44784681f52cc59b61a7`. Ветка Mac пока неизвестна.

## 1. Отдельная копия через GitHub

Ветка для этого этапа: `feat/luma-u3-account-debug` в `maikrais98/hiddify-app`. Сводка цели, выполненного и оставшихся проверок — [ACCOUNT-PROJECT-STATUS.md](../../ACCOUNT-PROJECT-STATUS.md). Основная ветка и релиз в этот перенос не входят.

В папке текущего проекта Luma на Mac сначала посмотрите состояние:

```sh
git branch --show-current
git log -1 --oneline
git status --short
```

Затем загрузите отдельную ветку и создайте соседнюю рабочую папку:

```sh
git fetch https://github.com/maikrais98/hiddify-app.git feat/luma-u3-account-debug
git worktree add -b u3-client-debug ../luma-u3-debug FETCH_HEAD
cd ../luma-u3-debug
```

Fetch не переключает исходную папку и не сливает изменения в её ветку. Текущая ревизия Mac может отличаться: новая копия открывает именно подготовленную account-ветку от 5b3d621; совместимость с рабочей веткой проверяется перед будущей интеграцией отдельно. Если имя ветки/каталог уже заняты, не сбрасывайте их; используйте другое свободное имя после проверки.

## 1а. Альтернатива без GitHub — Git bundle

Получите файл `luma-u3-client.bundle` из результата этого этапа обычным приватным способом переноса файлов между своими компьютерами. Он содержит только изменения клиента; SDK, ключи, сертификаты, базы и локальные токены в него не входят. После разрешения отдельной ветки основной способ переноса — GitHub; bundle остаётся дополнительным вариантом.

В существующем репозитории Luma на Mac проверьте bundle:

```sh
git status --short
git branch --show-current
git rev-parse --short HEAD
git bundle verify ~/Downloads/luma-u3-client.bundle
```

Если исходная ревизия отличается или отсутствует prerequisite `5b3d621`, сначала сверить ветку и изменения с подготовленной интеграцией. Не применять правки к текущей рабочей сборке вслепую. При совпадении базы создайте отдельную ветку и каталог, не переключая текущую копию:

```sh
git fetch ~/Downloads/luma-u3-client.bundle dev:refs/heads/u3-client-debug
git worktree add ../luma-u3-debug u3-client-debug
cd ../luma-u3-debug
```

Flutter этой базы: 3.38.5 / Dart 3.10.4. Используйте рабочую процедуру подготовки native frameworks именно этой ревизии, уже применяемую на Mac. Они не входят в Git bundle. Не запускайте release/upload/archive сценарии для этой проверки.

## 2. Закрытый маршрут

```text
iPhone — HTTPS в доверенной Wi-Fi сети → Mac:55443
Mac TLS relay → Mac 127.0.0.1:55442 → существующий SSH → Hermes 127.0.0.1:55441
```

Hermes API остаётся на loopback. Публичные DNS, порты, reverse proxy и правила VPN не меняются. Mac и iPhone должны быть в одной доверенной сети без client isolation. В командах замените `192.168.1.10` на IPv4 Wi-Fi интерфейса Mac (`ipconfig getifaddr en0`; имя интерфейса уточните на Mac).

Нужны существующий SSH-доступ к Гермесу, Python 3 и OpenSSL с `req -addext`. Новую учётную запись, SSH-ключ, облачный сервис или внешнюю авторизацию эти инструменты не создают. Если существующего доступа на Mac нет, этот шаг остаётся открытым. Конкретный SSH target и закрытый путь mailbox намеренно не публикуются: задайте локально `LUMA_LIVE_SSH_TARGET` (формат USER@HOST) и `LUMA_LIVE_MAILBOX_DIR` из существующей конфигурации тестового сервера. В shell-командах ниже должны быть заданы эти переменные; placeholders не являются реальными настройками.

В каталоге отдельной копии:

```sh
python3 tools/u3_lab.py prepare --bind 192.168.1.10
```

Это создаёт `.u3-lab/` с закрытым ключом, сертификатом на семь дней и `defines.json`. Каталог исключён из Git. В приложение встраивается только публичный сертификат. Не устанавливайте CA в системное хранилище iPhone и не включайте обход проверки сертификатов. При смене IP или истечении сертификата подготовьте новый локальный каталог и пересоберите debug-приложение; старую сессию заранее закройте.

В первом терминале оставьте SSH-туннель работающим:

```sh
ssh -N -T -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
  -L 127.0.0.1:55442:127.0.0.1:55441 "${LUMA_LIVE_SSH_TARGET:?set_existing_lab_ssh_target}"
```

Во втором терминале:

```sh
python3 tools/u3_lab.py serve --bind 192.168.1.10
```

Relay слушает только указанный частный IPv4, пересылает только операции U3 на фиксированный loopback SSH-порт, запрещает browser Origin/redirect и не ведёт access logs. Не используйте `0.0.0.0`, общий Wi-Fi, проброс портов роутера или публичный туннель. Оба процесса завершаются Ctrl-C; автозапуск не добавляется.

## 3. Подпись и сборка Debug

В этой ветке **только Debug** использует:

- Runner: `com.womaninred.app.u3debug`;
- extension: `com.womaninred.app.u3debug.HiddifyPacketTunnel`;
- группа: `group.com.womaninred.app.u3debug`;
- отдельный `Runner/Info-U3Debug.plist`, название `Luma U3 Lab` и разрешение локальной сети.

Debug использует Manual signing, чтобы сборка сама не регистрировала новые Apple identifiers. На Mac выберите подходящие уже имеющиеся development profiles для обоих Debug targets с этой группой. Если их нет, это отдельный незакрытый шаг подписи: не подставляйте рабочие bundle ID/app group и не включайте автоматическую регистрацию без отдельного решения пользователя. Release/Profile конфигурации и исходный Info.plist сохранены.

Подготовка и локальные проверки в отдельной копии:

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test test/features/account_lab test/features/identity
python3 -m unittest discover -s test/tools -v
```

Первую сборку запускайте через отдельную точку входа, которая открывает только аккаунт и не запускает обычную инициализацию core/telemetry/VPN:

```sh
flutter build ios --debug --no-codesign -t lib/main_account_lab.dart \
  --dart-define-from-file=.u3-lab/defines.json
```

После успешной сборки без подписи откройте **workspace из отдельной копии**:

```sh
open ios/Runner.xcworkspace
```

В Xcode выберите scheme Runner → Edit Scheme → Run → Build Configuration **Debug**, подключённый iPhone и существующие **ручные development profiles** для Runner и HiddifyPacketTunnel. Настройки подписи меняйте только для Debug, не для All/Release. Убедитесь, что Automatically manage signing выключен. В Build Settings проверьте Flutter Target `lib/main_account_lab.dart`, а в сгенерированном `ios/Flutter/Generated.xcconfig` — наличие FLUTTER_TARGET и DART_DEFINES от предыдущей команды; токенов там нет, но полный файл в чат не отправляйте. Затем используйте Product → Build и Product → Run (Cmd-R).

**Для подписанного запуска на этом этапе не используйте flutter run/flutter build ios без --no-codesign:** проверенный Flutter 3.38.5 автоматически добавляет в подписанные xcodebuild-вызовы `-allowProvisioningUpdates` и `-allowProvisioningDeviceRegistration`, даже если пользователь сам эти параметры не передал. Нужный первый запуск выполняется через Xcode с ручной подписью. Не подтверждайте регистрацию новых identifiers/devices или исправление signing автоматически; при отсутствии готовых подходящих profiles остановитесь на этом шаге.

Release/Archive/TestFlight не используются. Приложение должно установиться рядом с рабочим под именем Luma U3 Lab. При первом обращении разрешите ему доступ к локальной сети. Ручная подпись по конфигурациям описана в [справке Apple](https://help.apple.com/xcode/mac/current/en.lproj/dev1bf96f17e.html).

В обычном `lib/main.dart` за теми же debug defines подготовлен переход из профиля в «Тестовый аккаунт U3». Его проверяйте после отдельного account smoke; обычный старт включает существующие компоненты Luma. Кнопки VPN для проверки аккаунта не нужны.

## 4. Тестовый код

Рабочие фикстуры API: `alice@example.test`, `bob@example.test`. Настоящая почта не отправляется. Код лежит только в закрытом synthetic mailbox Гермеса; берите его через существующий SSH, не через HTTP и не через логи приложения.

Для Alice имя файла можно вычислить на Mac:

```sh
python3 -c 'import hashlib; print(hashlib.sha256(b"alice@example.test").hexdigest())'
```

Затем прочитайте соответствующий файл в своём терминале:

```sh
ssh -t "${LUMA_LIVE_SSH_TARGET:?set_existing_lab_ssh_target}" \
  "sudo cat '${LUMA_LIVE_MAILBOX_DIR:?set_existing_lab_mailbox_dir}/EMAIL_SHA256.json'"
```

Вместо `EMAIL_SHA256` подставьте вычисленный хеш; для Bob измените email в команде вычисления. JSON содержит `email` и `code`. После начала reauth прочитайте свежий код снова. Не отправляйте коды и токены в чат, скриншоты, issue или Git. При 429 дождитесь серверного ограничения, не запускайте повторные входы циклом.

## 5. Обязательная проверка на iPhone

- Убедиться, что рабочее приложение осталось установленным, его данные и VPN не изменились; Debug имеет отдельные bundle ID и группу в подписанных entitlements.
- Войти Alice; проверить маскированный email и текущую сессию. Email/аватар обычного локального профиля этим API не заменяются.
- Полностью закрыть и открыть Debug: сессия восстанавливается через новый refresh; access хранится только в памяти.
- Заблокировать iPhone: защищённый refresh недоступен до разблокировки. Если сохранить/прочитать Keychain не удалось, кабинет не открывается.
- Отключить relay/Wi-Fi во время восстановления: интерфейс показывает ошибку; приложение не повторяет использованный refresh и при неопределённом результате просит новый вход.
- Открыть вторую synthetic сессию, закрыть её через свежий код. Закрыть все сессии: текущий кабинет закрывается, после перезапуска вход не восстанавливается.
- Выполнить logout; повторно открыть Debug. При потере связи выход локальный, UI отдельно сообщает, если серверный отзыв не подтверждён.
- Проверить отказ при чужом сертификате/неверном IP/истёкшем сертификате. Не разрешать подключение обходом TLS.

Зафиксировать результат без секретов: ревизия Mac, версия iOS/Xcode, успешность сборки, отдельные identifiers, вход/перезапуск/Keychain/logout/revoke/TLS. До этого этап U3 на физическом iPhone не считается проверенным.

Для опционального повторного server smoke через существующий SSH используется `LUMA_LIVE_HERMES=1 flutter test test/features/account_lab/live_hermes_test.dart` после локального export двух LUMA_LIVE переменных выше: он работает только с Alice в тестовой БД и отзывает её synthetic сессии. Настройки проверяются до запуска SSH и не имеют встроенных адресов. Не запускать одновременно с ручной проверкой Alice. По умолчанию этот тест пропущен; обычные тесты локальны.

## Реализация и ограничения

Переиспользованы Dio, Riverpod, uuid и существующий platform channel. `crypto` закреплён напрямую на уже имеющейся версии 3.0.6 для PKCE S256. Общий Dio с retry/proxy и private Keychain-компонент локального VPN control не подходят для одноразовой account rotation, поэтому аккаунт имеет отдельный транспорт и отдельные записи.

Refresh и UUID хранятся в Keychain `WhenUnlockedThisDeviceOnly`, без синхронизации и App Group. Перед чтением refresh в UserDefaults синхронно сохраняется **только несекретный** запрет повторного чтения; успешная запись новой пары снимает его. Неопределённый результат rotation намеренно требует повторного входа. Keychain на настоящем устройстве ещё не проверен. [Apple accessibility](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly), [формат сертификата Dart на iOS](https://api.dart.dev/dart-io/SecurityContext/setTrustedCertificates.html).

Сетевой клиент доверяет одному локальному сертификату и проверяет IP SAN/срок; нет общих HTTP interceptors, proxy fallback, обхода TLS или повторов POST. Access, OTP, verifier и proof живут в памяти. Telegram, подписки, синхронизация VPN-конфигураций, устройства и семья относятся к следующим этапам.
