import 'dart:convert';
import 'dart:io';

import 'package:dartx/dartx_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'rules_notifier.g.dart';

@riverpod
class RulesNotifier extends _$RulesNotifier with AppLogger {
  late File file;
  Future<void> _mutationQueue = Future.value();

  @override
  List<Rule> build() {
    final directories = ref.watch(appDirectoriesProvider).requireValue;
    file = File('${directories.baseDir.path}/route_rule.proto');
    if (file.existsSync()) {
      return RouteRule.fromBuffer(file.readAsBytesSync()).rules;
    } else {
      return <Rule>[];
    }
  }

  Future<Rule> addRule(Rule rule) => _serializeMutation(() async {
    final current = state;
    assert(rule.hasName() && rule.hasOutbound());
    final savedRule = rule.deepCopy()
      ..listOrder = current.length
      ..enabled = true;
    final next = [...current, savedRule];
    await _updateFile(next);
    state = next;
    return savedRule.deepCopy();
  });

  Future<Rule> updateRule(Rule rule) => _serializeMutation(() async {
    final current = state;
    final index = current.indexWhere((element) => element.listOrder == rule.listOrder);
    if (index == -1) throw StateError('rule ${rule.listOrder} was not found');
    final savedRule = rule.deepCopy();
    final next = current.toList()..[index] = savedRule;
    await _updateFile(next);
    state = next;
    return savedRule.deepCopy();
  });

  Future<void> deleteRule(int listOrder) => _serializeMutation(() async {
    final current = state;
    state = _updateListOrder(current.where((element) => element.listOrder != listOrder).toList());
    await _updateFile();
  });

  Future<void> reorder(int oldIndex, int newIndex) => _serializeMutation(() async {
    final current = state.toList();
    final rule = current.removeAt(oldIndex);
    current.insert(oldIndex < newIndex ? newIndex - 1 : newIndex, rule);
    state = _updateListOrder(current).toList();
    await _updateFile();
  });

  Future<void> updateEnabled(bool enabled, int listOrder) => _serializeMutation(() async {
    final current = state.map((rule) => rule.deepCopy()).toList();
    current.firstWhere((rule) => rule.listOrder == listOrder).enabled = enabled;
    state = current;
    await _updateFile();
  });

  //export Clipboard
  Future<bool> exportJsonToClipboard() async {
    final t = ref.read(translationsProvider).requireValue;
    try {
      final routeRules = RouteRule(rules: state);
      final base64Data = base64.encode(utf8.encode(jsonEncode(routeRules.writeToJson())));
      await Clipboard.setData(ClipboardData(text: 'hiddify:///settings/routing-options?routeRule=$base64Data'));
      ref.read(inAppNotificationControllerProvider).showSuccessToast(t.common.msg.export.clipboard.success);
      return true;
    } on PlatformException {
      ref
          .read(inAppNotificationControllerProvider)
          .showInfoToast(t.common.msg.export.clipboard.contentTooLarge, duration: const Duration(seconds: 5));
      return false;
    } catch (e, st) {
      loggy.warning("error exporting route rules to clipboard", e, st);
      ref.read(inAppNotificationControllerProvider).showErrorToast(t.common.msg.export.clipboard.failure);
      return false;
    }
  }

  //import clipboard
  Future<bool> importRulesFromClipboard() async {
    final t = ref.read(translationsProvider).requireValue;
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain).then((value) => value?.text);
      if (clipboardData == null) return false;
      final encodedBase64 = Uri.parse(clipboardData).queryParameters['routeRule'];
      if (encodedBase64 == null) return false;
      return await importRules(encodedBase64);
    } catch (e, st) {
      loggy.warning("error importing route rules from clipboard", e, st);
      ref.read(inAppNotificationControllerProvider).showErrorToast(t.common.msg.import.failure);
      return false;
    }
  }

  //import deep link
  Future<bool> importRulesFromDeepLink(String encodedBase64) async {
    final t = ref.read(translationsProvider).requireValue;
    try {
      final isConfirmed = await ref
          .read(dialogNotifierProvider.notifier)
          .showConfirmation(
            title: t.dialogs.confirmation.importRouteRuleByDeepLinkWarning.title,
            message: t.dialogs.confirmation.importRouteRuleByDeepLinkWarning.message,
          );
      if (isConfirmed) {
        return await importRules(encodedBase64);
      }
      return false;
    } catch (e, st) {
      loggy.warning("error importing route rules from deep link", e, st);
      ref.read(inAppNotificationControllerProvider).showErrorToast(t.common.msg.import.failure);
      return false;
    }
  }

  //import
  Future<bool> importRules(String encodedBase64) async {
    final t = ref.read(translationsProvider).requireValue;
    final base64Content = base64.decode(encodedBase64);
    final routeRules = RouteRule.fromJson(jsonDecode(utf8.decode(base64Content)) as String);
    await _replaceRules(routeRules.rules);
    ref.read(inAppNotificationControllerProvider).showSuccessToast(t.common.msg.import.success);
    return true;
  }

  //export JSON
  Future<bool> saveRulesAsJsonFile() async {
    final t = ref.read(translationsProvider).requireValue;
    try {
      final bytes = utf8.encode(RouteRule(rules: state).writeToJson());
      final outputFile = await FilePicker.platform.saveFile(
        fileName: 'route_rules.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
      if (outputFile == null) return false;
      if (PlatformUtils.isDesktop) {
        final file = File(outputFile);
        if (file.extension != '.json') return false;
        if (!await file.exists()) await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
      }
      ref.read(inAppNotificationControllerProvider).showSuccessToast(t.common.msg.export.file.success);
      return true;
    } catch (e, st) {
      loggy.warning("error exporting route rules to json file", e, st);
      ref.read(inAppNotificationControllerProvider).showErrorToast(t.common.msg.export.file.failure);
      return false;
    }
  }

  //import JSON
  Future<bool> importRulesFromJsonFile() async {
    final t = ref.read(translationsProvider).requireValue;
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      if (result == null) return false;
      final file = File(result.files.single.path!);
      if (!await file.exists()) return false;
      final bytes = await file.readAsBytes();
      final routeRules = RouteRule.fromJson(utf8.decode(bytes));
      await _replaceRules(routeRules.rules);
      ref.read(inAppNotificationControllerProvider).showSuccessToast(t.common.msg.import.success);
      return true;
    } catch (e, st) {
      loggy.warning("error importing route rules from json file", e, st);
      ref.read(inAppNotificationControllerProvider).showErrorToast(t.common.msg.import.failure);
      return false;
    }
  }

  Future<void> resetRules() => _serializeMutation(() async {
    if (await file.exists()) {
      await file.delete(recursive: true);
    }
    state = <Rule>[];
  });

  Future<void> _replaceRules(List<Rule> rules) => _serializeMutation(() async {
    final next = rules.map((rule) => rule.deepCopy()).toList();
    await _updateFile(next);
    state = next;
  });

  Future<T> _serializeMutation<T>(Future<T> Function() mutation) {
    final request = _mutationQueue.then((_) => mutation());
    _mutationQueue = request.then<void>((_) {}, onError: (Object error, StackTrace stackTrace) {});
    return request;
  }

  Future<void> _updateFile([List<Rule>? rules]) async {
    if (!await file.exists()) {
      await file.parent.create(recursive: true);
    }
    final sortedRules = (rules ?? state).map((rule) => rule.deepCopy()).toList()
      ..sort((a, b) => a.listOrder.compareTo(b.listOrder));
    final routeRules = RouteRule(rules: sortedRules);
    await file.writeAsBytes(routeRules.writeToBuffer());
  }

  List<Rule> _updateListOrder(List<Rule> rules) {
    for (var i = 0; i < rules.length; i++) {
      rules[i].listOrder = i;
    }
    return rules;
  }
}
