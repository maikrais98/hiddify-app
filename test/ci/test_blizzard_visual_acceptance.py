import importlib.util
import io
import json
import os
import pathlib
import signal
import struct
import subprocess
import tempfile
import threading
import time
import unittest
import zlib
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "scripts" / "blizzard_visual_acceptance.py"


def load_module():
    spec = importlib.util.spec_from_file_location("blizzard_visual_acceptance", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class BlizzardVisualAcceptanceTest(unittest.TestCase):
    def setUp(self):
        self.module = load_module()
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        self.pngs = {}
        for index, name in enumerate(self.module.REQUIRED_SCREENSHOTS):
            path = self.root / f"{name}.png"
            self._write_png(path, red=index)
            self.pngs[name] = path
        self.home_video = self.root / "home.mp4"
        self.home_video.write_bytes(b"home-video")
        self.lifecycle_video = self.root / "lifecycle.mp4"
        self.lifecycle_video.write_bytes(b"lifecycle-video")
        self.capture_log = self.root / "capture.log"
        self.capture_log.write_text("capture complete\n")

    def tearDown(self):
        self.temp.cleanup()

    @staticmethod
    def _write_png(path, red=0):
        width, height = 786, 1704
        raw = b"".join(b"\x00" + bytes((red, 0, 0)) * width for _ in range(height))

        def chunk(kind, payload):
            return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))

        path.write_bytes(
            b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw))
            + chunk(b"IEND", b"")
        )

    def _write_source_directories(self, candidate):
        for name in self.module.SOURCE_DIRS:
            (candidate / name).mkdir(parents=True, exist_ok=True)

    @staticmethod
    def _write_qa_template_registration(template):
        app_delegate = template / "ios" / "Runner" / "AppDelegate.swift"
        app_delegate.parent.mkdir(parents=True, exist_ok=True)
        app_delegate.write_text(
            """import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    registrar(forPlugin: "BlizzardNativeGlass")?.register(
      BlizzardNativeGlassFactory(), withId: "app.blizzard/native-liquid-glass"
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
"""
        )

    @staticmethod
    def _write_native_candidate_contract(candidate, *, include_tab_registration=True, include_compile_membership=True):
        runner = candidate / "ios" / "Runner"
        runner.mkdir(parents=True, exist_ok=True)
        (runner / "BlizzardNativeGlass.swift").write_text("final class BlizzardNativeTabBarFactory {}")
        tab_registration = ""
        if include_tab_registration:
            tab_registration = """        if let nativeTabBarRegistrar = registrar(forPlugin: "BlizzardNativeTabBar") {
            nativeTabBarRegistrar.register(
                BlizzardNativeTabBarFactory(messenger: nativeTabBarRegistrar.messenger()),
                withId: "app.blizzard/native-tab-bar"
            )
        }
"""
        (runner / "AppDelegate.swift").write_text(
            """        registrar(forPlugin: "BlizzardNativeGlass")?.register(
            BlizzardNativeGlassFactory(), withId: "app.blizzard/native-liquid-glass"
        )
"""
            + tab_registration
        )
        project = candidate / "ios" / "Runner.xcodeproj" / "project.pbxproj"
        project.parent.mkdir(parents=True, exist_ok=True)
        source_entry = "        A1 /* BlizzardNativeGlass.swift in Sources */,\n" if include_compile_membership else ""
        project.write_text(
            """A1 /* BlizzardNativeGlass.swift in Sources */ = {isa = PBXBuildFile; fileRef = B1 /* BlizzardNativeGlass.swift */; };
C1 /* Runner */ = {
    isa = PBXNativeTarget;
    buildPhases = (
        D1 /* Sources */,
    );
};
D1 /* Sources */ = {
    isa = PBXSourcesBuildPhase;
    files = (
"""
            + source_entry
            + """    );
};
"""
        )

    def validate(self, receipt, source="abc123", design="design"):
        probes = {
            self.home_video.resolve(): {"duration_seconds": 16.5, "frame_count": 17, "decoded_span_seconds": 16.4},
            self.lifecycle_video.resolve(): {"duration_seconds": 2.0, "frame_count": 2, "decoded_span_seconds": 1.9},
        }
        with mock.patch.object(self.module, "_probe_video", side_effect=lambda path: probes[path.resolve()]):
            self.module.validate_receipt(receipt, source, design)

    def valid_receipt(self):
        return {
            "schema": "blizzard-visual-capture-v1",
            "result": "CAPTURE_COMPLETE",
            "source": {
                "git_sha": "abc123",
                "tree_sha256_before": "tree",
                "tree_sha256_after": "tree",
                "native_glass_sha256": "glass",
                "native_tab_bar_source_sha256": "glass",
                "native_tab_bar_registration": True,
                "native_glass_compiled_in_runner": True,
            },
            "design": {"manifest_sha256": "design"},
            "runtime": {
                "platform": "ios",
                "target_kind": "simulator",
                "capture_exit_code": 0,
                "semantics_leak": False,
                "viewport_points": [393, 852],
                "native_tree_sha256_before": "native",
                "native_tree_sha256_after": "native",
                "native_glass_sha256_before": "glass",
                "native_glass_sha256_after": "glass",
                "native_host_adapter": "qa_no_vpn_app_delegate",
                "native_host_adapter_sha256_before": "adapter",
                "native_host_adapter_sha256_after": "adapter",
                "native_glass_registration": True,
                "native_tab_bar_registration": True,
                "home_frame_interval_seconds": 0.6,
                "home_frame_interval_basis": "native_io_start_to_start",
                "lifecycle_driver": "framework_fixture",
                "app_metadata_source": "synthetic_fixture",
                "navigation_evidence": "rendered_state_fixture",
                "recorder_readiness_signal": "simctl_stderr_recording_started",
                "video_duration_basis": "avfoundation_asset_duration_after_full_frame_decode",
                "home_video_wall_seconds": 16.5,
                "lifecycle_video_wall_seconds": 2.0,
            },
            "coverage": {
                name: "CAPTURED"
                for name in self.module.REQUIRED_COVERAGE
            },
            "artifacts": [
                *[
                    {
                        "kind": "png",
                        "name": name,
                        "path": str(path),
                        "sha256": self.module.sha256_file(path),
                        "pixels": [786, 1704],
                    }
                    for name, path in self.pngs.items()
                ],
                {
                    "kind": "video",
                    "name": "home_loop_16s",
                    "path": str(self.home_video),
                    "sha256": self.module.sha256_file(self.home_video),
                    "duration_seconds": 16.5,
                    "frame_count": 17,
                    "decoded_span_seconds": 16.4,
                    "readiness": "simctl_stderr_recording_started",
                },
                {
                    "kind": "video",
                    "name": "lifecycle_tab_return",
                    "path": str(self.lifecycle_video),
                    "sha256": self.module.sha256_file(self.lifecycle_video),
                    "duration_seconds": 2.0,
                    "frame_count": 2,
                    "decoded_span_seconds": 1.9,
                    "readiness": "simctl_stderr_recording_started",
                },
            ],
            "capture_log": {
                "path": str(self.capture_log),
                "sha256": self.module.sha256_file(self.capture_log),
            },
        }

    def test_valid_capture_is_complete_but_never_self_approved(self):
        receipt = self.valid_receipt()
        self.validate(receipt)
        self.assertNotIn("visual_verdict", receipt)
        self.assertNotEqual(receipt["result"], "PASS")

    def test_rejects_source_or_design_identity_from_receipt_itself(self):
        receipt = self.valid_receipt()
        with self.assertRaisesRegex(self.module.AcceptanceError, "source SHA"):
            self.validate(receipt, "different", "design")
        with self.assertRaisesRegex(self.module.AcceptanceError, "design manifest"):
            self.validate(receipt, "abc123", "different")

    def test_rejects_failed_capture_semantics_leak_and_missing_coverage(self):
        for field, value, message in [
            ("capture_exit_code", 1, "capture exit"),
            ("semantics_leak", True, "semantics leak"),
            ("platform", "macos", "actual iOS"),
        ]:
            receipt = self.valid_receipt()
            receipt["runtime"][field] = value
            with self.assertRaisesRegex(self.module.AcceptanceError, message):
                self.validate(receipt)
        receipt = self.valid_receipt()
        receipt["coverage"][self.module.REQUIRED_COVERAGE[0]] = "NOT_RUN"
        with self.assertRaisesRegex(self.module.AcceptanceError, "coverage"):
            self.validate(receipt)

    def test_rejects_changed_or_substituted_artifacts_and_short_video(self):
        receipt = self.valid_receipt()
        receipt["artifacts"][0]["sha256"] = "0" * 64
        with self.assertRaisesRegex(self.module.AcceptanceError, "artifact hash"):
            self.validate(receipt)
        receipt = self.valid_receipt()
        home_video = next(
            item for item in receipt["artifacts"] if item.get("kind") == "video" and item.get("name") == "home_loop_16s"
        )
        home_video["duration_seconds"] = 15.99
        with self.assertRaisesRegex(self.module.AcceptanceError, "decoded media"):
            self.validate(receipt)
        receipt = self.valid_receipt()
        receipt["source"]["tree_sha256_after"] = "changed"
        with self.assertRaisesRegex(self.module.AcceptanceError, "changed during capture"):
            self.validate(receipt)
        receipt = self.valid_receipt()
        receipt["runtime"]["native_tree_sha256_after"] = "changed"
        with self.assertRaisesRegex(self.module.AcceptanceError, "native host changed"):
            self.validate(receipt)
        receipt = self.valid_receipt()
        receipt["runtime"]["native_glass_sha256_before"] = "template-glass"
        with self.assertRaisesRegex(self.module.AcceptanceError, "candidate native glass"):
            self.validate(receipt)
        receipt = self.valid_receipt()
        receipt["runtime"]["native_glass_registration"] = False
        with self.assertRaisesRegex(self.module.AcceptanceError, "native glass registration"):
            self.validate(receipt)
        receipt = self.valid_receipt()
        del receipt["runtime"]["native_tab_bar_registration"]
        with self.assertRaisesRegex(self.module.AcceptanceError, "native tab bar registration"):
            self.validate(receipt)
        receipt = self.valid_receipt()
        receipt["source"]["native_tab_bar_registration"] = False
        with self.assertRaisesRegex(self.module.AcceptanceError, "production native tab bar registration"):
            self.validate(receipt)
        receipt = self.valid_receipt()
        receipt["source"]["native_glass_compiled_in_runner"] = False
        with self.assertRaisesRegex(self.module.AcceptanceError, "native glass compile membership"):
            self.validate(receipt)
        receipt = self.valid_receipt()
        receipt["source"]["native_tab_bar_source_sha256"] = "substituted-native-tab-bar"
        with self.assertRaisesRegex(self.module.AcceptanceError, "shared native glass source"):
            self.validate(receipt)
        receipt = self.valid_receipt()
        receipt["runtime"]["native_host_adapter_sha256_after"] = "changed"
        with self.assertRaisesRegex(self.module.AcceptanceError, "QA native adapter changed"):
            self.validate(receipt)
        receipt = self.valid_receipt()
        receipt["runtime"]["home_frame_interval_seconds"] = 1.6
        with self.assertRaisesRegex(self.module.AcceptanceError, "600 ms"):
            self.validate(receipt)
        receipt = self.valid_receipt()
        receipt["runtime"]["home_frame_interval_basis"] = "capture_complete_to_start"
        with self.assertRaisesRegex(self.module.AcceptanceError, "start-to-start"):
            self.validate(receipt)

    def test_rejects_missing_or_reused_screenshot_artifacts_and_invalid_png(self):
        receipt = self.valid_receipt()
        receipt["artifacts"] = [item for item in receipt["artifacts"] if item.get("name") != "settings"]
        with self.assertRaisesRegex(self.module.AcceptanceError, "screenshot artifacts"):
            self.validate(receipt)

        receipt = self.valid_receipt()
        screenshots = [item for item in receipt["artifacts"] if item["kind"] == "png"]
        screenshots[1]["path"] = screenshots[0]["path"]
        screenshots[1]["sha256"] = screenshots[0]["sha256"]
        with self.assertRaisesRegex(self.module.AcceptanceError, "duplicate artifact path"):
            self.validate(receipt)

        receipt = self.valid_receipt()
        settings = next(item for item in receipt["artifacts"] if item.get("name") == "settings")
        settings_path = pathlib.Path(settings["path"])
        settings_path.write_bytes(b"\x89PNG\r\n\x1a\ntruncated")
        settings["sha256"] = self.module.sha256_file(settings_path)
        with self.assertRaisesRegex(self.module.AcceptanceError, "valid PNG"):
            self.validate(receipt)

    def test_rejects_reused_or_unreadable_video_and_capture_log_mismatch(self):
        receipt = self.valid_receipt()
        lifecycle = next(item for item in receipt["artifacts"] if item.get("name") == "lifecycle_tab_return")
        lifecycle["path"] = str(self.home_video)
        lifecycle["sha256"] = self.module.sha256_file(self.home_video)
        with self.assertRaisesRegex(self.module.AcceptanceError, "duplicate artifact path"):
            self.validate(receipt)

        receipt = self.valid_receipt()
        with mock.patch.object(
            self.module,
            "_probe_video",
            return_value={"duration_seconds": 0.0, "frame_count": 0, "decoded_span_seconds": 0.0},
        ):
            with self.assertRaisesRegex(self.module.AcceptanceError, "decodable video frames"):
                self.module.validate_receipt(receipt, "abc123", "design")

        receipt = self.valid_receipt()
        receipt["capture_log"]["sha256"] = "0" * 64
        with self.assertRaisesRegex(self.module.AcceptanceError, "capture log hash"):
            self.validate(receipt)

    def test_requires_real_recorder_readiness_and_decoded_home_span(self):
        receipt = self.valid_receipt()
        receipt["runtime"]["recorder_readiness_signal"] = "process_alive"
        with self.assertRaisesRegex(self.module.AcceptanceError, "readiness signal"):
            self.validate(receipt)

        receipt = self.valid_receipt()
        receipt["runtime"]["video_duration_basis"] = "wall_clock"
        with self.assertRaisesRegex(self.module.AcceptanceError, "duration basis"):
            self.validate(receipt)

        receipt = self.valid_receipt()
        home_video = next(
            item for item in receipt["artifacts"] if item.get("kind") == "video" and item.get("name") == "home_loop_16s"
        )
        home_video["readiness"] = "process_alive"
        with self.assertRaisesRegex(self.module.AcceptanceError, "readiness evidence"):
            self.validate(receipt)

        receipt = self.valid_receipt()
        home_video = next(
            item for item in receipt["artifacts"] if item.get("kind") == "video" and item.get("name") == "home_loop_16s"
        )
        home_video["decoded_span_seconds"] = 15.9
        with self.assertRaisesRegex(self.module.AcceptanceError, "decoded media"):
            self.validate(receipt)

    def test_recorder_ready_requires_simctl_first_frame_signal(self):
        recorder = mock.Mock()
        recorder.poll.return_value = None
        with self.assertRaisesRegex(self.module.AcceptanceError, "Recording started"):
            self.module._wait_for_recorder_ready(recorder, timeout_seconds=0.01, read_line=lambda *_: None)
        self.module._wait_for_recorder_ready(
            recorder,
            timeout_seconds=0.01,
            read_line=lambda *_: "Recording started\n",
        )

    def test_owned_child_cleanup_is_bounded_and_kills_after_timeout(self):
        child = mock.Mock()
        child.poll.return_value = None
        child.wait.side_effect = [subprocess.TimeoutExpired("child", 1), 0]
        self.module._stop_owned_process(child, signal.SIGTERM, timeout_seconds=1)
        child.send_signal.assert_called_once_with(signal.SIGTERM)
        child.kill.assert_called_once_with()

    def test_capture_failure_reaps_active_recorder_and_flutter_process(self):
        run_root = self.root / "run"
        (run_root / "ios").mkdir(parents=True)
        (run_root / "ios" / "Base.xcconfig").write_text("BASE_BUNDLE_IDENTIFIER = app.test\n")
        artifacts = self.root / "artifacts"
        artifacts.mkdir()
        container = self.root / "container"
        (container / "tmp").mkdir(parents=True)
        run_id = "1a2b3c"
        video_ack = container / "tmp" / f"blizzard_video_home_loop_16s_{run_id}.ack"
        capture_ack = container / "tmp" / f"blizzard_capture_settings_{run_id}.ack"
        lines = [
            f"BLIZZARD_VIDEO_START home_loop_16s {run_id} {video_ack}\n",
            f"BLIZZARD_CAPTURE_READY settings {run_id} {capture_ack}\n",
        ]
        flutter = mock.Mock(stdout=mock.Mock())
        flutter.poll.return_value = None
        flutter.wait.return_value = 0
        recorder = mock.Mock(stderr=mock.Mock())
        recorder.poll.return_value = None
        recorder.wait.return_value = 0
        container_result = subprocess.CompletedProcess(["xcrun"], 0, stdout=f"{container}\n", stderr="")
        with (
            mock.patch.object(self.module.subprocess, "Popen", side_effect=[flutter, recorder]),
            mock.patch.object(self.module, "_iter_lines_with_timeout", return_value=iter(lines)),
            mock.patch.object(self.module, "_wait_for_recorder_ready"),
            mock.patch.object(self.module, "_run", return_value=container_result),
            mock.patch.object(self.module, "_capture_png", side_effect=self.module.AcceptanceError("png failed")),
        ):
            with self.assertRaisesRegex(self.module.AcceptanceError, "png failed"):
                self.module._capture_process(
                    ["flutter", "test"],
                    run_root,
                    "simulator",
                    artifacts,
                    self.root / "capture-process.log",
                )
        recorder.send_signal.assert_called_once_with(signal.SIGINT)
        flutter.send_signal.assert_called_once_with(signal.SIGTERM)

    def test_capture_ack_is_accepted_before_png_and_captured_after(self):
        run_root = self.root / "run-capture-ack"
        (run_root / "ios").mkdir(parents=True)
        (run_root / "ios" / "Base.xcconfig").write_text("BASE_BUNDLE_IDENTIFIER = app.test\n")
        artifacts_dir = self.root / "capture-ack-artifacts"
        artifacts_dir.mkdir()
        container = self.root / "capture-ack-container"
        (container / "tmp").mkdir(parents=True)
        run_id = "1a2b3c"
        capture_ack = container / "tmp" / f"blizzard_capture_settings_{run_id}.ack"
        lines = [f"BLIZZARD_CAPTURE_READY settings {run_id} {capture_ack}\n"]
        flutter = mock.Mock(stdout=mock.Mock())
        flutter.poll.return_value = 0
        flutter.wait.return_value = 0
        container_result = subprocess.CompletedProcess(["xcrun"], 0, stdout=f"{container}\n", stderr="")

        def capture_png(_simulator, path, name):
            self.assertEqual(capture_ack.read_text(), "accepted\n")
            self._write_png(path, red=20)
            return {
                "kind": "png",
                "name": name,
                "path": str(path),
                "sha256": self.module.sha256_file(path),
                "pixels": [786, 1704],
            }

        log_path = self.root / "capture-ack.log"
        with (
            mock.patch.object(self.module.subprocess, "Popen", return_value=flutter),
            mock.patch.object(self.module, "_iter_lines_with_timeout", return_value=iter(lines)),
            mock.patch.object(self.module, "_run", return_value=container_result) as run_command,
            mock.patch.object(self.module, "_capture_png", side_effect=capture_png),
        ):
            exit_code, coverage, _, _, _, _ = self.module._capture_process(
                ["flutter", "test"], run_root, "simulator", artifacts_dir, log_path
            )

        self.assertEqual(exit_code, 0)
        self.assertEqual(run_command.call_args.kwargs["timeout_seconds"], 20)
        self.assertEqual(coverage["settings"], "CAPTURED")
        self.assertEqual(capture_ack.read_text(), "captured\n")
        log = log_path.read_text()
        self.assertIn("BLIZZARD_CAPTURE_IO_START settings", log)
        self.assertIn("BLIZZARD_CAPTURE_IO_END settings elapsed_ms=", log)
        self.assertIn("BLIZZARD_CAPTURE_ACK settings captured", log)

    def test_home_pair_starts_second_capture_while_first_is_pending(self):
        run_root = self.root / "run-home-pair"
        (run_root / "ios").mkdir(parents=True)
        (run_root / "ios" / "Base.xcconfig").write_text("BASE_BUNDLE_IDENTIFIER = app.test\n")
        artifacts_dir = self.root / "home-pair-artifacts"
        artifacts_dir.mkdir()
        container = self.root / "home-pair-container"
        (container / "tmp").mkdir(parents=True)
        run_id = "1a2b3c"
        capture_ack = container / "tmp" / f"blizzard_capture_home_initial_{run_id}.ack"
        lines = [f"BLIZZARD_CAPTURE_READY home_initial {run_id} {capture_ack}\n"]
        flutter = mock.Mock(stdout=mock.Mock())
        flutter.poll.return_value = 0
        flutter.wait.return_value = 0
        container_result = subprocess.CompletedProcess(["xcrun"], 0, stdout=f"{container}\n", stderr="")
        second_started = threading.Event()
        first_completed = threading.Event()
        starts = {}

        def capture_png(_simulator, path, name):
            starts[name] = time.monotonic()
            if name == "home_initial":
                if not second_started.wait(1.5):
                    raise AssertionError("second capture did not start while first was pending")
                first_completed.set()
            else:
                self.assertEqual(name, "home_600ms")
                self.assertFalse(first_completed.is_set())
                self.assertEqual(capture_ack.read_text(), "accepted\n")
                second_started.set()
            return {"kind": "png", "name": name, "path": str(path), "sha256": name, "pixels": [786, 1704]}

        with (
            mock.patch.object(self.module.subprocess, "Popen", return_value=flutter),
            mock.patch.object(self.module, "_iter_lines_with_timeout", return_value=iter(lines)),
            mock.patch.object(self.module, "_run", return_value=container_result),
            mock.patch.object(self.module, "_capture_png", side_effect=capture_png),
        ):
            exit_code, coverage, artifacts, _, interval, _ = self.module._capture_process(
                ["flutter", "test"], run_root, "simulator", artifacts_dir, self.root / "home-pair.log"
            )

        self.assertEqual(exit_code, 0)
        self.assertEqual([item["name"] for item in artifacts], ["home_initial", "home_600ms"])
        self.assertEqual(coverage["home_initial"], "CAPTURED")
        self.assertEqual(coverage["home_600ms"], "CAPTURED")
        self.assertTrue(0.55 <= starts["home_600ms"] - starts["home_initial"] <= 0.75)
        self.assertTrue(0.55 <= interval <= 0.75)
        self.assertAlmostEqual(interval, starts["home_600ms"] - starts["home_initial"], delta=0.02)
        self.assertEqual(capture_ack.read_text(), "captured\n")

    def test_home_pair_failure_never_writes_captured_ack(self):
        run_root = self.root / "run-home-pair-failure"
        (run_root / "ios").mkdir(parents=True)
        (run_root / "ios" / "Base.xcconfig").write_text("BASE_BUNDLE_IDENTIFIER = app.test\n")
        artifacts_dir = self.root / "home-pair-failure-artifacts"
        artifacts_dir.mkdir()
        container = self.root / "home-pair-failure-container"
        (container / "tmp").mkdir(parents=True)
        run_id = "1a2b3c"
        capture_ack = container / "tmp" / f"blizzard_capture_home_initial_{run_id}.ack"
        lines = [f"BLIZZARD_CAPTURE_READY home_initial {run_id} {capture_ack}\n"]
        flutter = mock.Mock(stdout=mock.Mock())
        flutter.poll.return_value = None
        flutter.wait.return_value = 0
        container_result = subprocess.CompletedProcess(["xcrun"], 0, stdout=f"{container}\n", stderr="")
        second_started = threading.Event()

        def capture_png(_simulator, path, name):
            if name == "home_initial":
                if not second_started.wait(1.5):
                    raise AssertionError("second capture did not start before first failed")
                raise self.module.AcceptanceError("first capture failed")
            second_started.set()
            return {"kind": "png", "name": name, "path": str(path), "sha256": name, "pixels": [786, 1704]}

        with (
            mock.patch.object(self.module.subprocess, "Popen", return_value=flutter),
            mock.patch.object(self.module, "_iter_lines_with_timeout", return_value=iter(lines)),
            mock.patch.object(self.module, "_run", return_value=container_result),
            mock.patch.object(self.module, "_capture_png", side_effect=capture_png),
        ):
            with self.assertRaisesRegex(self.module.AcceptanceError, "first capture failed"):
                self.module._capture_process(
                    ["flutter", "test"], run_root, "simulator", artifacts_dir, self.root / "home-pair-failure.log"
                )

        self.assertEqual(capture_ack.read_text(), "accepted\n")
        flutter.send_signal.assert_called_once_with(signal.SIGTERM)

    def test_video_probe_runs_after_flutter_output_is_drained(self):
        run_root = self.root / "run-deferred-probe"
        (run_root / "ios").mkdir(parents=True)
        (run_root / "ios" / "Base.xcconfig").write_text("BASE_BUNDLE_IDENTIFIER = app.test\n")
        artifacts_dir = self.root / "deferred-probe-artifacts"
        artifacts_dir.mkdir()
        container = self.root / "deferred-probe-container"
        (container / "tmp").mkdir(parents=True)
        run_id = "1a2b3c"
        video_ack = container / "tmp" / f"blizzard_video_home_loop_16s_{run_id}.ack"
        drained = False

        def lines():
            nonlocal drained
            yield f"BLIZZARD_VIDEO_START home_loop_16s {run_id} {video_ack}\n"
            yield "BLIZZARD_VIDEO_END home_loop_16s\n"
            drained = True

        flutter = mock.Mock(stdout=mock.Mock())
        flutter.poll.return_value = 0
        flutter.wait.return_value = 0
        recorder = mock.Mock(stderr=mock.Mock())
        recorder.poll.return_value = None
        recorder.wait.return_value = 0
        container_result = subprocess.CompletedProcess(["xcrun"], 0, stdout=f"{container}\n", stderr="")
        (artifacts_dir / "home_loop_16s.mp4").write_bytes(b"video")

        def probe(_path):
            self.assertTrue(drained)
            return {"duration_seconds": 16.5, "frame_count": 17, "decoded_span_seconds": 16.4}

        def recorder_ready(_recorder):
            self.assertEqual(video_ack.read_text(), "accepted\n")

        with (
            mock.patch.object(self.module.subprocess, "Popen", side_effect=[flutter, recorder]),
            mock.patch.object(self.module, "_iter_lines_with_timeout", return_value=lines()),
            mock.patch.object(self.module, "_wait_for_recorder_ready", side_effect=recorder_ready),
            mock.patch.object(self.module, "_run", return_value=container_result),
            mock.patch.object(self.module, "_probe_video", side_effect=probe),
        ):
            exit_code, _, artifacts, _, _, _ = self.module._capture_process(
                ["flutter", "test"], run_root, "simulator", artifacts_dir, self.root / "deferred-probe.log"
            )

        self.assertEqual(exit_code, 0)
        self.assertEqual(video_ack.read_text(), "recording\n")
        self.assertEqual([(item["kind"], item["name"]) for item in artifacts], [("video", "home_loop_16s")])

    def test_home_video_protocol_accepts_held_home_loop_screenshot_marker(self):
        run_root = self.root / "run-video"
        (run_root / "ios").mkdir(parents=True)
        (run_root / "ios" / "Base.xcconfig").write_text("BASE_BUNDLE_IDENTIFIER = app.test\n")
        artifacts_dir = self.root / "video-artifacts"
        artifacts_dir.mkdir()
        container = self.root / "video-container"
        (container / "tmp").mkdir(parents=True)
        run_id = "1a2b3c"
        video_ack = container / "tmp" / f"blizzard_video_home_loop_16s_{run_id}.ack"
        capture_ack = container / "tmp" / f"blizzard_capture_home_loop_16s_{run_id}.ack"
        lines = [
            f"BLIZZARD_VIDEO_START home_loop_16s {run_id} {video_ack}\n",
            f"BLIZZARD_CAPTURE_READY home_loop_16s {run_id} {capture_ack}\n",
            "BLIZZARD_VIDEO_END home_loop_16s\n",
        ]
        flutter = mock.Mock(stdout=mock.Mock())
        flutter.poll.return_value = 0
        flutter.wait.return_value = 0
        recorder = mock.Mock(stderr=mock.Mock())
        recorder.poll.return_value = None
        recorder.wait.return_value = 0
        container_result = subprocess.CompletedProcess(["xcrun"], 0, stdout=f"{container}\n", stderr="")
        screenshot_path = artifacts_dir / "home_loop_16s.png"
        self._write_png(screenshot_path, red=20)
        video_path = artifacts_dir / "home_loop_16s.mp4"
        video_path.write_bytes(b"video")
        png_artifact = {
            "kind": "png",
            "name": "home_loop_16s",
            "path": str(screenshot_path),
            "sha256": self.module.sha256_file(screenshot_path),
            "pixels": [786, 1704],
        }
        probe = {"duration_seconds": 16.5, "frame_count": 17, "decoded_span_seconds": 16.4}
        with (
            mock.patch.object(self.module.subprocess, "Popen", side_effect=[flutter, recorder]),
            mock.patch.object(self.module, "_iter_lines_with_timeout", return_value=iter(lines)),
            mock.patch.object(self.module, "_wait_for_recorder_ready"),
            mock.patch.object(self.module, "_run", return_value=container_result),
            mock.patch.object(self.module, "_capture_png", return_value=png_artifact),
            mock.patch.object(self.module, "_probe_video", return_value=probe),
        ):
            exit_code, coverage, artifacts, _, _, _ = self.module._capture_process(
                ["flutter", "test"], run_root, "simulator", artifacts_dir, self.root / "video-protocol.log"
            )
        self.assertEqual(exit_code, 0)
        self.assertEqual(coverage["home_loop_16s"], "CAPTURED")
        self.assertEqual([item["kind"] for item in artifacts], ["png", "video"])

    def test_line_reader_drains_two_markers_already_buffered_by_one_write(self):
        read_fd, write_fd = os.pipe()
        raw = os.fdopen(read_fd, "rb", buffering=0)
        stream = io.TextIOWrapper(raw, encoding="utf-8")
        try:
            os.write(write_fd, b"first\nsecond\n")
            lines = self.module._iter_lines_with_timeout(stream, idle_timeout_seconds=0.01)
            self.assertEqual(next(lines), "first\n")
            self.assertEqual(next(lines), "second\n")
        finally:
            os.close(write_fd)
            stream.close()

    def test_recorder_ready_finds_signal_after_diagnostic_in_same_write(self):
        read_fd, write_fd = os.pipe()
        stream = os.fdopen(read_fd, "rb", buffering=0)
        recorder = mock.Mock(stderr=stream)
        recorder.poll.return_value = None
        try:
            os.write(write_fd, b"diagnostic before readiness\nRecording started\n")
            self.module._wait_for_recorder_ready(recorder, timeout_seconds=0.05)
        finally:
            os.close(write_fd)
            stream.close()

    def test_requires_truthful_fixture_scope(self):
        receipt = self.valid_receipt()
        del receipt["runtime"]["lifecycle_driver"]
        with self.assertRaisesRegex(self.module.AcceptanceError, "framework fixture"):
            self.validate(receipt)
        receipt = self.valid_receipt()
        receipt["runtime"]["app_metadata_source"] = "installed_app"
        with self.assertRaisesRegex(self.module.AcceptanceError, "synthetic app metadata"):
            self.validate(receipt)
        receipt = self.valid_receipt()
        receipt["runtime"]["navigation_evidence"] = "production_navigation"
        with self.assertRaisesRegex(self.module.AcceptanceError, "rendered-state fixture"):
            self.validate(receipt)

    def test_snapshot_is_regular_and_symlink_free(self):
        source = self.root / "source"
        source.mkdir()
        (source / "lib").mkdir()
        (source / "lib" / "main.dart").write_text("void main() {}")
        snapshot = self.root / "snapshot"
        self.module.copy_candidate_snapshot(source, snapshot)
        self.assertFalse(any(path.is_symlink() for path in snapshot.rglob("*")))
        linked = self.root / "linked-source"
        linked.symlink_to(source, target_is_directory=True)
        with self.assertRaisesRegex(self.module.AcceptanceError, "symlink"):
            self.module.copy_candidate_snapshot(linked, self.root / "rejected")

    def _add_aurora_native_contract(self, candidate):
        runner = candidate / "ios" / "Runner"
        (runner / "BlizzardSystemSymbols.swift").write_text("final class BlizzardSystemSymbols {}")
        (candidate / "pubspec.yaml").write_text("flutter:\n  shaders:\n    - assets/shaders/blizzard_aurora.frag\n")
        glass = runner / "BlizzardNativeGlass.swift"
        glass.write_text(glass.read_text() + "\nfinal class BlizzardNativeConnectionControlFactory {}")
        delegate = runner / "AppDelegate.swift"
        delegate.write_text(delegate.read_text() + '''        if let connectionControlRegistrar = registrar(forPlugin: "BlizzardNativeConnectionControl") {
            connectionControlRegistrar.register(
                BlizzardNativeConnectionControlFactory(messenger: connectionControlRegistrar.messenger()),
                withId: "app.blizzard/native-connection-control"
            )
        }
        if let symbolsRegistrar = registrar(forPlugin: "BlizzardSystemSymbols") {
            BlizzardSystemSymbols.register(with: symbolsRegistrar)
        }
''')
        project = candidate / "ios" / "Runner.xcodeproj" / "project.pbxproj"
        project.write_text(project.read_text().replace(
            "A1 /* BlizzardNativeGlass.swift in Sources */,",
            "A1 /* BlizzardNativeGlass.swift in Sources */,\n        A2 /* BlizzardSystemSymbols.swift in Sources */,")
            + "\nA2 /* BlizzardSystemSymbols.swift in Sources */ = {isa = PBXBuildFile; fileRef = B2 /* BlizzardSystemSymbols.swift */; };\n")

    def test_regular_host_copies_and_registers_exact_aurora_native_inputs(self):
        candidate, template = self.root / "aurora-candidate", self.root / "aurora-template"
        self._write_source_directories(candidate)
        self._write_native_candidate_contract(candidate)
        self._add_aurora_native_contract(candidate)
        self._write_qa_template_registration(template)
        project_path = pathlib.Path("ios/Runner.xcodeproj/project.pbxproj")
        template_project = template / project_path
        template_project.parent.mkdir(parents=True, exist_ok=True)
        project_source = (candidate / project_path).read_text()
        project_source = project_source.replace("        A2 /* BlizzardSystemSymbols.swift in Sources */,", "")
        project_source = project_source[:project_source.index("\nA2 /* BlizzardSystemSymbols.swift in Sources */ =")]
        template_project.write_text(project_source)
        destination = self.root / "aurora-host"
        self.module.prepare_regular_host(candidate, template, destination)
        symbol_path = pathlib.Path("ios/Runner/BlizzardSystemSymbols.swift")
        self.assertTrue((destination / symbol_path).is_file(), "candidate system symbols must reach the host")
        self.assertEqual((destination / symbol_path).read_bytes(), (candidate / symbol_path).read_bytes())
        delegate = (destination / "ios/Runner/AppDelegate.swift").read_text()
        self.assertEqual(delegate.count('withId: "app.blizzard/native-connection-control"'), 1)
        self.assertEqual(delegate.count("BlizzardSystemSymbols.register(with: symbolsRegistrar)"), 1)
        project = (destination / "ios/Runner.xcodeproj/project.pbxproj").read_text()
        self.assertTrue(self.module._candidate_compiles_native_source(project, "BlizzardSystemSymbols.swift"))
        self.assertEqual((destination / "pubspec.yaml").read_bytes(), (candidate / "pubspec.yaml").read_bytes())

    def test_receipt_rejects_system_symbols_substituted_in_native_host(self):
        receipt = self.valid_receipt()
        receipt["source"]["system_symbols_sha256"] = "candidate-symbols"
        receipt["runtime"]["system_symbols_sha256_before"] = "stale-symbols"
        receipt["runtime"]["system_symbols_sha256_after"] = "candidate-symbols"
        with self.assertRaisesRegex(self.module.AcceptanceError, "system symbols"):
            self.validate(receipt)

    def aurora_receipt(self):
        receipt = self.valid_receipt()
        receipt["source"]["system_symbols_sha256"] = "symbols"
        receipt["source"].update(native_connection_control_registration=True,
                                 system_symbols_registration=True,
                                 system_symbols_compiled_in_runner=True)
        receipt["runtime"]["system_symbols_sha256_before"] = "symbols"
        receipt["runtime"]["system_symbols_sha256_after"] = "symbols"
        receipt["runtime"]["aurora_host_source_registration_validated"] = True
        receipt["runtime"]["system_symbols_probe"] = "native_png_decoded"
        self.capture_log.write_text("BLIZZARD_NATIVE_PROBE system_symbols native_png_decoded\n")
        receipt["capture_log"]["sha256"] = self.module.sha256_file(self.capture_log)
        return receipt

    def test_aurora_registration_evidence_has_explicit_source_scope(self):
        receipt = self.aurora_receipt()
        self.validate(receipt)
        receipt["runtime"]["aurora_host_source_registration_validated"] = False
        with self.assertRaisesRegex(self.module.AcceptanceError, "host source registration"):
            self.validate(receipt)

    def test_aurora_receipt_requires_observed_native_symbol_probe(self):
        for log in ("capture complete\n", "BLIZZARD_NATIVE_PROBE system_symbols fallback\n",
                    "prefix BLIZZARD_NATIVE_PROBE system_symbols native_png_decoded\n"):
            receipt = self.aurora_receipt()
            self.capture_log.write_text(log)
            receipt["capture_log"]["sha256"] = self.module.sha256_file(self.capture_log)
            with self.assertRaisesRegex(self.module.AcceptanceError, "native symbol probe"):
                self.validate(receipt)

    def test_aurora_runtime_evidence_does_not_claim_platform_view_handshake(self):
        self.capture_log.write_text("BLIZZARD_NATIVE_PROBE system_symbols native_png_decoded\n")
        evidence = self.module.aurora_runtime_evidence(self.capture_log)
        self.assertEqual(evidence, {"aurora_host_source_registration_validated": True,
                                    "system_symbols_probe": "native_png_decoded"})
        self.capture_log.write_text("")
        self.assertIsNone(self.module.aurora_runtime_evidence(self.capture_log)["system_symbols_probe"])

    def test_aurora_host_rejects_missing_connection_control_registration(self):
        candidate, template = self.root / "missing-lens", self.root / "template-lens"
        self._write_source_directories(candidate)
        self._write_native_candidate_contract(candidate)
        self._add_aurora_native_contract(candidate)
        delegate = candidate / "ios/Runner/AppDelegate.swift"
        delegate.write_text(delegate.read_text().replace("app.blizzard/native-connection-control", "wrong-control"))
        self._write_qa_template_registration(template)
        with self.assertRaisesRegex(self.module.AcceptanceError, "connection control registration"):
            self.module.prepare_regular_host(candidate, template, self.root / "rejected-lens")

    def test_aurora_host_rejects_uncompiled_system_symbols(self):
        candidate, template = self.root / "uncompiled-symbols", self.root / "template-symbols"
        self._write_source_directories(candidate)
        self._write_native_candidate_contract(candidate)
        self._add_aurora_native_contract(candidate)
        project = candidate / "ios/Runner.xcodeproj/project.pbxproj"
        project.write_text(project.read_text().replace("        A2 /* BlizzardSystemSymbols.swift in Sources */,", ""))
        self._write_qa_template_registration(template)
        with self.assertRaisesRegex(self.module.AcceptanceError, "system symbols compile membership"):
            self.module.prepare_regular_host(candidate, template, self.root / "rejected-symbols")

    def test_regular_host_replaces_stale_template_native_glass_with_candidate(self):
        candidate = self.root / "candidate"
        template = self.root / "template"
        self._write_source_directories(candidate)
        self._write_native_candidate_contract(candidate)
        candidate_glass = candidate / "ios" / "Runner" / "BlizzardNativeGlass.swift"
        template_glass = template / "ios" / "Runner" / "BlizzardNativeGlass.swift"
        template_glass.parent.mkdir(parents=True)
        template_glass.write_text("stale-template-native-glass")
        self._write_qa_template_registration(template)
        destination = self.root / "host"
        self.module.prepare_regular_host(candidate, template, destination)
        self.assertEqual(
            (destination / "ios" / "Runner" / "BlizzardNativeGlass.swift").read_text(),
            "final class BlizzardNativeTabBarFactory {}",
        )
        adapter = (destination / "ios" / "Runner" / "AppDelegate.swift").read_text()
        self.assertEqual(adapter.count('registrar(forPlugin: "BlizzardNativeGlass")'), 1)
        self.assertEqual(adapter.count('registrar(forPlugin: "BlizzardNativeTabBar")'), 1)
        self.assertIn(
            "BlizzardNativeTabBarFactory(messenger: nativeTabBarRegistrar.messenger())",
            adapter,
        )
        self.assertIn('withId: "app.blizzard/native-tab-bar"', adapter)

    def test_regular_host_adapts_actual_qa_app_delegate_indentation(self):
        candidate = self.root / "candidate-actual-qa-adapter"
        template = self.root / "template-actual-qa-adapter"
        self._write_source_directories(candidate)
        self._write_native_candidate_contract(candidate)
        self._write_qa_template_registration(template)
        destination = self.root / "host-actual-qa-adapter"

        self.module.prepare_regular_host(candidate, template, destination)

        adapter = (destination / "ios" / "Runner" / "AppDelegate.swift").read_text()
        self.assertIn(
            """    if let nativeTabBarRegistrar = registrar(forPlugin: "BlizzardNativeTabBar") {
      nativeTabBarRegistrar.register(
        BlizzardNativeTabBarFactory(messenger: nativeTabBarRegistrar.messenger()),
        withId: "app.blizzard/native-tab-bar"
      )
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)""",
            adapter,
        )

    def test_qa_tab_registration_accepts_exact_already_prepared_template(self):
        template = self.root / "prepared-template"
        self._write_qa_template_registration(template)
        delegate = template / "ios/Runner/AppDelegate.swift"
        self.module._install_qa_native_tab_bar_registration(delegate)
        before = delegate.read_bytes()
        self.module._install_qa_native_tab_bar_registration(delegate)
        self.assertEqual(delegate.read_bytes(), before)

    def test_regular_host_rejects_unexpected_qa_registration_context(self):
        candidate = self.root / "candidate-unexpected-adapter"
        template = self.root / "template-unexpected-adapter"
        self._write_native_candidate_contract(candidate)
        self._write_source_directories(candidate)
        app_delegate = template / "ios" / "Runner" / "AppDelegate.swift"
        app_delegate.parent.mkdir(parents=True)
        app_delegate.write_text(
            'registrar(forPlugin: "BlizzardNativeGlass")?.register(BlizzardNativeGlassFactory(), '
            'withId: "app.blizzard/native-liquid-glass")\n'
        )
        with self.assertRaisesRegex(self.module.AcceptanceError, "expected native glass registration context"):
            self.module.prepare_regular_host(candidate, template, self.root / "rejected-adapter-host")

    def test_regular_host_rejects_candidate_without_production_tab_bar_registration(self):
        candidate = self.root / "candidate-missing-tab-registration"
        template = self.root / "template-missing-tab-registration"
        self._write_native_candidate_contract(candidate, include_tab_registration=False)
        self._write_source_directories(candidate)
        self._write_qa_template_registration(template)
        with self.assertRaisesRegex(self.module.AcceptanceError, "production native tab bar registration"):
            self.module.prepare_regular_host(candidate, template, self.root / "rejected-candidate-host")

    def test_regular_host_rejects_wrong_production_tab_bar_messenger(self):
        candidate = self.root / "candidate-wrong-tab-messenger"
        template = self.root / "template-wrong-tab-messenger"
        self._write_native_candidate_contract(candidate)
        self._write_source_directories(candidate)
        self._write_qa_template_registration(template)
        app_delegate = candidate / "ios" / "Runner" / "AppDelegate.swift"
        app_delegate.write_text(app_delegate.read_text().replace("nativeTabBarRegistrar.messenger()", "messenger"))
        with self.assertRaisesRegex(self.module.AcceptanceError, "production native tab bar registration"):
            self.module.prepare_regular_host(candidate, template, self.root / "rejected-messenger-host")

    def test_regular_host_requires_tab_bar_factory_in_shared_native_glass_source(self):
        candidate = self.root / "candidate-tab-factory-outside-glass"
        template = self.root / "template-tab-factory-outside-glass"
        self._write_native_candidate_contract(candidate)
        self._write_source_directories(candidate)
        self._write_qa_template_registration(template)
        (candidate / "ios" / "Runner" / "BlizzardNativeGlass.swift").write_text("final class BlizzardNativeGlassFactory {}")
        with self.assertRaisesRegex(self.module.AcceptanceError, "shared native glass source"):
            self.module.prepare_regular_host(candidate, template, self.root / "rejected-shared-source-host")

    def test_regular_host_rejects_candidate_without_native_glass_compile_membership(self):
        candidate = self.root / "candidate-missing-compile-membership"
        template = self.root / "template-missing-compile-membership"
        self._write_native_candidate_contract(candidate, include_compile_membership=False)
        self._write_source_directories(candidate)
        self._write_qa_template_registration(template)
        with self.assertRaisesRegex(self.module.AcceptanceError, "native glass compile membership"):
            self.module.prepare_regular_host(candidate, template, self.root / "rejected-project-host")

    def test_bundle_identifier_falls_back_to_main_runner_xcode_project(self):
        host = self.root / "bundle-host"
        project = host / "ios" / "Runner.xcodeproj" / "project.pbxproj"
        project.parent.mkdir(parents=True)
        project.write_text(
            """
            PRODUCT_BUNDLE_IDENTIFIER = dev.blizzard.v3qa.hiddify;
            PRODUCT_BUNDLE_IDENTIFIER = dev.blizzard.v3qa.hiddify.RunnerTests;
            PRODUCT_BUNDLE_IDENTIFIER = dev.blizzard.v3qa.hiddify;
            """
        )
        self.assertEqual(self.module._bundle_identifier(host), "dev.blizzard.v3qa.hiddify")

    def test_receipt_json_round_trip_keeps_external_expectations_outside(self):
        receipt = self.valid_receipt()
        path = self.root / "receipt.json"
        path.write_text(json.dumps(receipt))
        loaded = json.loads(path.read_text())
        self.validate(loaded)

    def test_capture_source_head_must_match_external_input(self):
        completed = subprocess.CompletedProcess(["git"], 0, stdout="actual\n", stderr="")
        with mock.patch.object(self.module, "_run", return_value=completed):
            with self.assertRaisesRegex(self.module.AcceptanceError, "source SHA"):
                self.module.verify_source_sha(self.root, "expected")

    def test_video_ack_is_confined_to_the_simulator_app_container(self):
        container = self.root / "simulator-data"
        run_id = "1a2b3c"
        expected = container / "tmp" / f"blizzard_video_home_loop_16s_{run_id}.ack"
        self.assertEqual(
            self.module.validate_video_ack_path(str(expected), container, "home_loop_16s", run_id),
            expected.resolve(),
        )
        with self.assertRaisesRegex(self.module.AcceptanceError, "ack path"):
            self.module.validate_video_ack_path(str(self.root / "escape.ack"), container, "home_loop_16s", run_id)
        stale = container / "tmp" / "blizzard_video_home_loop_16s_deadbeef.ack"
        with self.assertRaisesRegex(self.module.AcceptanceError, "ack path"):
            self.module.validate_video_ack_path(str(stale), container, "home_loop_16s", run_id)
        capture = container / "tmp" / f"blizzard_capture_settings_{run_id}.ack"
        self.assertEqual(
            self.module.validate_capture_ack_path(str(capture), container, "settings", run_id),
            capture.resolve(),
        )
        with self.assertRaisesRegex(self.module.AcceptanceError, "ack path"):
            self.module.validate_capture_ack_path(str(self.root / "capture-escape.ack"), container, "settings", run_id)

    def test_stage_markers_require_a_well_formed_run_id_and_ack_path(self):
        marker = "BLIZZARD_CAPTURE_READY settings 1a2b3c /container/tmp/stage.ack"
        self.assertEqual(
            self.module.parse_stage_marker(marker, "BLIZZARD_CAPTURE_READY"),
            ("settings", "1a2b3c", "/container/tmp/stage.ack"),
        )
        for malformed in [
            "BLIZZARD_CAPTURE_READY settings",
            "BLIZZARD_CAPTURE_READY settings not-a-run-id /tmp/stage.ack",
        ]:
            with self.assertRaisesRegex(self.module.AcceptanceError, "stage marker"):
                self.module.parse_stage_marker(malformed, "BLIZZARD_CAPTURE_READY")


if __name__ == "__main__":
    unittest.main()
