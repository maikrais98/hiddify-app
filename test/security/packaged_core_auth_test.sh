#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
swift_adapter="$repo_root/ios/HiddifyPacketTunnel/SingBox/ExtensionPlatformInterface.swift"
framework="$repo_root/ios/Frameworks/HiddifyCore.xcframework"
manifest="$framework/provenance.json"

require_source_contract() {
  grep -Fq 'public func startNeighborMonitor(' "$swift_adapter" || {
    echo "Swift adapter does not implement startNeighborMonitor" >&2
    exit 1
  }
  grep -Fq 'public func closeNeighborMonitor(' "$swift_adapter" || {
    echo "Swift adapter does not implement closeNeighborMonitor" >&2
    exit 1
  }
  grep -Fq 'public func registerMyInterface(' "$swift_adapter" || {
    echo "Swift adapter does not implement registerMyInterface" >&2
    exit 1
  }
  if grep -Fq 'dnsServer.value' "$swift_adapter"; then
    echo "Swift adapter still treats the DNS iterator as a scalar" >&2
    exit 1
  fi

  grep -Fq 'case "_test_setup_packaged_core":' \
    "$repo_root/ios/Runner/Handlers/MethodHandler.swift" || {
    echo "missing packaged-core test bridge" >&2
    exit 1
  }
  python3 - "$repo_root/ios/Runner/Handlers/MethodHandler.swift" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text()
debug_start = source.index("#if targetEnvironment(simulator)")
bridge = source.index('case "_test_setup_packaged_core":')
debug_end = source.index("#endif", bridge)
if not debug_start < bridge < debug_end:
    raise SystemExit("packaged-core bridge must be excluded from device builds")
PY

  ios_recipe="$(sed -n '/^ios-libs:/,/^\.PHONY:/p' "$repo_root/Makefile")"
  if [[ "$ios_recipe" == *'download_core_archive'* ]]; then
    echo "ios-libs still downloads a core archive instead of building pinned sources" >&2
    exit 1
  fi
  [[ "$ios_recipe" == *'scripts/build_ios_core.sh'* ]] || {
    echo "ios-libs does not use the provenance-enforcing source build" >&2
    exit 1
  }

  grep -Fq 'core.source.commit=f2034de743b1ad775dba026f4e6e3c44cf7d9790' \
    "$repo_root/dependencies.properties" || {
    echo "missing pinned hiddify-core source revision" >&2
    exit 1
  }
  grep -Fq 'core.source.sing-box.commit=170d8315cab7a8695fd80469073ed2f1d07d63af' \
    "$repo_root/dependencies.properties" || {
    echo "missing pinned hiddify-sing-box source revision" >&2
    exit 1
  }
}

require_source_contract
bash "$repo_root/test/security/core_source_provenance_test.sh"

if [[ "${1:-}" == "--contract-only" ]]; then
  echo "packaged core source contract checks passed"
  exit 0
fi

[[ -d "$framework" ]] || {
  echo "missing built HiddifyCore.xcframework" >&2
  exit 1
}
[[ -f "$manifest" ]] || {
  echo "missing HiddifyCore provenance manifest" >&2
  exit 1
}

python3 - "$repo_root" "$manifest" <<'PY'
import hashlib
import json
import pathlib
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
manifest_path = pathlib.Path(sys.argv[2])
manifest = json.loads(manifest_path.read_text())

expected = {
    "core_commit": subprocess.check_output(
        ["git", "-C", root / "hiddify-core", "rev-parse", "HEAD"], text=True
    ).strip(),
    "sing_box_commit": subprocess.check_output(
        ["git", "-C", root / "hiddify-core/hiddify-sing-box", "rev-parse", "HEAD"], text=True
    ).strip(),
    "patch_sha256": hashlib.sha256(
        (root / "patches/hiddify-core-local-control.patch.gz").read_bytes()
    ).hexdigest(),
    "source_tree": subprocess.check_output(
        [
            "bash",
            root / "scripts/verify_patched_source.sh",
            root / "hiddify-core",
            root / "patches/hiddify-core-local-control.patch.gz",
            "f2034de743b1ad775dba026f4e6e3c44cf7d9790",
        ],
        text=True,
    ).strip(),
}
for key, value in expected.items():
    if manifest.get(key) != value:
        raise SystemExit(f"provenance mismatch for {key}: {manifest.get(key)!r} != {value!r}")

for artifact in manifest.get("artifacts", []):
    path = root / artifact["path"]
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != artifact["sha256"]:
        raise SystemExit(f"artifact digest mismatch for {path}")

if not manifest.get("artifacts"):
    raise SystemExit("provenance manifest contains no artifact digests")
PY

device="${PACKAGED_CORE_PROBE_DEVICE:-}"
[[ -n "$device" ]] || {
  echo "PACKAGED_CORE_PROBE_DEVICE must name a booted iOS Simulator" >&2
  exit 2
}

flutter_bin="${FLUTTER_BIN:-/Users/stasyudkin/fvm/versions/3.38.5/bin/flutter}"
"$flutter_bin" test \
  --no-pub \
  -d "$device" \
  integration_test/packaged_core_auth_test.dart
