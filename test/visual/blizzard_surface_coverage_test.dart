import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/logger/logger_setup.dart';
import 'package:hiddify/core/logger/ring/log_ring.dart';
import 'package:hiddify/core/router/dialog/widgets/setting_input_dialog.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/theme/blizzard_tokens.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_native_tab_bar.dart';
import 'package:hiddify/features/about/widget/about_page.dart';
import 'package:hiddify/features/app_update/notifier/app_update_notifier.dart';
import 'package:hiddify/features/common/qr_code_dialog.dart';
import 'package:hiddify/features/intro/widget/intro_page.dart';
import 'package:hiddify/features/log/overview/logs_overview_notifier.dart';
import 'package:hiddify/features/log/overview/logs_page.dart';
import 'package:hiddify/features/profile/details/json_editor.dart';
import 'package:hiddify/features/profile/details/profile_details_notifier.dart';
import 'package:hiddify/features/profile/details/profile_details_page.dart';
import 'package:hiddify/features/profile/details/profile_details_state.dart';
import 'package:hiddify/features/profile/overview/profiles_modal.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/data/proxy_repository.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_page.dart';
import 'package:hiddify/features/proxy/widget/proxy_tile.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/utils/placeholders.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../support/blizzard_capture.dart';
import '../support/blizzard_visual_fixture.dart';
import '../support/connection_fixtures.dart';
import '../support/home_fixture.dart' as home;
import '../support/profile_settings_fixtures.dart' show FixtureCore, FixtureHttp;
import '../support/surface_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerBlizzardSurfaceCoverage();
}

Widget _appliedBlizzard(Widget child) => Builder(
  builder: (context) => Theme(data: BlizzardTheme.from(Theme.of(context)), child: child),
);

// Aurora deliberately keeps scheduling decorative frames on iOS. Wait for
// finite route/menu transitions without asking the whole app to become idle.
Future<void> _finishSurfaceTransition(WidgetTester tester) async {
  if (Platform.isIOS) {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
}

Future<void> _finishSurfaceScroll(WidgetTester tester, Finder scrollable) async {
  final position = tester.state<ScrollableState>(scrollable).position;
  for (var frame = 0; frame < 40; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (!position.isScrollingNotifier.value) return;
  }
  expect(position.isScrollingNotifier.value, isFalse, reason: 'The actual scroll must finish before measuring rows');
}

void registerBlizzardSurfaceCoverage() {
  for (final editor in Editors.values) {
    testWidgets('legacy JSON ${editor.name} toolbar preserves trailing alignment', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OverflowBox(
              minWidth: 700,
              maxWidth: 700,
              minHeight: 500,
              maxHeight: 500,
              child: SizedBox(
                width: 700,
                height: 500,
                child: JsonEditor(json: '{"name":"initial"}', editors: [editor], onChanged: (_) {}),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.getSize(find.byType(JsonEditor)).width, 700);
      // This intentionally measures the wide legacy toolbar, independently of
      // the native host's phone viewport. Narrow Blizzard geometry is separate.
      // Confirmed against the shipped baseline: DecoratedBox paints its border
      // without adding an inset; the original toolbar has 10 px end padding.
      expect(
        tester.getRect(find.byTooltip('Copy')).right,
        closeTo(tester.getRect(find.byType(JsonEditor)).right - 10, .01),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('real scoped JSON editor keeps draft selection and focus when appearance changes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(599, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final changes = <dynamic>[];
    Widget app(AppThemeMode mode) {
      final base = AppTheme(mode, Platform.isIOS ? '.SF Pro Text' : '');
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: base.lightTheme(null),
        darkTheme: base.darkTheme(null),
        themeMode: mode.flutterThemeMode,
        builder: (context, child) => Center(
          child: SizedBox(
            width: 599,
            height: 620,
            child: RepaintBoundary(
              key: blizzardFixtureCanvas,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(size: const Size(599, 620)),
                child: child!,
              ),
            ),
          ),
        ),
        home: Scaffold(
          body: JsonEditor(
            key: const ValueKey('scoped-editor'),
            json: '{"name":"initial"}',
            editors: const [Editors.text],
            onChanged: changes.add,
          ),
        ),
      );
    }

    await tester.pumpWidget(app(AppThemeMode.dark));
    await tester.pump(const Duration(seconds: 1));
    final field = find.byType(TextField).last;
    await tester.tap(field);
    await tester.enterText(field, '{"name":"draft"}');
    final before = tester.widget<EditableText>(find.byType(EditableText).last);
    before.controller.selection = const TextSelection.collapsed(offset: 8);
    await tester.pump(const Duration(milliseconds: 600));
    expect(changes, [
      {'name': 'draft'},
    ]);
    if (expectsBlizzard(AppThemeMode.dark, Brightness.dark, 599)) {
      expect(before.style.fontFamily, 'monospace');
      expect(before.style.fontSize, 13);
    }
    await captureBlizzardFixture(tester, 'JsonEditor-dark-draft');
    await tester.pumpWidget(app(AppThemeMode.light));
    await tester.pump(const Duration(seconds: 1));
    final after = tester.widget<EditableText>(find.byType(EditableText).last);
    expect(identical(before.controller, after.controller), isTrue);
    expect(identical(before.focusNode, after.focusNode), isTrue);
    expect(after.focusNode.hasFocus, isTrue);
    expect(after.controller.text, '{"name":"draft"}');
    expect(after.controller.selection.baseOffset, 8);
    expect(changes.length, 1);
    expect(tester.takeException(), isNull);
    await captureBlizzardFixture(tester, 'JsonEditor-light-same-draft');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final width in [320.0, 393.0]) {
    testWidgets('real ten-server list remains reachable and forwards actions at $width', (tester) async {
      final group = OutboundGroup(
        tag: 'select',
        selected: 'Synthetic server 1',
        items: List.generate(
          10,
          (index) => OutboundInfo(
            tag: 'Synthetic server ${index + 1}',
            tagDisplay: 'Synthetic server ${index + 1}',
            type: 'vless',
            urlTestDelay: index == 1 ? 0 : (index == 2 ? 65001 : 84 + index),
          ),
        ),
      );
      final core = FixtureCore()..group = group;
      final http = FixtureHttp();
      final f = await home.mountHomeFixture(
        tester,
        width: width,
        scale: 1.3,
        locale: AppLocale.ru,
        child: const ProxiesOverviewPage(),
        extraOverrides: [
          proxiesOverviewNotifierProvider.overrideWith(() => SurfaceProxies(AsyncData(group))),
          proxyRepositoryProvider.overrideWith((ref) => ProxyRepositoryImpl(singbox: core, client: http)),
        ],
      );
      final grid = find.byKey(const ValueKey('servers_grid'));
      for (var index = 1; index <= 10; index++) {
        final label = find.text('Synthetic server $index');
        await tester.scrollUntilVisible(
          label,
          90,
          scrollable: find.descendant(of: grid, matching: find.byType(Scrollable)),
        );
        // ensureVisible can update the scroll offset after its final frame.
        // Commit that layout before checking the clipped native-glass viewport.
        await tester.pump(const Duration(milliseconds: 100));
        expect(label.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      final last = find.byWidgetPredicate((w) => w is ProxyTile && w.proxy.tag == 'Synthetic server 10');
      await tester.tap(last);
      await tester.pump(const Duration(seconds: 1));
      expect(core.selections, [('select', 'Synthetic server 10')]);
      expect(f.container.read(proxiesOverviewNotifierProvider).requireValue!.selected, 'Synthetic server 10');
      await tester.tap(find.byTooltip(f.container.read(translationsProvider).requireValue.pages.proxies.testDelay));
      await tester.pump(const Duration(seconds: 1));
      expect(core.delayTests, ['select']);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    });
  }
  for (final entry in settingsSurfaces.entries) {
    testWidgets('real ${entry.key} preferences have nonempty reachable controls and readable theme', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = await mountVisualFixture(
        tester,
        child: entry.key == 'chain' ? _appliedBlizzard(entry.value) : entry.value,
      );
      if (entry.key == 'chain') {
        await fixture.container.read(ConfigOptions.extraSecurityMode.notifier).update(ChainMode.warp);
        await fixture.container.read(ConfigOptions.chainStatus.notifier).update(ChainStatus.extraSecurity);
        await tester.pump(const Duration(milliseconds: 500));
      }
      final rows = interactiveRows();
      expect(rows, findsWidgets, reason: 'Cannot pass with an empty interactive inventory');
      var measured = 0;
      final scroll = find.descendant(of: find.byType(entry.value.runtimeType), matching: find.byType(Scrollable)).first;
      for (var pass = 0; pass < 8; pass++) {
        for (final element in rows.evaluate().toList()) {
          final finder = find.byWidget(element.widget);
          if (finder.hitTestable().evaluate().isEmpty) continue;
          final size = tester.getSize(finder);
          expect(size.width, greaterThanOrEqualTo(44));
          expect(size.height, greaterThanOrEqualTo(44));
          measured++;
        }
        if (scroll.evaluate().isEmpty) break;
        final state = tester.state<ScrollableState>(scroll);
        if (state.position.pixels >= state.position.maxScrollExtent) break;
        await tester.drag(scroll, const Offset(0, -450));
        await _finishSurfaceScroll(tester, scroll);
      }
      expect(measured, greaterThan(0));
      final state = tester.state<ScrollableState>(scroll);
      expect(state.position.extentAfter, lessThan(1), reason: 'Last actions must be reachable by scroll');
      final theme = fixture.innerTheme!;
      expect(contrastRatio(theme.colorScheme.onSurface, theme.colorScheme.surface), greaterThanOrEqualTo(4.5));
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    });
  }
  testWidgets('official empty logs render controls without async placeholders', (tester) async {
    logRing.clear();
    addTearDown(logRing.clear);
    final f = await home.mountHomeFixture(tester, child: _appliedBlizzard(const LogsPage()));
    final t = f.container.read(translationsProvider).requireValue;
    expect(find.text(t.common.empty), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(SliverErrorBodyPlaceholder), findsNothing);
    for (final tooltip in [t.common.pause, t.common.clear, t.common.share]) {
      final action = find.byTooltip(tooltip);
      expect(action.hitTestable(), findsOneWidget);
      expect(tester.getSize(action).shortestSide, greaterThanOrEqualTo(44));
    }
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });

  testWidgets('official live logs pause, resume and clear the real ring', (tester) async {
    logRing.clear();
    addTearDown(logRing.clear);
    logRing.add(LogRecord(Level.WARNING, 'Synthetic first record', 'app.surface'));
    final f = await home.mountHomeFixture(tester, child: const LogsPage());
    final t = f.container.read(translationsProvider).requireValue;
    expect(find.text('Synthetic first record'), findsOneWidget);
    await tester.tap(find.byTooltip(t.common.pause));
    await tester.pump();
    expect(f.container.read(logsOverviewNotifierProvider).paused, isTrue);
    expect(find.byTooltip(t.common.resume), findsOneWidget);
    logRing.add(LogRecord(Level.WARNING, 'Synthetic record while paused', 'core.surface'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Synthetic record while paused'), findsNothing);
    expect(logRing.length, 2);
    await tester.tap(find.byTooltip(t.common.resume));
    await tester.pump();
    expect(find.text('Synthetic record while paused'), findsOneWidget);
    await tester.tap(find.byTooltip(t.common.clear));
    await tester.pump();
    expect(logRing.length, 0);
    expect(f.container.read(logsOverviewNotifierProvider).logs, isEmpty);
    expect(find.text(t.common.empty), findsOneWidget);
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });

  testWidgets('official log search, category and level menus filter without deleting history', (tester) async {
    logRing.clear();
    addTearDown(logRing.clear);
    logRing
      ..add(LogRecord(Level.INFO, 'Synthetic keep app', 'app.surface'))
      ..add(LogRecord(Level.WARNING, 'Synthetic keep warning', 'core.surface'))
      ..add(LogRecord(Level.SEVERE, 'Synthetic keep error', 'core.surface'));
    final f = await home.mountHomeFixture(tester, child: const LogsPage());
    final t = f.container.read(translationsProvider).requireValue;
    await f.container.read(logsOverviewNotifierProvider.notifier).filterLevel(Level.FINEST);
    await tester.pump();
    expect(f.container.read(logsOverviewNotifierProvider).logs, hasLength(3));
    await tester.enterText(find.byType(TextField), 'Synthetic keep');
    await tester.tap(find.text(t.pages.logs.category));
    await _finishSurfaceTransition(tester);
    await tester.tap(find.text('core').last);
    await _finishSurfaceTransition(tester);
    expect(f.container.read(logsOverviewNotifierProvider).category, LogCategory.core);
    expect(find.text('Synthetic keep app'), findsNothing);
    await tester.tap(find.text(t.pages.logs.level));
    await _finishSurfaceTransition(tester);
    await tester.tap(find.text('error').last);
    await _finishSurfaceTransition(tester);
    expect(f.container.read(logsOverviewNotifierProvider).minLevel, Level.SEVERE);
    expect(find.text('Synthetic keep error'), findsOneWidget);
    expect(find.text('Synthetic keep warning'), findsNothing);
    await tester.enterText(find.byType(TextField), 'does not match');
    await tester.pump();
    expect(find.text(t.common.empty), findsOneWidget);
    expect(logRing.length, 3);
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });

  testWidgets('official log row long press copies its complete formatted record', (tester) async {
    logRing.clear();
    addTearDown(logRing.clear);
    logRing.add(LogRecord(Level.WARNING, 'Synthetic selected record', 'app.surface'));
    final clipboard = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard.add(call.arguments);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final f = await home.mountHomeFixture(tester, child: const LogsPage());
    final t = f.container.read(translationsProvider).requireValue;
    await tester.longPress(find.text('Synthetic selected record'));
    await _finishSurfaceTransition(tester);
    await tester.tap(find.text(t.common.addToClipboard));
    await _finishSurfaceTransition(tester);
    expect(clipboard, hasLength(1));
    final copied = (clipboard.single! as Map)['text'];
    expect(copied, contains('[WARN] [app.surface] Synthetic selected record'));
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });

  for (final state in ['loading', 'empty', 'error', 'data']) {
    testWidgets('real proxies $state retains sort and test actions', (tester) async {
      final error = StateError('Synthetic proxy error');
      final value = switch (state) {
        'loading' => const AsyncLoading<OutboundGroup?>(),
        'empty' => const AsyncData<OutboundGroup?>(null),
        'error' => AsyncError<OutboundGroup?>(error, StackTrace.current),
        _ => AsyncData<OutboundGroup?>(OutboundGroup(tag: 'select', items: [])),
      };
      final proxies = _SurfaceProxiesSpy(value);
      final f = await home.mountHomeFixture(
        tester,
        child: const ProxiesOverviewPage(),
        extraOverrides: [proxiesOverviewNotifierProvider.overrideWith(() => proxies)],
      );
      final blizzard = home.expectsBlizzard(AppThemeMode.dark, Brightness.dark, 393);
      final delayAction = find.byKey(const ValueKey('servers_test_delay_button'));
      if (blizzard) {
        expect(delayAction, findsOneWidget);
        expect(tester.getSize(delayAction).shortestSide, greaterThanOrEqualTo(44));
        if (state == 'data') {
          expect(find.text('Servers'), findsOneWidget);
          expect(find.textContaining('0 servers'), findsOneWidget);
          await tester.ensureVisible(delayAction);
        }
        expect(delayAction.hitTestable(), findsOneWidget);
        await tester.tap(delayAction);
        await tester.pump();
        expect(proxies.delayTests, ['select']);
      } else {
        final legacyAction = find.byTooltip(
          f.container.read(translationsProvider).requireValue.pages.proxies.testDelay,
        );
        expect(legacyAction, findsOneWidget);
        expect(find.byType(FloatingActionButton), findsNWidgets(state == 'data' ? 2 : 1));
        expect(tester.getSize(legacyAction).shortestSide, greaterThanOrEqualTo(44));
        await tester.tap(legacyAction);
        await tester.pump();
        expect(proxies.delayTests, ['select']);
      }
      if (state == 'loading') expect(find.byType(CircularProgressIndicator), findsOneWidget);
      if (state == 'empty') {
        expect(find.text(f.container.read(translationsProvider).requireValue.pages.proxies.empty), findsOneWidget);
      }
      if (state == 'error') {
        expect(find.text(f.container.read(translationsProvider).requireValue.pages.proxies.loadFailed), findsOneWidget);
        expect(find.text(f.container.read(translationsProvider).requireValue.connection.tapToRetry), findsOneWidget);
      }
      expect(find.byType(PopupMenuButton<ProxiesSort>), findsOneWidget);
      await tester.tap(find.byType(PopupMenuButton<ProxiesSort>));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(PopupMenuItem<ProxiesSort>), findsNWidgets(ProxiesSort.values.length));
      expect(tester.takeException(), isNull);
      await f.close(tester);
    });
  }
  for (final state in ['loading', 'empty', 'error']) {
    testWidgets('Blizzard proxies $state keeps the delay action reachable', (tester) async {
      final error = StateError('Synthetic proxy error');
      final value = switch (state) {
        'loading' => const AsyncLoading<OutboundGroup?>(),
        'empty' => const AsyncData<OutboundGroup?>(null),
        _ => AsyncError<OutboundGroup?>(error, StackTrace.current),
      };
      final proxies = _SurfaceProxiesSpy(value);
      final f = await home.mountHomeFixture(
        tester,
        child: _appliedBlizzard(const ProxiesOverviewPage()),
        extraOverrides: [proxiesOverviewNotifierProvider.overrideWith(() => proxies)],
      );
      final delayAction = find.byKey(const ValueKey('servers_test_delay_button'));
      expect(delayAction, findsOneWidget);
      expect(tester.getSize(delayAction).shortestSide, greaterThanOrEqualTo(44));
      expect(delayAction.hitTestable(), findsOneWidget);
      await tester.tap(delayAction);
      await tester.pump();
      expect(proxies.delayTests, ['select']);
      if (state == 'loading') expect(find.byType(CircularProgressIndicator), findsOneWidget);
      if (state == 'empty') {
        expect(find.text(f.container.read(translationsProvider).requireValue.pages.proxies.empty), findsOneWidget);
      }
      if (state == 'error') {
        expect(find.text(f.container.read(translationsProvider).requireValue.pages.proxies.loadFailed), findsOneWidget);
        expect(find.text(f.container.read(translationsProvider).requireValue.connection.tapToRetry), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await f.close(tester);
    });
  }
  testWidgets('real About information and action rows are rendered', (tester) async {
    final f = await home.mountHomeFixture(
      tester,
      child: const AboutPage(),
      extraOverrides: [appUpdateNotifierProvider.overrideWith(SurfaceAppUpdate.new)],
    );
    expect(find.text('luma'), findsOneWidget);
    expect(find.byType(ListTile), findsWidgets);
    expect(interactiveRows(), findsWidgets);
    final menu = find.byWidgetPredicate((w) => w is PopupMenuButton);
    expect(menu, findsOneWidget);
    await tester.tap(menu);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byWidgetPredicate((w) => w is PopupMenuItem), findsWidgets);
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });

  for (final entry in dialogSurfaces.entries) {
    testWidgets('real ${entry.key} dialog has visible content and accessible action geometry', (tester) async {
      final f = await home.mountHomeFixture(tester, child: entry.value);
      expect(find.byType(AlertDialog), findsOneWidget);
      if (entry.key == 'D11') {
        expect(find.textContaining('luma'), findsOneWidget);
      }
      final actions = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byWidgetPredicate(
          (w) => (w is ButtonStyleButton && w.onPressed != null) || (w is ListTile && w.enabled && w.onTap != null),
        ),
      );
      expect(actions, findsWidgets);
      for (final element in actions.evaluate()) {
        final size = tester.getSize(find.byWidget(element.widget));
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
      expect(tester.takeException(), isNull);
      await f.close(tester);
    });
  }
  testWidgets('real QR output retains measurable code and textual label', (tester) async {
    final f = await home.mountHomeFixture(
      tester,
      child: const QrCodeDialog('https://example.invalid', title: 'Synthetic profile', link: 'https://example.invalid'),
    );
    expect(find.byType(QrImageView), findsOneWidget);
    expect(tester.getSize(find.byType(QrImageView)).width, 184);
    expect(find.text('Synthetic profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });
  testWidgets('real Intro retains preference and start controls', (tester) async {
    IntroPage.locationInfoLoaded = true; // External IP geolocation excluded from renderer fixture.
    final f = await home.mountHomeFixture(tester, child: const IntroPage());
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byType(Text), findsWidgets);
    expect(tester.takeException(), isNull);
    await f.close(tester);
    IntroPage.locationInfoLoaded = false;
  });
  testWidgets('real Settings overview renders section navigation and overflow', (tester) async {
    final f = await home.mountHomeFixture(tester, child: SettingsPage());
    expect(find.byType(ListTile), findsWidgets);
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });

  testWidgets('real profile details renders draft fields and disabled save before changes', (tester) async {
    final f = await home.mountHomeFixture(
      tester,
      child: ProfileDetailsPage(id: connectionProfile.id),
      extraOverrides: [
        profileDetailsNotifierProvider(connectionProfile.id).overrideWith(
          () => SurfaceDetails(
            ProfileDetailsState(
              loadingState: const AsyncData(null),
              profile: connectionProfile,
              config: const AsyncData((text: '{"outbounds":[]}', isJson: true)),
              isDetailsChanged: false,
            ),
          ),
        ),
      ],
    );
    expect(find.byType(TextFormField), findsWidgets);
    final saves = tester.widgetList<ButtonStyleButton>(find.byWidgetPredicate((w) => w is ButtonStyleButton));
    expect(saves.where((w) => w.onPressed == null), isNotEmpty);
    final layoutError = tester.takeException();
    if (expectsBlizzard(AppThemeMode.dark, Brightness.dark, 393)) {
      expect(layoutError, isNull);
    } else {
      // Baseline desktop JSON toolbar overflows in this phone-width host fixture.
      // Explicit characterization, not a claim of visual acceptance.
      expect(layoutError.toString(), contains('A RenderFlex overflowed'));
    }
    await f.close(tester);
  });
  testWidgets('real profiles sheet renders actual profile row and footer controls', (tester) async {
    final profiles = home.TileProfilesSpy()..profiles = [connectionProfile];
    final f = await home.mountHomeFixture(
      tester,
      child: const ProfilesModal(),
      extraOverrides: [profilesNotifierProvider.overrideWith(() => profiles)],
    );
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.text(connectionProfile.name), findsWidgets);
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });

  testWidgets('real input modal focus enters field and traversal stays inside modal', (tester) async {
    final f = await home.mountHomeFixture(
      tester,
      child: SafeArea(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const SettingInputDialog<int>(
                title: 'Port',
                initialValue: 1080,
                mapTo: int.tryParse,
                digitsOnly: true,
              ),
            ),
            child: const Text('Open input'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open input'));
    await _finishSurfaceTransition(tester);
    final input = tester.widget<EditableText>(find.byType(EditableText));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(input.focusNode.hasFocus, true);
    await tester.enterText(find.byType(TextField), '2080');
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focusContext = FocusManager.instance.primaryFocus!.context!;
      expect(
        focusContext.findAncestorWidgetOfExactType<AlertDialog>(),
        isNotNull,
        reason: 'Modal keyboard traversal must not enter underlying actions',
      );
    }
    expect(input.controller.text, '2080');
    await f.close(tester);
  });

  testWidgets('real input suggestions retain selection and use the scoped material', (tester) async {
    final f = await home.mountHomeFixture(
      tester,
      child: SafeArea(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const SettingInputDialog<String>(
                title: 'Synthetic choice',
                initialValue: 'One',
                possibleValues: ['One', 'Two'],
              ),
            ),
            child: const Text('Open suggestions'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open suggestions'));
    await _finishSurfaceTransition(tester);
    expect(find.byType(TypeAheadField<String>), findsOneWidget);
    final controller = tester.widget<EditableText>(find.byType(EditableText)).controller;
    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Two'), findsOneWidget);
    final material = tester.element(find.text('Two')).findAncestorWidgetOfExactType<Material>()!;
    if (home.expectsBlizzard(AppThemeMode.dark, Brightness.dark, 393)) {
      expect(material.color, BlizzardPalette.surface);
      expect(material.borderRadius, BorderRadius.circular(12));
    } else {
      expect(material.color, isNull);
      expect(material.borderRadius, BorderRadius.circular(8));
    }
    await tester.tap(find.text('Two'));
    await tester.pump();
    expect(controller.text, 'Two');
    expect(identical(controller, tester.widget<EditableText>(find.byType(EditableText)).controller), isTrue);
    expect(f.events, isEmpty);
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });

  testWidgets('scoped high contrast changes contrast without Flutter-owned native dock motion', (tester) async {
    // Numeric behavioral acceptance is armed only on an actual iOS process.
    final normal = await mountVisualFixture(tester, child: settingsSurfaces['dns']!);
    final regularRatio = contrastRatio(
      normal.innerTheme!.colorScheme.onSurfaceVariant,
      normal.innerTheme!.colorScheme.surface,
    );
    await normal.close(tester);
    final accessible = await mountVisualFixture(
      tester,
      child: settingsSurfaces['dns']!,
      highContrast: true,
      disableAnimations: true,
    );
    if (expectsBlizzard(AppThemeMode.dark, Brightness.dark, 393)) {
      final ratio = contrastRatio(
        accessible.innerTheme!.colorScheme.onSurfaceVariant,
        accessible.innerTheme!.colorScheme.surface,
      );
      expect(ratio, greaterThan(regularRatio));
      expect(ratio, greaterThanOrEqualTo(7));
      final dock = find.byKey(const ValueKey('blizzard_bottom_dock'));
      final nativeDock = find.descendant(of: dock, matching: find.byType(BlizzardNativeTabBar));
      expect(tester.getSize(dock), const Size(320, 88));
      expect(nativeDock, findsOneWidget);
      expect(find.descendant(of: nativeDock, matching: find.byType(UiKitView)), findsOneWidget);
      expect(find.byKey(const ValueKey('blizzard_bottom_dock_tab_0')), findsNothing);
      expect(find.descendant(of: nativeDock, matching: find.byType(AnimatedContainer)), findsNothing);
      // Flutter owns routing state only. XCTest verifies the UIKit dock's
      // Reduce Motion behavior because MediaQuery cannot prove native timing.
    }
    await accessible.close(tester);
  });
}

class _SurfaceProxiesSpy extends SurfaceProxies {
  _SurfaceProxiesSpy(super.initial);

  final delayTests = <String>[];

  @override
  Future<void> urlTest(String groupTag) async {
    delayTests.add(groupTag);
  }
}
