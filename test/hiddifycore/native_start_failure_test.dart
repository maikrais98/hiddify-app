import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _FailingNativeCore implements CoreInterface {
  _FailingNativeCore(this.code);
  final int code;
  @override
  Future<CoreStatus> setupBackground(String path, String name, {String? operationId}) async =>
      throw PlatformException(code: 'SETUP_CONNECTION', details: {'domain': 'NEVPNErrorDomain', 'nativeCode': code});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final code in [4, 5]) {
    test('native start code $code error returns typed Left and leaves Starting immediately', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final refProvider = Provider<Ref>((ref) => ref);
      final service = HiddifyCoreService(container.read(refProvider), core: _FailingNativeCore(code));
      addTearDown(service.statusController.close);
      addTearDown(service.logController.close);
      final states = <CoreStatus>[];
      final subscription = service.statusController.listen(states.add);
      addTearDown(subscription.cancel);

      final result = await service.start('/unused/test-config', 'test', false).run();
      await Future<void>.delayed(Duration.zero);

      result.match((failure) {
        expect(failure, isA<BackgroundCoreNotAvailable>());
        expect((failure as BackgroundCoreNotAvailable).message, contains('NEVPNErrorDomain: $code'));
      }, (_) => fail('native failure must reach the repository as Left'));
      expect(service.currentState, const CoreStatus.stopped());
      expect(states, [const CoreStatus.starting(), const CoreStatus.stopped()]);
    });
  }
}
