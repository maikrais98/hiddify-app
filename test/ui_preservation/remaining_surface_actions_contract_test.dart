import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/region.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/data/connection_data_providers.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/intro/widget/intro_page.dart';
import 'package:hiddify/features/profile/details/json_editor.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hiddify/features/settings/notifier/warp_option/warp_option_notifier.dart';
import 'package:hiddify/features/settings/overview/sections/general_page.dart';
import 'package:hiddify/features/settings/overview/sections/warp_options_page.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../support/connection_fixtures.dart';
import '../support/home_fixture.dart';
import '../support/remaining_surface_fixtures.dart';

// Widget binding spies: no assertion below claims notifier/core implementation coverage.
class SettingsActions extends ConfigOptionNotifier {
  final calls = <String>[];
  @override
  Future<bool> build() async => false;
  @override
  Future<bool> importFromClipboard() async {
    calls.add('import:clipboard');
    return true;
  }

  @override
  Future<bool> importFromJsonFile() async {
    calls.add('import:file');
    return true;
  }

  @override
  Future<bool> exportJsonClipboard({bool excludePrivate = true}) async {
    calls.add('export:clipboard:$excludePrivate');
    return true;
  }

  @override
  Future<bool> exportJsonFile({bool excludePrivate = true}) async {
    calls.add('export:file:$excludePrivate');
    return true;
  }

  @override
  Future<void> resetOption() async {
    calls.add('reset');
  }
}

class WarpActions extends WarpOptionNotifier {
  WarpActions(this.initial);
  final AsyncValue<String> initial;
  int calls = 0;
  @override
  AsyncValue<String> build() => initial;
  @override
  Future<void> genWarps({bool showToast = true}) async {
    calls++;
  }
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FilePicker.platform = RemainingFiles(); // Widget runner has no registered native plugin.
  final t = AppLocale.en.buildSync();
  testWidgets('Settings actual overflow preserves confirmation cancel and exact action arguments', (tester) async {
    final actions = SettingsActions();
    final f = await mountHomeFixture(
      tester,
      child: SettingsPage(),
      extraOverrides: [configOptionNotifierProvider.overrideWith(() => actions)],
    );
    await f.container.read(ConfigOptions.mixedPort.notifier).update(12345);
    Future<void> submenu(String title) async {
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tapText(tester, title);
    }

    for (final entry in [
      (t.pages.settings.options.import.clipboard, 'clipboard'),
      (t.pages.settings.options.import.file, 'file'),
    ]) {
      await submenu(t.common.import);
      await tapText(tester, entry.$1);
      expect(find.text(t.dialogs.confirmation.settings.import.msg), findsOneWidget);
      await tapText(tester, t.common.cancel);
      expect(actions.calls, isEmpty);
      expect(f.container.read(ConfigOptions.mixedPort), 12345);
    }
    for (final entry in [
      (t.pages.settings.options.import.clipboard, 'clipboard'),
      (t.pages.settings.options.import.file, 'file'),
    ]) {
      await submenu(t.common.import);
      await tapText(tester, entry.$1);
      await tapText(tester, t.common.ok);
      expect(actions.calls.removeAt(0), 'import:${entry.$2}');
      expect(actions.calls, isEmpty);
    }
    for (final entry in [
      (t.pages.settings.options.export.anonymousToClipboard, 'clipboard:true'),
      (t.pages.settings.options.export.anonymousToFile, 'file:true'),
      (t.pages.settings.options.export.allToClipboard, 'clipboard:false'),
      (t.pages.settings.options.export.allToFile, 'file:false'),
    ]) {
      await submenu(t.common.export);
      await tapText(tester, entry.$1);
      expect(actions.calls, ['export:${entry.$2}']);
      actions.calls.clear();
    }
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tapText(tester, t.pages.settings.options.reset);
    expect(actions.calls, ['reset']); // Source reset has no confirmation dialog.
    expect(find.byType(AlertDialog), findsNothing);
    await f.close(tester);
  });
  testWidgets('Settings real notifier clipboard/file continuation and reset preserve platform contracts', (
    tester,
  ) async {
    final files = RemainingFiles();
    final previousFiles = FilePicker.platform;
    FilePicker.platform = files;
    addTearDown(() => FilePicker.platform = previousFiles);
    final clipboard = <String>[];
    String? exported;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        clipboard.add('get');
        return {'text': '{"mixed-port":12345}'};
      }
      if (call.method == 'Clipboard.setData') {
        clipboard.add('set');
        exported = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final repository = RecordingConnectionRepository();
    addTearDown(repository.statuses.close);
    final f = await mountHomeFixture(
      tester,
      child: SettingsPage(),
      extraOverrides: [
        configOptionNotifierProvider.overrideWith(ConfigOptionNotifier.new),
        serviceRunningProvider.overrideWith((ref) => false),
        connectionRepositoryProvider.overrideWith((ref) => repository),
        inAppNotificationControllerProvider.overrideWith((ref) => RemainingNotifications()),
      ],
    );
    await f.container.read(configOptionNotifierProvider.future);
    Future<void> choose(String group, String item) async {
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tapText(tester, group);
      await tapText(tester, item);
    }

    await choose(t.common.import, t.pages.settings.options.import.clipboard);
    await tapText(tester, t.common.ok);
    expect(clipboard, ['get']);
    expect(f.container.read(sharedPreferencesProvider).requireValue.getInt('mixed-port'), 12345);
    await choose(t.common.export, t.pages.settings.options.export.anonymousToClipboard);
    expect(clipboard, ['get', 'set']);
    expect((jsonDecode(exported!) as Map)['mixed-port'], 12345);
    await choose(t.common.import, t.pages.settings.options.import.file);
    await tapText(tester, t.common.ok);
    expect(files.calls, ['pick:custom:json:false']);
    expect(f.container.read(ConfigOptions.mixedPort), 12345);
    await choose(t.common.export, t.pages.settings.options.export.allToFile);
    expect(files.calls, ['pick:custom:json:false', 'save:options.json:custom:json']);
    expect((jsonDecode(utf8.decode(files.exported!)) as Map)['mixed-port'], 12345);
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tapText(tester, t.pages.settings.options.reset);
    expect(f.container.read(ConfigOptions.mixedPort), 12334);
    expect(f.container.read(sharedPreferencesProvider).requireValue.getInt('mixed-port'), isNull);
    await f.close(tester);
  });
  testWidgets('Intro actual region picker commits exact region and DNS reset; cancel preserves value', (tester) async {
    final previous = IntroPage.locationInfoLoaded;
    IntroPage.locationInfoLoaded = true; // Isolate the OS timezone/network auto-detection boundary.
    addTearDown(() => IntroPage.locationInfoLoaded = previous);
    final f = await mountHomeFixture(tester, child: const IntroPage());
    await tapText(tester, t.pages.settings.routing.region);
    await tapText(tester, Region.cn.present(t));
    expect(f.container.read(ConfigOptions.region), Region.cn);
    expect(f.container.read(sharedPreferencesProvider).requireValue.getString('region'), 'cn');
    expect(f.container.read(ConfigOptions.directDnsAddress), '223.5.5.5');
    await tapText(tester, t.pages.settings.routing.region);
    await tapText(tester, t.common.cancel);
    expect(f.container.read(ConfigOptions.region), Region.cn);
    await f.close(tester);
  });
  for (final state in ['busy', 'error', 'generated']) {
    testWidgets('WARP $state actual rows map dependent availability and generate action', (tester) async {
      final actions = WarpActions(switch (state) {
        'busy' => const AsyncLoading(),
        'error' => AsyncError(StateError('synthetic'), StackTrace.empty),
        _ => const AsyncData('synthetic generated'),
      });
      final f = await mountHomeFixture(
        tester,
        child: const WarpOptionsPage(),
        extraOverrides: [warpOptionNotifierProvider.overrideWith(() => actions)],
      );
      ListTile row(String title) =>
          tester.widget<ListTile>(find.ancestor(of: find.text(title), matching: find.byType(ListTile)).first);
      expect(row(t.pages.settings.warp.generateConfig).enabled, false);
      expect(row(t.pages.settings.warp.licenseKey).enabled, false);
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pump();
      expect(f.container.read(ConfigOptions.enableWarp), true);
      expect(actions.calls, 1);
      expect(row(t.pages.settings.warp.licenseKey).enabled, true);
      expect(row(t.pages.settings.warp.generateConfig).enabled, state != 'busy');
      if (state == 'busy') {
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(row(t.pages.settings.warp.generateConfig).onTap, isNull);
      } else {
        expect(find.text(t.pages.settings.warp.missingConfig), state == 'error' ? findsOneWidget : findsNothing);
        await tester.tap(find.text(t.pages.settings.warp.generateConfig));
        await tester.pump();
        expect(actions.calls, 2);
      }
      await f.close(tester);
    });
  }
  testWidgets('General scrolled input and slider bind exact stored values and cancel preserves scroll', (tester) async {
    final f = await mountHomeFixture(tester, child: const GeneralPage());
    final scrollable = find.descendant(of: find.byType(GeneralPage), matching: find.byType(Scrollable)).first;
    Future<void> reveal(String title) async {
      await tester.scrollUntilVisible(find.text(title), 160, scrollable: scrollable);
      await tester.pumpAndSettle();
    }

    await reveal(t.pages.settings.general.clashApiPort);
    final position = tester.state<ScrollableState>(scrollable).position;
    final offset = position.pixels;
    final before = f.container.read(ConfigOptions.clashApiPort);
    await tapText(tester, t.pages.settings.general.clashApiPort);
    await tester.enterText(find.byType(TextField).last, '12346');
    await tapText(tester, 'CANCEL');
    expect(f.container.read(ConfigOptions.clashApiPort), before);
    expect(position.pixels, offset);
    await tapText(tester, t.pages.settings.general.clashApiPort);
    await tester.enterText(find.byType(TextField).last, '12346');
    await tapText(tester, 'OK');
    expect(f.container.read(ConfigOptions.clashApiPort), 12346);
    expect(f.container.read(sharedPreferencesProvider).requireValue.getInt('clash-api-port'), 12346);
    await reveal(t.pages.settings.general.urlTestInterval);
    await tapText(tester, t.pages.settings.general.urlTestInterval);
    await tester.tapAt(tester.getCenter(find.byType(Slider)));
    await tester.pump();
    final selected = tester.widget<Slider>(find.byType(Slider)).value.toInt();
    await tapText(tester, 'OK');
    expect(f.container.read(ConfigOptions.urlTestInterval), Duration(minutes: selected));
    expect(
      f.container.read(sharedPreferencesProvider).requireValue.getInt('url-test-interval'),
      Duration(minutes: selected).inSeconds,
    );
    await f.close(tester);
  });
  testWidgets('JSON tree delete menu removes only selected field once', (tester) async {
    final changes = <dynamic>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JsonEditor(json: '{"keep":true,"remove":false}', onChanged: changes.add),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Add new object').last);
    await tester.pumpAndSettle();
    await tapText(tester, 'Delete');
    await tester.pump(const Duration(milliseconds: 600));
    expect(changes, [
      {'keep': true},
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('JSON schema menu inserts the selected protocol once', (tester) async {
    final changes = <dynamic>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JsonEditor(json: '{"outbounds":[]}', onChanged: changes.add),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Add new object').last);
    await tester.pumpAndSettle();
    await tapText(tester, 'warp');
    await tester.pump(const Duration(milliseconds: 600));
    expect(changes, [
      {
        'outbounds': [protocolSchemaValues['warp']],
      },
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('JSON tree nested add menu changes draft once and survives appearance rebuild', (tester) async {
    final changes = <dynamic>[];
    Widget app(Brightness brightness) => MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: JsonEditor(
          key: const ValueKey('tree'),
          json: '{"nested":{}}',
          onChanged: changes.add,
          expandedObjects: const ['nested'],
        ),
      ),
    );
    await tester.pumpWidget(app(Brightness.light));
    await tester.tap(find.byTooltip('Add new object').last);
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    await tapText(tester, 'String');
    await tester.pump(const Duration(milliseconds: 600));
    expect(changes, [
      {
        'nested': {'new_key_added': ''},
      },
    ]);
    await tester.pumpWidget(app(Brightness.dark));
    await tester.tap(find.byTooltip('Change editor'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Text');
    expect(tester.widget<EditableText>(find.byType(EditableText).last).controller.text, contains('new_key_added'));
    expect(changes.length, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
