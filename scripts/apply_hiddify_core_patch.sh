#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
core_dir="$repo_root/hiddify-core"
ray2sing_dir="$core_dir/ray2sing"
patch_file="$repo_root/patches/hiddify-core-local-control.patch.gz"
patch_tmp="$(mktemp "${TMPDIR:-/tmp}/hiddify-core-local-control.XXXXXX.patch")"
trap 'rm -f "$patch_tmp"' EXIT
gzip -dc "$patch_file" > "$patch_tmp"
sing_box_dir="$core_dir/hiddify-sing-box"
core_commit="f2034de743b1ad775dba026f4e6e3c44cf7d9790"
sing_box_commit="170d8315cab7a8695fd80469073ed2f1d07d63af"

if [[ ! -d "$core_dir/.git" && ! -f "$core_dir/.git" ]]; then
  echo "hiddify-core submodule is not initialized" >&2
  exit 1
fi

actual_core_commit="$(git -C "$core_dir" rev-parse HEAD)"
if [[ "$actual_core_commit" != "$core_commit" ]]; then
  echo "expected hiddify-core commit $core_commit, found $actual_core_commit" >&2
  exit 1
fi

ray2sing_path="$(
  git -C "$core_dir" config -f .gitmodules --get submodule.ray2sing.path
)"
ray2sing_url="$(
  git -C "$core_dir" config -f .gitmodules --get submodule.ray2sing.url
)"
if [[ "$ray2sing_path" != "ray2sing" || "$ray2sing_url" != "git@github.com:hiddify/ray2sing.git" ]]; then
  echo "unexpected pinned configuration for hiddify-core submodule ray2sing" >&2
  exit 1
fi
git -C "$core_dir" config --local --replace-all \
  submodule.ray2sing.url https://github.com/hiddify/ray2sing.git
git -C "$core_dir" submodule update --init ray2sing
expected_ray2sing_commit="$(git -C "$core_dir" rev-parse HEAD:ray2sing)"
actual_ray2sing_commit="$(git -C "$ray2sing_dir" rev-parse HEAD)"
if [[ "$actual_ray2sing_commit" != "$expected_ray2sing_commit" ]]; then
  echo "ray2sing is at $actual_ray2sing_commit instead of pinned $expected_ray2sing_commit" >&2
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

expected_submodules="$(printf '%s\n' \
  replace/psiphon-quic-go \
  replace/psiphon-tls \
  replace/tailscale \
  replace/wireguard-go | LC_ALL=C sort)"
actual_submodules="$(
  git -C "$sing_box_dir" config -f .gitmodules --name-only \
    --get-regexp '^submodule\..*\.url$' |
    sed -e 's/^submodule\.//' -e 's/\.url$//' |
    LC_ALL=C sort
)"
if [[ "$actual_submodules" != "$expected_submodules" ]]; then
  echo "hiddify-sing-box nested submodules do not match the expected public dependency set" >&2
  exit 1
fi

configure_https_submodule() {
  local name="$1"
  local repository="$2"
  local expected_ssh_url="git@github.com:hiddify/$repository"
  local https_url="https://github.com/hiddify/$repository"
  local configured_path
  local configured_url

  configured_path="$(
    git -C "$sing_box_dir" config -f .gitmodules --get "submodule.$name.path"
  )"
  configured_url="$(
    git -C "$sing_box_dir" config -f .gitmodules --get "submodule.$name.url"
  )"
  if [[ "$configured_path" != "$name" || "$configured_url" != "$expected_ssh_url" ]]; then
    echo "unexpected pinned configuration for hiddify-sing-box submodule $name" >&2
    exit 1
  fi

  git -C "$sing_box_dir" config --local --replace-all \
    "submodule.$name.url" "$https_url"
}

configure_https_submodule replace/tailscale tailscale
configure_https_submodule replace/psiphon-quic-go psiphon-quic-go
configure_https_submodule replace/psiphon-tls psiphon-tls
configure_https_submodule replace/wireguard-go wireguard-go
git -C "$sing_box_dir" submodule update --init --recursive

for path in \
  replace/tailscale \
  replace/psiphon-quic-go \
  replace/psiphon-tls \
  replace/wireguard-go; do
  expected_commit="$(git -C "$sing_box_dir" rev-parse "HEAD:$path")"
  actual_commit="$(git -C "$sing_box_dir/$path" rev-parse HEAD)"
  if [[ "$actual_commit" != "$expected_commit" ]]; then
    echo "$path is at $actual_commit instead of pinned $expected_commit" >&2
    exit 1
  fi
done
