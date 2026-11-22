import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/widgets/proxy_info_dialog.dart';
import 'package:hiddify/core/theme/blizzard_theme.dart';
import 'package:hiddify/features/common/qr_code_dialog.dart';
import 'package:hiddify/features/profile/model/download_problem.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/widget/download_failure_dialog.dart';
import 'package:hiddify/features/proxy/keep_top/keep_top.dart';
import 'package:hiddify/features/proxy/keep_top/keep_top_widgets.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/settings/overview/sections/general_page.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../support/blizzard_capture.dart';
import '../support/connection_fixtures.dart';
import '../support/home_fixture.dart';

class _EmptyProxyList extends ProxiesOverviewNotifier {
  @override
  Stream<OutboundGroup?> build() => Stream.value(null);
}

Widget _aurora(Widget child) => Builder(
  builder: (context) => Theme(
    data: BlizzardTheme.from(Theme.of(context).copyWith(platform: TargetPlatform.iOS)),
    child: child,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Use the pinned Flutter SDK's font so the goldens render the same text on any host.
    final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
    final font = await File.fromUri(artifacts.uri.resolve('material_fonts/Roboto-Regular.ttf')).readAsBytes();
    for (final family in ['.SF Pro Text', '.SF Pro Display']) {
      await (FontLoader(family)..addFont(Future.value(font.buffer.asByteData()))).load();
    }
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final weight in ['Regular', 'Filled']) {
      await (FontLoader(
        'packages/fluentui_system_icons/FluentSystemIcons-$weight',
      )..addFont(rootBundle.load('packages/fluentui_system_icons/fonts/FluentSystemIcons-$weight.ttf'))).load();
    }
  });

  final profile = connectionProfile.copyWith(userOverride: const UserOverride(keepTop: 5));
  final proxy = OutboundInfo(tag: 'Example', tagDisplay: 'Example', type: 'vless', urlTestDelay: 52);

  final surfaces = <String, Widget>{
    'keep-top': Column(
      children: [
        const KeepTopFooter(listed: 5, picking: false),
        RestingProxiesHeader(count: 25, shown: true, onToggle: () {}),
      ],
    ),
    'keep-top-region': const KeepTopDialog(count: 30, keep: 5, available: [('DE', 12), ('FR', 18)]),
    'proxy-info': ProxyInfoDialog(outboundInfo: proxy),
    'download-failure': const DownloadFailureDialog(failure: ProfileDownloadFailure(DownloadProblem.timeout)),
    'qr': const QrCodeDialog(
      'https://example.invalid/sample',
      title: 'Sample profile',
      link: 'https://example.invalid/sample',
    ),
    'general': const GeneralPage(),
  };

  for (final entry in surfaces.entries) {
    testWidgets('Blizzard ${entry.key} at 393 points', (tester) async {
      final fixture = await mountHomeFixture(
        tester,
        profile: profile,
        disableAnimations: true,
        child: _aurora(Material(child: entry.value)),
        extraOverrides: [
          profileProxyCountProvider(profile.id).overrideWith((ref) => 30),
          proxiesOverviewNotifierProvider.overrideWith(_EmptyProxyList.new),
        ],
      );
      await tester.pumpAndSettle();
      final t = fixture.container.read(translationsProvider).requireValue;
      if (entry.key == 'keep-top-region') {
        await tester.tap(find.byIcon(Icons.expand_more_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.text(t.dialogs.keepTop.region));
        await tester.pumpAndSettle();
      }
      if (entry.key == 'proxy-info') {
        expect(find.text(t.dialogs.proxyInfo.keepLoaded), findsOneWidget);
      }
      if (entry.key == 'general') {
        expect(find.text(t.pages.settings.general.reduceAnimations), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      final surface = entry.key == 'general'
          ? find.byKey(const ValueKey('general-settings-group-appearance'))
          : find.byKey(blizzardFixtureCanvas);
      await expectLater(surface, matchesGoldenFile('goldens/luma-5915-${entry.key}.png'));
      if (entry.key == 'general') {
        await tester.tap(find.text(t.pages.settings.general.reduceAnimations));
        await tester.pumpAndSettle();
        expect(fixture.container.read(Preferences.reduceAnimations), isTrue);
      }
      await fixture.close(tester);
    });
  }
}
