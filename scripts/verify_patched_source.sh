#!/usr/bin/env bash

set -euo pipefail

repo="${1:?source repository is required}"
patch_file="${2:?compressed patch is required}"
base_commit="${3:-HEAD}"

actual_head="$(git -C "$repo" rev-parse HEAD)"
expected_head="$(git -C "$repo" rev-parse "$base_commit")"
[[ "$actual_head" == "$expected_head" ]] || {
  echo "source HEAD mismatch: $actual_head != $expected_head" >&2
  exit 1
}

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
expected_index="$scratch/expected.index"
actual_index="$scratch/actual.index"

GIT_INDEX_FILE="$expected_index" git -C "$repo" read-tree "$expected_head"
gzip -dc "$patch_file" | GIT_INDEX_FILE="$expected_index" git -C "$repo" apply --cached -
expected_tree="$(GIT_INDEX_FILE="$expected_index" git -C "$repo" write-tree)"

GIT_INDEX_FILE="$actual_index" git -C "$repo" read-tree "$expected_head"
GIT_INDEX_FILE="$actual_index" git -C "$repo" add -A
actual_tree="$(GIT_INDEX_FILE="$actual_index" git -C "$repo" write-tree)"

[[ "$actual_tree" == "$expected_tree" ]] || {
  echo "source tree differs from pinned commit plus approved patch" >&2
  git -C "$repo" status --short --untracked-files=all >&2
  exit 1
}

ignored_go="$(git -C "$repo" ls-files --others --ignored --exclude-standard '*.go')"
[[ -z "$ignored_go" ]] || {
  echo "unexpected ignored Go sources:" >&2
  printf '%s\n' "$ignored_go" >&2
  exit 1
}

git -C "$repo" submodule foreach --quiet --recursive '
  dirty="$(git status --porcelain --untracked-files=all)"
  ignored_go="$(git ls-files --others --ignored --exclude-standard "*.go")"
  if test -n "$dirty" || test -n "$ignored_go"; then
    echo "nested source is dirty: $displaypath" >&2
    test -z "$dirty" || printf "%s\n" "$dirty" >&2
    test -z "$ignored_go" || printf "%s\n" "$ignored_go" >&2
    exit 1
  fi
'

printf '%s\n' "$expected_tree"
