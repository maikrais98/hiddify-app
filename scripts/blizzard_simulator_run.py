#!/usr/bin/env python3
"""Run the two-phase iOS fixture only on the unique named verification simulator."""
import argparse
import json
import os
import re
import queue
import threading
import time
from pathlib import Path
import subprocess
import sys
from ui_test_simulator_id import select_device

ROOT = Path(__file__).resolve().parents[1]
FLUTTER = '/private/tmp/wir-baseline-tools/flutter-3.38.5/bin/flutter'

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--test-host', action='store_true')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--visual-checks', action='store_true')
    mode.add_argument('--preserve-storage', action='store_true')
    args = parser.parse_args()
    # The default storage verification must survive Flutter test's uninstall.
    args.preserve_storage = not args.visual_checks
    run_root = Path('/private/tmp/blizzard-ios-test-host') if args.test_host else ROOT
    bundle_id = 'dev.blizzardharness.hiddify' if args.test_host else 'com.womaninred.baseline'
    inventory = json.loads(subprocess.check_output(
        ['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], text=True))
    selected = select_device(inventory)
    device = next(d for ds in inventory['devices'].values() for d in ds if d['udid'] == selected)
    if device['state'] != 'Booted':
        subprocess.run(['xcrun', 'simctl', 'boot', selected], check=True, capture_output=True)
    subprocess.run(['xcrun', 'simctl', 'bootstatus', selected, '-b'], check=True, capture_output=True)
    env = dict(os.environ, PUB_CACHE='/private/tmp/wir-baseline-tools/pub-cache')
    for phase in (['visual'] if args.visual_checks else ['write', 'read']):
        log = Path(f'/private/tmp/blizzard-ios-{phase}.log')
        command = [FLUTTER, '--suppress-analytics', 'test',
                   'integration_test/blizzard_preservation_test.dart', '--no-pub',
                   '-d', selected, f'--dart-define=BLIZZARD_STORAGE_PHASE={"write" if phase == "visual" else phase}']
        if args.visual_checks:
            command += ['--dart-define=BLIZZARD_VISUAL_CHECKS=true',
                        '--dart-define=BLIZZARD_VISUALS=true']
        if args.preserve_storage:
            # flutter test uninstalls its app in kill(); flutter run preserves data.
            command = [FLUTTER, '--suppress-analytics', 'run', '--no-pub', '-d', selected,
                       '--target', 'integration_test/blizzard_preservation_test.dart',
                       f'--dart-define=BLIZZARD_STORAGE_PHASE={phase}']
            process = subprocess.Popen(command, cwd=run_root, env=env, stdin=subprocess.PIPE,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            lines = queue.Queue()
            def collect():
                for line in process.stdout:
                    lines.put(line)
            threading.Thread(target=collect, daemon=True).start()
            passed = False
            deadline = time.monotonic() + 600
            with log.open('w') as output:
                while process.poll() is None and time.monotonic() < deadline:
                    try:
                        line = lines.get(timeout=1)
                    except queue.Empty:
                        continue
                    output.write(line)
                    output.flush()
                    if 'All tests passed' in line or 'Some tests failed' in line:
                        passed = 'All tests passed' in line
                        process.stdin.write('q\n')
                        process.stdin.flush()
                        break
                try:
                    process.wait(timeout=30)
                    while not lines.empty():
                        output.write(lines.get_nowait())
                except subprocess.TimeoutExpired:
                    process.terminate()
                    process.wait(timeout=10)
                    while not lines.empty():
                        output.write(lines.get_nowait())
            result = subprocess.CompletedProcess(command, 0 if passed and process.returncode == 0 else 1)
        else:
            with log.open('w') as output:
                result = subprocess.run(command, cwd=run_root, env=env, stdout=output, stderr=subprocess.STDOUT)
        # Flutter logs may contain the selector ID: keep persisted diagnostics redacted.
        content = log.read_text().replace(selected, '<selected-simulator>')
        content = re.sub(r'\b[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\b|\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}\b', '<device-id>', content)
        content = re.sub(r'name:iPhone \([^)]*\)', 'name:<physical-device>', content)
        log.write_text(content)
        print(f'phase={phase} exit={result.returncode} log={log}', flush=True)
        if result.returncode:
            return result.returncode
        storage_phase = 'write' if phase == 'visual' else phase
        if f'BLIZZARD_STORAGE backend=ios_shared_preferences phase={storage_phase}' not in content:
            raise RuntimeError('Missing native storage receipt')
        # flutter test exits the test process. Explicitly terminate the same host too;
        # a nonzero status means it is already stopped. Never reset/uninstall data.
        subprocess.run(['xcrun', 'simctl', 'terminate', selected, bundle_id], capture_output=True)
    return 0

if __name__ == '__main__':
    sys.exit(main())
