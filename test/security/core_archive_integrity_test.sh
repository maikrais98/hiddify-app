#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/core-archive-integrity.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
real_tar="$(command -v tar)"
tar_spy_log="$work_dir/tar-spy.log"

mkdir -p "$work_dir/bin"
cat > "$work_dir/bin/tar" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'called\n' >> "$TAR_SPY_LOG"
exec "$REAL_TAR" "$@"
EOF
chmod +x "$work_dir/bin/tar"

mkdir -p "$work_dir/source"
printf 'trusted native core fixture\n' > "$work_dir/source/core-marker"
archive="$work_dir/core-linux-amd64.tar.gz"
tar -czf "$archive" -C "$work_dir/source" core-marker

if command -v sha256sum >/dev/null 2>&1; then
  expected_digest="$(sha256sum "$archive" | awk '{print $1}')"
else
  expected_digest="$(shasum -a 256 "$archive" | awk '{print $1}')"
fi

> "$tar_spy_log"
PATH="$work_dir/bin:$PATH" REAL_TAR="$real_tar" TAR_SPY_LOG="$tar_spy_log" \
make -s -C "$repo_root" \
  CHANNEL=prod \
  CORE_URL="file://$work_dir" \
  CORE_NAME=core \
  DESKTOP_OUT="$work_dir/verified" \
  core.release.sha256.linux-amd64="$expected_digest" \
  linux-amd64-libs
test -f "$work_dir/verified/core-marker"
test "$(wc -l < "$tar_spy_log")" -eq 1

printf 'tamper' >> "$archive"
> "$tar_spy_log"
if PATH="$work_dir/bin:$PATH" REAL_TAR="$real_tar" TAR_SPY_LOG="$tar_spy_log" \
  make -s -C "$repo_root" \
  CHANNEL=prod \
  CORE_URL="file://$work_dir" \
  CORE_NAME=core \
  DESKTOP_OUT="$work_dir/tampered" \
  core.release.sha256.linux-amd64="$expected_digest" \
  linux-amd64-libs; then
  echo "tampered archive unexpectedly passed SHA-256 verification" >&2
  exit 1
fi
test ! -e "$work_dir/tampered/core-marker"
test ! -s "$tar_spy_log"

echo "core archive integrity checks passed"
