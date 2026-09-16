import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/overview/proxy_picker_state.dart';

void main() {
  test('recent selections are unique, newest-first, and bounded', () {
    final notifier = ProxyRecentTagsNotifier();

    notifier.record('Stockholm');
    notifier.record('Vienna');
    notifier.record('Tokyo');
    notifier.record('Paris');
    notifier.record('Vienna');

    expect(notifier.state, ['Vienna', 'Paris', 'Tokyo']);
  });

  test('blank selections do not create dishonest shortcuts', () {
    final notifier = ProxyRecentTagsNotifier();

    notifier.record('');
    notifier.record('   ');

    expect(notifier.state, isEmpty);
  });
}
