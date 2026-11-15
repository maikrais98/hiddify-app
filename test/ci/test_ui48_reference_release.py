import copy
import hashlib
import json
import os
import re
import shlex
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = "f0217fddcd5ed1d9df8769ddffb4722fe6f4ecf0"


class UiReferenceReleaseTest(unittest.TestCase):
    def setUp(self):
        self.workflow = (ROOT / ".github/workflows/ios-baseline.yml").read_text()
        self.approval = ROOT / f"release/reference-approvals/{SOURCE}.json"
        self.evidence = json.loads((ROOT / f"release/qa-evidence/{SOURCE}.json").read_text())

    def pin(self, name):
        return re.search(rf"^\s+{name}: ([0-9a-f]+)$", self.workflow, re.MULTILINE).group(1)

    def run_evidence_gate(self, evidence):
        command = next(line.strip() for line in self.workflow.splitlines() if line.strip().startswith("python3 -c "))
        script = shlex.split(command)[2]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / f"release/qa-evidence/{SOURCE}.json"
            path.parent.mkdir(parents=True)
            raw = json.dumps(evidence).encode()
            path.write_bytes(raw)
            return subprocess.run(
                ["python3", "-c", script], cwd=directory, capture_output=True, text=True,
                env={**os.environ, "EXPECTED_SOURCE_SHA": SOURCE,
                     "EXPECTED_EVIDENCE_SHA256": hashlib.sha256(raw).hexdigest()},
            )

    def run_approval(self, build="48"):
        return subprocess.run([
            "python3", str(ROOT / "scripts/verify_reference_release_approval.py"),
            "--approval", str(self.approval),
            "--expected-approval-sha256", self.pin("EXPECTED_APPROVAL_SHA256"),
            "--expected-source-sha", SOURCE, "--expected-version", "0.1.0",
            "--expected-minimum-build-number", "48", "--requested-build-number", build,
            "--expected-approver", "maikrais98", "--expected-decision", "publish-testflight",
            "--expected-visual-status", "waived-by-owner",
        ], capture_output=True, text=True)

    def test_exact_source_and_evidence_are_bound_to_controller(self):
        self.assertEqual(SOURCE, self.pin("TRUSTED_RELEASE_SOURCE_SHA"))
        self.assertEqual(SOURCE, self.pin("EXPECTED_SOURCE_SHA"))
        raw = (ROOT / f"release/qa-evidence/{SOURCE}.json").read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(), self.pin("EXPECTED_EVIDENCE_SHA256"))
        self.assertEqual(0, self.run_evidence_gate(self.evidence).returncode)
        self.assertEqual(0, self.run_approval().returncode)
        self.assertNotEqual(0, self.run_approval("47").returncode)

    def test_reference_delivery_cannot_claim_native_acceptance_or_store_submission(self):
        changes = [
            ("native_acceptance", "verified"),
            ("native_captures", {"screenshots": 10, "videos": 2}),
            ("app_store_submission", True),
            ("historical_qa_evidence_reused", True),
        ]
        for key, value in changes:
            with self.subTest(key=key):
                evidence = copy.deepcopy(self.evidence)
                evidence[key] = value
                self.assertNotEqual(0, self.run_evidence_gate(evidence).returncode)


if __name__ == "__main__":
    unittest.main()
