import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/per_app_proxy/data/per_app_routing_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/per-app-routing');
  const repository = MethodChannelPerAppRoutingRepository(channel: channel);

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
  );

  test('decodes the native installed-app inventory', () async {
    final icon = Uint8List.fromList([1, 2, 3]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'get_installed_packages');
      expect(call.arguments, {'excludeSystemApps': true, 'withIcons': true});
      return jsonEncode([
        {
          'package-name': 'org.example.chat',
          'name': 'Example Chat',
          'is-system-app': false,
          'icon': base64Encode(icon),
        },
      ]);
    });

    final apps = await repository.getInstalledApps(excludeSystemApps: true);

    expect(apps.single.packageName, 'org.example.chat');
    expect(apps.single.name, 'Example Chat');
    expect(apps.single.icon, icon);
  });

  test('preserves restricted state and does not advertise settings', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(
        code: 'PER_APP_ROUTING_RESTRICTED',
        message: 'Installed-app inventory is restricted',
        details: {'state': 'denied', 'canOpenSettings': false},
      ),
    );

    await expectLater(
      repository.getInstalledApps(),
      throwsA(
        isA<PerAppRoutingException>()
            .having((e) => e.kind, 'kind', PerAppRoutingFailureKind.denied)
            .having((e) => e.canOpenSettings, 'canOpenSettings', isFalse),
      ),
    );
  });

  test('maps unknown platform errors to unavailable', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'OTHER'),
    );

    await expectLater(
      repository.getInstalledApps(),
      throwsA(
        isA<PerAppRoutingException>()
            .having((e) => e.kind, 'kind', PerAppRoutingFailureKind.unavailable)
            .having((e) => e.canOpenSettings, 'canOpenSettings', isFalse),
      ),
    );
  });
}
