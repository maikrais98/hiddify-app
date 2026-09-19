#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
provider="$repo_root/ios/HiddifyPacketTunnel/SingBox/ExtensionProvider.swift"
logger="$repo_root/ios/HiddifyPacketTunnel/Logger.swift"
file_path="$repo_root/ios/Shared/FilePath.swift"
vpn_manager="$repo_root/ios/Runner/VPN/VPNManager.swift"
fixture="$repo_root/test/security/native_extension_log_privacy_test.swift"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/native-extension-log-privacy.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

if grep -Fq 'messageWithNewline' "$provider"; then
  echo "packet tunnel still persists native messages verbatim" >&2
  exit 1
fi
if grep -Fq 'logger.debug("\(message)")' "$provider" || grep -Fq 'logger.fault("Fatal error: \(message)")' "$provider"; then
  echo "packet tunnel still forwards native messages to unified logging" >&2
  exit 1
fi
if grep -Fq 'NSLocalizedDescriptionKey: message' "$provider"; then
  echo "packet tunnel still forwards raw native messages to the system error boundary" >&2
  exit 1
fi
if ! grep -Fq 'connection === self.manager.connection' "$vpn_manager"; then
  echo "VPN manager does not verify notification ownership" >&2
  exit 1
fi
ruby - "$vpn_manager" <<'RUBY'
source = File.read(ARGV.fetch(0))
connected = source[/if connection\.status == \.connected \{(.*?)\} else if connection\.status == \.disconnected/m, 1]
raise "VPN manager clears the active operation before a terminal state" if connected&.include?("currentOperationID = nil")
terminal = source[/else if connection\.status == \.disconnected \|\| connection\.status == \.invalid \{(.*?)\n            \}/m, 1]
raise "VPN manager does not consume the correlated native failure at a terminal state" unless terminal&.include?("consume(expectedOperationID: $0)")
raise "VPN manager does not clear the active operation after terminal consumption" unless terminal&.include?("currentOperationID = nil")
RUBY

xcrun swiftc -swift-version 5 "$file_path" "$logger" "$fixture" -o "$work_dir/native-extension-log-privacy-test"
"$work_dir/native-extension-log-privacy-test"
