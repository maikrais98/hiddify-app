import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/system_tray/notifier/system_tray_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';

const _trayChannel = MethodChannel('tray_manager');
const _windowChannel = MethodChannel('window_manager');

class _ConnectionState extends ConnectionNotifier {
  _ConnectionState(this.connection);

  final ConnectionStatus connection;
  int toggleCount = 0;

  @override
  Stream<ConnectionStatus> build() => Stream.value(connection);

  @override
  Future<void> toggleConnection() async {
    toggleCount++;
  }
}

class _ActiveProxyState extends ActiveProxyNotifier {
  _ActiveProxyState({this.delay, this.error});

  final int? delay;
  final Object? error;

  @override
  Stream<OutboundInfo> build() {
    if (error != null) return Stream.error(error!);
    return Stream.value(OutboundInfo(urlTestDelay: delay));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> trayCalls;

  setUp(() {
    trayCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_trayChannel, (
      call,
    ) async {
      trayCalls.add(call);
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _windowChannel,
      (_) async => null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_trayChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_windowChannel, null);
  });

  Future<({ProviderContainer container, _ConnectionState connection})> initializeTray({
    required ConnectionStatus status,
    int? delay,
    Object? proxyError,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final translations = await AppLocale.en.build();
    final connection = _ConnectionState(status);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => preferences),
        translationsProvider.overrideWith((ref) => translations),
        connectionNotifierProvider.overrideWith(() => connection),
        activeProxyNotifierProvider.overrideWith(() => _ActiveProxyState(delay: delay, error: proxyError)),
      ],
    );
    addTearDown(container.dispose);

    await container.read(systemTrayNotifierProvider.future);
    return (container: container, connection: connection);
  }

  Map<Object?, Object?> methodArguments(MethodCall call) {
    final arguments = call.arguments;
    if (arguments is Map<Object?, Object?>) return arguments;
    fail('${call.method} did not receive map arguments');
  }

  Map<Object?, Object?> connectionMenuItem() {
    final call = trayCalls.singleWhere((call) => call.method == 'setContextMenu');
    final arguments = methodArguments(call);
    final menu = arguments['menu'];
    if (menu is! Map<Object?, Object?>) fail('setContextMenu did not receive a menu map');
    final items = menu['items'];
    if (items is! List<Object?>) fail('setContextMenu did not receive menu items');
    return items.cast<Map<Object?, Object?>>().singleWhere((item) => item['key'] == 'connection');
  }

  group('connected tray lifecycle', () {
    for (final probe in <({String name, int? delay, Object? error})>[
      (name: 'zero delay', delay: 0, error: null),
      (name: 'timeout sentinel', delay: 65000, error: null),
      (name: 'failed probe', delay: null, error: StateError('probe timeout')),
    ]) {
      test('${probe.name} keeps Disconnect enabled', () async {
        await initializeTray(status: const ConnectionStatus.connected(), delay: probe.delay, proxyError: probe.error);

        final item = connectionMenuItem();
        expect(item['label'], 'Disconnect');
        expect(item['disabled'], isFalse);
      });
    }

    test('normal latency follows platform tooltip support', () async {
      await initializeTray(status: const ConnectionStatus.connected(), delay: 42);

      if (Platform.isLinux) {
        expect(trayCalls.where((call) => call.method == 'setToolTip'), isEmpty);
        return;
      }
      final toolTipCall = trayCalls.singleWhere((call) => call.method == 'setToolTip');
      expect(methodArguments(toolTipCall)['toolTip'], contains('42ms'));
    });

    test('connection menu action delegates to the existing toggle', () async {
      final result = await initializeTray(status: const ConnectionStatus.connected(), delay: 42);

      await result.container.read(systemTrayNotifierProvider.notifier).onTrayMenuItemClick(MenuItem(key: 'connection'));

      expect(result.connection.toggleCount, 1);
    });
  });

  group('switching tray lifecycle', () {
    for (final status in const <ConnectionStatus>[ConnectionStatus.connecting(), ConnectionStatus.disconnecting()]) {
      test('$status keeps the connection action disabled', () async {
        await initializeTray(status: status, delay: 42);

        expect(connectionMenuItem()['disabled'], isTrue);
      });
    }
  });
}
