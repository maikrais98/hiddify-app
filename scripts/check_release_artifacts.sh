#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifact_dir="${1:-$repo_root/out}"
manifest_file="${2:-$repo_root/.github/release-artifacts.txt}"

if [[ ! -d "$artifact_dir" ]]; then
  echo "release artifact directory not found: $artifact_dir" >&2
  exit 1
fi

if [[ ! -f "$manifest_file" ]]; then
  echo "release artifact manifest not found: $manifest_file" >&2
  exit 2
fi

expected_names=()
while IFS= read -r expected || [[ -n "$expected" ]]; do
  expected="${expected%$'\r'}"
  [[ -z "$expected" || "$expected" == \#* ]] && continue
  for existing in "${expected_names[@]:-}"; do
    if [[ "$existing" == "$expected" ]]; then
      echo "duplicate release artifact in manifest: $expected" >&2
      exit 2
    fi
  done
  expected_names+=("$expected")
done < "$manifest_file"

if (( ${#expected_names[@]} == 0 )); then
  echo "release artifact manifest is empty: $manifest_file" >&2
  exit 2
fi

invalid=()
shopt -s dotglob nullglob
for entry in "$artifact_dir"/*; do
  name="$(basename "$entry")"
  expected_entry=false
  for expected in "${expected_names[@]}"; do
    if [[ "$name" == "$expected" ]]; then
      expected_entry=true
      break
    fi
  done

  if [[ "$expected_entry" != true ]]; then
    invalid+=("unexpected: $name")
  elif [[ -L "$entry" ]]; then
    invalid+=("symlink: $name")
  elif [[ ! -f "$entry" ]]; then
    invalid+=("not a regular file: $name")
  elif [[ ! -s "$entry" ]]; then
    invalid+=("empty: $name")
  fi
done

for expected in "${expected_names[@]}"; do
  entry="$artifact_dir/$expected"
  if [[ ! -e "$entry" && ! -L "$entry" ]]; then
    invalid+=("missing: $expected")
  fi
done

if (( ${#invalid[@]} > 0 )); then
  echo "release artifact check failed:" >&2
  printf '  - %s\n' "${invalid[@]}" >&2
  exit 1
fi

echo "release artifact check passed: exact top-level set of ${#expected_names[@]} regular, non-empty files"
