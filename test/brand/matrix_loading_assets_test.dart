import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bundles the licensed Woman in Red loading assets', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final license = File('assets/animations/rabbit_running.LICENSE.md');

    expect(pubspec, contains('lottie:'));
    expect(pubspec, contains('assets/animations/rabbit_running.json'));
    expect(pubspec, contains('assets/images/source/woman_in_red_splash.png'));
    expect(pubspec, isNot(contains('ic_launcher_splash.png')));
    expect(pubspec, isNot(contains('ic_launcher_foreground.png')));
    expect(File('assets/animations/rabbit_running.json').lengthSync(), greaterThan(0));
    expect(license.readAsStringSync(), contains('Lottie Simple License'));
  });

  test('native launch frame is a neutral handoff to the Flutter loader', () {
    final storyboard = File('ios/Runner/Base.lproj/LaunchScreen.storyboard').readAsStringSync();

    expect(storyboard, isNot(contains('<imageView')));
    expect(storyboard, isNot(contains('image="LaunchImage"')));
    expect(storyboard, contains('<color key="backgroundColor"'));
  });

  test('translations use Woman in Red branding', () {
    final translations = Directory(
      'assets/translations',
    ).listSync().whereType<File>().map((file) => file.readAsStringSync());

    expect(translations.every((translation) => !translation.contains('Hiddify')), isTrue);
  });

  test('first-run onboarding is wired into the runtime graph', () {
    final introPage = File('lib/features/intro/widget/intro_page.dart');
    final runtimeSources = [
      File('lib/core/router/go_router/routing_config_notifier.dart').readAsStringSync(),
      File('lib/core/router/go_router/refresh_listenable.dart').readAsStringSync(),
      File('lib/core/preferences/general_preferences.dart').readAsStringSync(),
      File('lib/features/profile/notifier/profiles_update_notifier.dart').readAsStringSync(),
      File('lib/core/model/constants.dart').readAsStringSync(),
    ].join('\n');

    expect(introPage.existsSync(), isTrue);
    expect(runtimeSources, contains('intro_page.dart'));
    expect(runtimeSources, contains("path: '/intro'"));
    expect(runtimeSources, contains('introCompleted'));
    expect(runtimeSources, contains('intro_completed'));
  });
}
