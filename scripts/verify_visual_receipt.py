#!/usr/bin/env python3

import argparse
import hashlib
import json
import math
import pathlib
import re
import sys

REQUIRED_COVERAGE = (
    "home_initial",
    "home_600ms",
    "home_loop_16s",
    "settings",
    "servers",
    "profiles",
    "add_profile",
    "quick_settings",
    "lifecycle_return",
    "tab_return",
)

REQUIRED_REGIONS = (
    "home",
    "servers",
    "profiles_and_sheets",
    "settings",
    "motion_and_lifecycle",
)

_SHA40 = re.compile(r"^[0-9a-f]{40}$")
_SHA256 = re.compile(r"^[0-9a-f]{64}$")
_UTC_SECONDS = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
_EMPTY_SHA256 = hashlib.sha256(b"").hexdigest()
_AUTOMATED_REVIEWERS = frozenset(
    {"capture-job", "github-actions", "automation", "visual-capture"}
)
_IDENTITY_PATHS = {
    "fixture": "test/support/home_fixture.dart",
    "driver": "integration_test/blizzard_visual_acceptance_test.dart",
    "capture script": "scripts/blizzard_visual_acceptance.py",
}


class VisualReceiptError(ValueError):
    pass


def _mapping(value, label):
    if not isinstance(value, dict):
        raise VisualReceiptError(f"{label} must be an object")
    return value


def _sequence(value, label):
    if not isinstance(value, list):
        raise VisualReceiptError(f"{label} must be an array")
    return value


def _sha256(value, label):
    if not isinstance(value, str) or not _SHA256.fullmatch(value):
        raise VisualReceiptError(f"{label} must be a lowercase SHA-256")
    return value


def _finite_number(value, label):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise VisualReceiptError(f"{label} must be a finite number")
    return float(value)


def _positive_int(value, label):
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise VisualReceiptError(f"{label} must be a positive integer")
    return value


def _canonical_sha256(value):
    encoded = json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _identity_hashes(source):
    identities = _mapping(source.get("identity_files"), "capture identity files")
    result = {}
    for role, path in _IDENTITY_PATHS.items():
        if path not in identities:
            raise VisualReceiptError(f"missing {role} identity")
        result[role] = _sha256(identities[path], f"{role} hash")
    return result


def _verify_capture(capture, expected_source_sha, expected_design_sha256, bindings):
    if capture.get("schema") != "blizzard-visual-capture-v1":
        raise VisualReceiptError("unsupported capture schema")
    if capture.get("result") != "CAPTURE_COMPLETE":
        raise VisualReceiptError("capture is not complete")
    if "visual_verdict" in capture:
        raise VisualReceiptError("capture cannot contain a visual verdict")

    source = _mapping(capture.get("source"), "capture source")
    if source.get("git_sha") != expected_source_sha:
        raise VisualReceiptError("capture source SHA mismatch")
    for field in ("status_sha256", "tracked_diff_sha256", "tree_sha256_before", "tree_sha256_after"):
        _sha256(source.get(field), f"capture source {field}")
    if (
        source["status_sha256"] != _EMPTY_SHA256
        or source["tracked_diff_sha256"] != _EMPTY_SHA256
    ):
        raise VisualReceiptError("capture must come from clean committed source")
    if source["tree_sha256_before"] != source["tree_sha256_after"]:
        raise VisualReceiptError("source tree changed during capture")
    identities = _identity_hashes(source)
    binding_fields = {
        "fixture": "fixture_sha256",
        "driver": "driver_sha256",
        "capture script": "capture_script_sha256",
    }
    for role, field in binding_fields.items():
        if bindings.get(field) != identities[role]:
            raise VisualReceiptError(f"{role} binding mismatch")

    design = _mapping(capture.get("design"), "capture design")
    if design.get("manifest_sha256") != expected_design_sha256:
        raise VisualReceiptError("capture design manifest mismatch")

    runtime = _mapping(capture.get("runtime"), "capture runtime")
    if runtime.get("platform") != "ios" or runtime.get("target_kind") != "simulator":
        raise VisualReceiptError("capture must use the iOS simulator target")
    if runtime.get("capture_exit_code") != 0:
        raise VisualReceiptError("capture exit code is nonzero")
    if runtime.get("semantics_leak") is not False:
        raise VisualReceiptError("capture reports a semantics leak")
    if runtime.get("viewport_points") != [393, 852]:
        raise VisualReceiptError("capture viewport mismatch")
    for field in ("native_tree_sha256_before", "native_tree_sha256_after"):
        _sha256(runtime.get(field), f"capture runtime {field}")
    if runtime["native_tree_sha256_before"] != runtime["native_tree_sha256_after"]:
        raise VisualReceiptError("native tree changed during capture")
    native_glass = _sha256(source.get("native_glass_sha256"), "native glass hash")
    for field in ("native_glass_sha256_before", "native_glass_sha256_after"):
        if _sha256(runtime.get(field), f"runtime {field}") != native_glass:
            raise VisualReceiptError("native glass hash mismatch")
    if runtime.get("native_glass_registration") is not True:
        raise VisualReceiptError("native glass registration was not proven")
    if runtime.get("native_host_adapter") != "qa_no_vpn_app_delegate":
        raise VisualReceiptError("runtime scope metadata mismatch")
    adapter_before = _sha256(
        runtime.get("native_host_adapter_sha256_before"), "native adapter hash before"
    )
    adapter_after = _sha256(
        runtime.get("native_host_adapter_sha256_after"), "native adapter hash after"
    )
    if adapter_before != adapter_after:
        raise VisualReceiptError("native adapter hash mismatch")
    expected_scope = {
        "lifecycle_driver": "framework_fixture",
        "app_metadata_source": "synthetic_fixture",
        "navigation_evidence": "rendered_state_fixture",
    }
    if any(runtime.get(field) != expected for field, expected in expected_scope.items()):
        raise VisualReceiptError("runtime scope metadata mismatch")
    if runtime.get("home_frame_interval_basis") != "native_io_start_to_start":
        raise VisualReceiptError("capture frame interval basis mismatch")
    frame_interval = _finite_number(
        runtime.get("home_frame_interval_seconds"), "capture frame interval"
    )
    if not 0.55 <= frame_interval <= 0.75:
        raise VisualReceiptError("capture frame interval is outside 0.55 to 0.75 seconds")
    if runtime.get("recorder_readiness_signal") != "simctl_stderr_recording_started":
        raise VisualReceiptError("capture recorder readiness is missing or untrusted")
    if (
        runtime.get("video_duration_basis")
        != "avfoundation_asset_duration_after_full_frame_decode"
    ):
        raise VisualReceiptError("capture video duration basis is missing or untrusted")
    home_video_duration = _finite_number(
        runtime.get("home_video_wall_seconds"), "Home video duration wall measurement"
    )
    lifecycle_video_duration = _finite_number(
        runtime.get("lifecycle_video_wall_seconds"),
        "lifecycle video duration wall measurement",
    )
    if home_video_duration <= 0 or lifecycle_video_duration <= 0:
        raise VisualReceiptError("runtime video duration is incomplete")

    coverage = _mapping(capture.get("coverage"), "capture coverage")
    missing = [name for name in REQUIRED_COVERAGE if coverage.get(name) != "CAPTURED"]
    if missing:
        raise VisualReceiptError("required coverage is missing or not captured")

    artifacts = _sequence(capture.get("artifacts"), "capture artifacts")
    paths = set()
    state_artifacts = {name: 0 for name in REQUIRED_COVERAGE}
    videos = {}
    for artifact in artifacts:
        artifact = _mapping(artifact, "capture artifact")
        path = artifact.get("path")
        if not isinstance(path, str) or not path or path in paths:
            raise VisualReceiptError("capture artifact path is missing or duplicated")
        paths.add(path)
        _sha256(artifact.get("sha256"), "capture artifact hash")
        basename = pathlib.PurePath(path).name
        if artifact.get("kind") == "png":
            name = artifact.get("name")
            if name not in state_artifacts or basename != f"{name}.png":
                raise VisualReceiptError(
                    "capture requires the exact named PNG coverage artifact"
                )
            state_artifacts[name] += 1
        elif artifact.get("kind") == "video":
            name = artifact.get("name")
            if not isinstance(name, str) or name in videos or basename != f"{name}.mp4":
                raise VisualReceiptError("capture requires separate Home and lifecycle/tab videos")
            videos[name] = artifact
        else:
            raise VisualReceiptError("capture artifact kind is unsupported")
    if any(count != 1 for count in state_artifacts.values()):
        raise VisualReceiptError("each captured state requires one named coverage artifact")
    if set(videos) != {"home_loop_16s", "lifecycle_tab_return"}:
        raise VisualReceiptError("capture requires separate Home and lifecycle/tab videos")
    for name, artifact in videos.items():
        label = "Home video" if name == "home_loop_16s" else "lifecycle video"
        if artifact.get("readiness") != "simctl_stderr_recording_started":
            raise VisualReceiptError(f"{label} readiness is missing or untrusted")
        duration = _finite_number(artifact.get("duration_seconds"), f"{label} duration")
        frame_count = _positive_int(artifact.get("frame_count"), f"{label} frame count")
        decoded_span = _finite_number(
            artifact.get("decoded_span_seconds"), f"{label} decoded span"
        )
        if decoded_span < 0:
            raise VisualReceiptError(f"{label} decoded span must not be negative")
        if name == "home_loop_16s" and (
            duration < 16 or frame_count < 2 or decoded_span < 16
        ):
            raise VisualReceiptError(
                "Home video is shorter than 16 seconds; Home and lifecycle/tab videos require decoded proof"
            )
        if name == "lifecycle_tab_return" and duration <= 0:
            raise VisualReceiptError(
                "lifecycle video is empty; Home and lifecycle/tab videos require decoded proof"
            )

    capture_log = _mapping(capture.get("capture_log"), "capture log")
    _sha256(capture_log.get("sha256"), "capture log hash")


def verify_receipt(receipt, expected_source_sha, expected_design_manifest_sha256):
    receipt = _mapping(receipt, "review receipt")
    if receipt.get("schema") != "blizzard-visual-review-v1":
        raise VisualReceiptError("a separate visual review receipt is required")
    if not isinstance(expected_source_sha, str) or not _SHA40.fullmatch(expected_source_sha):
        raise VisualReceiptError("expected source SHA is invalid")
    if not expected_design_manifest_sha256:
        raise VisualReceiptError("expected design manifest is unconfigured")
    _sha256(expected_design_manifest_sha256, "expected design manifest")

    review = _mapping(receipt.get("review"), "review")
    reviewer = review.get("reviewer_identity")
    if (
        not isinstance(reviewer, str)
        or not reviewer.strip()
        or reviewer.strip().lower() in _AUTOMATED_REVIEWERS
    ):
        raise VisualReceiptError("reviewer identity must name an independent reviewer")
    reviewed_at = review.get("reviewed_at_utc")
    if not isinstance(reviewed_at, str) or not _UTC_SECONDS.fullmatch(reviewed_at):
        raise VisualReceiptError("review time must be explicit UTC with a Z suffix")
    if review.get("verdict") != "PASS":
        raise VisualReceiptError("review verdict must be PASS")

    bindings = _mapping(receipt.get("bindings"), "review bindings")
    if bindings.get("source_sha") != expected_source_sha:
        raise VisualReceiptError("review source SHA mismatch")
    if bindings.get("design_manifest_sha256") != expected_design_manifest_sha256:
        raise VisualReceiptError("review design manifest mismatch")
    for field in (
        "fixture_sha256",
        "driver_sha256",
        "capture_script_sha256",
        "capture_sha256",
        "artifacts_sha256",
    ):
        _sha256(bindings.get(field), f"review {field}")

    regions = _mapping(receipt.get("region_verdicts"), "region verdicts")
    if any(regions.get(name) != "PASS" for name in REQUIRED_REGIONS):
        raise VisualReceiptError("every required region verdict must be PASS")

    capture = _mapping(receipt.get("capture"), "capture")
    if bindings["capture_sha256"] != _canonical_sha256(capture):
        raise VisualReceiptError("capture hash binding mismatch")
    if bindings["artifacts_sha256"] != _canonical_sha256(capture.get("artifacts")):
        raise VisualReceiptError("artifact binding mismatch")
    _verify_capture(
        capture,
        expected_source_sha,
        expected_design_manifest_sha256,
        bindings,
    )


def _parse_args(argv=None):
    parser = argparse.ArgumentParser(description="Verify a Blizzard visual review receipt")
    parser.add_argument("--receipt", required=True, type=pathlib.Path)
    parser.add_argument("--expected-source-sha", required=True)
    parser.add_argument("--expected-design-manifest-sha256", required=True)
    return parser.parse_args(argv)


def main(argv=None):
    args = _parse_args(argv)
    if not args.expected_design_manifest_sha256:
        print("ERROR_CODE=VISUAL_DESIGN_DIGEST_UNCONFIGURED", file=sys.stderr)
        return 1
    try:
        receipt = json.loads(args.receipt.read_text(encoding="utf-8"))
        verify_receipt(
            receipt,
            args.expected_source_sha,
            args.expected_design_manifest_sha256,
        )
    except FileNotFoundError:
        print("ERROR_CODE=VISUAL_RECEIPT_MISSING", file=sys.stderr)
        return 1
    except (json.JSONDecodeError, OSError, VisualReceiptError):
        print("ERROR_CODE=VISUAL_RECEIPT_INVALID", file=sys.stderr)
        return 1
    print("VISUAL_RECEIPT_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
