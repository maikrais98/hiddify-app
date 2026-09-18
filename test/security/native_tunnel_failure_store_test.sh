#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/native-tunnel-failure-store.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

xcrun swiftc -swift-version 5 \
  "$repo_root/ios/Shared/FilePath.swift" \
  "$repo_root/ios/HiddifyPacketTunnel/Logger.swift" \
  "$repo_root/test/native/ios_tunnel_failure_store_test.swift" \
  -o "$work_dir/native-tunnel-failure-store-test"
"$work_dir/native-tunnel-failure-store-test"
