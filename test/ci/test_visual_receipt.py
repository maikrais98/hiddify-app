import copy
import hashlib
import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "verify_visual_receipt.py"
SOURCE_SHA = "19092ea5bdcec9b16a38dc792b66af45b29787a7"
DESIGN_SHA256 = "d" * 64
FIXTURE_SHA256 = "f" * 64
DRIVER_SHA256 = "e" * 64
CAPTURE_SCRIPT_SHA256 = "c" * 64
NATIVE_GLASS_SHA256 = "6" * 64
NATIVE_ADAPTER_SHA256 = "7" * 64
EMPTY_SHA256 = hashlib.sha256(b"").hexdigest()


def canonical_sha256(value):
    encoded = json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def load_module():
    spec = importlib.util.spec_from_file_location("verify_visual_receipt", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class VisualReceiptTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_module()

    def valid_capture(self):
        artifacts = [
            {
                "kind": "png",
                "name": name,
                "path": f"artifacts/{name}.png",
                "sha256": hashlib.sha256(name.encode()).hexdigest(),
            }
            for name in self.module.REQUIRED_COVERAGE
        ]
        artifacts.append(
            {
                "kind": "video",
                "name": "home_loop_16s",
                "path": "artifacts/home_loop_16s.mp4",
                "sha256": hashlib.sha256(b"home-loop").hexdigest(),
                "duration_seconds": 17.8,
                "frame_count": 534,
                "decoded_span_seconds": 17.8,
                "readiness": "simctl_stderr_recording_started",
            }
        )
        artifacts.append(
            {
                "kind": "video",
                "name": "lifecycle_tab_return",
                "path": "artifacts/lifecycle_tab_return.mp4",
                "sha256": hashlib.sha256(b"lifecycle-tab-return").hexdigest(),
                "duration_seconds": 2.0,
                "frame_count": 60,
                "decoded_span_seconds": 2.0,
                "readiness": "simctl_stderr_recording_started",
            }
        )
        return {
            "schema": "blizzard-visual-capture-v1",
            "result": "CAPTURE_COMPLETE",
            "source": {
                "git_sha": SOURCE_SHA,
                "status_sha256": EMPTY_SHA256,
                "tracked_diff_sha256": EMPTY_SHA256,
                "tree_sha256_before": "3" * 64,
                "tree_sha256_after": "3" * 64,
                "native_glass_sha256": NATIVE_GLASS_SHA256,
                "native_tab_bar_source_sha256": NATIVE_GLASS_SHA256,
                "native_tab_bar_registration": True,
                "native_glass_compiled_in_runner": True,
                "identity_files": {
                    "integration_test/blizzard_visual_acceptance_test.dart": DRIVER_SHA256,
                    "test/support/home_fixture.dart": FIXTURE_SHA256,
                    "scripts/blizzard_visual_acceptance.py": CAPTURE_SCRIPT_SHA256,
                },
            },
            "design": {
                "manifest_path": "design/final-source-manifest.json",
                "manifest_sha256": DESIGN_SHA256,
            },
            "runtime": {
                "platform": "ios",
                "target_kind": "simulator",
                "capture_exit_code": 0,
                "semantics_leak": False,
                "viewport_points": [393, 852],
                "native_tree_sha256_before": "4" * 64,
                "native_tree_sha256_after": "4" * 64,
                "native_glass_sha256_before": NATIVE_GLASS_SHA256,
                "native_glass_sha256_after": NATIVE_GLASS_SHA256,
                "native_host_adapter": "qa_no_vpn_app_delegate",
                "native_host_adapter_sha256_before": NATIVE_ADAPTER_SHA256,
                "native_host_adapter_sha256_after": NATIVE_ADAPTER_SHA256,
                "native_glass_registration": True,
                "native_tab_bar_registration": True,
                "lifecycle_driver": "framework_fixture",
                "app_metadata_source": "synthetic_fixture",
                "navigation_evidence": "rendered_state_fixture",
                "flutter": "3.38.5",
                "xcode": "26.6 (17F113)",
                "command": ["flutter", "test", "integration_test/blizzard_visual_acceptance_test.dart"],
                "home_frame_interval_seconds": 0.6,
                "home_frame_interval_basis": "native_io_start_to_start",
                "recorder_readiness_signal": "simctl_stderr_recording_started",
                "video_duration_basis": "avfoundation_asset_duration_after_full_frame_decode",
                "home_video_wall_seconds": 17.8,
                "lifecycle_video_wall_seconds": 2.0,
                "simulator": {"name": "Blizzard Visual 393x852", "runtime": "26.5"},
            },
            "coverage": {name: "CAPTURED" for name in self.module.REQUIRED_COVERAGE},
            "artifacts": artifacts,
            "capture_log": {"path": "capture.log", "sha256": "5" * 64},
        }

    def valid_receipt(self):
        capture = self.valid_capture()
        return {
            "schema": "blizzard-visual-review-v1",
            "review": {
                "reviewer_identity": "release-reviewer@example.invalid",
                "reviewed_at_utc": "2026-10-22T15:30:00Z",
                "verdict": "PASS",
            },
            "bindings": {
                "source_sha": SOURCE_SHA,
                "design_manifest_sha256": DESIGN_SHA256,
                "fixture_sha256": FIXTURE_SHA256,
                "driver_sha256": DRIVER_SHA256,
                "capture_script_sha256": CAPTURE_SCRIPT_SHA256,
                "capture_sha256": canonical_sha256(capture),
                "artifacts_sha256": canonical_sha256(capture["artifacts"]),
            },
            "region_verdicts": {
                "home": "PASS",
                "servers": "PASS",
                "profiles_and_sheets": "PASS",
                "settings": "PASS",
                "motion_and_lifecycle": "PASS",
            },
            "capture": capture,
        }

    def verify(self, receipt):
        self.module.verify_receipt(receipt, SOURCE_SHA, DESIGN_SHA256)

    def rebind_capture(self, receipt):
        receipt["bindings"]["capture_sha256"] = canonical_sha256(receipt["capture"])

    def rebind_artifacts(self, receipt):
        self.rebind_capture(receipt)
        receipt["bindings"]["artifacts_sha256"] = canonical_sha256(
            receipt["capture"]["artifacts"]
        )

    def test_accepts_independent_pass_bound_to_exact_capture(self):
        self.verify(self.valid_receipt())

    def test_rejects_source_and_design_mismatch(self):
        for field, value, message in [
            ("source_sha", "a" * 40, "source SHA"),
            ("design_manifest_sha256", "a" * 64, "design manifest"),
        ]:
            receipt = self.valid_receipt()
            receipt["bindings"][field] = value
            with self.subTest(field=field), self.assertRaisesRegex(
                self.module.VisualReceiptError, message
            ):
                self.verify(receipt)

    def test_rejects_fixture_driver_capture_script_and_artifact_mismatch(self):
        mutations = [
            (lambda r: r["bindings"].__setitem__("fixture_sha256", "a" * 64), "fixture"),
            (lambda r: r["bindings"].__setitem__("driver_sha256", "a" * 64), "driver"),
            (
                lambda r: r["bindings"].__setitem__("capture_script_sha256", "a" * 64),
                "capture script",
            ),
            (
                lambda r: r["capture"]["artifacts"][0].__setitem__("sha256", "a" * 64),
                "capture hash",
            ),
        ]
        for mutate, message in mutations:
            receipt = self.valid_receipt()
            mutate(receipt)
            with self.subTest(message=message), self.assertRaisesRegex(
                self.module.VisualReceiptError, message
            ):
                self.verify(receipt)

    def test_rejects_dirty_capture_from_the_same_git_sha(self):
        for field, content in [
            ("status_sha256", b" M lib/main.dart\n"),
            ("tracked_diff_sha256", b"diff --git a/lib/main.dart b/lib/main.dart\n"),
        ]:
            receipt = self.valid_receipt()
            receipt["capture"]["source"][field] = hashlib.sha256(content).hexdigest()
            receipt["bindings"]["capture_sha256"] = canonical_sha256(receipt["capture"])
            with self.subTest(field=field), self.assertRaisesRegex(
                self.module.VisualReceiptError, "clean committed source"
            ):
                self.verify(receipt)

    def test_rejects_missing_invalid_or_mismatched_native_host_hashes(self):
        mutations = [
            (lambda capture: capture["source"].pop("native_glass_sha256"), "native glass"),
            (
                lambda capture: capture["source"].__setitem__("native_glass_sha256", "not-hex"),
                "native glass",
            ),
            (
                lambda capture: capture["runtime"].__setitem__(
                    "native_glass_sha256_after", "8" * 64
                ),
                "native glass",
            ),
            (
                lambda capture: capture["runtime"].pop("native_host_adapter_sha256_before"),
                "native adapter",
            ),
            (
                lambda capture: capture["runtime"].__setitem__(
                    "native_host_adapter_sha256_after", "8" * 64
                ),
                "native adapter",
            ),
            (
                lambda capture: capture["runtime"].__setitem__("native_glass_registration", False),
                "registration",
            ),
        ]
        for mutate, message in mutations:
            receipt = self.valid_receipt()
            mutate(receipt["capture"])
            self.rebind_capture(receipt)
            with self.subTest(message=message), self.assertRaisesRegex(
                self.module.VisualReceiptError, message
            ):
                self.verify(receipt)

    def test_rejects_missing_invalid_or_substituted_native_tab_bar_source_hash(self):
        mutations = [
            lambda capture: capture["source"].pop("native_tab_bar_source_sha256"),
            lambda capture: capture["source"].__setitem__(
                "native_tab_bar_source_sha256", "not-hex"
            ),
            lambda capture: capture["source"].__setitem__(
                "native_tab_bar_source_sha256", "8" * 64
            ),
        ]
        for mutate in mutations:
            receipt = self.valid_receipt()
            mutate(receipt["capture"])
            self.rebind_capture(receipt)
            with self.subTest(mutate=mutate), self.assertRaisesRegex(
                self.module.VisualReceiptError, "native tab bar source"
            ):
                self.verify(receipt)

    def test_rejects_missing_false_or_substituted_native_menu_registration_proof(self):
        fields = [
            ("source", "native_tab_bar_registration"),
            ("source", "native_glass_compiled_in_runner"),
            ("runtime", "native_tab_bar_registration"),
        ]
        for location, field in fields:
            for value in (None, False, "true"):
                receipt = self.valid_receipt()
                target = receipt["capture"][location]
                if value is None:
                    target.pop(field)
                else:
                    target[field] = value
                self.rebind_capture(receipt)
                with self.subTest(
                    location=location, field=field, value=value
                ), self.assertRaisesRegex(
                    self.module.VisualReceiptError, "native menu registration proof"
                ):
                    self.verify(receipt)

    def test_rejects_overstated_runtime_scope_metadata(self):
        for field, value in [
            ("native_host_adapter", "production_app_delegate"),
            ("lifecycle_driver", "physical_device"),
            ("app_metadata_source", "installed_app"),
            ("navigation_evidence", "physical_navigation"),
        ]:
            receipt = self.valid_receipt()
            receipt["capture"]["runtime"][field] = value
            self.rebind_capture(receipt)
            with self.subTest(field=field), self.assertRaisesRegex(
                self.module.VisualReceiptError, "scope metadata"
            ):
                self.verify(receipt)

    def test_rejects_wrong_frame_basis_or_nonfinite_out_of_range_interval(self):
        mutations = [
            ("home_frame_interval_basis", "flutter_callback"),
            ("home_frame_interval_seconds", 0.54),
            ("home_frame_interval_seconds", 0.76),
            ("home_frame_interval_seconds", float("nan")),
            ("home_frame_interval_seconds", float("inf")),
        ]
        for field, value in mutations:
            receipt = self.valid_receipt()
            receipt["capture"]["runtime"][field] = value
            self.rebind_capture(receipt)
            with self.subTest(field=field, value=value), self.assertRaisesRegex(
                self.module.VisualReceiptError, "frame interval"
            ):
                self.verify(receipt)

    def test_rejects_missing_or_invalid_runtime_video_wall_durations(self):
        for field, value in [
            ("home_video_wall_seconds", 0),
            ("home_video_wall_seconds", float("nan")),
            ("lifecycle_video_wall_seconds", 0),
            ("lifecycle_video_wall_seconds", float("inf")),
        ]:
            receipt = self.valid_receipt()
            receipt["capture"]["runtime"][field] = value
            self.rebind_capture(receipt)
            with self.subTest(field=field, value=value), self.assertRaisesRegex(
                self.module.VisualReceiptError, "video duration"
            ):
                self.verify(receipt)

    def test_wall_duration_is_recorded_but_is_not_decoded_media_proof(self):
        receipt = self.valid_receipt()
        receipt["capture"]["runtime"]["home_video_wall_seconds"] = 0.01
        self.rebind_capture(receipt)
        self.verify(receipt)

    def test_rejects_missing_or_untrusted_recorder_readiness(self):
        for target, field, value in [
            ("runtime", "recorder_readiness_signal", None),
            ("runtime", "recorder_readiness_signal", "process_spawned"),
            ("video", "readiness", None),
            ("video", "readiness", "process_spawned"),
        ]:
            receipt = self.valid_receipt()
            if target == "runtime":
                if value is None:
                    receipt["capture"]["runtime"].pop(field)
                else:
                    receipt["capture"]["runtime"][field] = value
                self.rebind_capture(receipt)
            else:
                video = next(
                    artifact
                    for artifact in receipt["capture"]["artifacts"]
                    if artifact.get("kind") == "video"
                    and artifact.get("name") == "home_loop_16s"
                )
                if value is None:
                    video.pop(field)
                else:
                    video[field] = value
                self.rebind_artifacts(receipt)
            with self.subTest(target=target, value=value), self.assertRaisesRegex(
                self.module.VisualReceiptError, "readiness"
            ):
                self.verify(receipt)

    def test_rejects_missing_or_untrusted_decoded_video_basis(self):
        for value in (None, "wall_clock"):
            receipt = self.valid_receipt()
            if value is None:
                receipt["capture"]["runtime"].pop("video_duration_basis")
            else:
                receipt["capture"]["runtime"]["video_duration_basis"] = value
            self.rebind_capture(receipt)
            with self.subTest(value=value), self.assertRaisesRegex(
                self.module.VisualReceiptError, "duration basis"
            ):
                self.verify(receipt)

    def test_rejects_fake_or_short_decoded_home_video_metadata(self):
        for field, value in [
            ("frame_count", 0),
            ("frame_count", True),
            ("decoded_span_seconds", 15.99),
            ("decoded_span_seconds", float("nan")),
            ("duration_seconds", 15.99),
        ]:
            receipt = self.valid_receipt()
            video = next(
                artifact
                for artifact in receipt["capture"]["artifacts"]
                if artifact.get("kind") == "video"
                and artifact.get("name") == "home_loop_16s"
            )
            video[field] = value
            self.rebind_artifacts(receipt)
            with self.subTest(field=field, value=value), self.assertRaisesRegex(
                self.module.VisualReceiptError, "Home video"
            ):
                self.verify(receipt)

    def test_rejects_missing_decoded_lifecycle_video_metadata(self):
        for field in ("frame_count", "decoded_span_seconds"):
            receipt = self.valid_receipt()
            video = next(
                artifact
                for artifact in receipt["capture"]["artifacts"]
                if artifact.get("kind") == "video"
                and artifact.get("name") == "lifecycle_tab_return"
            )
            video.pop(field)
            self.rebind_artifacts(receipt)
            with self.subTest(field=field), self.assertRaisesRegex(
                self.module.VisualReceiptError, "lifecycle video"
            ):
                self.verify(receipt)

    def test_rejects_lifecycle_video_without_decoded_motion(self):
        for field, value in [
            ("frame_count", 1),
            ("decoded_span_seconds", 0),
        ]:
            receipt = self.valid_receipt()
            video = next(
                artifact
                for artifact in receipt["capture"]["artifacts"]
                if artifact.get("kind") == "video"
                and artifact.get("name") == "lifecycle_tab_return"
            )
            video[field] = value
            self.rebind_artifacts(receipt)
            with self.subTest(field=field, value=value), self.assertRaisesRegex(
                self.module.VisualReceiptError, "lifecycle video"
            ):
                self.verify(receipt)

    def test_requires_exact_named_png_artifact_contract(self):
        for mutate in (
            lambda png: png.pop("name"),
            lambda png: png.__setitem__("name", "settings"),
        ):
            receipt = self.valid_receipt()
            png = next(
                artifact
                for artifact in receipt["capture"]["artifacts"]
                if artifact.get("name") == "home_initial"
            )
            mutate(png)
            self.rebind_artifacts(receipt)
            with self.assertRaisesRegex(
                self.module.VisualReceiptError, "named PNG"
            ):
                self.verify(receipt)

    def test_requires_the_actual_producer_identity_map(self):
        receipt = self.valid_receipt()
        receipt["capture"]["source"]["identity_files"] = [
            {
                "role": "fixture",
                "path": "test/support/home_fixture.dart",
                "sha256": FIXTURE_SHA256,
            }
        ]
        receipt["bindings"]["capture_sha256"] = canonical_sha256(receipt["capture"])
        with self.assertRaisesRegex(self.module.VisualReceiptError, "identity files.*object"):
            self.verify(receipt)

    def test_rejects_coverage_without_the_matching_state_artifact(self):
        receipt = self.valid_receipt()
        artifact = next(
            item
            for item in receipt["capture"]["artifacts"]
            if item["path"].endswith("/quick_settings.png")
        )
        artifact["path"] = "artifacts/unrelated.png"
        receipt["bindings"]["capture_sha256"] = canonical_sha256(receipt["capture"])
        receipt["bindings"]["artifacts_sha256"] = canonical_sha256(
            receipt["capture"]["artifacts"]
        )
        with self.assertRaisesRegex(self.module.VisualReceiptError, "coverage artifact"):
            self.verify(receipt)

    def test_rejects_missing_short_or_extra_named_video(self):
        def rebind(receipt):
            receipt["bindings"]["capture_sha256"] = canonical_sha256(receipt["capture"])
            receipt["bindings"]["artifacts_sha256"] = canonical_sha256(
                receipt["capture"]["artifacts"]
            )

        cases = []
        missing = self.valid_receipt()
        missing["capture"]["artifacts"] = [
            artifact
            for artifact in missing["capture"]["artifacts"]
            if not (
                artifact.get("kind") == "video"
                and artifact.get("name") == "lifecycle_tab_return"
            )
        ]
        cases.append(("missing", missing))

        short_home = self.valid_receipt()
        next(
            artifact
            for artifact in short_home["capture"]["artifacts"]
            if artifact.get("kind") == "video"
            and artifact.get("name") == "home_loop_16s"
        )["duration_seconds"] = 15.99
        cases.append(("short home", short_home))

        empty_lifecycle = self.valid_receipt()
        next(
            artifact
            for artifact in empty_lifecycle["capture"]["artifacts"]
            if artifact.get("kind") == "video"
            and artifact.get("name") == "lifecycle_tab_return"
        )["duration_seconds"] = 0
        cases.append(("empty lifecycle", empty_lifecycle))

        extra = self.valid_receipt()
        extra["capture"]["artifacts"].append(
            {
                "kind": "video",
                "name": "extra",
                "path": "artifacts/extra.mp4",
                "sha256": hashlib.sha256(b"extra").hexdigest(),
                "duration_seconds": 1.0,
            }
        )
        cases.append(("extra", extra))

        for label, receipt in cases:
            rebind(receipt)
            with self.subTest(label=label), self.assertRaisesRegex(
                self.module.VisualReceiptError, "Home and lifecycle/tab videos"
            ):
                self.verify(receipt)

    def test_rejects_non_pass_review_and_region_verdicts(self):
        for verdict in ("FAIL", "BLOCKED", "NOT RUN"):
            receipt = self.valid_receipt()
            receipt["review"]["verdict"] = verdict
            with self.subTest(verdict=verdict), self.assertRaisesRegex(
                self.module.VisualReceiptError, "review verdict"
            ):
                self.verify(receipt)

        receipt = self.valid_receipt()
        receipt["region_verdicts"]["settings"] = "BLOCKED"
        with self.assertRaisesRegex(self.module.VisualReceiptError, "region verdict"):
            self.verify(receipt)

    def test_rejects_failed_capture_and_missing_coverage(self):
        receipt = self.valid_receipt()
        receipt["capture"]["runtime"]["capture_exit_code"] = 1
        receipt["bindings"]["capture_sha256"] = canonical_sha256(receipt["capture"])
        with self.assertRaisesRegex(self.module.VisualReceiptError, "capture exit"):
            self.verify(receipt)

        receipt = self.valid_receipt()
        receipt["capture"]["coverage"]["quick_settings"] = "NOT RUN"
        receipt["bindings"]["capture_sha256"] = canonical_sha256(receipt["capture"])
        with self.assertRaisesRegex(self.module.VisualReceiptError, "coverage"):
            self.verify(receipt)

    def test_capture_complete_cannot_self_approve(self):
        capture = self.valid_capture()
        with self.assertRaisesRegex(self.module.VisualReceiptError, "review receipt"):
            self.verify(capture)

        receipt = self.valid_receipt()
        receipt["review"]["reviewer_identity"] = "capture-job"
        with self.assertRaisesRegex(self.module.VisualReceiptError, "reviewer identity"):
            self.verify(receipt)

    def test_rejects_missing_reviewer_time_or_artifact_binding(self):
        receipt = self.valid_receipt()
        receipt["review"]["reviewed_at_utc"] = "2026-10-22T15:30:00+03:00"
        with self.assertRaisesRegex(self.module.VisualReceiptError, "UTC"):
            self.verify(receipt)

        receipt = self.valid_receipt()
        receipt["bindings"]["artifacts_sha256"] = "a" * 64
        with self.assertRaisesRegex(self.module.VisualReceiptError, "artifact binding"):
            self.verify(receipt)

    def test_cli_fails_closed_when_expected_design_digest_is_unconfigured(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / f"{SOURCE_SHA}.json"
            path.write_text(json.dumps(self.valid_receipt()), encoding="utf-8")
            completed = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--receipt",
                    str(path),
                    "--expected-source-sha",
                    SOURCE_SHA,
                    "--expected-design-manifest-sha256",
                    "",
                ],
                text=True,
                capture_output=True,
                check=False,
            )
        self.assertNotEqual(0, completed.returncode)
        self.assertEqual("ERROR_CODE=VISUAL_DESIGN_DIGEST_UNCONFIGURED\n", completed.stderr)


if __name__ == "__main__":
    unittest.main()
