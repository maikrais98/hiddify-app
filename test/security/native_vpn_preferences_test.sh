#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/native-vpn-preferences.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

app_dir="$work_dir/PreferenceTests.app/Contents"
mkdir -p "$app_dir/MacOS"
cat > "$app_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>test.wir.preferences</string>
<key>CFBundleExecutable</key><string>native-vpn-preferences-test</string>
<key>BASE_BUNDLE_IDENTIFIER</key><string>test.wir.preferences</string>
</dict></plist>
PLIST

# Compile the complete, unchanged production class against a controlled OS API.
xcrun swiftc -swift-version 5 -emit-module -emit-library -module-name NetworkExtension \
  "$repo_root/test/native/fakes/NetworkExtension.swift" \
  -emit-module-path "$work_dir/NetworkExtension.swiftmodule" \
  -o "$work_dir/libNetworkExtension.dylib"
xcrun swiftc -swift-version 5 -I "$work_dir" -L "$work_dir" -lNetworkExtension \
  -Xlinker -rpath -Xlinker "$work_dir" \
  "$repo_root/ios/Shared/FilePath.swift" \
  "$repo_root/ios/Runner/Extensions/Bundle+Properties.swift" \
  "$repo_root/ios/Runner/VPN/VPNManager.swift" \
  "$repo_root/test/native/ios_vpn_preferences_test.swift" \
  -o "$app_dir/MacOS/native-vpn-preferences-test"
"$app_dir/MacOS/native-vpn-preferences-test"
