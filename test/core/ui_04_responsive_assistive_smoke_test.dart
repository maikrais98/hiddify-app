import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/router/adaptive_layout/nova_tab_route.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
import 'package:hiddify/core/widget/nova_glass_tab_bar.dart';
import 'package:hiddify/features/home/widget/home_page.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _dockLabels = <NovaTab, String>{
  NovaTab.home: 'Главная',
  NovaTab.servers: 'Серверы',
  NovaTab.rules: 'Правила',
  NovaTab.settings: 'Настройки',
};

Widget _dockFixture({
  required Size size,
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
  Map<NovaTab, String> labels = _dockLabels,
  EdgeInsets viewInsets = EdgeInsets.zero,
  ValueChanged<NovaTab>? onSelected,
  bool showTextField = false,
}) {
  return MaterialApp(
    theme: ThemeData(extensions: const [NovaThemeData.dark]),
    home: MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale), viewInsets: viewInsets),
      child: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: Stack(
            children: [
              if (showTextField)
                const Align(
                  alignment: Alignment.topCenter,
                  child: TextField(key: ValueKey('ui04_keyboard_field'), autofocus: true),
                ),
              NovaGlassTabBar(selected: NovaTab.home, labels: labels, onSelected: onSelected ?? (_) {}),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('server card preserves long metadata at the narrow large-text boundary', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const longName = 'Private access server with a deliberately long name';
    const longSubtitle = 'Very long city and transport description';
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [NovaThemeData.dark]),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: NovaServerCard(
                profile: null,
                proxy: OutboundInfo(tag: longName, type: longSubtitle, tagDisplay: longName),
                addProfileLabel: 'Add access',
                profilesLabel: 'Profiles',
                errorLabel: 'Failed to load',
                isLoading: false,
                hasError: false,
                onTap: null,
              ),
            ),
          ),
        ),
      ),
    );

    final title = tester.widget<Text>(find.text(longName));
    final subtitle = tester.widget<Text>(find.text(longSubtitle));
    expect(title.maxLines == null || title.maxLines! > 1, isTrue);
    expect(subtitle.maxLines == null || subtitle.maxLines! > 1, isTrue);
    expect(title.overflow, isNot(TextOverflow.ellipsis));
    expect(subtitle.overflow, isNot(TextOverflow.ellipsis));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dock labels remain readable across compact widths and text scales', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final size in const [Size(320, 568), Size(393, 852)]) {
      for (final textScale in const [1.0, 1.5, 2.0]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(_dockFixture(size: size, textScale: textScale));

        for (final entry in _dockLabels.entries) {
          final label = entry.value;
          final text = find.text(label);
          expect(text, findsOneWidget);
          final paragraph = tester.renderObject<RenderParagraph>(text);
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: '$label is clipped at ${size.width}px and ${textScale}x text',
          );
          final fitted = find.ancestor(of: text, matching: find.byType(FittedBox));
          if (textScale > 1.25) {
            expect(fitted, findsNothing, reason: '$label must retain Dynamic Type size at ${textScale}x text');
            final paragraph = tester.renderObject<RenderParagraph>(text);
            expect(paragraph.textScaler.scale(11), greaterThan(11));
          } else {
            expect(fitted, findsOneWidget);
            final itemRect = tester.getRect(find.byKey(ValueKey('nova_tab_${entry.key.name}')));
            expect(
              tester.getSize(fitted).width,
              lessThanOrEqualTo(itemRect.width),
              reason: '$label layout exceeds its dock item at ${size.width}px and ${textScale}x text',
            );
          }
        }
        expect(tester.takeException(), isNull, reason: '$size at ${textScale}x text');
      }
    }
  });

  testWidgets('stats remain readable at 200% text scale on a 320px viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [NovaThemeData.dark]),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: NovaStatsGrid(
              stats: AsyncData(SystemInfo.create()),
              delay: 42,
              downlinkLabel: 'Скорость загрузки',
              uplinkLabel: 'Скорость отправки',
              delayLabel: 'Задержка сервера',
              trafficLabel: 'Передано данных',
              loadingLabel: 'Обновляем данные',
              unavailableLabel: 'Данные недоступны',
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('stats state copy wraps at 200% text scale', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const longStateLabel = 'Статистика временно недоступна, попробуйте повторить запрос позже';

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [NovaThemeData.dark]),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: NovaStatsGrid(
              stats: AsyncError<SystemInfo>(Object(), StackTrace.current),
              delay: 42,
              downlinkLabel: 'Скорость загрузки',
              uplinkLabel: 'Скорость отправки',
              delayLabel: 'Задержка сервера',
              trafficLabel: 'Передано данных',
              loadingLabel: longStateLabel,
              unavailableLabel: longStateLabel,
            ),
          ),
        ),
      ),
    );

    final stateText = tester.widget<Text>(find.text(longStateLabel));
    expect(stateText.maxLines, isNull);
    expect(stateText.overflow, isNot(TextOverflow.ellipsis));
    expect(tester.renderObject<RenderParagraph>(find.text(longStateLabel)).didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('actionable server card exposes one combined semantics control', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const title = 'Private access server';
    const subtitle = 'Long transport description';

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [NovaThemeData.dark]),
        home: Scaffold(
          body: NovaServerCard(
            profile: null,
            proxy: OutboundInfo(tag: title, type: subtitle, tagDisplay: title),
            addProfileLabel: 'Add access',
            profilesLabel: 'Profiles',
            errorLabel: 'Failed to load',
            isLoading: false,
            hasError: false,
            onTap: () {},
          ),
        ),
      ),
    );

    final semantics = tester.ensureSemantics();
    final card = find.bySemanticsLabel('$title, $subtitle');
    expect(card, findsOneWidget);
    final data = tester.getSemantics(card).getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();
  });

  testWidgets('content smoke covers requested viewports and text scales without clipping', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const longName = 'Private access server with a deliberately long name';
    const longSubtitle = 'Very long city and transport description';

    for (final size in const [Size(320, 568), Size(393, 852), Size(600, 1024), Size(1024, 768), Size(852, 393)]) {
      for (final textScale in const [1.0, 1.5, 2.0]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(extensions: const [NovaThemeData.dark]),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    NovaServerCard(
                      profile: null,
                      proxy: OutboundInfo(tag: longName, type: longSubtitle, tagDisplay: longName),
                      addProfileLabel: 'Add access',
                      profilesLabel: 'Profiles',
                      errorLabel: 'Failed to load',
                      isLoading: false,
                      hasError: false,
                      onTap: null,
                    ),
                    NovaStatsGrid(
                      stats: AsyncData(SystemInfo.create()),
                      delay: 42,
                      downlinkLabel: 'Скорость загрузки',
                      uplinkLabel: 'Скорость отправки',
                      delayLabel: 'Задержка сервера',
                      trafficLabel: 'Передано данных',
                      loadingLabel: 'Обновляем данные',
                      unavailableLabel: 'Данные недоступны',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        expect(tester.renderObject<RenderParagraph>(find.text(longName)).didExceedMaxLines, isFalse);
        expect(tester.renderObject<RenderParagraph>(find.text(longSubtitle)).didExceedMaxLines, isFalse);
        expect(tester.takeException(), isNull, reason: '$size at ${textScale}x text');
      }
    }
  });

  testWidgets('dock keeps all destinations in RTL semantics and supports keyboard focus', (tester) async {
    const rtlLabels = <NovaTab, String>{
      NovaTab.home: 'الرئيسية',
      NovaTab.servers: 'الخوادم',
      NovaTab.rules: 'القواعد',
      NovaTab.settings: 'الإعدادات',
    };
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    final selections = <NovaTab>[];
    await tester.pumpWidget(
      _dockFixture(
        size: const Size(320, 568),
        textScale: 2,
        direction: TextDirection.rtl,
        labels: rtlLabels,
        onSelected: selections.add,
      ),
    );

    for (final entry in rtlLabels.entries) {
      final label = entry.value;
      final target = find.bySemanticsLabel(label);
      expect(target, findsOneWidget);
      final data = tester.getSemantics(target).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(tester.getSize(target).shortestSide, greaterThanOrEqualTo(44));
      final text = find.text(label);
      final fitted = find.ancestor(of: text, matching: find.byType(FittedBox));
      expect(fitted, findsNothing, reason: '$label must retain Dynamic Type size at 2x text');
      final paragraph = tester.renderObject<RenderParagraph>(text);
      expect(paragraph.textScaler.scale(11), greaterThan(11));
    }
    expect(tester.getSemantics(find.bySemanticsLabel('الرئيسية')).flagsCollection.isSelected, Tristate.isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    final focused = find.byElementPredicate(
      (element) => identical(element, FocusManager.instance.primaryFocus?.context),
    );
    expect(find.ancestor(of: focused, matching: find.byKey(const ValueKey('nova_tab_home'))), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selections, [NovaTab.home]);
    semantics.dispose();
  });

  testWidgets('dock clears a software keyboard inset', (tester) async {
    const keyboardInset = 300.0;
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _dockFixture(
        size: const Size(393, 852),
        viewInsets: const EdgeInsets.only(bottom: keyboardInset),
        showTextField: true,
      ),
    );

    expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);
    final dock = tester.getRect(find.byKey(const ValueKey('nova_dock_surface')));
    expect(dock.bottom, lessThanOrEqualTo(852 - keyboardInset));
  });

  testWidgets('breakpoints cover compact, tablet, desktop, and landscape widths', (tester) async {
    for (final entry in <({Size size, Breakpoints breakpoint})>[
      (size: const Size(320, 568), breakpoint: Breakpoints.mobile),
      (size: const Size(393, 852), breakpoint: Breakpoints.mobile),
      (size: const Size(600, 1024), breakpoint: Breakpoints.tablet),
      (size: const Size(1024, 768), breakpoint: Breakpoints.desktop),
      (size: const Size(852, 393), breakpoint: Breakpoints.desktop),
    ]) {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: entry.size),
          child: MaterialApp(home: Builder(builder: (context) => Text(Breakpoint(context).activeBreakpoint.name))),
        ),
      );
      expect(find.text(entry.breakpoint.name), findsOneWidget, reason: '${entry.size} breakpoint');
    }
  });
}
