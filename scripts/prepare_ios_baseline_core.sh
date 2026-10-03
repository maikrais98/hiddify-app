#!/usr/bin/env bash

set -euo pipefail

EXPECTED_ARCHIVE_SHA256="31a03842df31fcebd8a1d43c883acd82f437639075815029f00859fb3470164b"
EXPECTED_ARCHIVE_SIZE="63496240"

usage() {
  printf 'Usage: %s --archive PATH --destination PATH\n' "${0##*/}" >&2
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

archive=""
destination=""

while (($# > 0)); do
  case "$1" in
    --archive)
      (($# >= 2)) || fail "--archive requires a path"
      [[ -z "$archive" ]] || fail "--archive may be specified only once"
      archive="$2"
      shift 2
      ;;
    --destination)
      (($# >= 2)) || fail "--destination requires a path"
      [[ -z "$destination" ]] || fail "--destination may be specified only once"
      destination="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      fail "unknown argument: $1"
      ;;
  esac
done

[[ -n "$archive" ]] || fail "--archive is required"
[[ -n "$destination" ]] || fail "--destination is required"
[[ -f "$archive" && ! -L "$archive" ]] || fail "archive must be an existing regular file"

actual_size="$(stat -f '%z' "$archive" 2>/dev/null || stat -c '%s' "$archive")"
[[ "$actual_size" == "$EXPECTED_ARCHIVE_SIZE" ]] || \
  fail "archive size mismatch: expected $EXPECTED_ARCHIVE_SIZE bytes"

actual_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
[[ "$actual_sha256" == "$EXPECTED_ARCHIVE_SHA256" ]] || \
  fail "archive SHA256 mismatch"

destination_parent="$(dirname "$destination")"
destination_name="$(basename "$destination")"
[[ "$destination_name" != "." && "$destination_name" != ".." && "$destination_name" != "/" ]] || \
  fail "destination must name a directory below its parent"

mkdir -p "$destination_parent"
work_root="$(mktemp -d "$destination_parent/.ios-baseline-core.XXXXXX")"
prepared_destination="$work_root/prepared"
backup_destination="$work_root/previous"
restore_previous=0

cleanup() {
  if ((restore_previous)) && [[ -e "$backup_destination" || -L "$backup_destination" ]]; then
    mv "$backup_destination" "$destination"
  fi
  rm -rf "$work_root"
}
trap cleanup EXIT

mkdir "$prepared_destination"

while IFS= read -r member; do
  normalized="${member#./}"
  case "$normalized" in
    HiddifyCore.xcframework|HiddifyCore.xcframework/*) ;;
    *) fail "archive contains an unexpected path" ;;
  esac
  case "/$normalized/" in
    */../*|*/./*) fail "archive contains an unsafe path" ;;
  esac
done < <(tar -tzf "$archive")

tar -xzf "$archive" -C "$prepared_destination"

xcframework="$prepared_destination/HiddifyCore.xcframework"
[[ -d "$xcframework" && ! -L "$xcframework" ]] || \
  fail "archive does not contain HiddifyCore.xcframework"

manifest="$prepared_destination/HiddifyCore.xcframework.sha256"
(
  cd "$prepared_destination"
  find HiddifyCore.xcframework -type f | LC_ALL=C sort | while IFS= read -r file; do
    digest="$(shasum -a 256 "$file" | awk '{print $1}')"
    printf '%s  %s\n' "$digest" "$file"
  done
) > "$manifest"

if [[ -e "$destination" || -L "$destination" ]]; then
  mv "$destination" "$backup_destination"
  restore_previous=1
fi

mv "$prepared_destination" "$destination"
restore_previous=0
