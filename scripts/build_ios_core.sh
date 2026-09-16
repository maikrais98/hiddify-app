#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
core_dir="$repo_root/hiddify-core"
sing_box_dir="$core_dir/hiddify-sing-box"
properties="$repo_root/dependencies.properties"
patch_file="$repo_root/patches/hiddify-core-local-control.patch.gz"
destination="$repo_root/ios/Frameworks/HiddifyCore.xcframework"

property() {
  local key="$1"
  awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1) }' "$properties"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

expected_core_commit="$(property core.source.commit)"
expected_sing_box_commit="$(property core.source.sing-box.commit)"
expected_patch_digest="$(property core.source.patch.sha256)"
expected_gomobile_version="$(property core.ios.gomobile.version)"
minimum_xcode_major="$(property core.ios.minimum-xcode-major)"

for value in \
  "$expected_core_commit" \
  "$expected_sing_box_commit" \
  "$expected_patch_digest" \
  "$expected_gomobile_version" \
  "$minimum_xcode_major"; do
  [[ -n "$value" ]] || {
    echo "incomplete iOS source contract in dependencies.properties" >&2
    exit 1
  }
done

[[ -e "$core_dir/.git" ]] || {
  echo "hiddify-core is not initialized; run git submodule update --init hiddify-core" >&2
  exit 1
}

bash "$repo_root/scripts/apply_hiddify_core_patch.sh"

actual_core_commit="$(git -C "$core_dir" rev-parse HEAD)"
actual_sing_box_commit="$(git -C "$sing_box_dir" rev-parse HEAD)"
actual_patch_digest="$(sha256_file "$patch_file")"

[[ "$actual_core_commit" == "$expected_core_commit" ]] || {
  echo "hiddify-core source mismatch: $actual_core_commit" >&2
  exit 1
}
[[ "$actual_sing_box_commit" == "$expected_sing_box_commit" ]] || {
  echo "hiddify-sing-box source mismatch: $actual_sing_box_commit" >&2
  exit 1
}
[[ "$actual_patch_digest" == "$expected_patch_digest" ]] || {
  echo "hiddify-core patch digest mismatch: $actual_patch_digest" >&2
  exit 1
}
verified_source_tree="$(
  bash "$repo_root/scripts/verify_patched_source.sh" \
    "$core_dir" "$patch_file" "$expected_core_commit"
)"

xcode_version="$(xcodebuild -version | sed -n '1p')"
xcode_major="${xcode_version#Xcode }"
xcode_major="${xcode_major%%.*}"
[[ "$xcode_major" =~ ^[0-9]+$ && "$xcode_major" -ge "$minimum_xcode_major" ]] || {
  echo "Xcode $minimum_xcode_major or newer is required, found $xcode_version" >&2
  exit 1
}

rm -rf "$core_dir/bin/HiddifyCore.xcframework" "$destination"
PATH="$(go env GOPATH)/bin:$PATH" make -C "$core_dir" -f Makefile ios

gomobile_path="$(go env GOPATH)/bin/gomobile"
[[ -x "$gomobile_path" ]] || {
  echo "gomobile was not installed by the native build" >&2
  exit 1
}
actual_gomobile_version="$(go version -m "$gomobile_path" | awk '$1 == "mod" { print $3 }')"
[[ "$actual_gomobile_version" == "$expected_gomobile_version" ]] || {
  echo "gomobile version mismatch: $actual_gomobile_version" >&2
  exit 1
}

mv "$core_dir/bin/HiddifyCore.xcframework" "$destination"

device_binary="$destination/ios-arm64/HiddifyCore.framework/Versions/A/HiddifyCore"
simulator_binary="$destination/ios-arm64_x86_64-simulator/HiddifyCore.framework/Versions/A/HiddifyCore"
for binary in "$device_binary" "$simulator_binary"; do
  [[ -f "$binary" ]] || {
    echo "built XCFramework is missing $binary" >&2
    exit 1
  }
done

export WIR_REPO_ROOT="$repo_root"
export WIR_CORE_COMMIT="$actual_core_commit"
export WIR_SING_BOX_COMMIT="$actual_sing_box_commit"
export WIR_PATCH_SHA256="$actual_patch_digest"
export WIR_PATCH_CONTENT_SHA256="$(gzip -dc "$patch_file" | shasum -a 256 | awk '{print $1}')"
export WIR_SOURCE_TREE="$verified_source_tree"
export WIR_XCODE_VERSION="$(xcodebuild -version | tr '\n' ';' | sed 's/;$//')"
export WIR_SWIFT_VERSION="$(xcrun swift --version 2>&1 | sed -n '1p')"
export WIR_GO_VERSION="$(go version)"
export WIR_GOMOBILE_VERSION="$actual_gomobile_version"
export WIR_DEVICE_BINARY="$device_binary"
export WIR_SIMULATOR_BINARY="$simulator_binary"

python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

root = Path(os.environ["WIR_REPO_ROOT"])
framework = root / "ios/Frameworks/HiddifyCore.xcframework"
artifact_paths = [
    Path(os.environ["WIR_DEVICE_BINARY"]),
    Path(os.environ["WIR_SIMULATOR_BINARY"]),
]

manifest = {
    "schema_version": 1,
    "core_commit": os.environ["WIR_CORE_COMMIT"],
    "sing_box_commit": os.environ["WIR_SING_BOX_COMMIT"],
    "patch_sha256": os.environ["WIR_PATCH_SHA256"],
    "patch_content_sha256": os.environ["WIR_PATCH_CONTENT_SHA256"],
    "source_tree": os.environ["WIR_SOURCE_TREE"],
    "toolchain": {
        "xcode": os.environ["WIR_XCODE_VERSION"],
        "swift": os.environ["WIR_SWIFT_VERSION"],
        "go": os.environ["WIR_GO_VERSION"],
        "gomobile": os.environ["WIR_GOMOBILE_VERSION"],
    },
    "artifacts": [
        {
            "path": path.relative_to(root).as_posix(),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        }
        for path in artifact_paths
    ],
}
(framework / "provenance.json").write_text(
    json.dumps(manifest, indent=2, sort_keys=True) + "\n"
)
PY

echo "built pinned iOS core with provenance at $destination/provenance.json"
