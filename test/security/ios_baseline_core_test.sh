#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HELPER="$REPOSITORY_ROOT/scripts/prepare_ios_baseline_core.sh"
EXPECTED_ARCHIVE_SHA256="31a03842df31fcebd8a1d43c883acd82f437639075815029f00859fb3470164b"
EXPECTED_ARCHIVE_SIZE="63496240"

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$*"
}

assert_file_contains() {
  local file="$1"
  local expected="$2"
  local description="$3"

  grep -Fq -- "$expected" "$file" || fail "$description"
}

assert_command_fails() {
  local description="$1"
  shift

  if "$@"; then
    fail "$description"
  fi
}

if [[ ! -x "$HELPER" ]]; then
  fail "missing executable helper scripts/prepare_ios_baseline_core.sh"
fi
pass "production helper exists and is executable"

assert_file_contains "$HELPER" "$EXPECTED_ARCHIVE_SHA256" \
  "helper must pin the official core 4.1.0 SHA256"
assert_file_contains "$HELPER" "$EXPECTED_ARCHIVE_SIZE" \
  "helper must pin the official core 4.1.0 byte size"
pass "helper pins the official archive identity"

if grep -Eiq '(https?://|curl([[:space:]]|$)|wget([[:space:]]|$))' "$HELPER"; then
  fail "helper must prepare only the supplied local archive and contain no download path"
fi
pass "helper exposes no implicit archive download path"

ARCHIVE="${IOS_BASELINE_CORE_ARCHIVE:-}"
if [[ -z "$ARCHIVE" ]]; then
  fail "set IOS_BASELINE_CORE_ARCHIVE to the official local hiddify-lib-ios.tar.gz"
fi
if [[ ! -f "$ARCHIVE" ]]; then
  fail "IOS_BASELINE_CORE_ARCHIVE does not name a regular file"
fi

ACTUAL_ARCHIVE_SIZE="$(stat -f '%z' "$ARCHIVE" 2>/dev/null || stat -c '%s' "$ARCHIVE")"
[[ "$ACTUAL_ARCHIVE_SIZE" == "$EXPECTED_ARCHIVE_SIZE" ]] || \
  fail "test input does not have the official archive size"
ACTUAL_ARCHIVE_SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
[[ "$ACTUAL_ARCHIVE_SHA256" == "$EXPECTED_ARCHIVE_SHA256" ]] || \
  fail "test input does not have the official archive SHA256"
pass "test input is the pinned official core archive"

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ios-baseline-core-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

PROBE_BIN="$TEST_ROOT/probe-bin"
PROBE_LOG="$TEST_ROOT/probe.log"
mkdir -p "$PROBE_BIN"
printf '%s\n' \
  '#!/bin/sh' \
  'printf "%s\n" "${0##*/}" >> "$IOS_BASELINE_TEST_PROBE_LOG"' \
  'case "${0##*/}" in' \
  '  tar|bsdtar) exec /usr/bin/tar "$@" ;;' \
  '  *) exit 97 ;;' \
  'esac' > "$PROBE_BIN/probe"
chmod +x "$PROBE_BIN/probe"
for command_name in tar bsdtar curl wget git gh; do
  ln -s probe "$PROBE_BIN/$command_name"
done

MISSING_DESTINATION="$TEST_ROOT/missing-destination"
rm -f "$PROBE_LOG"
assert_command_fails \
  "missing archive path must be rejected" \
  env PATH="$PROBE_BIN:$PATH" IOS_BASELINE_TEST_PROBE_LOG="$PROBE_LOG" \
  "$HELPER" --archive "$TEST_ROOT/does-not-exist.tar.gz" --destination "$MISSING_DESTINATION"
[[ ! -e "$MISSING_DESTINATION" ]] || fail "missing archive failure must not create destination"
[[ ! -e "$PROBE_LOG" ]] || fail "missing archive failure must happen before extraction or network tools"
pass "missing archive fails before destination mutation or expensive tools"

TRUNCATED_ARCHIVE="$TEST_ROOT/hiddify-lib-ios-truncated.tar.gz"
head -c 1024 "$ARCHIVE" > "$TRUNCATED_ARCHIVE"
TRUNCATED_DESTINATION="$TEST_ROOT/truncated-destination"
rm -f "$PROBE_LOG"
assert_command_fails \
  "truncated archive must be rejected" \
  env PATH="$PROBE_BIN:$PATH" IOS_BASELINE_TEST_PROBE_LOG="$PROBE_LOG" \
  "$HELPER" --archive "$TRUNCATED_ARCHIVE" --destination "$TRUNCATED_DESTINATION"
[[ ! -e "$TRUNCATED_DESTINATION" ]] || fail "size rejection must not create destination"
[[ ! -e "$PROBE_LOG" ]] || fail "size rejection must happen before extraction or network tools"
pass "wrong-size archive fails before destination mutation or expensive tools"

CORRUPT_ARCHIVE="$TEST_ROOT/hiddify-lib-ios-corrupt.tar.gz"
cp "$ARCHIVE" "$CORRUPT_ARCHIVE"
printf 'X' | dd of="$CORRUPT_ARCHIVE" bs=1 seek=0 conv=notrunc status=none
[[ "$(stat -f '%z' "$CORRUPT_ARCHIVE" 2>/dev/null || stat -c '%s' "$CORRUPT_ARCHIVE")" == "$EXPECTED_ARCHIVE_SIZE" ]] || \
  fail "negative fixture must preserve the official byte size"
[[ "$(shasum -a 256 "$CORRUPT_ARCHIVE" | awk '{print $1}')" != "$EXPECTED_ARCHIVE_SHA256" ]] || \
  fail "negative fixture must change the archive SHA256"

CORRUPT_DESTINATION="$TEST_ROOT/corrupt-destination"
mkdir -p "$CORRUPT_DESTINATION"
printf 'keep-existing-destination\n' > "$CORRUPT_DESTINATION/sentinel.txt"
SENTINEL_SHA256="$(shasum -a 256 "$CORRUPT_DESTINATION/sentinel.txt" | awk '{print $1}')"
rm -f "$PROBE_LOG"
assert_command_fails \
  "same-size archive with the wrong digest must be rejected" \
  env PATH="$PROBE_BIN:$PATH" IOS_BASELINE_TEST_PROBE_LOG="$PROBE_LOG" \
  "$HELPER" --archive "$CORRUPT_ARCHIVE" --destination "$CORRUPT_DESTINATION"
[[ "$(shasum -a 256 "$CORRUPT_DESTINATION/sentinel.txt" | awk '{print $1}')" == "$SENTINEL_SHA256" ]] || \
  fail "digest rejection must leave existing destination bytes unchanged"
[[ "$(find "$CORRUPT_DESTINATION" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" == "1" ]] || \
  fail "digest rejection must not add destination entries"
[[ ! -e "$PROBE_LOG" ]] || fail "digest rejection must happen before extraction or network tools"
pass "corrupt same-size archive is rejected before extraction and destination mutation"

NETWORK_BIN="$TEST_ROOT/network-bin"
NETWORK_LOG="$TEST_ROOT/network.log"
mkdir -p "$NETWORK_BIN"
printf '%s\n' \
  '#!/bin/sh' \
  'printf "%s\n" "${0##*/}" >> "$IOS_BASELINE_TEST_NETWORK_LOG"' \
  'exit 97' > "$NETWORK_BIN/network-blocker"
chmod +x "$NETWORK_BIN/network-blocker"
for command_name in curl wget git gh; do
  ln -s network-blocker "$NETWORK_BIN/$command_name"
done

VALID_DESTINATION="$TEST_ROOT/valid-destination"
rm -f "$NETWORK_LOG"
env PATH="$NETWORK_BIN:$PATH" IOS_BASELINE_TEST_NETWORK_LOG="$NETWORK_LOG" \
  "$HELPER" --archive "$ARCHIVE" --destination "$VALID_DESTINATION"
[[ ! -e "$NETWORK_LOG" ]] || fail "valid preparation must not invoke network tools"

XCFRAMEWORK="$VALID_DESTINATION/HiddifyCore.xcframework"
MANIFEST="$VALID_DESTINATION/HiddifyCore.xcframework.sha256"
[[ -d "$XCFRAMEWORK" ]] || fail "valid preparation must install HiddifyCore.xcframework"
[[ -f "$MANIFEST" ]] || fail "valid preparation must write HiddifyCore.xcframework.sha256"

TOP_LEVEL_ENTRIES="$(find "$VALID_DESTINATION" -mindepth 1 -maxdepth 1 -exec basename {} \; | LC_ALL=C sort)"
[[ "$TOP_LEVEL_ENTRIES" == $'HiddifyCore.xcframework\nHiddifyCore.xcframework.sha256' ]] || \
  fail "destination must contain only the framework and its SHA256 manifest"
pass "valid preparation is local and has the exact output boundary"

DEVICE_FRAMEWORK="$XCFRAMEWORK/ios-arm64/HiddifyCore.framework"
SIMULATOR_FRAMEWORK="$XCFRAMEWORK/ios-arm64_x86_64-simulator/HiddifyCore.framework"
DEVICE_BINARY="$DEVICE_FRAMEWORK/Versions/A/HiddifyCore"
SIMULATOR_BINARY="$SIMULATOR_FRAMEWORK/Versions/A/HiddifyCore"
DEVICE_MODULE="$DEVICE_FRAMEWORK/Versions/A/Modules/module.modulemap"
SIMULATOR_MODULE="$SIMULATOR_FRAMEWORK/Versions/A/Modules/module.modulemap"

for required_file in \
  "$XCFRAMEWORK/Info.plist" \
  "$DEVICE_BINARY" "$SIMULATOR_BINARY" \
  "$DEVICE_MODULE" "$SIMULATOR_MODULE"; do
  [[ -f "$required_file" ]] || fail "missing required framework file: ${required_file#"$VALID_DESTINATION/"}"
done

[[ "$(lipo -archs "$DEVICE_BINARY")" == "arm64" ]] || \
  fail "device slice must contain only arm64"
SIMULATOR_ARCHS=" $(lipo -archs "$SIMULATOR_BINARY") "
[[ "$SIMULATOR_ARCHS" == *" arm64 "* && "$SIMULATOR_ARCHS" == *" x86_64 "* ]] || \
  fail "simulator slice must contain arm64 and x86_64"
[[ "$(wc -w <<< "$SIMULATOR_ARCHS" | tr -d ' ')" == "2" ]] || \
  fail "simulator slice must contain exactly two architectures"

assert_file_contains "$DEVICE_MODULE" 'framework module "HiddifyCore"' \
  "device slice must expose the HiddifyCore module"
assert_file_contains "$SIMULATOR_MODULE" 'framework module "HiddifyCore"' \
  "simulator slice must expose the HiddifyCore module"

EXPECTED_MANIFEST_PATHS="$TEST_ROOT/expected-manifest-paths.txt"
ACTUAL_MANIFEST_PATHS="$TEST_ROOT/actual-manifest-paths.txt"
(
  cd "$VALID_DESTINATION"
  find HiddifyCore.xcframework -type f | LC_ALL=C sort
) > "$EXPECTED_MANIFEST_PATHS"
sed 's/^[0-9a-f]\{64\}  //' "$MANIFEST" > "$ACTUAL_MANIFEST_PATHS"
cmp -s "$EXPECTED_MANIFEST_PATHS" "$ACTUAL_MANIFEST_PATHS" || \
  fail "framework manifest must cover every regular file exactly once in sorted relative-path order"
if grep -Evq '^[0-9a-f]{64}  HiddifyCore\.xcframework/' "$MANIFEST"; then
  fail "framework manifest must contain lowercase SHA256 and safe relative framework paths"
fi
(
  cd "$VALID_DESTINATION"
  shasum -a 256 -c HiddifyCore.xcframework.sha256 >/dev/null
) || fail "framework manifest digests must verify against prepared output"

pass "official device and simulator slices, modules, and complete SHA256 manifest verify"
printf '1..9\n'
