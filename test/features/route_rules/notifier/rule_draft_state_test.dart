import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/route_rules/notifier/rule_notifier.dart';
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
}
