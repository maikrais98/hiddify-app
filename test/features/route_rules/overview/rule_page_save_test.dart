import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/route_rules/notifier/rule_notifier.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/features/route_rules/overview/rule_page.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets('failed explicit save keeps the draft and retry leaves only after persistence succeeds', (tester) async {
    final harness = await _RulePageHarness.pump(tester);

    harness.editName('Draft');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.check));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(RulePage), findsOneWidget);
    expect(find.text('Unsaved rule'), findsOneWidget);
    expect(find.text('Retry save'), findsOneWidget);
    expect(find.text('Stay'), findsOneWidget);
    expect(find.text('Exit without saving'), findsOneWidget);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.check)).onPressed, isNull);
    expect(harness.container.read(ruleNotifierProvider(null)).name, 'Draft');
    expect(harness.container.read(IsRuleEditedProvider(null)), isTrue);
    expect(harness.container.read(rulesNotifierProvider), isEmpty);

    harness.allowSaves();
    await tester.tap(find.text('Retry save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Rule editor home'), findsOneWidget);
    expect(harness.container.read(rulesNotifierProvider), hasLength(1));
    expect(harness.container.read(rulesNotifierProvider).single.name, 'Draft');
  });

  testWidgets('stay preserves the draft while explicit discard leaves without persistence', (tester) async {
    final harness = await _RulePageHarness.pump(tester);

    harness.editName('Draft');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.check));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Stay'));
    await tester.pump();

    expect(find.text('Unsaved rule'), findsNothing);
    expect(harness.container.read(ruleNotifierProvider(null)).name, 'Draft');
    expect(harness.container.read(IsRuleEditedProvider(null)), isTrue);

    await tester.tap(find.byIcon(Icons.check));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Exit without saving'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Rule editor home'), findsOneWidget);
    expect(harness.container.read(rulesNotifierProvider), isEmpty);
  });
}

class _RulePageHarness {
  _RulePageHarness(this.container, this.router, this.rulesSubscription);

  final ProviderContainer container;
  final GoRouter router;
  final ProviderSubscription<List<Rule>> rulesSubscription;

  static Future<_RulePageHarness> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final translations = await AppLocale.en.build();
    final container = ProviderContainer(
      overrides: [
        translationsProvider.overrideWith((ref) => translations),
        rulesNotifierProvider.overrideWith(_TestRulesNotifier.new),
      ],
    );
    final rulesSubscription = container.listen(rulesNotifierProvider, (_, _) {}, fireImmediately: true);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: TextButton(onPressed: () => context.push('/rule'), child: const Text('Rule editor home')),
          ),
        ),
        GoRoute(path: '/rule', builder: (context, state) => const RulePage()),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('Rule editor home'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final harness = _RulePageHarness(container, router, rulesSubscription);
    addTearDown(harness.dispose);
    return harness;
  }

  void editName(String name) {
    container.read(ruleNotifierProvider(null).notifier).update<String>(RuleEnum.name, name);
  }

  void allowSaves() => (container.read(rulesNotifierProvider.notifier) as _TestRulesNotifier).failWrites = false;

  void dispose() {
    rulesSubscription.close();
    router.dispose();
    container.dispose();
  }
}

class _TestRulesNotifier extends RulesNotifier {
  bool failWrites = true;

  @override
  List<Rule> build() => [];

  @override
  Future<Rule> addRule(Rule rule) async {
    if (failWrites) throw StateError('write failed');
    final saved = rule.deepCopy()
      ..listOrder = state.length
      ..enabled = true;
    state = [...state, saved];
    return saved.deepCopy();
  }

  @override
  Future<Rule> updateRule(Rule rule) async {
    if (failWrites) throw StateError('update failed');
    final index = state.indexWhere((item) => item.listOrder == rule.listOrder);
    if (index == -1) throw StateError('missing rule');
    final saved = rule.deepCopy();
    state = state.toList()..[index] = saved;
    return saved.deepCopy();
  }
}
