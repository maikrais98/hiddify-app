import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/router/go_router/startup_destination.dart';

void main() {
  test('Matrix and Rabbit bootstrap hands off directly to Home', () {
    expect(startupLocation, '/home');
  });
}
