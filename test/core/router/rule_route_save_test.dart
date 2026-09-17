import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/route_rules/notifier/rule_notifier.dart';
import 'package:hiddify/features/route_rules/notifier/rule_route_save.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:toastification/toastification.dart';

void main() {
  test('failed route autosave blocks exit, preserves the draft, and never claims success', () async {
    final translations = await AppLocale.en.build();
    final notifications = _RecordingNotifications();
    final container = ProviderContainer(
      overrides: [
        translationsProvider.overrideWith((ref) => translations),
        inAppNotificationControllerProvider.overrideWithValue(notifications),
        rulesNotifierProvider.overrideWith(_ThrowingRulesNotifier.new),
      ],
    );
    addTearDown(container.dispose);
    final rulesSubscription = container.listen(rulesNotifierProvider, (_, _) {}, fireImmediately: true);
    addTearDown(rulesSubscription.close);
    final draftSubscription = container.listen(ruleNotifierProvider(null), (_, _) {}, fireImmediately: true);
    addTearDown(draftSubscription.close);

    container.read(ruleNotifierProvider(null).notifier).update<String>(RuleEnum.name, 'Draft');

    expect(await container.read(ruleRouteSaveProvider(null)).call(), isFalse);
    expect(container.read(ruleNotifierProvider(null)).name, 'Draft');
    expect(container.read(IsRuleEditedProvider(null)), isTrue);
    expect(container.read(ruleSaveStatusProvider(null)), RuleSaveStatus.failed);
    expect(notifications.successCount, 0);
    expect(container.read(rulesNotifierProvider.notifier), isA<_ThrowingRulesNotifier>());
    expect((container.read(rulesNotifierProvider.notifier) as _ThrowingRulesNotifier).attempts, 1);

    expect(await container.read(ruleRouteSaveProvider(null)).call(), isFalse);
    expect((container.read(rulesNotifierProvider.notifier) as _ThrowingRulesNotifier).attempts, 1);
    expect(notifications.successCount, 0);
  });

  test('successful route autosave allows exit and reports success once', () async {
    final translations = await AppLocale.en.build();
    final notifications = _RecordingNotifications();
    final container = ProviderContainer(
      overrides: [
        translationsProvider.overrideWith((ref) => translations),
        inAppNotificationControllerProvider.overrideWithValue(notifications),
        rulesNotifierProvider.overrideWith(_SuccessfulRulesNotifier.new),
      ],
    );
    addTearDown(container.dispose);
    final rulesSubscription = container.listen(rulesNotifierProvider, (_, _) {}, fireImmediately: true);
    addTearDown(rulesSubscription.close);
    final draftSubscription = container.listen(ruleNotifierProvider(null), (_, _) {}, fireImmediately: true);
    addTearDown(draftSubscription.close);

    container.read(ruleNotifierProvider(null).notifier).update<String>(RuleEnum.name, 'Saved');

    expect(await container.read(ruleRouteSaveProvider(null)).call(), isTrue);
    expect(container.read(rulesNotifierProvider), hasLength(1));
    expect(container.read(IsRuleEditedProvider(null)), isFalse);
    expect(notifications.successCount, 1);
  });
}

class _ThrowingRulesNotifier extends RulesNotifier {
  int attempts = 0;

  @override
  List<Rule> build() => [];

  @override
  Future<Rule> addRule(Rule rule) {
    attempts++;
    return Future.error(StateError('repository write failed'));
  }
}

class _SuccessfulRulesNotifier extends RulesNotifier {
  @override
  List<Rule> build() => [];

  @override
  Future<Rule> addRule(Rule rule) async {
    final saved = rule.deepCopy()
      ..listOrder = state.length
      ..enabled = true;
    state = [...state, saved];
    return saved.deepCopy();
  }
}

class _RecordingNotifications extends InAppNotificationController {
  int successCount = 0;

  @override
  ToastificationItem? showSuccessToast(String message) {
    successCount++;
    return null;
  }
}
