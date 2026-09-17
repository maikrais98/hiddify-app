import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/analytics/analytics_controller.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/app_info_entity.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
import 'package:hiddify/features/about/widget/about_page.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:hiddify/features/home/widget/home_page.dart';
import 'package:hiddify/features/home/widget/nova_connection_control.dart';
import 'package:hiddify/features/home/widget/nova_protection_status.dart';
import 'package:hiddify/features/home/widget/nova_ritual_hero.dart';
import 'package:hiddify/features/intro/widget/intro_page.dart';
import 'package:hiddify/features/log/overview/logs_overview_notifier.dart';
import 'package:hiddify/features/log/overview/logs_overview_state.dart';
import 'package:hiddify/features/log/overview/logs_page.dart';
import 'package:hiddify/features/per_app_proxy/data/per_app_routing_repository.dart';
import 'package:hiddify/features/per_app_proxy/overview/per_app_proxy_page.dart';
import 'package:hiddify/features/per_app_proxy/widget/per_app_routing_recovery_view.dart';
import 'package:hiddify/features/profile/add/add_profile_modal.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_page.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_page.dart';
import 'package:hiddify/features/route_rules/notifier/rule_notifier.dart';
import 'package:hiddify/features/route_rules/overview/generic_list_page.dart';
import 'package:hiddify/features/settings/overview/advanced_settings_page.dart';
import 'package:hiddify/features/settings/overview/sections/chain_options_page.dart';
import 'package:hiddify/features/settings/overview/sections/dns_options_page.dart';
import 'package:hiddify/features/settings/overview/sections/general_page.dart';
import 'package:hiddify/features/settings/overview/sections/inbound_options_page.dart';
import 'package:hiddify/features/settings/overview/sections/tls_tricks_page.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _viewport = Size(393, 852);
const _deviceInsets = EdgeInsets.only(top: 59, bottom: 34);

class _LoadingProfiles extends ProfilesNotifier {
  @override
  Stream<List<ProfileEntity>> build() => const Stream.empty();
}

class _NoActiveProfile extends ActiveProfile {
  @override
  Stream<ProfileEntity?> build() => Stream.value(null);
}

class _TestAppInfo extends AppInfo {
  _TestAppInfo(this.info);

  final AppInfoEntity info;

  @override
  Future<AppInfoEntity> build() async => info;
}

class _TestAppDirectories extends AppDirectories {
  _TestAppDirectories(this.directories);

  final Directories directories;

  @override
  Future<Directories> build() async => directories;
}

class _EmptyLogs extends LogsOverviewNotifier {
  @override
  LogsOverviewState build() => const LogsOverviewState();
}

class _DisabledAutoStart extends AutoStartNotifier {
  @override
  Future<bool> build() async => false;
}

Widget _canonicalApp({
  required Translations translations,
  required Widget child,
  double textScale = 1,
  EdgeInsets viewInsets = EdgeInsets.zero,
  SharedPreferences? preferences,
}) {
  return ProviderScope(
    overrides: [
      translationsProvider.overrideWith((ref) => translations),
      if (preferences != null) sharedPreferencesProvider.overrideWith((ref) => preferences),
    ],
    child: MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData.dark().copyWith(extensions: const [NovaThemeData.dark]),
      builder: (context, appChild) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          size: _viewport,
          padding: _deviceInsets,
          viewPadding: _deviceInsets,
          viewInsets: viewInsets,
          textScaler: TextScaler.linear(textScale),
        ),
        child: appChild!,
      ),
      home: Scaffold(
        body: SafeArea(key: const ValueKey('canonical_safe_area'), child: child),
      ),
    ),
  );
}

Widget _scrollable(Widget child) => SingleChildScrollView(
  padding: const EdgeInsets.all(NovaSpacing.gutter),
  child: Center(
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: child),
  ),
);

Widget _canonicalRouterApp({
  required Translations translations,
  required GoRouter router,
  required SharedPreferences preferences,
  required double textScale,
}) {
  return ProviderScope(
    overrides: [
      translationsProvider.overrideWith((ref) => translations),
      sharedPreferencesProvider.overrideWith((ref) => preferences),
      hasAnyProfileProvider.overrideWith((ref) => const Stream.empty()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData.dark().copyWith(extensions: const [NovaThemeData.dark]),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          size: _viewport,
          padding: _deviceInsets,
          viewPadding: _deviceInsets,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
    ),
  );
}

void main() {
  test('constructor-only entries instantiate the real production widget types', () {
    final widgets = <Widget>[const PerAppProxyPage()];

    expect(widgets, hasLength(1));
    expect(widgets, everyElement(isA<Widget>()));
  });

  testWidgets('stateful production components render in Russian at 393x852 and 1x/1.5x/2x', (tester) async {
    tester.view.physicalSize = _viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final translations = (await tester.runAsync(AppLocale.ru.build))!;

    final fixtures = <({String id, Widget child})>[
      (
        id: '02a',
        child: const NovaRitualHero(
          state: NovaRitualState.connecting,
          statusLabel: 'Подключение',
          child: NovaConnectionControl(
            enabled: false,
            connected: false,
            loading: true,
            label: 'Подключение',
            onTap: _noop,
          ),
        ),
      ),
      (
        id: '02c',
        child: const NovaRitualHero(
          state: NovaRitualState.error,
          statusLabel: 'Не удалось подключиться',
          child: NovaConnectionControl(
            enabled: true,
            connected: false,
            loading: false,
            label: 'Повторить',
            onTap: _noop,
          ),
        ),
      ),
      (
        id: '02d',
        child: const NovaHomeRecoveryCard(
          title: 'VPN-доступ не настроен',
          message: 'Добавьте ссылку подписки или отсканируйте QR-код.',
          primaryLabel: 'Добавить VPN-доступ',
          onPrimary: _noop,
        ),
      ),
      (
        id: '02f',
        child: const NovaProtectionStatus(
          state: NovaProtectionState.checking,
          checkingTitle: 'Проверяем защиту',
          verifiedTitle: 'Защита подтверждена',
          failedTitle: 'Проверка не пройдена',
          tunnelStartedLabel: 'VPN-туннель запущен',
          checkingMessage: 'Проверяем доступность интернета через защищённое соединение.',
          verifiedMessage: 'Интернет доступен через VPN.',
          failedMessage: 'Интернет через VPN пока недоступен.',
          retryLabel: 'Повторить',
        ),
      ),
      (
        id: '04a',
        child: const ProxiesRecoveryPanel(
          title: 'Служба VPN остановлена',
          message: 'Подключитесь, чтобы загрузить серверы.',
          actionLabel: 'Подключиться',
          onAction: _noop,
        ),
      ),
      (
        id: '04b',
        child: const ProxiesRecoveryPanel(
          title: 'Серверы не найдены',
          message: 'Обновите текущий VPN-доступ или выберите другой.',
          actionLabel: 'Обновить доступ',
          onAction: _noop,
          secondaryActionLabel: 'Выбрать доступ',
          onSecondaryAction: _noop,
        ),
      ),
      (id: '19a', child: const ImportOutcome(phase: ImportPhase.validating)),
      (id: '19c', child: const ImportOutcome(phase: ImportPhase.success)),
      (
        id: '20',
        child: const PerAppRoutingRecoveryView(
          failure: PerAppRoutingException(kind: PerAppRoutingFailureKind.denied),
          onRetry: _noop,
          onContinueWithoutPerApp: _noop,
        ),
      ),
    ];

    for (final textScale in const [1.0, 1.5, 2.0]) {
      for (final fixture in fixtures) {
        final child = fixture.id == '19a' || fixture.id == '19c' ? fixture.child : _scrollable(fixture.child);
        await tester.pumpWidget(
          _canonicalApp(
            translations: translations,
            textScale: textScale,
            child: KeyedSubtree(key: ValueKey('pen_frame_${fixture.id}'), child: child),
          ),
        );
        await tester.pump();

        expect(find.byKey(ValueKey('pen_frame_${fixture.id}')), findsOneWidget);
        final contentRect = tester.getRect(find.byKey(ValueKey('pen_frame_${fixture.id}')));
        expect(contentRect.top, greaterThanOrEqualTo(_deviceInsets.top), reason: '${fixture.id} at ${textScale}x');
        expect(
          contentRect.bottom,
          lessThanOrEqualTo(_viewport.height - _deviceInsets.bottom),
          reason: '${fixture.id} at ${textScale}x',
        );
        expect(tester.takeException(), isNull, reason: '${fixture.id} at ${textScale}x');
      }
    }

    expect(find.text('Маршрутизация приложений недоступна'), findsOneWidget);
  });

  testWidgets('provider-light production pages render at the canonical viewport', (tester) async {
    tester.view.physicalSize = _viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'locale': 'ru'});
    final preferences = await SharedPreferences.getInstance();
    final translations = (await tester.runAsync(AppLocale.ru.build))!;

    final pages = <({String id, Widget page})>[
      (id: '11', page: const GenericListPage(ruleEnum: RuleEnum.domain)),
      (id: '13', page: const DnsOptionsPage()),
      (id: '14', page: const InboundOptionsPage()),
      (id: '15', page: const TlsTricksPage()),
    ];

    for (final textScale in const [1.0, 1.5, 2.0]) {
      for (final fixture in pages) {
        await tester.pumpWidget(
          _canonicalApp(
            translations: translations,
            preferences: preferences,
            textScale: textScale,
            child: KeyedSubtree(key: ValueKey('pen_page_${fixture.id}'), child: fixture.page),
          ),
        );
        await tester.pump();

        expect(find.byKey(ValueKey('pen_page_${fixture.id}')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '${fixture.id} at ${textScale}x');
      }
    }
  });

  testWidgets('ProfilesPage renders its production loading state at 393x852', (tester) async {
    tester.view.physicalSize = _viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final translations = (await tester.runAsync(AppLocale.ru.build))!;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWith((ref) => translations),
          profilesNotifierProvider.overrideWith(_LoadingProfiles.new),
          hasAnyProfileProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: MaterialApp(
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: ThemeData.dark().copyWith(extensions: const [NovaThemeData.dark]),
          home: const MediaQuery(
            data: MediaQueryData(
              size: _viewport,
              padding: _deviceInsets,
              viewPadding: _deviceInsets,
              textScaler: TextScaler.linear(2),
            ),
            child: ProfilesPage(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ProfilesPage), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ChainOptionsPage renders with deterministic empty profile state', (tester) async {
    tester.view.physicalSize = _viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'locale': 'ru', 'chain-status': 'extraSecurity'});
    final preferences = await SharedPreferences.getInstance();
    final translations = (await tester.runAsync(AppLocale.ru.build))!;

    for (final textScale in const [1.0, 1.5, 2.0]) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWith((ref) => preferences),
            profilesNotifierProvider.overrideWith(_LoadingProfiles.new),
            activeProfileProvider.overrideWith(_NoActiveProfile.new),
          ],
          child: _canonicalApp(
            translations: translations,
            preferences: preferences,
            textScale: textScale,
            child: const ChainOptionsPage(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ChainOptionsPage), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '16 at ${textScale}x');
    }
  });

  testWidgets('LogsPage and AboutPage render from deterministic production providers', (tester) async {
    tester.view.physicalSize = _viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'locale': 'ru'});
    final preferences = await SharedPreferences.getInstance();
    final translations = (await tester.runAsync(AppLocale.ru.build))!;
    final directory = Directory('.');
    final directories = (baseDir: directory, workingDir: directory, tempDir: directory);
    const appInfo = AppInfoEntity(
      name: 'Woman in Red',
      version: '0.0.1',
      buildNumber: '1',
      release: Release.general,
      operatingSystem: 'ios',
      operatingSystemVersion: 'test',
      environment: Environment.prod,
    );
    final container = ProviderContainer(
      overrides: [
        translationsProvider.overrideWith((ref) => translations),
        sharedPreferencesProvider.overrideWith((ref) => preferences),
        environmentProvider.overrideWith((ref) => Environment.prod),
        appInfoProvider.overrideWith(() => _TestAppInfo(appInfo)),
        appDirectoriesProvider.overrideWith(() => _TestAppDirectories(directories)),
        logsOverviewNotifierProvider.overrideWith(_EmptyLogs.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(appInfoProvider.future);
    await container.read(appDirectoriesProvider.future);

    for (final fixture in <({String id, Widget page})>[
      (id: '17', page: const LogsPage()),
      (id: '18', page: const AboutPage()),
    ]) {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('ru'),
            supportedLocales: const [Locale('ru'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: ThemeData.dark().copyWith(extensions: const [NovaThemeData.dark]),
            home: MediaQuery(
              data: const MediaQueryData(
                size: _viewport,
                padding: _deviceInsets,
                viewPadding: _deviceInsets,
                textScaler: TextScaler.linear(2),
              ),
              child: fixture.page,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(fixture.page.runtimeType), findsOneWidget);
      expect(tester.takeException(), isNull, reason: fixture.id);
    }
  });

  testWidgets('GeneralPage renders after its desktop capability provider is ready', (tester) async {
    tester.view.physicalSize = _viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'locale': 'ru'});
    final preferences = await SharedPreferences.getInstance();
    final translations = (await tester.runAsync(AppLocale.ru.build))!;
    final container = ProviderContainer(
      overrides: [
        translationsProvider.overrideWith((ref) => translations),
        sharedPreferencesProvider.overrideWith((ref) => preferences),
        environmentProvider.overrideWith((ref) => Environment.prod),
        autoStartNotifierProvider.overrideWith(_DisabledAutoStart.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(autoStartNotifierProvider.future);
    await container.read(analyticsControllerProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: ThemeData.dark().copyWith(extensions: const [NovaThemeData.dark]),
          home: const MediaQuery(
            data: MediaQueryData(
              size: _viewport,
              padding: _deviceInsets,
              viewPadding: _deviceInsets,
              textScaler: TextScaler.linear(2),
            ),
            child: GeneralPage(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(GeneralPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('IntroPage and SettingsPage render through production routes in Russian', (tester) async {
    tester.view.physicalSize = _viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'locale': 'ru'});
    final preferences = await SharedPreferences.getInstance();
    final translations = (await tester.runAsync(AppLocale.ru.build))!;

    final introRouter = GoRouter(
      initialLocation: '/intro',
      routes: [
        GoRoute(path: '/intro', builder: (_, _) => const IntroPage()),
        GoRoute(name: 'home', path: '/home', builder: (_, _) => const SizedBox.shrink()),
      ],
    );
    addTearDown(introRouter.dispose);

    for (final textScale in const [1.0, 1.5, 2.0]) {
      await tester.pumpWidget(
        _canonicalRouterApp(
          translations: translations,
          router: introRouter,
          preferences: preferences,
          textScale: textScale,
        ),
      );
      await tester.pump();
      expect(find.byType(IntroPage), findsOneWidget);
      expect(find.byKey(const ValueKey('intro_add_profile')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '01 at ${textScale}x');
    }

    final settingsRouter = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(name: 'settings', path: '/settings', builder: (_, _) => SettingsPage()),
        GoRoute(name: 'general', path: '/general', builder: (_, _) => const GeneralPage()),
        GoRoute(name: 'advanced', path: '/advanced', builder: (_, _) => const AdvancedSettingsPage()),
        GoRoute(name: 'logs', path: '/logs', builder: (_, _) => const LogsPage()),
        GoRoute(name: 'about', path: '/about', builder: (_, _) => const AboutPage()),
        GoRoute(name: 'routingOptions', path: '/routing', builder: (_, _) => const SizedBox.shrink()),
        GoRoute(name: 'chainOptions', path: '/chain', builder: (_, _) => const SizedBox.shrink()),
        GoRoute(name: 'dnsOptions', path: '/dns', builder: (_, _) => const SizedBox.shrink()),
        GoRoute(name: 'inboundOptions', path: '/inbound', builder: (_, _) => const SizedBox.shrink()),
        GoRoute(name: 'tlsTricks', path: '/tls', builder: (_, _) => const SizedBox.shrink()),
      ],
    );
    addTearDown(settingsRouter.dispose);

    for (final textScale in const [1.0, 1.5, 2.0]) {
      await tester.pumpWidget(
        _canonicalRouterApp(
          translations: translations,
          router: settingsRouter,
          preferences: preferences,
          textScale: textScale,
        ),
      );
      await tester.pump();
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.text(translations.pages.settings.title), findsWidgets);
      expect(tester.takeException(), isNull, reason: '07 at ${textScale}x');
    }

    settingsRouter.go('/advanced');
    await tester.pumpAndSettle();
    expect(find.byType(AdvancedSettingsPage), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '35 at 2.0x');
  });

  testWidgets('manual import remains inside the safe area above a software keyboard at 2x', (tester) async {
    tester.view.physicalSize = _viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final translations = (await tester.runAsync(AppLocale.ru.build))!;

    await tester.pumpWidget(
      _canonicalApp(
        translations: translations,
        textScale: 2,
        viewInsets: const EdgeInsets.only(bottom: 320),
        child: const AddProfileManual(),
      ),
    );
    await tester.pump();

    expect(find.byType(TextFormField), findsNWidgets(2));
    final submit = find.widgetWithText(FilledButton, 'Добавить');
    await tester.ensureVisible(submit);
    await tester.pump();
    final submitRect = tester.getRect(submit);
    expect(submitRect.bottom, lessThanOrEqualTo(_viewport.height - 320));
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
