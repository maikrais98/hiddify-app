import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _FailingNativeCore implements CoreInterface {
  @override
  Future<CoreStatus> setupBackground(String path, String name) async =>
      throw PlatformException(code: 'SETUP_CONNECTION', details: {'domain': 'NEVPNErrorDomain', 'nativeCode': 5});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('native start error returns typed Left and leaves Starting immediately', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final refProvider = Provider<Ref>((ref) => ref);
    final service = HiddifyCoreService(container.read(refProvider), core: _FailingNativeCore());
    addTearDown(service.statusController.close);
    addTearDown(service.logController.close);
    final states = <CoreStatus>[];
    final subscription = service.statusController.listen(states.add);
    addTearDown(subscription.cancel);

    final result = await service.start('/unused/test-config', 'test', false).run();
    await Future<void>.delayed(Duration.zero);

    result.match((failure) {
      expect(failure, isA<BackgroundCoreNotAvailable>());
      expect((failure as BackgroundCoreNotAvailable).message, contains('NEVPNErrorDomain: 5'));
    }, (_) => fail('native failure must reach the repository as Left'));
    expect(service.currentState, const CoreStatus.stopped());
    expect(states, [const CoreStatus.starting(), const CoreStatus.stopped()]);
  });
}
