import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/dialog/widgets/warp_license_dialog.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/features/intro/widget/intro_page.dart';
import 'package:hiddify/features/profile/details/json_editor.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../support/home_fixture.dart';

Widget _appliedLuma(Widget child) => Builder(
  builder: (context) => Theme(data: BlizzardTheme.from(Theme.of(context)), child: child),
);

Iterable<TextSpan> _recognizedSpans(InlineSpan span) sync* {
  if (span is! TextSpan) return;
  if (span.recognizer != null) yield span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* _recognizedSpans(child);
  }
}

List<TextSpan> _linksWithin(WidgetTester tester, Finder owner) => tester
    .widgetList<RichText>(find.descendant(of: owner, matching: find.byType(RichText)))
    .expand((richText) => _recognizedSpans(richText.text))
    .toList();

List<FocusNode> _explicitFocusNodes(WidgetTester tester, Finder owner) => tester
    .widgetList<Focus>(
      find.descendant(
        of: owner,
        matching: find.byWidgetPredicate(
          (widget) => widget is Focus && widget.focusNode != null && widget.onKeyEvent != null,
        ),
      ),
    )
    .map((focus) => focus.focusNode!)
    .toList();

List<BorderSide> _twoPointBorders(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.descendant(of: find.byType(JsonEditor), matching: find.byType(DecoratedBox)))
    .where((box) => box.decoration is BoxDecoration)
    .expand((box) {
      final border = (box.decoration as BoxDecoration).border;
      if (border is! Border) return const <BorderSide>[];
      return [border.top, border.right, border.bottom, border.left];
    })
    .where((side) => side.width == 2)
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final active in [true, false]) {
    testWidgets('JSON invalid borders use ${active ? "scoped luma error" : "legacy red"} without losing draft', (
      tester,
    ) async {
      final changes = <dynamic>[];
      final appTheme = AppTheme(active ? AppThemeMode.dark : AppThemeMode.light, 'BlizzardFixture');
      final theme = active ? BlizzardTheme.from(appTheme.darkTheme(null)) : appTheme.lightTheme(null);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: JsonEditor(
              json: '{"name":"initial"}',
              editors: const [Editors.text],
              duration: const Duration(milliseconds: 1),
              onChanged: changes.add,
            ),
          ),
        ),
      );

      final field = find.byType(TextField).last;
      await tester.tap(field);
      await tester.enterText(field, '{"name":');
      await tester.pump(const Duration(milliseconds: 2));
      final invalid = tester.widget<EditableText>(find.byType(EditableText).last);
      final invalidBorders = _twoPointBorders(tester);
      final expectedError = active ? theme.colorScheme.error : Colors.red;
      expect(invalidBorders, isNotEmpty);
      expect(invalidBorders.map((side) => side.color).toSet(), {expectedError});
      expect(changes, isEmpty);
      expect(invalid.focusNode.hasFocus, isTrue);
      expect(invalid.controller.text, '{"name":');

      await tester.enterText(field, '{"name":"corrected"}');
      await tester.pump(const Duration(milliseconds: 2));
      final corrected = tester.widget<EditableText>(find.byType(EditableText).last);
      expect(corrected.controller, same(invalid.controller));
      expect(corrected.focusNode, same(invalid.focusNode));
      expect(corrected.focusNode.hasFocus, isTrue);
      expect(corrected.controller.text, '{"name":"corrected"}');
      expect(changes, [
        {'name': 'corrected'},
      ]);
      expect(_twoPointBorders(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final active in [true, false]) {
    testWidgets('WARP links keep ${active ? "luma primary and underline" : "legacy blue and green"} focus styling', (
      tester,
    ) async {
      bool? decision;
      final fixture = await mountHomeFixture(
        tester,
        mode: active ? AppThemeMode.dark : AppThemeMode.light,
        child: active
            ? _appliedLuma(
                Builder(
                  builder: (context) => TextButton(
                    onPressed: () async {
                      decision = await showDialog<bool>(context: context, builder: (_) => const WarpLicenseDialog());
                    },
                    child: const Text('Open WARP'),
                  ),
                ),
              )
            : Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    decision = await showDialog<bool>(context: context, builder: (_) => const WarpLicenseDialog());
                  },
                  child: const Text('Open WARP'),
                ),
              ),
      );
      await tester.tap(find.text('Open WARP'));
      await tester.pumpAndSettle();

      final owner = find.byType(WarpLicenseDialog);
      var links = _linksWithin(tester, owner);
      expect(links, hasLength(2));
      expect(links.every((link) => link.recognizer is TapGestureRecognizer), isTrue);
      final linkTheme = Theme.of(tester.element(owner));
      final expectedColor = active ? linkTheme.colorScheme.primary : Colors.blue;
      expect(links.map((link) => link.style!.color).toSet(), {expectedColor});
      expect(links.every((link) => link.style!.decoration == null), isTrue);

      final focusNodes = _explicitFocusNodes(tester, owner);
      expect(focusNodes, hasLength(2));
      focusNodes.first.requestFocus();
      await tester.pumpAndSettle();
      expect(focusNodes.first.hasPrimaryFocus, isTrue);
      links = _linksWithin(tester, owner);
      expect(links.first.style!.color, active ? linkTheme.colorScheme.primary : Colors.green);
      expect(links.first.style!.decoration, active ? TextDecoration.underline : null);
      expect(links.last.style!.decoration, isNull);

      final t = fixture.container.read(translationsProvider).requireValue;
      await tester.tap(find.text(t.common.agree));
      await tester.pumpAndSettle();
      expect(decision, isTrue);

      await tester.tap(find.text('Open WARP'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.common.decline));
      await tester.pumpAndSettle();
      expect(decision, isFalse);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    });
  }

  for (final active in [true, false]) {
    testWidgets('Intro links keep ${active ? "luma primary and underline" : "legacy blue and green"} focus styling', (
      tester,
    ) async {
      final previous = IntroPage.locationInfoLoaded;
      IntroPage.locationInfoLoaded = true;
      addTearDown(() => IntroPage.locationInfoLoaded = previous);
      final fixture = await mountHomeFixture(
        tester,
        mode: active ? AppThemeMode.dark : AppThemeMode.light,
        child: active ? _appliedLuma(const IntroPage()) : const IntroPage(),
      );

      final owner = find.byType(IntroPage);
      var links = _linksWithin(tester, owner);
      expect(links, hasLength(3));
      expect(links.every((link) => link.recognizer is TapGestureRecognizer), isTrue);
      final linkTheme = Theme.of(tester.element(owner));
      final expectedColor = active ? linkTheme.colorScheme.primary : Colors.blue;
      expect(links.map((link) => link.style!.color).toSet(), {expectedColor});
      expect(links.every((link) => link.style!.decoration == null), isTrue);

      final focusNodes = _explicitFocusNodes(tester, owner);
      expect(focusNodes, hasLength(3));
      focusNodes[1].requestFocus();
      await tester.pumpAndSettle();
      expect(focusNodes[1].hasPrimaryFocus, isTrue);
      links = _linksWithin(tester, owner);
      expect(links.first.style!.decoration, isNull);
      for (final link in links.skip(1)) {
        expect(link.style!.color, active ? linkTheme.colorScheme.primary : Colors.green);
        expect(link.style!.decoration, active ? TextDecoration.underline : null);
      }
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    });
  }
}
