import 'dart:ui';

enum NovaPenEvidenceKind {
  /// The production page itself is mounted by the referenced widget test.
  productionPage,

  /// A production component used by the page is mounted for this exact state.
  productionComponent,

  /// The state transition is exercised through the production page/notifier.
  productionBehavior,

  /// The production widget is constructed by the smoke harness, but still
  /// needs a provider-complete render test before it can be called a golden.
  constructorSmoke,
}

class NovaPenExecutableEvidence {
  const NovaPenExecutableEvidence({
    required this.kind,
    required this.testPath,
    required this.productionSymbol,
    required this.scenario,
  });

  final NovaPenEvidenceKind kind;
  final String testPath;
  final String productionSymbol;
  final String scenario;
}

class NovaPenFrameFixture {
  const NovaPenFrameFixture(
    this.id,
    this.russianName,
    this.productionTarget, {
    required this.evidence,
    this.platform = 'all',
  });

  final String id;
  final String russianName;
  final String productionTarget;
  final NovaPenExecutableEvidence evidence;
  final String platform;
  Size get viewport => const Size(393, 852);
}

const _homeEvidencePath = 'test/features/home/widget/connection_button_production_test.dart';
const _serversEvidencePath = 'test/features/proxy/overview/proxies_overview_page_test.dart';
const _importEvidencePath = 'test/features/profile/add/import_flow_test.dart';
const _canonicalHarnessPath = 'test/fixtures/nova_pen_production_widget_smoke_test.dart';

NovaPenExecutableEvidence _page(String path, String symbol, String scenario) => NovaPenExecutableEvidence(
  kind: NovaPenEvidenceKind.productionPage,
  testPath: path,
  productionSymbol: symbol,
  scenario: scenario,
);

NovaPenExecutableEvidence _component(String path, String symbol, String scenario) => NovaPenExecutableEvidence(
  kind: NovaPenEvidenceKind.productionComponent,
  testPath: path,
  productionSymbol: symbol,
  scenario: scenario,
);

NovaPenExecutableEvidence _behavior(String path, String symbol, String scenario) => NovaPenExecutableEvidence(
  kind: NovaPenEvidenceKind.productionBehavior,
  testPath: path,
  productionSymbol: symbol,
  scenario: scenario,
);

NovaPenExecutableEvidence _constructor(String symbol, String scenario) => NovaPenExecutableEvidence(
  kind: NovaPenEvidenceKind.constructorSmoke,
  testPath: _canonicalHarnessPath,
  productionSymbol: symbol,
  scenario: scenario,
);

final novaPenFrameFixtures = <NovaPenFrameFixture>[
  NovaPenFrameFixture(
    '01',
    'Intro',
    'IntroPage:firstRun',
    evidence: _page(_canonicalHarnessPath, 'IntroPage', 'first-run Russian onboarding'),
  ),
  NovaPenFrameFixture(
    '02',
    'Главная · Отключено · профиль настроен',
    'HomePage:disconnected',
    evidence: _page(_homeEvidencePath, 'HomePage', 'disconnected with an active profile'),
  ),
  NovaPenFrameFixture(
    '02a',
    'Главная · Подключение',
    'HomePage:connecting',
    evidence: _component(_canonicalHarnessPath, 'NovaConnectionControl', 'connecting ritual'),
  ),
  NovaPenFrameFixture(
    '02b',
    'Главная · Подключено',
    'HomePage:connected',
    evidence: _page(_homeEvidencePath, 'HomePage', 'connected with an active profile'),
  ),
  NovaPenFrameFixture(
    '02c',
    'Главная · Ошибка',
    'HomePage:connectionError',
    evidence: _component(_canonicalHarnessPath, 'NovaRitualHero', 'connection error ritual'),
  ),
  NovaPenFrameFixture(
    '02d',
    'Главная · Нет доступа',
    'HomePage:noProfile',
    evidence: _page(_homeEvidencePath, 'HomePage', 'missing access with one import action'),
  ),
  NovaPenFrameFixture(
    '02e',
    'Главная · Ошибка провайдера',
    'HomePage:providerError',
    evidence: _page(_homeEvidencePath, 'HomePage', 'profile provider failure and recovery'),
  ),
  NovaPenFrameFixture(
    '02f',
    'Главная · Проверка защиты',
    'HomePage:checkingProtection',
    evidence: _component(_canonicalHarnessPath, 'NovaProtectionStatus', 'connected while reachability is checking'),
  ),
  NovaPenFrameFixture(
    '03',
    'Личные данные',
    'IdentityProfilePage',
    evidence: _page(
      'test/features/identity/identity_profile_page_test.dart',
      'IdentityProfilePage',
      'editable identity form',
    ),
  ),
  NovaPenFrameFixture(
    '04',
    'Серверы',
    'ProxiesOverviewPage:ready',
    evidence: _page(_serversEvidencePath, 'ProxiesOverviewPage', 'ready server group'),
  ),
  NovaPenFrameFixture(
    '04a',
    'Серверы · Сервис остановлен',
    'ProxiesOverviewPage:serviceStopped',
    evidence: _page(_serversEvidencePath, 'ProxiesOverviewPage', 'service stopped recovery'),
  ),
  NovaPenFrameFixture(
    '04b',
    'Серверы · Пустая группа',
    'ProxiesOverviewPage:emptyGroup',
    evidence: _page(_serversEvidencePath, 'ProxiesOverviewPage', 'empty server group recovery'),
  ),
  NovaPenFrameFixture(
    '05',
    'Детали VPN-доступа',
    'ProfileDetailsPage',
    evidence: _page(
      'test/features/profile/details/profile_details_save_test.dart',
      'ProfileDetailsPage',
      'profile details edit and save',
    ),
  ),
  NovaPenFrameFixture(
    '06',
    'Список доступов',
    'ProfilesPage',
    evidence: _page(_canonicalHarnessPath, 'ProfilesPage', 'loading profile list'),
  ),
  NovaPenFrameFixture(
    '07',
    'Настройки',
    'SettingsPage',
    evidence: _page(_canonicalHarnessPath, 'SettingsPage', 'grouped settings overview'),
  ),
  NovaPenFrameFixture(
    '08',
    'Общие настройки',
    'GeneralPage',
    evidence: _page(_canonicalHarnessPath, 'GeneralPage', 'general preferences'),
  ),
  NovaPenFrameFixture(
    '09',
    'Маршрутизация',
    'RoutingOptionsPage',
    evidence: _component(
      'test/features/settings/overview/sections/routing_options_page_test.dart',
      'NovaRoutingModeControl',
      'routing mode and global controls',
    ),
  ),
  NovaPenFrameFixture(
    '10',
    'Редактор правила',
    'RulePage:editing',
    evidence: _page('test/features/route_rules/overview/rule_page_save_test.dart', 'RulePage', 'editable route rule'),
  ),
  NovaPenFrameFixture(
    '11',
    'Редактор списка',
    'GenericListPage',
    evidence: _page(_canonicalHarnessPath, 'GenericListPage', 'empty domain list editor'),
  ),
  NovaPenFrameFixture(
    '12',
    'Маршрутизация приложений',
    'PerAppProxyPage',
    platform: 'android',
    evidence: _constructor('PerAppProxyPage', 'platform capability recovery'),
  ),
  NovaPenFrameFixture(
    '13',
    'DNS',
    'DnsOptionsPage',
    evidence: _page(_canonicalHarnessPath, 'DnsOptionsPage', 'DNS preferences'),
  ),
  NovaPenFrameFixture(
    '14',
    'Входящие соединения',
    'InboundOptionsPage',
    evidence: _page(_canonicalHarnessPath, 'InboundOptionsPage', 'inbound preferences'),
  ),
  NovaPenFrameFixture(
    '15',
    'TLS и фрагментация',
    'TlsTricksPage',
    evidence: _page(_canonicalHarnessPath, 'TlsTricksPage', 'TLS fragmentation preferences'),
  ),
  NovaPenFrameFixture(
    '16',
    'Цепочка прокси',
    'ChainOptionsPage',
    evidence: _page(_canonicalHarnessPath, 'ChainOptionsPage', 'proxy chain preferences'),
  ),
  NovaPenFrameFixture(
    '17',
    'Логи',
    'LogsPage',
    evidence: _page(_canonicalHarnessPath, 'LogsPage', 'empty production log viewer'),
  ),
  NovaPenFrameFixture(
    '18',
    'О приложении',
    'AboutPage',
    evidence: _page(_canonicalHarnessPath, 'AboutPage', 'runtime application information'),
  ),
  NovaPenFrameFixture(
    '19a',
    'Импорт · Проверка',
    'AddProfileModal:checking',
    evidence: _component(_canonicalHarnessPath, 'ImportOutcome', 'validating access'),
  ),
  NovaPenFrameFixture(
    '19b',
    'Импорт · Ошибка',
    'AddProfileModal:error',
    evidence: _page(_importEvidencePath, 'AddProfileModal', 'categorized safe import failure'),
  ),
  NovaPenFrameFixture(
    '19c',
    'Импорт · Готово',
    'AddProfileModal:success',
    evidence: _component(_canonicalHarnessPath, 'ImportOutcome', 'successful access import'),
  ),
  NovaPenFrameFixture(
    '20',
    'Разрешение приложений · Отказано',
    'PerAppRoutingRecoveryView',
    platform: 'android',
    evidence: _component(
      'test/features/per_app_proxy/widget/per_app_routing_recovery_view_test.dart',
      'PerAppRoutingRecoveryView',
      'Android installed-app inventory denied',
    ),
  ),
  NovaPenFrameFixture(
    '21',
    'Метаданные профиля · Неизвестны',
    'ProfileSubscriptionInfo:unknown',
    evidence: _component(
      'test/features/profile/widget/profile_subscription_info_test.dart',
      'ProfileSubscriptionInfo',
      'unknown quota and expiry',
    ),
  ),
  NovaPenFrameFixture(
    '22',
    'Редактор правила · Не сохранено',
    'RulePage:saveFailure',
    evidence: _page(
      'test/features/route_rules/overview/rule_page_save_test.dart',
      'RulePage',
      'failed save keeps draft recoverable',
    ),
  ),
  NovaPenFrameFixture(
    '23',
    'Безопасная диагностика',
    'SafeDiagnosticsPage',
    evidence: _page('test/security/safe_diagnostics_test.dart', 'SafeDiagnosticsPage', 'redacted diagnostic snapshot'),
  ),
  NovaPenFrameFixture(
    '24',
    'Обновление · Установлено',
    'PostUpdateOutcomeDialog',
    evidence: _component(
      'test/features/app_update/widget/post_update_outcome_dialog_test.dart',
      'PostUpdateOutcomeDialog',
      'installed update outcome',
    ),
  ),
  NovaPenFrameFixture(
    '25',
    'Профиль · Экспорт и удаление',
    'ProfileExportDeletePage',
    evidence: _page(
      'test/features/profile/overview/profile_export_delete_page_test.dart',
      'ProfileExportDeletePage',
      'export and destructive actions',
    ),
  ),
  NovaPenFrameFixture(
    '35',
    'Расширенные настройки',
    'AdvancedSettingsPage',
    evidence: _page(_canonicalHarnessPath, 'AdvancedSettingsPage', 'advanced grouped settings'),
  ),
  NovaPenFrameFixture(
    '36',
    'Auto Mode · Подтверждение',
    'ProxiesOverviewPage:autoConfirm',
    evidence: _behavior(_serversEvidencePath, 'ProxiesOverviewPage', 'Auto Mode confirmation'),
  ),
  NovaPenFrameFixture(
    '37',
    'Auto Mode · Нет кандидатов',
    'ProxiesOverviewPage:autoNoCandidates',
    evidence: _behavior(_serversEvidencePath, 'ProxiesOverviewPage', 'Auto Mode has no authorized candidates'),
  ),
  NovaPenFrameFixture(
    '38',
    'Auto Mode · Ошибка переключения',
    'ProxiesOverviewPage:autoFailure',
    evidence: _behavior(_serversEvidencePath, 'ProxiesOverviewPage', 'Auto Mode switch failure'),
  ),
  NovaPenFrameFixture(
    '39',
    'Auto Mode · Сервер изменён',
    'ProxiesOverviewPage:autoChanged',
    evidence: _behavior(_serversEvidencePath, 'ProxiesOverviewPage', 'Auto Mode applies selected server'),
  ),
];
