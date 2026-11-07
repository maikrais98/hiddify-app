import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_native_connection_control.dart';
import 'package:hiddify/features/chain/overview/chain_mode_button.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/settings/overview/sections/chain_options_page.dart';
import 'package:hiddify/features/settings/overview/sections/dns_options_page.dart';
import 'package:hiddify/features/settings/overview/sections/general_page.dart';
import 'package:hiddify/features/settings/overview/sections/inbound_options_page.dart';
import 'package:hiddify/features/settings/overview/sections/routing_options_page.dart';
import 'package:hiddify/features/settings/overview/sections/tls_tricks_page.dart';

import '../support/blizzard_connection_fixture_action.dart';
import '../support/blizzard_motion_contract.dart';
import '../support/blizzard_visual_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerBlizzardAccessibilityContracts();
}

void registerBlizzardAccessibilityContracts() {
  registerBlizzardMotionContracts();
  for (final width in [320.0, 393.0, 430.0]) {
    for (final locale in [AppLocale.en, AppLocale.ru, AppLocale.fa]) {
      for (final child in [
        const GeneralPage(),
        const ChainOptionsPage(),
        const DnsOptionsPage(),
        const InboundOptionsPage(),
        const RoutingOptionsPage(routeRule: null),
        const TlsTricksPage(),
      ]) {
        testWidgets('readable ${child.runtimeType} ${locale.name} $width with enlarged text', (tester) async {
          final fixture = await mountVisualFixture(
            tester,
            child: child,
            width: width,
            scale: 1.3,
            locale: locale,
            direction: locale == AppLocale.fa ? TextDirection.rtl : TextDirection.ltr,
            highContrast: true,
            disableAnimations: true,
          );
          if (child is ChainOptionsPage) {
            expect(find.byType(ChainModeButton), findsNWidgets(2));
            for (final control in tester.widgetList<ChainModeButton>(find.byType(ChainModeButton))) {
              expect(tester.getSize(find.byWidget(control)).shortestSide, greaterThanOrEqualTo(44));
            }
          } else {
            expect(find.byType(ListTile), findsWidgets);
          }
          for (final target in tester.widgetList<IconButton>(find.byType(IconButton))) {
            if (target.onPressed != null) {
              final size = tester.getSize(find.byWidget(target));
              expect(size.width, greaterThanOrEqualTo(44));
              expect(size.height, greaterThanOrEqualTo(44));
            }
          }
          expect(fixture.events, isEmpty);
          expect(tester.takeException(), isNull);
          await fixture.close(tester);
        });
      }
    }
  }
  testWidgets('primary action semantics and hit area survive accessible appearance', (tester) async {
    final semantics = tester.ensureSemantics();
    final fixture = await mountVisualFixture(tester, highContrast: true, disableAnimations: true);
    final button = find.byKey(const ValueKey('home_connection_button'));
    expect(tester.getSize(button).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
    final t = AppLocale.en.buildSync();
    final label = expectsBlizzard(AppThemeMode.dark, Brightness.dark, 393)
        ? t.connection.disconnect
        : t.connection.connected;
    final native = find.byType(BlizzardNativeConnectionControl);
    if (native.evaluate().isNotEmpty) {
      final control = tester.widget<BlizzardNativeConnectionControl>(native);
      expect(control.label, label);
      expect(control.enabled, isTrue);
      expect(control.connectionState, 'connected');
      expect(find.descendant(of: native, matching: find.byType(UiKitView)), findsOneWidget);
      expect(
        tester
            .widgetList<Semantics>(find.descendant(of: native, matching: find.byType(Semantics)))
            .where((widget) => widget.properties.button == true),
        isEmpty,
        reason: 'the UIKit control is the sole accessibility owner of the primary action',
      );
    } else {
      expect(
        find.descendant(
          of: find.byType(ConnectionButton),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.button == true &&
                widget.properties.enabled == true &&
                widget.properties.label == label,
          ),
        ),
        findsOneWidget,
      );
    }
    await activateFixtureConnection(tester);
    expect(fixture.events, ['toggle']);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
    semantics.dispose();
  });
}
