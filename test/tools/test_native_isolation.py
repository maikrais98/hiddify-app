"""Guard release configuration while preparing a separately signed debug app.

These are source/configuration checks, not a substitute for Xcode or Keychain device tests.
"""
from pathlib import Path
import plistlib
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
BASELINE = '5b3d62165b782ba7ba2c44784681f52cc59b61a7'
PROJECT = 'ios/Runner.xcodeproj/project.pbxproj'
DEBUG_IDS = {'03E392C22ADDA00F000ADF15', '97C147061CF9000F007C117D'}

def baseline(path):
    return subprocess.check_output(['git', 'show', f'{BASELINE}:{path}'], cwd=ROOT)

def configurations(text):
    return dict(re.findall(r'([A-F0-9]{24}) /\* (?:Debug|Release|Profile) \*/ = (\{.*?\n\t\t\};)', text, re.S))

class NativeIsolationTest(unittest.TestCase):
    def test_only_runner_and_tunnel_debug_configuration_changed(self):
        old = configurations(baseline(PROJECT).decode())
        new = configurations((ROOT / PROJECT).read_text())
        self.assertGreater(len(old), 6)
        self.assertEqual(old.keys(), new.keys())
        for key in old:
            if key not in DEBUG_IDS:
                self.assertEqual(old[key], new[key], key)
            else:
                self.assertIn('BASE_BUNDLE_IDENTIFIER = com.womaninred.app.u3debug;', new[key])
                self.assertIn('CODE_SIGN_STYLE = Manual;', new[key])

    def test_original_release_plist_entitlements_and_base_configuration_are_unchanged(self):
        for path in ['ios/Runner/Info.plist', 'ios/Runner/Runner.entitlements',
                     'ios/HiddifyPacketTunnel/HiddifyPacketTunnel.entitlements', 'ios/Base.xcconfig',
                     'ios/Flutter/Release.xcconfig', 'HISTORY.md']:
            self.assertEqual(baseline(path).replace(b'\r\n', b'\n'),
                             (ROOT / path).read_bytes().replace(b'\r\n', b'\n'), path)

    def test_debug_plist_has_local_network_permission_and_no_shared_url_schemes(self):
        value = plistlib.loads((ROOT / 'ios/Runner/Info-U3Debug.plist').read_bytes())
        self.assertIs(value['LUMA_ACCOUNT_LAB'], True)
        self.assertTrue(value['NSLocalNetworkUsageDescription'])
        self.assertEqual(value['CFBundleDisplayName'], 'Luma U3 Lab')
        self.assertNotIn('CFBundleURLTypes', value)
        self.assertNotIn('NSAllowsArbitraryLoads', str(value))

if __name__ == '__main__':
    unittest.main()
