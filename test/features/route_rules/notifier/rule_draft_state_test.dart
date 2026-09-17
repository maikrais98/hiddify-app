import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/features/route_rules/notifier/rule_notifier.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('a new rule becomes dirty only after the draft changes', () async {
    final translations = await AppLocale.en.build();
    final container = ProviderContainer(overrides: [translationsProvider.overrideWith((ref) => translations)]);
    addTearDown(container.dispose);

    expect(container.read(IsRuleEditedProvider(null)), isFalse);

    final initialName = container.read(ruleNotifierProvider(null)).name;
    container.read(ruleNotifierProvider(null).notifier).update<String>(RuleEnum.name, 'Edited rule');
    expect(container.read(IsRuleEditedProvider(null)), isTrue);

    container.read(ruleNotifierProvider(null).notifier).update<String>(RuleEnum.name, initialName);
    expect(container.read(IsRuleEditedProvider(null)), isFalse);
  });

  test('a failed new-rule write keeps one dirty draft and retry persists it once', () async {
    final harness = await _RuleDraftHarness.create();
    addTearDown(harness.dispose);

    final draftSubscription = harness.container.listen(ruleNotifierProvider(null), (_, _) {}, fireImmediately: true);
    addTearDown(draftSubscription.close);
    harness.container.read(ruleNotifierProvider(null).notifier).update<String>(RuleEnum.name, 'Draft');
    await harness.blockRuleFile();

    expect(await harness.container.read(ruleNotifierProvider(null).notifier).save(), isFalse);
    expect(harness.container.read(rulesNotifierProvider), isEmpty);
    expect(harness.container.read(ruleNotifierProvider(null)).name, 'Draft');
    expect(harness.container.read(IsRuleEditedProvider(null)), isTrue);

    await harness.unblockRuleFile();
    expect(await harness.container.read(ruleNotifierProvider(null).notifier).save(), isTrue);
    expect(harness.container.read(rulesNotifierProvider), hasLength(1));
    expect(harness.container.read(rulesNotifierProvider).single.name, 'Draft');
    expect(harness.container.read(IsRuleEditedProvider(null)), isFalse);
  });

  test('a failed existing-rule update does not claim the runtime list was saved', () async {
    final initialRule = Rule(listOrder: 0, enabled: true, name: 'Original', outbound: Outbound.direct);
    final harness = await _RuleDraftHarness.create(initialRules: [initialRule]);
    addTearDown(harness.dispose);

    final draftSubscription = harness.container.listen(ruleNotifierProvider(0), (_, _) {}, fireImmediately: true);
    addTearDown(draftSubscription.close);
    harness.container.read(ruleNotifierProvider(0).notifier).update<String>(RuleEnum.name, 'Draft');
    await harness.blockRuleFile();

    expect(await harness.container.read(ruleNotifierProvider(0).notifier).save(), isFalse);
    expect(harness.container.read(rulesNotifierProvider).single.name, 'Original');
    expect(harness.container.read(ruleNotifierProvider(0)).name, 'Draft');
    expect(harness.container.read(IsRuleEditedProvider(0)), isTrue);

    await harness.unblockRuleFile();
    expect(await harness.container.read(ruleNotifierProvider(0).notifier).save(), isTrue);
    expect(harness.container.read(rulesNotifierProvider).single.name, 'Draft');
    expect(harness.container.read(IsRuleEditedProvider(0)), isFalse);
  });

  test('an edit made while saving remains as a dirty draft for the next save', () async {
    final translations = await AppLocale.en.build();
    final container = ProviderContainer(
      overrides: [
        translationsProvider.overrideWith((ref) => translations),
        rulesNotifierProvider.overrideWith(_ControlledRulesNotifier.new),
      ],
    );
    addTearDown(container.dispose);
    final rulesSubscription = container.listen(rulesNotifierProvider, (_, _) {}, fireImmediately: true);
    final draftSubscription = container.listen(ruleNotifierProvider(null), (_, _) {}, fireImmediately: true);
    addTearDown(rulesSubscription.close);
    addTearDown(draftSubscription.close);

    final draft = container.read(ruleNotifierProvider(null).notifier);
    draft.update<String>(RuleEnum.name, 'First edit');
    final firstSave = draft.save();
    final rules = container.read(rulesNotifierProvider.notifier) as _ControlledRulesNotifier;
    await rules.firstSaveStarted.future;

    draft.update<String>(RuleEnum.name, 'Second edit');
    rules.releaseFirstSave.complete();

    expect(await firstSave, isFalse);
    expect(container.read(rulesNotifierProvider).single.name, 'First edit');
    expect(container.read(ruleNotifierProvider(null)).name, 'Second edit');
    expect(container.read(IsRuleEditedProvider(null)), isTrue);

    expect(await draft.save(), isTrue);
    expect(container.read(rulesNotifierProvider).single.name, 'Second edit');
    expect(container.read(IsRuleEditedProvider(null)), isFalse);
  });

  test('concurrent rule additions are serialized without losing entries', () async {
    final harness = await _RuleDraftHarness.create();
    addTearDown(harness.dispose);
    final notifier = harness.container.read(rulesNotifierProvider.notifier);
    final additions = List.generate(
      10,
      (index) => notifier.addRule(Rule(name: 'Rule $index', outbound: Outbound.direct)),
    );

    final saved = await Future.wait(additions);

    expect(saved.map((rule) => rule.listOrder), orderedEquals(List.generate(10, (index) => index)));
    expect(
      harness.container.read(rulesNotifierProvider).map((rule) => rule.name),
      orderedEquals(List.generate(10, (index) => 'Rule $index')),
    );
    final persisted = RouteRule.fromBuffer(await harness.ruleFile.readAsBytes());
    expect(persisted.rules.map((rule) => rule.name), orderedEquals(List.generate(10, (index) => 'Rule $index')));
  });
}

class _ControlledRulesNotifier extends RulesNotifier {
  final firstSaveStarted = Completer<void>();
  final releaseFirstSave = Completer<void>();

  @override
  List<Rule> build() => [];

  @override
  Future<Rule> addRule(Rule rule) async {
    final savedRule = rule.deepCopy()
      ..listOrder = 0
      ..enabled = true;
    firstSaveStarted.complete();
    await releaseFirstSave.future;
    state = [savedRule];
    return savedRule.deepCopy();
  }

  @override
  Future<Rule> updateRule(Rule rule) async {
    final savedRule = rule.deepCopy();
    state = [savedRule];
    return savedRule.deepCopy();
  }
}

class _RuleDraftHarness {
  _RuleDraftHarness(this.container, this.directory, this.rulesSubscription);

  final ProviderContainer container;
  final Directory directory;
  final ProviderSubscription<List<Rule>> rulesSubscription;

  File get ruleFile => File('${directory.path}/route_rule.proto');

  static Future<_RuleDraftHarness> create({List<Rule> initialRules = const []}) async {
    final directory = await Directory.systemTemp.createTemp('rule-draft-test-');
    if (initialRules.isNotEmpty) {
      await File('${directory.path}/route_rule.proto').writeAsBytes(RouteRule(rules: initialRules).writeToBuffer());
    }
    final translations = await AppLocale.en.build();
    final directories = (baseDir: directory, workingDir: directory, tempDir: directory);
    final container = ProviderContainer(
      overrides: [
        translationsProvider.overrideWith((ref) => translations),
        appDirectoriesProvider.overrideWith(() => _TestAppDirectories(directories)),
      ],
    );
    await container.read(appDirectoriesProvider.future);
    final rulesSubscription = container.listen(rulesNotifierProvider, (_, _) {}, fireImmediately: true);
    return _RuleDraftHarness(container, directory, rulesSubscription);
  }

  Future<void> blockRuleFile() async {
    if (await ruleFile.exists()) await ruleFile.delete();
    await Directory(ruleFile.path).create();
  }

  Future<void> unblockRuleFile() async {
    final blocker = Directory(ruleFile.path);
    if (await blocker.exists()) await blocker.delete();
  }

  Future<void> dispose() async {
    rulesSubscription.close();
    container.dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class _TestAppDirectories extends AppDirectories {
  _TestAppDirectories(this.directories);

  final Directories directories;

  @override
  Future<Directories> build() async => directories;
}
