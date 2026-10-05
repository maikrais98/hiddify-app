import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/settings/overview/sections/dns_options_page.dart';
import 'package:hiddify/features/settings/overview/sections/general_page.dart';
import 'package:hiddify/features/settings/overview/sections/inbound_options_page.dart';
import 'package:hiddify/features/settings/overview/sections/route_options_page.dart';
import 'package:hiddify/features/settings/overview/sections/tls_tricks_page.dart';
import 'package:hiddify/features/settings/overview/sections/warp_options_page.dart';

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
        const WarpOptionsPage(),
        const DnsOptionsPage(),
        const InboundOptionsPage(),
        const RouteOptionsPage(),
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
          expect(find.byType(ListTile), findsWidgets);
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
    expect(find.bySemanticsLabel(t.connection.connected), findsOneWidget);
    await tester.tap(button);
    await tester.pump();
    expect(fixture.events, ['toggle']);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
    semantics.dispose();
  });
}
