import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fallback no-profile dialog has no expert server action or copy', () {
    final source = File('lib/core/router/dialog/widgets/no_active_profile_dialog.dart').readAsStringSync();
    final ru = jsonDecode(File('assets/translations/ru.i18n.json').readAsStringSync()) as Map<String, dynamic>;
    final en = jsonDecode(File('assets/translations/en.i18n.json').readAsStringSync()) as Map<String, dynamic>;
    final ruMessage = (((ru['dialogs'] as Map<String, dynamic>)['noActiveProfile'] as Map<String, dynamic>)['msg'])
        as String;
    final enMessage = (((en['dialogs'] as Map<String, dynamic>)['noActiveProfile'] as Map<String, dynamic>)['msg'])
        as String;

    expect(source, isNot(contains('helpBtn')));
    expect(source, isNot(contains('UriUtils')));
    expect(ruMessage, isNot(contains('эксперт')));
    expect(ruMessage, isNot(contains('настраиваете VPN-сервер')));
    expect(enMessage, isNot(contains('expert')));
    expect(enMessage, isNot(contains('own VPN server')));
  });
}
