import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/app_update/model/post_update_state.dart';

void main() {
  test('installed state carries the verified previous and current revisions', () {
    const state = PostUpdateInstalled(
      previousRevision: '4.1.1+40101',
      currentRevision: '4.1.2+40102',
      currentVersion: '4.1.2',
    );

    expect(state.previousRevision, '4.1.1+40101');
    expect(state.currentRevision, '4.1.2+40102');
    expect(state.currentVersion, '4.1.2');
  });

  test('idle state contains no unverified installation claim', () {
    expect(const PostUpdateIdle(), isA<PostUpdateState>());
    expect(const PostUpdateIdle(), isNot(isA<PostUpdateInstalled>()));
  });
}
