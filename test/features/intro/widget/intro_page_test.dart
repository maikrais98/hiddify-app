import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
import 'package:hiddify/features/intro/widget/intro_page.dart';

void main() {
  Widget app() => MaterialApp(
    theme: ThemeData(
      colorScheme: const ColorScheme.dark(primary: NovaColors.ritualRed),
      extensions: const [NovaThemeData.dark],
    ),
    home: Scaffold(
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IntroInlineLink(
            key: const ValueKey('intro_link_terms'),
            text: 'Terms and conditions',
            focusNode: FocusNode(),
            onKeyEvent: (_, event) => event is KeyUpEvent ? KeyEventResult.handled : KeyEventResult.ignored,
            onActivate: () async {},
          ),
          IntroInlineLink(
            key: const ValueKey('intro_link_source'),
            text: 'Open Source',
            focusNode: FocusNode(),
            onKeyEvent: (_, event) => event is KeyUpEvent ? KeyEventResult.handled : KeyEventResult.ignored,
            onActivate: () async {},
          ),
          IntroInlineLink(
            key: const ValueKey('intro_link_license'),
            text: 'License',
            focusNode: FocusNode(),
            onKeyEvent: (_, event) => event is KeyUpEvent ? KeyEventResult.handled : KeyEventResult.ignored,
            onActivate: () async {},
          ),
        ],
      ),
    ),
  );

  Finder linkFinder(String key) => find.byKey(ValueKey(key));

  Color linkColor(WidgetTester tester, String key) {
    final text = tester.widget<Text>(find.descendant(of: linkFinder(key), matching: find.byType(Text)));
    return text.style!.color!;
  }

  BoxDecoration linkDecoration(WidgetTester tester, String key) {
    final decorated = tester.widget<DecoratedBox>(
      find.descendant(of: linkFinder(key), matching: find.byType(DecoratedBox)),
    );
    return decorated.decoration as BoxDecoration;
  }

  testWidgets('uses semantic link tokens across Intro inline link states', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('intro_link_terms')), findsOneWidget);
    expect(find.byKey(const ValueKey('intro_link_source')), findsOneWidget);
    expect(find.byKey(const ValueKey('intro_link_license')), findsOneWidget);
    expect(linkColor(tester, 'intro_link_terms'), NovaThemeData.dark.link);
    expect(linkColor(tester, 'intro_link_source'), NovaThemeData.dark.link);
    expect(linkColor(tester, 'intro_link_license'), NovaThemeData.dark.link);

    final sourceMouse = tester.widget<MouseRegion>(
      find.descendant(of: linkFinder('intro_link_source'), matching: find.byType(MouseRegion)),
    );
    sourceMouse.onEnter!(const PointerEnterEvent());
    await tester.pump();
    expect(linkColor(tester, 'intro_link_source'), NovaThemeData.dark.linkHover);

    final sourceGesture = tester.widget<GestureDetector>(
      find.descendant(of: linkFinder('intro_link_source'), matching: find.byType(GestureDetector)),
    );
    sourceGesture.onTapDown!(TapDownDetails());
    await tester.pump();
    expect(linkColor(tester, 'intro_link_source'), NovaThemeData.dark.linkPressed);
    sourceGesture.onTapUp!(TapUpDetails(kind: PointerDeviceKind.mouse));
    await tester.pump();
    expect(linkColor(tester, 'intro_link_source'), NovaThemeData.dark.linkHover);

    final termsFocus = find.descendant(of: linkFinder('intro_link_terms'), matching: find.byType(Focus));
    expect(termsFocus, findsOneWidget);
    tester.widget<Focus>(termsFocus).focusNode!.requestFocus();
    await tester.pumpAndSettle();

    expect(linkColor(tester, 'intro_link_terms'), NovaThemeData.dark.focusRing);
    expect(linkDecoration(tester, 'intro_link_terms').border!.top.color, NovaThemeData.dark.focusRing);
  });
}
