import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/app_update/model/post_update_state.dart';
import 'package:hiddify/features/app_update/notifier/post_update_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(SharedPreferences, PostUpdateNotifier)> createNotifier({String? storedRevision}) async {
    SharedPreferences.setMockInitialValues({
      if (storedRevision != null) PostUpdateNotifier.lastAcknowledgedRevisionKey: storedRevision,
    });
    final preferences = await SharedPreferences.getInstance();
    return (
      preferences,
      PostUpdateNotifier(preferences: preferences, currentVersion: '4.1.2', currentBuildNumber: '40102'),
    );
  }

  test('first launch records a baseline without claiming an update', () async {
    final (preferences, notifier) = await createNotifier();

    await notifier.detect();

    expect(notifier.state, isA<PostUpdateIdle>());
    expect(preferences.getString(PostUpdateNotifier.lastAcknowledgedRevisionKey), '4.1.2+40102');
  });

  test('a newer launched revision produces the installed outcome once', () async {
    final (preferences, notifier) = await createNotifier(storedRevision: '4.1.1+40101');

    await notifier.detect();

    expect(
      notifier.state,
      isA<PostUpdateInstalled>()
          .having((state) => state.previousRevision, 'previous revision', '4.1.1+40101')
          .having((state) => state.currentRevision, 'current revision', '4.1.2+40102'),
    );
    expect(preferences.getString(PostUpdateNotifier.lastAcknowledgedRevisionKey), '4.1.1+40101');

    final interruptedNotifier = PostUpdateNotifier(
      preferences: preferences,
      currentVersion: '4.1.2',
      currentBuildNumber: '40102',
    );
    await interruptedNotifier.detect();
    expect(interruptedNotifier.state, isA<PostUpdateInstalled>());

    await notifier.acknowledge();
    expect(preferences.getString(PostUpdateNotifier.lastAcknowledgedRevisionKey), '4.1.2+40102');
    await notifier.detect();
    expect(notifier.state, isA<PostUpdateIdle>());
  });

  test('same revision and downgrade do not claim a successful update', () async {
    for (final storedRevision in ['4.1.2+40102', '4.2.0+40200']) {
      final (_, notifier) = await createNotifier(storedRevision: storedRevision);

      await notifier.detect();

      expect(notifier.state, isA<PostUpdateIdle>(), reason: storedRevision);
    }
  });

  test('a higher build of the same version is a verified update', () async {
    final (_, notifier) = await createNotifier(storedRevision: '4.1.2+40101');

    await notifier.detect();

    expect(notifier.state, isA<PostUpdateInstalled>());
  });

  test('beta numbering reset becomes the new baseline without a false update', () async {
    SharedPreferences.setMockInitialValues({
      PostUpdateNotifier.lastAcknowledgedRevisionKey: '4.1.2+40102',
      'existing_profile_data': 'preserved',
    });
    final preferences = await SharedPreferences.getInstance();
    final notifier = PostUpdateNotifier(preferences: preferences, currentVersion: '0.0.1', currentBuildNumber: '1');

    await notifier.detect();

    expect(notifier.state, isA<PostUpdateIdle>());
    expect(preferences.getString(PostUpdateNotifier.lastAcknowledgedRevisionKey), '0.0.1+1');
    expect(preferences.getString('existing_profile_data'), 'preserved');
  });

  test('a later beta build remains detectable after the numbering reset', () async {
    SharedPreferences.setMockInitialValues({PostUpdateNotifier.lastAcknowledgedRevisionKey: '0.0.1+1'});
    final preferences = await SharedPreferences.getInstance();
    final notifier = PostUpdateNotifier(preferences: preferences, currentVersion: '0.0.1', currentBuildNumber: '2');

    await notifier.detect();

    expect(notifier.state, isA<PostUpdateInstalled>());
  });

  test('a failed baseline write can be retried without an unhandled error', () async {
    final (preferences, _) = await createNotifier();
    var writes = 0;
    final notifier = PostUpdateNotifier(
      preferences: preferences,
      currentVersion: '4.1.2',
      currentBuildNumber: '40102',
      writeRevision: (_, _) async {
        writes++;
        if (writes == 1) throw StateError('synthetic write failure');
        return true;
      },
    );

    await notifier.detect();
    await notifier.detect();

    expect(writes, 2);
    expect(notifier.state, isA<PostUpdateIdle>());
  });

  test('a failed acknowledgement keeps the durable outcome pending', () async {
    final (preferences, _) = await createNotifier(storedRevision: '4.1.1+40101');
    final notifier = PostUpdateNotifier(
      preferences: preferences,
      currentVersion: '4.1.2',
      currentBuildNumber: '40102',
      writeRevision: (_, _) async => throw StateError('synthetic write failure'),
    );
    await notifier.detect();

    expect(await notifier.acknowledge(), isFalse);
    expect(notifier.state, isA<PostUpdateInstalled>());
    expect(preferences.getString(PostUpdateNotifier.lastAcknowledgedRevisionKey), '4.1.1+40101');
  });
}
