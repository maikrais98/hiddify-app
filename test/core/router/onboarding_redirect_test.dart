import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/router/go_router/routing_config_notifier.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
import 'package:hiddify/features/intro/widget/intro_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingBottomSheets extends BottomSheetsNotifier {
  int addProfileCalls = 0;

  @override
  void build() {}

  @override
  Future<void> showAddProfile({String? url, bool triggeredByDeepLink = false}) async {
    addProfileCalls++;
  }
}

void main() {
  const subscription = 'hiddify://import?url=https%3A%2F%2Fexample.com%2Fsub%3Ftoken%3Da%26b';

  test('first run is gated without losing a pending deep link', () {
    expect(
      onboardingRedirect(onboardingCompleted: false, matchedLocation: '/home', pendingUrl: subscription),
      Uri(path: '/intro', queryParameters: {'url': subscription}).toString(),
    );
  });

  test('intro does not redirect to itself', () {
    expect(onboardingRedirect(onboardingCompleted: false, matchedLocation: '/intro', pendingUrl: subscription), isNull);
  });

  test('completing intro hands the pending deep link back to home', () {
    expect(
      onboardingRedirect(onboardingCompleted: true, matchedLocation: '/intro', pendingUrl: subscription),
      Uri(path: '/home', queryParameters: {'url': subscription}).toString(),
    );
  });

  test('completed users stay on their requested route', () {
    expect(onboardingRedirect(onboardingCompleted: true, matchedLocation: '/settings', pendingUrl: null), isNull);
  });

  testWidgets('actual router keeps a first-run import link parked on Intro', (tester) async {
    SharedPreferences.setMockInitialValues({'intro_completed': false});
    final preferences = await SharedPreferences.getInstance();
    final bottomSheets = _RecordingBottomSheets();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => preferences),
        isMobileBreakpointProvider.overrideWith((ref) => true),
        bottomSheetsNotifierProvider.overrideWith(() => bottomSheets),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(Preferences.introCompleted), isFalse);

    final productionRedirect = container.read(routingConfigNotifierProvider).redirect;
    final router = GoRouter(
      initialLocation: '/home?url=${Uri.encodeQueryComponent(subscription)}',
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const Text('home')),
        GoRoute(path: '/intro', builder: (_, _) => const Text('intro')),
      ],
      redirect: productionRedirect,
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('intro'), findsOneWidget);
    expect(bottomSheets.addProfileCalls, 0);
    expect(router.routeInformationProvider.value.uri.path, '/intro');
    expect(router.routeInformationProvider.value.uri.queryParameters['url'], subscription);
  });

  for (final openImporter in [true, false]) {
    testWidgets('Intro ${openImporter ? 'opens the importer once' : 'continues without opening the importer'}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({'intro_completed': false, 'locale': 'ru'});
      final preferences = await SharedPreferences.getInstance();
      final translations = (await tester.runAsync(AppLocale.ru.build))!;
      final bottomSheets = _RecordingBottomSheets();
      final router = GoRouter(
        initialLocation: '/intro',
        routes: [
          GoRoute(path: '/intro', builder: (_, _) => const IntroPage()),
          GoRoute(path: '/home', builder: (_, _) => const Text('home')),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWith((ref) => preferences),
            translationsProvider.overrideWith((ref) => translations),
            bottomSheetsNotifierProvider.overrideWith(() => bottomSheets),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            locale: const Locale('ru'),
            supportedLocales: const [Locale('ru'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: ThemeData.dark().copyWith(extensions: const [NovaThemeData.dark]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final action = find.byKey(ValueKey(openImporter ? 'intro_add_profile' : 'intro_later'));
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
      expect(preferences.getBool('intro_completed'), isTrue);
      expect(bottomSheets.addProfileCalls, openImporter ? 1 : 0);
    });
  }
}
