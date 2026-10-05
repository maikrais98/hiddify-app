#!/usr/bin/env python3
"""Create the disposable, isolated iOS UI fixture host; never edit production native files."""
import os
from pathlib import Path
import shutil
import subprocess

SOURCE = Path(__file__).resolve().parents[1]
HOST = Path('/private/tmp/blizzard-ios-test-host')
FLUTTER = '/private/tmp/wir-baseline-tools/flutter-3.38.5/bin/flutter'

def main():
    if HOST.exists():
        raise SystemExit('Test host exists; inspect it instead of overwriting or deleting it.')
    env = dict(os.environ, PUB_CACHE='/private/tmp/wir-baseline-tools/pub-cache')
    subprocess.run([FLUTTER, '--suppress-analytics', 'create', '--no-pub', '--platforms=ios',
                    '--project-name=hiddify', '--org=dev.blizzardharness', str(HOST)], env=env, check=True)
    for name in ['lib', 'test', 'assets', 'integration_test']:
        target = HOST / name
        # Only default files inside the newly created test host are removed.
        if target.is_dir():
            shutil.rmtree(target)
        target.symlink_to(SOURCE / name, target_is_directory=True)
    for name in ['pubspec.yaml', 'pubspec.lock']:
        shutil.copyfile(SOURCE / name, HOST / name)
    subprocess.run([FLUTTER, '--suppress-analytics', 'pub', 'get', '--offline'],
                   cwd=HOST, env=env, check=True)
    if (HOST / 'pubspec.lock').read_bytes() != (SOURCE / 'pubspec.lock').read_bytes():
        raise RuntimeError('Fixture dependency graph changed; host rejected')
    podfile = HOST / 'ios/Podfile'
    contents = podfile.read_text()
    expected = "# platform :ios, '13.0'"
    if expected not in contents:
        raise RuntimeError('Unexpected template Podfile; inspect before continuing')
    podfile.write_text(contents.replace(expected, "platform :ios, '15.5'"))
    print('Isolated host ready; exact dependency lock preserved; no app group or VPN extension.')

if __name__ == '__main__':
    main()
