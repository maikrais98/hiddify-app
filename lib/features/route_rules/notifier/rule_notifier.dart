import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:protobuf/protobuf.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'rule_notifier.g.dart';

enum RuleSaveStatus { idle, saving, failed }

final ruleSaveStatusProvider = StateProvider.autoDispose.family<RuleSaveStatus, int?>(
  (ref, listOrder) => RuleSaveStatus.idle,
);

enum RuleEnum {
  listOrder,
  enabled,
  name,
  outbound,
  ruleSet,
  packageName,
  processName,
  processPath,
  network,
  portRange,
  sourcePortRange,
  protocol,
  ipCidr,
  sourceIpCidr,
  domain,
  domainSuffix,
  domainKeyword,
  domainRegex;

  int getIndex() => index + 1;

  String present(Translations t) => switch (this) {
    listOrder => this.name,
    enabled => this.name,
    name => t.pages.settings.routing.routeRule.rule.tileTitle['name']!,
    outbound => t.pages.settings.routing.routeRule.rule.tileTitle['outbound']!,
    ruleSet => t.pages.settings.routing.routeRule.rule.tileTitle['rule_set']!,
    packageName => t.pages.settings.routing.routeRule.rule.tileTitle['package_name']!,
    processName => t.pages.settings.routing.routeRule.rule.tileTitle['process_name']!,
    processPath => t.pages.settings.routing.routeRule.rule.tileTitle['process_path']!,
    network => t.pages.settings.routing.routeRule.rule.tileTitle['network']!,
    portRange => t.pages.settings.routing.routeRule.rule.tileTitle['port_range']!,
    sourcePortRange => t.pages.settings.routing.routeRule.rule.tileTitle['source_port_range']!,
    protocol => t.pages.settings.routing.routeRule.rule.tileTitle['protocol']!,
    ipCidr => t.pages.settings.routing.routeRule.rule.tileTitle['ip_cidr']!,
    sourceIpCidr => t.pages.settings.routing.routeRule.rule.tileTitle['source_ip_cidr']!,
    domain => t.pages.settings.routing.routeRule.rule.tileTitle['domain']!,
    domainSuffix => t.pages.settings.routing.routeRule.rule.tileTitle['domain_suffixe']!,
    domainKeyword => t.pages.settings.routing.routeRule.rule.tileTitle['domain_keyword']!,
    domainRegex => t.pages.settings.routing.routeRule.rule.tileTitle['domain_regex']!,
  };

  FormFieldValidator<String>? validator(Translations t) => switch (this) {
    ruleSet => (value) => isUrl('$value') ? null : t.pages.settings.routing.routeRule.rule.validUrl,
    processName => (value) => isProcessName('$value') ? null : t.pages.settings.routing.routeRule.rule.validProcessName,
    processPath => (value) => isProcessPath('$value') ? null : t.pages.settings.routing.routeRule.rule.validProcessPath,
    portRange || sourcePortRange =>
      (value) => isPortOrPortRange('$value') ? null : t.pages.settings.routing.routeRule.rule.validPortRange,
    ipCidr ||
    sourceIpCidr => (value) => isIpCidr('$value') ? null : t.pages.settings.routing.routeRule.rule.validIpCidr,
    domain => (value) => isDomain('$value') ? null : t.pages.settings.routing.routeRule.rule.validDomain,
    domainSuffix =>
      (value) => isDomainSuffix('$value') ? null : t.pages.settings.routing.routeRule.rule.validDomainSuffix,
    _ => null,
  };
}

@riverpod
class RuleNotifier extends _$RuleNotifier {
  bool isEditMode = false;
  late Rule _initialState;
  Future<bool>? _pendingSave;

  @override
  Rule build(int? listOrder) {
    final Rule rule;
    if (listOrder == null) {
      final t = ref.read(translationsProvider).requireValue;
      rule = Rule(name: t.pages.settings.routing.routeRule.rule.title, outbound: Outbound.direct, network: Network.all);
    } else {
      isEditMode = true;
      rule = ref.read(rulesNotifierProvider).where((rule) => rule.listOrder == listOrder).first;
    }
    _initialState = rule.deepCopy();
    return rule;
  }

  bool get isEdited => !listEquals(state.writeToBuffer(), _initialState.writeToBuffer());

  void update<T>(RuleEnum key, T value) {
    final map = state.writeToJsonMap();
    map['${key.getIndex()}'] = value is ProtobufEnum
        ? '${value.value}'
        : value is List<ProtobufEnum>
        ? value.map((e) => '${e.value}').toList()
        : value;
    state = Rule.fromJson(jsonEncode(map));
    if (ref.read(ruleSaveStatusProvider(listOrder)) == RuleSaveStatus.failed) {
      ref.read(ruleSaveStatusProvider(listOrder).notifier).state = RuleSaveStatus.idle;
    }
  }

  Future<bool> save() {
    final pendingSave = _pendingSave;
    if (pendingSave != null) return pendingSave;

    late final Future<bool> request;
    request = _save().whenComplete(() {
      if (identical(_pendingSave, request)) _pendingSave = null;
    });
    _pendingSave = request;
    return request;
  }

  Future<bool> _save() async {
    assert(state.hasName() && state.hasOutbound());
    ref.read(ruleSaveStatusProvider(listOrder).notifier).state = RuleSaveStatus.saving;
    try {
      final draftBeingSaved = state.deepCopy();
      if (isEditMode) assert(draftBeingSaved.hasListOrder() && draftBeingSaved.hasEnabled());
      final savedRule = isEditMode
          ? await ref.read(rulesNotifierProvider.notifier).updateRule(draftBeingSaved)
          : await ref.read(rulesNotifierProvider.notifier).addRule(draftBeingSaved);
      final latestDraft = state.deepCopy();
      final changedWhileSaving = !listEquals(latestDraft.writeToBuffer(), draftBeingSaved.writeToBuffer());
      isEditMode = true;
      _initialState = savedRule.deepCopy();
      if (changedWhileSaving) {
        latestDraft
          ..listOrder = savedRule.listOrder
          ..enabled = savedRule.enabled;
        state = latestDraft;
      } else {
        state = savedRule.deepCopy();
      }
      ref.read(ruleSaveStatusProvider(listOrder).notifier).state = RuleSaveStatus.idle;
      return !changedWhileSaving;
    } catch (_) {
      ref.read(ruleSaveStatusProvider(listOrder).notifier).state = RuleSaveStatus.failed;
      state = state.deepCopy();
      return false;
    }
  }

  void continueEditing() {
    ref.read(ruleSaveStatusProvider(listOrder).notifier).state = RuleSaveStatus.idle;
  }

  void discard() {
    state = _initialState.deepCopy();
    ref.read(ruleSaveStatusProvider(listOrder).notifier).state = RuleSaveStatus.idle;
  }
}

@riverpod
bool isRuleEdited(Ref ref, int? listOrder) {
  ref.watch(RuleNotifierProvider(listOrder));
  return ref.read(RuleNotifierProvider(listOrder).notifier).isEdited;
}

@riverpod
class DialogCheckboxNotifier extends _$DialogCheckboxNotifier {
  @override
  List<ProtobufEnum> build(List<ProtobufEnum> selected) {
    return selected;
  }

  void update(ProtobufEnum value) {
    state = state.contains(value) ? state.where((element) => element != value).toList() : [...state, value];
  }
}
