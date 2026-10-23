import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_native_connection_control.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/home/widget/home_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../support/connection_fixtures.dart';
import '../support/home_fixture.dart';

void _testNativeWidgets(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    try {
      await callback(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        null,
      );
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
  });

  _testNativeWidgets('actual Blizzard Home gives the complete primary action surface to UIKit', (tester) async {
    final native = _NativeConnectionRecorder(tester);
    final fixture = await _mountNativeHome(tester, native);
    addTearDown(() => fixture.close(tester));

    final control = find.byType(BlizzardNativeConnectionControl);
    final platformView = find.descendant(of: control, matching: find.byType(UiKitView));
    expect(control, findsOneWidget);
    expect(platformView, findsOneWidget);
    expect(tester.getSize(control), const Size.square(148));
    expect(tester.widget<UiKitView>(platformView).viewType, 'app.blizzard/native-connection-control');
    expect(tester.widget<UiKitView>(platformView).creationParams, {
      'enabled': true,
      'visible': true,
      'label': fixture.container.read(translationsProvider).requireValue.connection.disconnect,
      'connectionState': 'connected',
    });
    expect(find.descendant(of: control, matching: find.byType(InkWell)), findsNothing);
    expect(find.descendant(of: control, matching: find.byType(GestureDetector)), findsNothing);
  });

  _testNativeWidgets('one native press invokes the existing Home connection action exactly once', (tester) async {
    final native = _NativeConnectionRecorder(tester);
    final fixture = await _mountNativeHome(tester, native);
    addTearDown(() => fixture.close(tester));

    await native.press(tester);

    expect(fixture.events, ['toggle']);
  });

  _testNativeWidgets('enabled, visible, label, and connection state update as one native value', (tester) async {
    final native = _NativeConnectionRecorder(tester);
    final fixture = await _mountNativeHome(tester, native);
    addTearDown(() => fixture.close(tester));
    final notifier = fixture.container.read(connectionNotifierProvider.notifier) as ButtonConnectionSpy;
    final translations = fixture.container.read(translationsProvider).requireValue;

    native.updates.clear();
    notifier.state = const AsyncData(Connecting());
    await tester.pump();

    expect(native.updates, [
      {'enabled': false, 'visible': true, 'label': translations.connection.connecting, 'connectionState': 'connecting'},
    ]);
  });

  _testNativeWidgets('pending native control rejects a stale press callback', (tester) async {
    final native = _NativeConnectionRecorder(tester);
    final fixture = await _mountNativeHome(tester, native);
    addTearDown(() => fixture.close(tester));
    final notifier = fixture.container.read(connectionNotifierProvider.notifier) as ButtonConnectionSpy;

    notifier.state = const AsyncLoading();
    await tester.pump();
    await native.press(tester);

    expect(fixture.events, isEmpty);
    expect(native.updates.single['enabled'], false);
  });

  _testNativeWidgets('root bottom sheet hides and blocks the nested Home native action until dismissal', (tester) async {
    final native = _NativeConnectionRecorder(tester);
    final fixture = await _mountNativeHome(tester, native);
    addTearDown(() => fixture.close(tester));

    final shown = showModalBottomSheet<void>(
      context: rootNavKey.currentContext!,
      builder: (_) => const SizedBox(height: 120, child: Text('root sheet')),
    );
    await tester.pump();
    expect(native.updates.last['visible'], false);
    await native.press(tester);
    expect(fixture.events, isEmpty);

    Navigator.of(rootNavKey.currentContext!, rootNavigator: true).pop();
    await shown;
    await tester.pump();
    expect(native.updates.last['visible'], true);
    await native.press(tester);
    expect(fixture.events, ['toggle']);
  });

  _testNativeWidgets('root dialog hides and blocks the nested Home native action until dismissal', (tester) async {
    final native = _NativeConnectionRecorder(tester);
    final fixture = await _mountNativeHome(tester, native);
    addTearDown(() => fixture.close(tester));

    final shown = showDialog<void>(
      context: rootNavKey.currentContext!,
      builder: (_) => const AlertDialog(content: Text('root dialog')),
    );
    await tester.pump();
    expect(native.updates.last['visible'], false);
    await native.press(tester);
    expect(fixture.events, isEmpty);

    Navigator.of(rootNavKey.currentContext!, rootNavigator: true).pop();
    await shown;
    await tester.pump();
    expect(native.updates.last['visible'], true);
    await native.press(tester);
    expect(fixture.events, ['toggle']);
  });

  _testNativeWidgets('offstage Home blocks native presses and tab return restores one action', (tester) async {
    final native = _NativeConnectionRecorder(tester);
    final fixture = await _mountNativeHome(tester, native);
    addTearDown(() => fixture.close(tester));

    fixture.router.go('/settings');
    await tester.pump();
    expect(native.updates.last['visible'], false);
    await native.press(tester);
    expect(fixture.events, isEmpty);

    fixture.router.go('/home');
    await tester.pump();
    expect(native.updates.last['visible'], true);
    await native.press(tester);
    expect(fixture.events, ['toggle']);
  });

  _testNativeWidgets('background lifecycle blocks native presses and resume restores one action', (tester) async {
    final native = _NativeConnectionRecorder(tester);
    final fixture = await _mountNativeHome(tester, native);
    addTearDown(() => fixture.close(tester));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(native.updates.last['visible'], false);
    await native.press(tester);
    expect(fixture.events, isEmpty);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(native.updates.last['visible'], true);
    await native.press(tester);
    expect(fixture.events, ['toggle']);
  });

  _testNativeWidgets('native control is the only button semantics owner for the primary action', (tester) async {
    final native = _NativeConnectionRecorder(tester);
    final fixture = await _mountNativeHome(tester, native);
    addTearDown(() => fixture.close(tester));

    final primaryAction = find.byKey(const ValueKey('home_connection_button'));
    final flutterButtons = tester
        .widgetList<Semantics>(find.descendant(of: primaryAction, matching: find.byType(Semantics)))
        .where((widget) => widget.properties.button == true);
    expect(flutterButtons, isEmpty);
    expect(
      tester
          .widgetList<UiKitView>(find.byType(UiKitView))
          .where((view) => view.viewType == 'app.blizzard/native-connection-control'),
      hasLength(1),
    );
  });

  _testNativeWidgets('disposed native control clears its callback channel', (tester) async {
    final native = _NativeConnectionRecorder(tester);
    final fixture = await _mountNativeHome(tester, native);

    await fixture.close(tester);
    await tester.pump();
    await native.press(tester);

    expect(fixture.events, isEmpty);
  });
}

Widget _appliedHome() => Builder(
  builder: (context) => Theme(
    data: BlizzardTheme.from(Theme.of(context)).copyWith(platform: TargetPlatform.iOS),
    child: const HomePage(),
  ),
);

Future<HomeFixture> _mountNativeHome(WidgetTester tester, _NativeConnectionRecorder native) async {
  native.install();
  final fixture = await mountHomeFixture(tester, child: _appliedHome());
  await native.created;
  native.updates.clear();
  return fixture;
}

final class _NativeConnectionRecorder {
  _NativeConnectionRecorder(this.tester);

  final WidgetTester tester;
  final updates = <Map<Object?, Object?>>[];
  final _created = Completer<int>();
  late MethodChannel _channel;

  Future<int> get created => _created.future;

  void install() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
      if (call.method != 'create') return null;
      final arguments = Map<Object?, Object?>.from(call.arguments! as Map);
      if (arguments['viewType'] != 'app.blizzard/native-connection-control') return null;
      final id = arguments['id']! as int;
      _channel = MethodChannel('app.blizzard/native-connection-control/$id');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'update') {
          updates.add(Map<Object?, Object?>.from(call.arguments! as Map));
        }
        return null;
      });
      if (!_created.isCompleted) _created.complete(id);
      return null;
    });
  }

  Future<void> press(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      _channel.name,
      _channel.codec.encodeMethodCall(const MethodCall('pressed')),
      (_) {},
    );
    await tester.pump();
  }
}
