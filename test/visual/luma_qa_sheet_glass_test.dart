import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/bottom_sheets/widgets/quick_settings_modal.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_glass.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../support/home_fixture.dart';

Widget _underAurora(Widget child) => Builder(
  builder: (context) => Theme(data: BlizzardTheme.from(Theme.of(context)), child: child),
);

void main() {
  testWidgets('Quick Settings gives the service selector and WARP row independent native glass owners', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await mountHomeFixture(tester, child: _underAurora(const QuickSettingsModal()));

    final selector = find.byKey(const ValueKey('quick-settings-service-mode-glass'));
    final warp = find.byKey(const ValueKey('quick-settings-warp-glass'));
    expect(selector, findsOneWidget);
    expect(warp, findsOneWidget);
    expect(find.descendant(of: selector, matching: find.byType(UiKitView)), findsOneWidget);
    expect(find.descendant(of: warp, matching: find.byType(UiKitView)), findsOneWidget);
    expect(find.descendant(of: selector, matching: find.byType(BlizzardGlass)), findsOneWidget);
    expect(find.descendant(of: warp, matching: find.byType(BlizzardGlass)), findsOneWidget);

    final selectorMaterials = tester.widgetList<Material>(
      find.descendant(of: selector, matching: find.byType(Material)),
    );
    expect(
      selectorMaterials.any((material) => material.type == MaterialType.transparency),
      isTrue,
      reason: 'The segmented control content needs a clear Material boundary above native glass',
    );
    final segmented = tester.widget<SegmentedButton<ServiceMode>>(
      find.descendant(of: selector, matching: find.byType(SegmentedButton<ServiceMode>)),
    );
    expect(segmented.style!.backgroundColor!.resolve(<WidgetState>{}), Colors.transparent);
    expect(
      segmented.style!.backgroundColor!.resolve(<WidgetState>{WidgetState.selected})!.a,
      lessThan(1),
      reason: 'The selected tint must remain translucent instead of masking the group material',
    );
    final warpMaterials = tester.widgetList<Material>(find.descendant(of: warp, matching: find.byType(Material)));
    expect(
      warpMaterials.any((material) => material.type == MaterialType.transparency),
      isTrue,
      reason: 'The WARP row needs a clear Material boundary above native glass',
    );

    final beforeMode = fixture.container.read(ConfigOptions.serviceMode);
    final nextMode = ServiceMode.choices.firstWhere((mode) => mode != beforeMode);
    await tester.tap(find.text(nextMode.presentShort(fixture.container.read(translationsProvider).requireValue)));
    await tester.pump();
    expect(fixture.container.read(ConfigOptions.serviceMode), nextMode);

    final beforeWarp = fixture.container.read(ConfigOptions.enableWarp);
    await tester.tap(find.descendant(of: warp, matching: find.byType(ListTile)));
    await tester.pump();
    expect(fixture.container.read(ConfigOptions.enableWarp), !beforeWarp);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
    await fixture.close(tester);
  });

  testWidgets('Settings overflow opens one native glass popup and keeps the import submenu interactive', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await mountHomeFixture(tester, child: _underAurora(SettingsPage()));
    final t = fixture.container.read(translationsProvider).requireValue;
    final overflow = find.descendant(of: find.byType(MenuAnchor), matching: find.byType(IconButton));

    expect(find.byType(UiKitView), findsOneWidget, reason: 'Only the overflow button owns glass while closed');
    await tester.tap(overflow);
    await tester.pumpAndSettle();

    final popup = find.byKey(const ValueKey('settings-overflow-menu-glass'));
    expect(popup, findsOneWidget);
    expect(find.descendant(of: popup, matching: find.byType(UiKitView)), findsOneWidget);
    expect(find.byType(UiKitView), findsNWidgets(2), reason: 'The popup is one surface, not per-item glass');
    final popupMaterials = tester.widgetList<Material>(find.descendant(of: popup, matching: find.byType(Material)));
    expect(
      popupMaterials.every(
        (material) => material.type == MaterialType.transparency || material.color == Colors.transparent,
      ),
      isTrue,
      reason: 'Flutter menu materials must not mask the native popup surface',
    );

    await tester.tap(find.text(t.common.import));
    await tester.pumpAndSettle();
    expect(find.text(t.pages.settings.options.import.clipboard), findsOneWidget);
    expect(find.text(t.pages.settings.options.import.file), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
    await fixture.close(tester);
  });

  testWidgets('Quick Settings owns the sheet glass surface and preserves dismissal', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    Future<void>? shown;
    late final HomeFixture fixture;
    fixture = await mountHomeFixture(
      tester,
      nativeViewport: true,
      child: Builder(
        builder: (context) => TextButton(
          key: const ValueKey('open-quick-settings'),
          onPressed: () {
            shown = fixture.container.read(bottomSheetsNotifierProvider.notifier).showQuickSettings();
          },
          child: const Text('open quick settings'),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-quick-settings')));
    await tester.pumpAndSettle();

    final modal = find.byType(QuickSettingsModal);
    expect(modal, findsOneWidget);
    expect(tester.takeException(), isNull);

    final surface = find.descendant(of: modal, matching: find.byType(ColoredBox));
    expect(surface, findsOneWidget);
    expect(tester.widget<ColoredBox>(surface).color, Colors.transparent);

    tester.view.viewInsets = const FakeViewPadding(bottom: 120);
    await tester.pump();
    expect(
      find.ancestor(
        of: modal,
        matching: find.byWidgetPredicate(
          (widget) => widget is Padding && widget.padding == const EdgeInsets.only(bottom: 120),
        ),
      ),
      findsOneWidget,
    );

    final glass = find.byType(BlizzardGlass);
    if (Platform.isIOS) {
      expect(glass, findsOneWidget);
      expect(find.byType(UiKitView), findsOneWidget);
      final native = tester.widget<UiKitView>(find.byType(UiKitView));
      expect(native.viewType, 'app.blizzard/native-liquid-glass');
      expect(native.creationParams, {'radius': 32.0, 'lens': false});
      expect(find.ancestor(of: find.byType(UiKitView), matching: find.byType(ClipRRect)), findsNothing);
      expect(find.ancestor(of: glass, matching: find.byType(ClipRRect)), findsNothing);
      final innerMaterial = find.descendant(of: glass, matching: find.byType(Material));
      expect(innerMaterial, findsOneWidget);
      expect(tester.widget<Material>(innerMaterial).type, MaterialType.transparency);
    } else {
      expect(glass, findsNothing);
    }

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await shown;
    expect(modal, findsNothing);
    expect(find.text('open quick settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });
}
