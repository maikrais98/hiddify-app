import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/logger/logger_setup.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/bottom_sheets/widgets/quick_settings_modal.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/features/common/qr_code_dialog.dart';
import 'package:hiddify/features/log/overview/logs_modals.dart';
import 'package:hiddify/features/log/overview/logs_overview_notifier.dart';
import 'package:hiddify/features/log/overview/logs_page.dart';
import 'package:hiddify/features/profile/add/add_profile_modal.dart';
import 'package:hiddify/features/profile/add/widgets/loading.dart';
import 'package:hiddify/features/profile/details/json_editor.dart';
import 'package:hiddify/features/profile/details/profile_details_notifier.dart';
import 'package:hiddify/features/profile/details/profile_details_page.dart';
import 'package:hiddify/features/profile/details/profile_details_state.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../support/home_fixture.dart';
import '../support/surface_fixtures.dart' show SurfaceDetails, contrastRatio;

Widget _underAurora(Widget child) => Builder(
  builder: (context) => Theme(data: BlizzardTheme.from(Theme.of(context)), child: child),
);

Widget _addProfileSheetLauncher(ValueChanged<Future<void>> onShown) => Builder(
  builder: (context) => TextButton(
    key: const ValueKey('open-import-sheet'),
    onPressed: () {
      final shown = Navigator.of(context, rootNavigator: true).push<void>(
        ModalBottomSheetRoute(
          constraints: BottomSheetConst.boxConstraints,
          isScrollControlled: true,
          builder: (context) => ClipRRect(
            borderRadius: BottomSheetConst.borderRadius,
            child: Material(
              child: Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
                child: _underAurora(const AddProfileModal()),
              ),
            ),
          ),
        ),
      );
      onShown(shown);
    },
    child: const Text('open import sheet'),
  ),
);

Future<void> _openImportSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-import-sheet')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  expect(find.byType(AddProfileModal), findsOneWidget);
}

Future<void> _closeImportSheet(WidgetTester tester, Future<void>? shown) async {
  Navigator.of(tester.element(find.byType(AddProfileModal))).pop();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await shown;
}

void _expectAuroraReadable(WidgetTester tester, Finder visibleText) {
  expect(visibleText.hitTestable(), findsOneWidget);
  final theme = Theme.of(tester.element(visibleText));
  expect(theme.extension<BlizzardEligibility>()?.applied, isTrue);
  expect(contrastRatio(theme.colorScheme.onSurface, theme.colorScheme.surface), greaterThanOrEqualTo(4.5));
}

class _LoadingAddProfile extends AddProfileNotifier {
  @override
  AsyncValue<Unit?> build() => const AsyncLoading();
}

ProfileEntity _remoteProfile(String id) => ProfileEntity.remote(
  id: id,
  active: true,
  name: 'Aurora remote profile',
  url: 'https://example.invalid/remote-profile',
  lastUpdate: DateTime.utc(2026, 10, 24),
  options: const ProfileOptions(updateInterval: Duration(hours: 24)),
);

ProfileDetailsState _detailsState(String id, String config) => ProfileDetailsState(
  loadingState: const AsyncData(null),
  profile: _remoteProfile(id),
  config: AsyncData((text: config, isJson: false)),
  isDetailsChanged: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('zJ8PW real 320pt manual-import sheet shows its validation error under Aurora', (tester) async {
    Future<void>? shown;
    final fixture = await mountHomeFixture(
      tester,
      width: 320,
      child: _addProfileSheetLauncher((value) => shown = value),
    );
    await _openImportSheet(tester);
    fixture.container.read(addProfilePageNotifierProvider.notifier).goManual();
    await tester.pump();
    final t = fixture.container.read(translationsProvider).requireValue;

    await tester.enterText(find.byType(TextFormField).at(0), 'Invalid import');
    await tester.enterText(find.byType(TextFormField).at(1), 'not a URL');
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    final error = find.text(t.pages.profileDetails.form.invalidUrl);
    _expectAuroraReadable(tester, error);
    expect(tester.getSize(find.byType(AddProfileModal)).width, lessThanOrEqualTo(320));
    expect(find.byType(ProfileLoading), findsNothing);
    expect(tester.takeException(), isNull);
    await _closeImportSheet(tester, shown);
    await fixture.close(tester);
  });

  testWidgets('fxhVs real manual-import sheet preserves the keyboard inset and reachable draft', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    Future<void>? shown;
    final fixture = await mountHomeFixture(
      tester,
      nativeViewport: true,
      child: _addProfileSheetLauncher((value) => shown = value),
    );
    await _openImportSheet(tester);
    fixture.container.read(addProfilePageNotifierProvider.notifier).goManual();
    await tester.pump();
    final t = fixture.container.read(translationsProvider).requireValue;
    final urlField = find.byType(TextFormField).at(1);
    await tester.tap(urlField);
    await tester.enterText(urlField, 'https://example.invalid/keyboard');

    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final modalContext = tester.element(find.byType(AddProfileModal));
    expect(MediaQuery.viewInsetsOf(modalContext).bottom, 260);
    expect(
      find.ancestor(
        of: find.byType(AddProfileModal),
        matching: find.byWidgetPredicate(
          (widget) => widget is Padding && widget.padding == const EdgeInsets.only(bottom: 260),
        ),
      ),
      findsOneWidget,
    );
    expect(tester.widget<EditableText>(find.byType(EditableText).at(1)).controller.text, contains('keyboard'));
    _expectAuroraReadable(tester, find.text(t.common.manually));
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    await tester.pump();
    await _closeImportSheet(tester, shown);
    await fixture.close(tester);
  });

  testWidgets('XDLxP real Add Profile waiting sheet keeps progress, label and Cancel visible', (tester) async {
    Future<void>? shown;
    final fixture = await mountHomeFixture(
      tester,
      child: _addProfileSheetLauncher((value) => shown = value),
      extraOverrides: [addProfileNotifierProvider.overrideWith(_LoadingAddProfile.new)],
    );
    await _openImportSheet(tester);
    final t = fixture.container.read(translationsProvider).requireValue;

    expect(find.byType(ProfileLoading), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    _expectAuroraReadable(tester, find.text(t.pages.profileDetails.form.loading));
    final cancel = find.text(MaterialLocalizations.of(tester.element(find.byType(ProfileLoading))).cancelButtonLabel);
    expect(cancel.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _closeImportSheet(tester, shown);
    await fixture.close(tester);
  });

  testWidgets('wCTIm real manual-import sheet renders a valid ready-to-add draft', (tester) async {
    Future<void>? shown;
    final fixture = await mountHomeFixture(tester, child: _addProfileSheetLauncher((value) => shown = value));
    await _openImportSheet(tester);
    fixture.container.read(addProfilePageNotifierProvider.notifier).goManual();
    await tester.pump();
    final t = fixture.container.read(translationsProvider).requireValue;

    await tester.enterText(find.byType(TextFormField).at(0), 'Ready remote profile');
    await tester.enterText(find.byType(TextFormField).at(1), 'https://example.invalid/ready');
    await tester.pump();
    final form = tester.state<FormState>(find.byType(Form));

    expect(form.validate(), isTrue);
    expect(find.text(t.pages.profileDetails.form.invalidUrl), findsNothing);
    expect(find.text('Ready remote profile'), findsOneWidget);
    final add = find.widgetWithText(FilledButton, t.common.add);
    expect(add.hitTestable(), findsOneWidget);
    _expectAuroraReadable(tester, find.text(t.common.manually));
    expect(tester.takeException(), isNull);
    await _closeImportSheet(tester, shown);
    await fixture.close(tester);
  });

  testWidgets('lQtGg real remote ProfileDetailsPage shows URL and remote controls under Aurora', (tester) async {
    const id = 'lQtGg';
    final fixture = await mountHomeFixture(
      tester,
      child: _underAurora(const ProfileDetailsPage(id: id)),
      extraOverrides: [
        profileDetailsNotifierProvider(
          id,
        ).overrideWith(() => SurfaceDetails(_detailsState(id, 'outbound = remote-profile'))),
      ],
    );
    final t = fixture.container.read(translationsProvider).requireValue;

    _expectAuroraReadable(tester, find.text(t.pages.profileDetails.title));
    expect(find.text('Aurora remote profile'), findsOneWidget);
    expect(find.text('https://example.invalid/remote-profile'), findsOneWidget);
    expect(find.text(t.pages.profileDetails.form.disableAutoUpdate), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('Tir2v real ProfileDetails text-config branch keeps draft editing and readable text', (tester) async {
    const id = 'Tir2v';
    const storedConfig = 'outbound = stored-text-config';
    final fixture = await mountHomeFixture(
      tester,
      child: _underAurora(const ProfileDetailsPage(id: id)),
      extraOverrides: [
        profileDetailsNotifierProvider(id).overrideWith(() => SurfaceDetails(_detailsState(id, storedConfig))),
      ],
    );
    final t = fixture.container.read(translationsProvider).requireValue;
    final configField = find.byType(TextFormField).last;
    final editable = tester.widget<EditableText>(find.descendant(of: configField, matching: find.byType(EditableText)));

    _expectAuroraReadable(tester, find.text(t.pages.profileDetails.title));
    expect(configField, findsOneWidget);
    expect(find.byType(JsonEditor), findsNothing);
    expect(
      contrastRatio(editable.style.color!, Theme.of(tester.element(configField)).scaffoldBackgroundColor),
      greaterThanOrEqualTo(4.5),
    );
    await tester.enterText(configField, 'outbound = edited-draft');
    await tester.pump();
    expect(
      fixture.container.read(profileDetailsNotifierProvider(id)).requireValue.config.requireValue.text,
      'outbound = edited-draft',
    );
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('PeEr0 real Quick Settings starts in the WARP-on visual state under Aurora', (tester) async {
    final fixture = await mountHomeFixture(tester, child: _underAurora(const QuickSettingsModal()));
    await fixture.container.read(ConfigOptions.extraSecurityMode.notifier).update(ChainMode.warp);
    await fixture.container.read(ConfigOptions.chainStatus.notifier).update(ChainStatus.extraSecurity);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final t = fixture.container.read(translationsProvider).requireValue;
    expect(fixture.container.read(ConfigOptions.chainStatus), ChainStatus.extraSecurity);
    expect(fixture.container.read(ConfigOptions.extraSecurityMode), ChainMode.warp);
    expect(find.text(ChainMode.warp.present(t)), findsOneWidget);
    expect(find.text(t.pages.settings.chain.quick.extraSecurity.title), findsOneWidget);
    _expectAuroraReadable(tester, find.text(t.pages.home.quickSettings));
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('FadGV real QR dialog renders the exact LAN-share payload and label', (tester) async {
    const endpoint = 'socks://192.0.2.10:12334';
    const payload = '#profile-title: LAN only\n$endpoint#LAN only';
    final fixture = await mountHomeFixture(
      tester,
      child: _underAurora(const QrCodeDialog(payload, title: endpoint, link: endpoint)),
    );
    final dialog = tester.widget<QrCodeDialog>(find.byType(QrCodeDialog));

    expect(dialog.data, payload);
    expect(find.text(endpoint), findsOneWidget);
    expect(tester.getSize(find.byType(QrImageView)).width, 184);
    _expectAuroraReadable(tester, find.text(endpoint));
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('JEInY official logs scroll a full history and share the filtered view under Aurora', (tester) async {
    logRing.clear();
    addTearDown(logRing.clear);
    for (var index = 0; index < logRing.capacity; index++) {
      logRing.add(LogRecord(Level.WARNING, 'Synthetic line ${index.toString().padLeft(4, '0')}', 'app.aurora'));
    }
    final clipboard = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard.add(call.arguments);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final fixture = await mountHomeFixture(
      tester,
      width: 390,
      height: 844,
      scale: 1.8,
      child: _underAurora(const LogsPage()),
    );
    expect(tester.takeException(), isNull, reason: 'logs page at large text');
    final t = fixture.container.read(translationsProvider).requireValue;
    final scrollable = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    position.jumpTo(0);
    await tester.pump();
    expect(find.text('Synthetic line 0000').hitTestable(), findsOneWidget);
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(position.extentAfter, 0);
    final newest = fixture.container.read(logsOverviewNotifierProvider).logs.last.message;
    expect(fixture.container.read(logsOverviewNotifierProvider).logs, hasLength(logRing.capacity));
    // A lazy list estimates its extent until the destination has been laid out.
    for (var attempt = 0; attempt < 20 && find.text(newest).hitTestable().evaluate().isEmpty; attempt++) {
      position.jumpTo(position.maxScrollExtent);
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text(newest), findsOneWidget, reason: 'The newest record must be built at the list end');
    _expectAuroraReadable(tester, find.text(newest));
    await tester.enterText(find.byType(TextField), newest);
    await tester.pump();
    expect(fixture.container.read(logsOverviewNotifierProvider).logs, hasLength(1));
    await tester.tap(find.byTooltip(t.common.share));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'logs share choices at large text');
    await tester.tap(find.text(t.pages.logs.recentLogs));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'recent logs copy/export actions at large text');
    expect(find.byType(LogsRecentModal), findsOneWidget);
    final copy = find.text(t.common.addToClipboard);
    expect(copy.hitTestable(), findsOneWidget);
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(clipboard, hasLength(1));
    expect((clipboard.single! as Map)['text'], contains(newest));
    expect((clipboard.single! as Map)['text'], isNot(contains('Synthetic line 0000')));
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });
}
