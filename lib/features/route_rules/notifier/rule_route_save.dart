import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/route_rules/notifier/rule_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final ruleRouteSaveProvider = Provider.autoDispose.family<RuleRouteSave, int?>(RuleRouteSave.new);

class RuleRouteSave {
  RuleRouteSave(this.ref, this.listOrder);

  final Ref ref;
  final int? listOrder;

  Future<bool> call() async {
    final isRuleEdited = ref.read(IsRuleEditedProvider(listOrder));
    if (!isRuleEdited) return true;
    if (ref.read(ruleSaveStatusProvider(listOrder)) == RuleSaveStatus.failed) return false;

    final saved = await ref.read(ruleNotifierProvider(listOrder).notifier).save();
    if (!saved) return false;

    final t = ref.read(translationsProvider).requireValue;
    ref.read(inAppNotificationControllerProvider).showSuccessToast(t.common.msg.autoSave.success);
    return true;
  }
}
