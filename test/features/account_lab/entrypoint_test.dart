import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/main_account_lab.dart' as lab;

void main() {
  test('standalone lab cannot start without explicit debug flag', () {
    expect(lab.main, throwsStateError);
  });
}
