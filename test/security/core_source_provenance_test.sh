#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

git -C "$fixture" init -q
git -C "$fixture" config user.email test@example.invalid
git -C "$fixture" config user.name 'Provenance Test'
printf 'package fixture\n\nconst Value = 1\n' > "$fixture/main.go"
git -C "$fixture" add main.go
git -C "$fixture" commit -qm base
base_commit="$(git -C "$fixture" rev-parse HEAD)"

printf 'package fixture\n\nconst Value = 2\n' > "$fixture/main.go"
printf 'package fixture\n\nconst Auth = true\n' > "$fixture/auth.go"
git -C "$fixture" diff --binary -- main.go > "$fixture.patch"
git -C "$fixture" diff --binary --no-index /dev/null auth.go >> "$fixture.patch" || true
gzip -c "$fixture.patch" > "$fixture.patch.gz"

bash "$repo_root/scripts/verify_patched_source.sh" \
  "$fixture" "$fixture.patch.gz" "$base_commit" >/dev/null

printf '\n// unapproved edit\n' >> "$fixture/main.go"
if bash "$repo_root/scripts/verify_patched_source.sh" \
  "$fixture" "$fixture.patch.gz" "$base_commit" >/dev/null 2>&1; then
  echo "provenance check accepted an extra tracked edit" >&2
  exit 1
fi
printf 'package fixture\n\nconst Value = 2\n' > "$fixture/main.go"

printf 'package fixture\n' > "$fixture/rogue.go"
if bash "$repo_root/scripts/verify_patched_source.sh" \
  "$fixture" "$fixture.patch.gz" "$base_commit" >/dev/null 2>&1; then
  echo "provenance check accepted an untracked Go source" >&2
  exit 1
fi

echo "core source provenance checks passed"
