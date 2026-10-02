import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/settings/data/config_option_data_providers.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('chain option serialization', () {
    test('keeps Warp extra security independent from Psiphon unblocker when unblocker is enabled', () async {
      final harness = await _Harness.create({
        'chain-status': 'unblocker',
        'extra-security-mode': 'warp',
        'unblocker-mode': 'psiphon',
      });
      addTearDown(harness.dispose);

      final json = harness.fullOptions().toJson();

      expect(json['chain-status'], 'unblocker');
      expect((json['extra-security'] as Map<String, dynamic>)['mode'], 'warp');
      expect((json['unblocker'] as Map<String, dynamic>)['mode'], 'psiphon');
    });

    test('keeps Psiphon extra security independent from profile unblocker when extra security is enabled', () async {
      final harness = await _Harness.create({
        'chain-status': 'extraSecurity',
        'extra-security-mode': 'psiphon',
        'unblocker-mode': 'profile',
      });
      addTearDown(harness.dispose);

      final json = harness.fullOptions().toJson();

      expect(json['chain-status'], 'extra_security');
      expect((json['extra-security'] as Map<String, dynamic>)['mode'], 'psiphon');
      expect((json['unblocker'] as Map<String, dynamic>)['mode'], 'profile');
    });

    test('extra-security profile override does not replace the persisted unblocker mode', () async {
      final harness = await _Harness.create({
        'chain-status': 'unblocker',
        'extra-security-mode': 'warp',
        'unblocker-mode': 'psiphon',
      });
      addTearDown(harness.dispose);

      final json = harness
          .fullOptionsOverrided('{"chain-status":"extra_security","extra-security":{"mode":"profile"}}')
          .toJson();

      expect(json['chain-status'], 'extra_security');
      expect((json['extra-security'] as Map<String, dynamic>)['mode'], 'profile');
      expect((json['unblocker'] as Map<String, dynamic>)['mode'], 'psiphon');
    });

    test('unblocker profile override does not replace the persisted extra-security mode', () async {
      final harness = await _Harness.create({
        'chain-status': 'extraSecurity',
        'extra-security-mode': 'warp',
        'unblocker-mode': 'psiphon',
      });
      addTearDown(harness.dispose);

      final json = harness.fullOptionsOverrided('{"chain-status":"unblocker","unblocker":{"mode":"profile"}}').toJson();

      expect(json['chain-status'], 'unblocker');
      expect((json['extra-security'] as Map<String, dynamic>)['mode'], 'warp');
      expect((json['unblocker'] as Map<String, dynamic>)['mode'], 'profile');
    });
  });
}

final class _Harness {
  const _Harness(this.container, this.directory);

  final ProviderContainer container;
  final Directory directory;

  static Future<_Harness> create(Map<String, Object> initialPreferences) async {
    SharedPreferences.setMockInitialValues(initialPreferences);
    final preferences = await SharedPreferences.getInstance();
    final directory = await Directory.systemTemp.createTemp('config-option-repository-test-');
    final directories = (baseDir: directory, workingDir: directory, tempDir: directory);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => preferences),
        appDirectoriesProvider.overrideWith(() => _TestAppDirectories(directories)),
      ],
    );
    await container.read(sharedPreferencesProvider.future);
    await container.read(appDirectoriesProvider.future);
    return _Harness(container, directory);
  }

  SingboxConfigOption fullOptions() => container
      .read(configOptionRepositoryProvider)
      .fullOptions()
      .getOrElse((failure) => throw TestFailure('fullOptions failed: $failure'));

  SingboxConfigOption fullOptionsOverrided(String profileOverride) => container
      .read(configOptionRepositoryProvider)
      .fullOptionsOverrided(profileOverride)
      .getOrElse((failure) => throw TestFailure('fullOptionsOverrided failed: $failure'));

  Future<void> dispose() async {
    container.dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

final class _TestAppDirectories extends AppDirectories {
  _TestAppDirectories(this.directories);

  final Directories directories;

  @override
  Future<Directories> build() async => directories;
}
