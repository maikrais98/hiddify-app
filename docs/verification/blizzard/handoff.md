# Blizzard Dark v1 — developer handoff

Visual-only перенос реализован. Candidate: `01149e654180af858de02ff542c836c2ed282d55`, оформление включено по умолчанию. Исходный checkout сохранён; работа находится в ветке `codex/blizzard-dark-v1`.

## Где продолжать

- [blizzard_theme.dart](../../../lib/core/theme/blizzard_theme.dart): локальная ThemeData, типографика, opaque материалы, aliases canvas/card/primary/search и compile-time gate.
- [blizzard_tokens.dart](../../../lib/core/theme/blizzard_tokens.dart): цвета, радиусы, размеры и high-contrast материалы.
- [blizzard_presentation.dart](../../../lib/core/widget/blizzard/blizzard_presentation.dart): стабильная локальная Theme boundary и eligibility. Глобальная [AppTheme](../../../lib/core/theme/app_theme.dart) сохраняет legacy оформление.
- [blizzard_backdrop.dart](../../../lib/core/widget/blizzard/blizzard_backdrop.dart), [blizzard_scene.dart](../../../lib/core/widget/blizzard/blizzard_scene.dart), [blizzard_surface.dart](../../../lib/core/widget/blizzard/blizzard_surface.dart): статичный decor hero/quiet/off и поверхности; без новых таймеров, haptics и обработки ввода. Scene/Surface сами не являются eligibility boundary.
- [my_adaptive_layout.dart](../../../lib/core/router/adaptive_layout/my_adaptive_layout.dart), [home_page.dart](../../../lib/features/home/widget/home_page.dart), [settings_page.dart](../../../lib/features/settings/overview/settings_page.dart): существующий shell и основные scoped entrypoints. Остальные маршруты/overlays перечислены в [implementation-coverage.json](implementation-coverage.json).

Blizzard применяется только при iOS + существующей mobile-ширине `<600` logical px + Dark либо System с фактической тёмной яркостью. Light, Black, System-light, ширина≥600 и остальные платформы сохраняют legacy. Узкое окно iPad следует существующей mobile-ветке. Границы Theme остаются на месте при переключениях, чтобы сохранять mounted state, drafts, focus и controllers.

## Что проверено

- Свежий candidate `01149e65`: полный host suite **353/353 PASS** в explicit OFF, explicit ON и default. См. [candidate-tests.json](candidate-tests.json).
- Предыдущий frozen native source `a87da1e9`: **178/178 PASS**, **166 raw PNG**, `changedDuringRun=false`; см. [d5-full-green/manifest.json](d5-full-green/manifest.json).
- Текущий candidate без visual define: **41/41 PASS**, **39 raw PNG**, frozen tree; см. [candidate-default/manifest.json](candidate-default/manifest.json). Shipping compile ведётся отдельно, см. [final-result.json](final-result.json).
- Реестр содержит **89 mapped frames / 40 families** и 17 дополнительных transient-групп. Это source/family coverage, **не 89 индивидуальных pixel-acceptance**; ограничения отражены в [implementation-coverage.md](implementation-coverage.md).

Сохранены исходные callbacks, provider/core calls, маршруты и результаты закрытия, storage keys/schema, VPN/native lifecycle и идентификаторы приложения. Проверки находятся в [test/ui_preservation](../../../test/ui_preservation), [test/visual](../../../test/visual) и [integration_test/blizzard_preservation_test.dart](../../../integration_test/blizzard_preservation_test.dart). Нейтральное VPN используется только в согласованном экранном brand slot; юридические тексты, About/Intro identity, logo и URLs оставлены исходными.

## Открытые границы

Analyzer: прежние 366 диагностик production сохранены буквально после нормализации номеров строк. Новых task diagnostics и errors нет; ещё одна import-order info относится к неизменённому baseline drift test. См. [candidate-analyzer.json](candidate-analyzer.json). Независимое широкое ревью [final-source-review.md](final-source-review.md) не нашло Critical/Important. Native/core/identity/release guards прошли; финальные receipts — [final-result.json](final-result.json).

Toast-оформление в обоих защищённых файлах [in_app_notification_controller.dart](../../../lib/core/notification/in_app_notification_controller.dart) и [alerts.dart](../../../lib/utils/alerts.dart) не перенесено: требуется отдельное разрешение. Не расширять визуальный diff на orchestration.

Известные legacy-особенности сознательно не исправлялись: pending manual-add Cancel сбрасывает notifier, но загрузка всё ещё может записать профиль; ConnectionButton AsyncError при latency1..65000 падает при чтении secure label; connected `>=65000` и secure `>65000` имеют разные границы; generic input с validator=false закрывается без inline error; исходный About caller использует canIgnore:false. Legacy JSON toolbar overflow характеризован; eligible toolbar исправлен только геометрией, legacy wide alignment сверено с исходником. Подробности: [coverage-readiness.json](coverage-readiness.json), [device-acceptance.md](device-acceptance.md), [d3-rereview.md](d3-rereview.md).

## Порядок следующей проверки

1. Уточнить состав native build inputs по [pods-reconciliation.md](pods-reconciliation.md) и получить exact shipping artifact с принятым lockfile; не объединять receipts разных SHA.
2. Сопоставить оставшиеся mapped/transient состояния с actual render и отдельно принять дизайн. Host GREEN не является физической iOS-приёмкой.
3. По [device-acceptance.md](device-acceptance.md) проверить exact artifact поверх существующих данных: connect/reconnect/profile switch, TCP/UDP/DNS и доступные IP endpoints, Wi-Fi↔cellular, background/lock/relaunch; native camera/VPN permissions, VoiceOver/focus/Dynamic Type и performance. Непроверенное отмечать NOT RUN.
4. Выпуск/private TestFlight — только по отдельной авторизации. Не добавлять testers, app record или серверные изменения в этот этап.

Для визуального отката собрать **новый** artifact с `--dart-define=BLIZZARD_VISUALS=false`, заново проверить и доставить разрешённым способом. Изменение define требует rebuild; оно не переключает уже установленный бинарник и не гарантирует downgrade на старый TestFlight build.

Local `main_prod` Simulator Debug compilation **PASS**, artifact `build/ios/iphonesimulator/Runner.app`, architecture `x86_64`, unsigned and uninstalled. CocoaPods regenerated only tracked `Podfile.lock`, then original bytes were restored; common runtime versions and dependency edges match. Actual build inputs,18changed spec checksums and test SDK pod are preserved in [shipping-compile.json](shipping-compile.json), [shipping-pods-delta.json](shipping-pods-delta.json), [shipping-inputs](shipping-inputs/). This is compile-only evidence; it does not certify the original-lock release artifact or execution of that x86_64 app on the selected arm64 Simulator.
