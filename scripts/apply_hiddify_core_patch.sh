#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
core_dir="$repo_root/hiddify-core"
patch_file="$repo_root/patches/hiddify-core-local-control.patch.gz"
patch_tmp="$(mktemp "${TMPDIR:-/tmp}/hiddify-core-local-control.XXXXXX.patch")"
trap 'rm -f "$patch_tmp"' EXIT
gzip -dc "$patch_file" > "$patch_tmp"
sing_box_dir="$core_dir/hiddify-sing-box"
sing_box_commit="170d8315cab7a8695fd80469073ed2f1d07d63af"

if [[ ! -d "$core_dir/.git" && ! -f "$core_dir/.git" ]]; then
  echo "hiddify-core submodule is not initialized" >&2
  exit 1
fi

if git -C "$core_dir" apply --reverse --check "$patch_tmp" >/dev/null 2>&1; then
  echo "hiddify-core local-control patch already applied"
elif git -C "$core_dir" apply --check "$patch_tmp"; then
  git -C "$core_dir" apply "$patch_tmp"
  echo "applied hiddify-core local-control patch"
else
  echo "hiddify-core does not match the expected patch base" >&2
  exit 1
fi

git -C "$core_dir" submodule update --init hiddify-sing-box
if ! git -C "$sing_box_dir" cat-file -e "$sing_box_commit^{commit}" 2>/dev/null; then
  git -C "$sing_box_dir" fetch origin "$sing_box_commit"
fi
git -C "$sing_box_dir" checkout --detach "$sing_box_commit"
