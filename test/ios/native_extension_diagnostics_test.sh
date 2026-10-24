#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
provider="$repo_root/ios/HiddifyPacketTunnel/SingBox/ExtensionProvider.swift"
platform="$repo_root/ios/HiddifyPacketTunnel/SingBox/ExtensionPlatformInterface.swift"
failures=()

if grep -Fq 'diagnosticLog.reset()' "$provider"; then
  failures+=("tunnel start still resets native diagnostic history")
fi
for required in \
  'source: .extension' \
  'structuredFileURL: FilePath.workingDirectory.appendingPathComponent("extension-safe-diagnostics.json")' \
  'stopReason: Int(reason.rawValue)' \
  'phase: .sleep' \
  'phase: .wake'; do
  grep -Fq "$required" "$provider" || failures+=("provider missing: $required")
done

for required in \
  'recordNetworkSettingsRequested()' \
  'recordNetworkSettingsAccepted()' \
  'recordNetworkSettingsFailed(error)' \
  'recordTunDescriptorAccepted()' \
  'recordTunDescriptorUnavailable()'; do
  grep -Fq "$required" "$platform" || failures+=("platform missing: $required")
done

if grep -Eq 'recordTunDescriptor[^\n]*(tunFd|fileDescriptor)' "$platform"; then
  failures+=("TUN descriptor value reached diagnostics")
fi

if ((${#failures[@]})); then
  printf '%s\n' "${failures[@]}" >&2
  exit 1
fi

echo "native extension diagnostics source contract passed"
