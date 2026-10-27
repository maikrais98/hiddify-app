import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/overview/profiles_modal.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';

import '../support/home_fixture.dart';

Widget _applied(Widget child) => Builder(
  builder: (context) => Theme(data: BlizzardTheme.from(Theme.of(context)), child: child),
);

Finder _dragHandle() => find.descendant(
  of: find.byType(ProfilesModal),
  matching: find.byWidgetPredicate(
    (widget) => widget is SizedBox && widget.width == 32 && widget.height == 4,
    description: '32 by 4 Profiles drag handle',
  ),
);

double _sheetHeight(WidgetTester tester) {
  final surface = find.descendant(of: find.byType(ProfilesModal), matching: find.byType(ColoredBox)).first;
  return tester.getSize(surface).height;
}

Future<_ProfilesSheetFixture> _openProfilesSheet(WidgetTester tester) async {
  tester.view.physicalSize = const Size(440, 956);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final profiles = TileProfilesSpy()
    ..profiles = [
      ProfileEntity.remote(
        id: 'first-subscription',
        active: true,
        name: 'First subscription',
        url: 'https://example.invalid/first',
        lastUpdate: DateTime.utc(2026),
      ),
      ProfileEntity.remote(
        id: 'second-subscription',
        active: false,
        name: 'Second subscription',
        url: 'https://example.invalid/second',
        lastUpdate: DateTime.utc(2026),
      ),
    ];
  Future<void>? shown;
  final fixture = await mountHomeFixture(
    tester,
    width: 440,
    height: 956,
    nativeViewport: true,
    extraOverrides: [profilesNotifierProvider.overrideWith(() => profiles)],
    child: Builder(
      builder: (context) => TextButton(
        key: const ValueKey('open_profiles_modal'),
        onPressed: () {
          shown = Navigator.of(context, rootNavigator: true).push<void>(
            ModalBottomSheetRoute(
              constraints: BottomSheetConst.boxConstraints,
              isScrollControlled: true,
              builder: (context) => Material(child: _applied(const ProfilesModal())),
            ),
          );
        },
        child: const Text('open profiles'),
      ),
    ),
  );

  await tester.tap(find.byKey(const ValueKey('open_profiles_modal')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));

  expect(tester.takeException(), isNull);
  expect(find.byType(ProfilesModal), findsOneWidget);
  return _ProfilesSheetFixture(fixture, () => shown);
}

class _ProfilesSheetFixture {
  const _ProfilesSheetFixture(this.home, this.shown);

  final HomeFixture home;
  final Future<void>? Function() shown;

  Future<void> close(WidgetTester tester) async {
    if (find.byType(ProfilesModal).evaluate().isNotEmpty) {
      Navigator.of(tester.element(find.byType(ProfilesModal))).pop();
      await tester.pumpAndSettle();
    }
    await shown();
    await home.close(tester);
  }
}

void main() {
  testWidgets('Profiles sheet stays open and reveals the next subscription after an upward drag on iPhone 16 Pro Max', (
    tester,
  ) async {
    final fixture = await _openProfilesSheet(tester);

    expect(_sheetHeight(tester), closeTo(223, 0.01));
    final compactViewportHeight = tester.getSize(find.byType(ListView)).height;

    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(ProfilesModal), findsOneWidget);
    expect(tester.getSize(find.byType(ListView)).height, greaterThan(compactViewportHeight));
    expect(find.text('Second subscription').hitTestable(), findsOneWidget);

    await fixture.close(tester);
  });

  for (final dragSource in <String, Finder Function()>{
    'title': () => find.text('Profiles'),
    'handle': _dragHandle,
  }.entries) {
    testWidgets('upward drag starting on the Profiles ${dragSource.key} expands the sheet', (tester) async {
      final fixture = await _openProfilesSheet(tester);
      final compactHeight = _sheetHeight(tester);

      expect(compactHeight, closeTo(223, 0.01));
      expect(dragSource.value(), findsOneWidget);

      await tester.dragFrom(tester.getCenter(dragSource.value()), const Offset(0, -261));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ProfilesModal), findsOneWidget);
      expect(_sheetHeight(tester), greaterThan(compactHeight));
      expect(find.text('Second subscription').hitTestable(), findsOneWidget);

      await fixture.close(tester);
    });
  }

  testWidgets('downward drag starting on the Profiles title contracts an expanded sheet', (tester) async {
    final fixture = await _openProfilesSheet(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final expandedHeight = _sheetHeight(tester);

    await tester.drag(find.text('Profiles'), const Offset(0, 180));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final modalDismissed = find.byType(ProfilesModal).evaluate().isEmpty;
    expect(modalDismissed || _sheetHeight(tester) < expandedHeight, isTrue);

    await fixture.close(tester);
  });
}
