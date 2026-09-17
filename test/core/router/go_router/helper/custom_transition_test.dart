import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/router/go_router/helper/custom_transition.dart';

void main() {
  testWidgets('keeps the slide transition when reduced motion is disabled', (tester) async {
    final homeFocusNode = FocusNode();
    final detailFocusNode = FocusNode();
    addTearDown(homeFocusNode.dispose);
    addTearDown(detailFocusNode.dispose);

    await tester.pumpWidget(
      _TransitionApp(
        mediaQueryData: const MediaQueryData(),
        homeFocusNode: homeFocusNode,
        detailFocusNode: detailFocusNode,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(_openRouteKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(_fullPageSlideTransitions, findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(_detailRouteKey), findsOneWidget);
    expect(detailFocusNode.hasFocus, isTrue);

    await tester.tap(find.byKey(_closeRouteKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_homeRouteKey), findsOneWidget);
    expect(find.byKey(_detailRouteKey), findsNothing);
    expect(homeFocusNode.hasFocus, isTrue);
  });

  for (final mediaQueryData in const [
    MediaQueryData(disableAnimations: true),
    MediaQueryData(accessibleNavigation: true),
  ]) {
    testWidgets('removes the slide transition for reduced motion $mediaQueryData', (tester) async {
      final homeFocusNode = FocusNode();
      final detailFocusNode = FocusNode();
      addTearDown(homeFocusNode.dispose);
      addTearDown(detailFocusNode.dispose);

      await tester.pumpWidget(
        _TransitionApp(mediaQueryData: mediaQueryData, homeFocusNode: homeFocusNode, detailFocusNode: detailFocusNode),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_openRouteKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(_fullPageSlideTransitions, findsNothing);
      expect(find.byKey(_detailRouteKey), findsOneWidget);
      await tester.pumpAndSettle();
      expect(detailFocusNode.hasFocus, isTrue);

      await tester.tap(find.byKey(_closeRouteKey));
      await tester.pumpAndSettle();
      expect(find.byKey(_homeRouteKey), findsOneWidget);
      expect(find.byKey(_detailRouteKey), findsNothing);
      expect(homeFocusNode.hasFocus, isTrue);
    });
  }
}

const _homeRouteKey = ValueKey('home-route');
const _detailRouteKey = ValueKey('detail-route');
const _openRouteKey = ValueKey('open-route');
const _closeRouteKey = ValueKey('close-route');

final _fullPageSlideTransitions = find.byWidgetPredicate(
  (widget) => widget is SlideTransition && widget.position.value.dx.abs() > 0.5,
  description: 'full-page SlideTransition',
);

class _TransitionApp extends StatelessWidget {
  const _TransitionApp({required this.mediaQueryData, required this.homeFocusNode, required this.detailFocusNode});

  final MediaQueryData mediaQueryData;
  final FocusNode homeFocusNode;
  final FocusNode detailFocusNode;

  @override
  Widget build(BuildContext context) => MaterialApp(
    builder: (context, child) => MediaQuery(data: mediaQueryData, child: child!),
    home: Scaffold(
      key: _homeRouteKey,
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            key: _openRouteKey,
            focusNode: homeFocusNode,
            autofocus: true,
            onPressed: () {
              final page = customTransition(
                TransitionType.slide,
                const ValueKey('detail-page'),
                Scaffold(
                  key: _detailRouteKey,
                  body: Center(
                    child: TextButton(
                      key: _closeRouteKey,
                      focusNode: detailFocusNode,
                      autofocus: true,
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                ),
              );
              Navigator.of(context).push(page.createRoute(context));
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}
