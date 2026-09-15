import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
import 'package:hiddify/features/home/widget/home_page.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/features/stats/widget/side_bar_stats_overview.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpGrid(WidgetTester tester, AsyncValue<SystemInfo> stats) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [NovaThemeData.dark]),
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: NovaStatsGrid(
              stats: stats,
              delay: 42,
              downlinkLabel: 'Downlink',
              uplinkLabel: 'Uplink',
              delayLabel: 'Delay',
              trafficLabel: 'Transferred',
              loadingLabel: 'Updating data',
              unavailableLabel: 'Data unavailable',
            ),
          ),
        ),
      ),
    );
  }

  List<String> textValues(WidgetTester tester) =>
      tester.widgetList<Text>(find.byType(Text)).map((widget) => widget.data).whereType<String>().toList();

  testWidgets('loading uses one state label and placeholders instead of formatted zero', (tester) async {
    final previous = SystemInfo(downlink: Int64(1024), uplink: Int64(2048), downlinkTotal: Int64(4096));
    final loading = const AsyncLoading<SystemInfo>().copyWithPrevious(AsyncData(previous));
    await pumpGrid(tester, loading);

    expect(find.text('Updating data'), findsOneWidget);
    expect(find.bySemanticsLabel('Updating data'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('—'), findsNWidgets(3));
    expect(textValues(tester).where((value) => value.endsWith('↓') || value.endsWith('↑')), isEmpty);
    expect(find.text('42 ms'), findsOneWidget);
  });

  testWidgets('error uses one unavailable label and placeholders instead of formatted zero', (tester) async {
    final previous = SystemInfo(downlink: Int64(1024), uplink: Int64(2048), downlinkTotal: Int64(4096));
    final error = AsyncError<SystemInfo>(
      StateError('stats failed'),
      StackTrace.empty,
    ).copyWithPrevious(AsyncData(previous));
    await pumpGrid(tester, error);

    expect(find.text('Data unavailable'), findsOneWidget);
    expect(find.bySemanticsLabel('Data unavailable'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('—'), findsNWidgets(3));
    expect(textValues(tester).where((value) => value.endsWith('↓') || value.endsWith('↑')), isEmpty);
    expect(find.text('42 ms'), findsOneWidget);
  });

  testWidgets('successful zero is rendered as a measured value', (tester) async {
    await pumpGrid(tester, AsyncData(SystemInfo.create()));

    final values = textValues(tester);
    expect(find.text('Updating data'), findsNothing);
    expect(find.text('Data unavailable'), findsNothing);
    expect(find.text('—'), findsNothing);
    expect(values.singleWhere((value) => value.endsWith('↓')), startsWith('0'));
    expect(values.singleWhere((value) => value.endsWith('↑')), startsWith('0'));
    expect(values.where((value) => value.startsWith('0')).length, greaterThanOrEqualTo(3));
  });

  testWidgets('successful nonzero is rendered without an availability label', (tester) async {
    final stats = SystemInfo(
      downlink: Int64(1024),
      uplink: Int64(2048),
      downlinkTotal: Int64(4096),
      uplinkTotal: Int64(8192),
    );
    await pumpGrid(tester, AsyncData(stats));

    final values = textValues(tester);
    expect(find.text('Updating data'), findsNothing);
    expect(find.text('Data unavailable'), findsNothing);
    expect(find.text('—'), findsNothing);
    expect(values.singleWhere((value) => value.endsWith('↓')), isNot(startsWith('0')));
    expect(values.singleWhere((value) => value.endsWith('↑')), isNot(startsWith('0')));
  });

  testWidgets('sidebar keeps one unavailable state in collapsed and expanded layouts', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final translations = await AppLocale.en.build();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWith((ref) => translations),
          sharedPreferencesProvider.overrideWith((ref) => preferences),
          statsNotifierProvider.overrideWith(() => _TestStatsNotifier(Stream.error(StateError('stats failed')))),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SizedBox(width: 320, child: SideBarStatsOverview())),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Data unavailable'), findsOneWidget);
    expect(find.bySemanticsLabel('Data unavailable'), findsOneWidget);
    expect(textValues(tester).where((value) => value.startsWith('0')), isEmpty);

    await tester.tap(find.byWidgetPredicate((widget) => widget is TextButton));
    await tester.pumpAndSettle();

    expect(find.text('Data unavailable'), findsOneWidget);
    expect(find.bySemanticsLabel('Data unavailable'), findsOneWidget);
    expect(textValues(tester).where((value) => value.startsWith('0')), isEmpty);
  });
}

class _TestStatsNotifier extends StatsNotifier {
  _TestStatsNotifier(this.events);

  final Stream<SystemInfo> events;

  @override
  Stream<SystemInfo> build() => events;
}
