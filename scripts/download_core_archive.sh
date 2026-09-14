#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <archive-url> <expected-sha256> <destination>" >&2
  exit 2
fi

archive_url="$1"
expected_digest="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
destination="$3"

if [[ ! "$expected_digest" =~ ^[0-9a-f]{64}$ ]]; then
  echo "missing or invalid SHA-256 digest for native core archive" >&2
  exit 2
fi

archive_file="$(mktemp "${TMPDIR:-/tmp}/hiddify-core-archive.XXXXXX")"
trap 'rm -f "$archive_file"' EXIT

curl --fail --location --silent --show-error --output "$archive_file" "$archive_url"

if command -v sha256sum >/dev/null 2>&1; then
  actual_digest="$(sha256sum "$archive_file" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  actual_digest="$(shasum -a 256 "$archive_file" | awk '{print $1}')"
elif command -v openssl >/dev/null 2>&1; then
  actual_digest="$(openssl dgst -sha256 "$archive_file" | awk '{print $NF}')"
else
  echo "no SHA-256 tool available (sha256sum, shasum, or openssl required)" >&2
  exit 2
fi

actual_digest="$(printf '%s' "$actual_digest" | tr '[:upper:]' '[:lower:]')"
if [[ "$actual_digest" != "$expected_digest" ]]; then
  echo "SHA-256 mismatch for native core archive" >&2
  exit 1
fi

tar -xzf "$archive_file" -C "$destination"
