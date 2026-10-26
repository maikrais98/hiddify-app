import copy
import hashlib
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Optional


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/verify_reference_release_approval.py"
SOURCE_SHA = "2c45e4e73fae9de250787c544dae634d92b9985f"
APPROVAL = ROOT / "release/reference-approvals" / f"{SOURCE_SHA}.json"
APPROVAL_SHA256 = "9b6a36fa44f9fef0cbe65eee6f3725bf4ce6775019faece183784f560a3c5b52"


class ReferenceReleaseApprovalTest(unittest.TestCase):
    def run_verifier(self, path: Path, *, build: str = "28", digest: Optional[str] = None, extra_args=()):
        digest = digest or APPROVAL_SHA256
        return subprocess.run(
            [
                "python3",
                str(SCRIPT),
                "--approval",
                str(path),
                "--expected-approval-sha256",
                digest,
                "--expected-source-sha",
                SOURCE_SHA,
                "--expected-version",
                "0.1.0",
                "--expected-minimum-build-number",
                "28",
                "--requested-build-number",
                build,
                "--expected-approver",
                "maikrais98",
            ] + list(extra_args),
            capture_output=True,
            text=True,
        )

    def test_repository_approval_accepts_minimum_and_later_builds(self):
        self.assertEqual(0, self.run_verifier(APPROVAL).returncode)
        self.assertEqual(0, self.run_verifier(APPROVAL, build="29").returncode)

    def test_rejects_build_below_approved_minimum(self):
        result = self.run_verifier(APPROVAL, build="27")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("ERROR_CODE=REFERENCE_APPROVAL_INVALID", result.stderr)

    def test_digest_pin_detects_byte_tampering(self):
        original_digest = hashlib.sha256(APPROVAL.read_bytes()).hexdigest()
        with tempfile.TemporaryDirectory() as directory:
            changed = Path(directory) / "approval.json"
            changed.write_bytes(APPROVAL.read_bytes() + b"\n")
            result = self.run_verifier(changed, digest=original_digest)
        self.assertNotEqual(0, result.returncode)
        self.assertIn("approval digest mismatch", result.stderr)

    def test_rejects_semantic_tampering_even_with_updated_digest(self):
        approval = json.loads(APPROVAL.read_text())
        cases = [
            ("source", lambda value: value.__setitem__("source_sha", "0" * 40)),
            ("version", lambda value: value.__setitem__("marketing_version", "0.1.1")),
            ("minimum build", lambda value: value.__setitem__("minimum_build_number", 29)),
            ("decision", lambda value: value.__setitem__("decision", "reviewed")),
            ("approver", lambda value: value["approver"].__setitem__("identity", "someone-else")),
            ("authority", lambda value: value["approver"].__setitem__("role", "reviewer")),
            ("visual waiver", lambda value: value["visual_acceptance"].__setitem__("status", "passed")),
            ("parity claim", lambda value: value["visual_acceptance"].__setitem__("design_parity_claimed", True)),
            ("timestamp", lambda value: value["approver"].__setitem__("created_at", "2026-10-25T20:43:24+03:00")),
        ]
        with tempfile.TemporaryDirectory() as directory:
            for name, mutate in cases:
                with self.subTest(name=name):
                    changed_value = copy.deepcopy(approval)
                    mutate(changed_value)
                    changed = Path(directory) / f"{name.replace(' ', '-')}.json"
                    changed.write_text(json.dumps(changed_value))
                    result = self.run_verifier(
                        changed, digest=hashlib.sha256(changed.read_bytes()).hexdigest()
                    )
                    self.assertNotEqual(0, result.returncode)
                    self.assertIn("ERROR_CODE=REFERENCE_APPROVAL_INVALID", result.stderr)


    def test_verified_qa_requires_explicit_mode_and_complete_evidence(self):
        approval = json.loads(APPROVAL.read_text())
        approval["decision"] = "publish-testflight"
        approval["visual_acceptance"] = {
            "status": "verified-qa",
            "design_parity_claimed": False,
            "reason": "57 tests passed; 11 native captures; evidence-sha256=" + "a" * 64,
        }
        flags = ("--expected-decision", "publish-testflight", "--expected-visual-status", "verified-qa")
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "qa.json"
            path.write_text(json.dumps(approval))
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            self.assertNotEqual(0, self.run_verifier(path, digest=digest).returncode)
            result = self.run_verifier(path, digest=digest, extra_args=flags)
            self.assertEqual(0, result.returncode, result.stderr)
            path.write_bytes(path.read_bytes() + b"\n")
            self.assertIn("approval digest mismatch", self.run_verifier(path, digest=digest, extra_args=flags).stderr)
            cases = [
                ("wrong count", lambda v: v["visual_acceptance"].__setitem__("reason", "157 tests passed; 111 native captures; evidence-sha256=" + "a" * 64)),
                ("missing tests", lambda v: v["visual_acceptance"].__setitem__("reason", "11 native captures; evidence-sha256=" + "a" * 64)),
                ("missing captures", lambda v: v["visual_acceptance"].__setitem__("reason", "57 tests passed; evidence-sha256=" + "a" * 64)),
                ("missing digest", lambda v: v["visual_acceptance"].__setitem__("reason", "57 tests passed; 11 native captures")),
                ("parity", lambda v: v["visual_acceptance"].__setitem__("design_parity_claimed", True)),
                ("extra key", lambda v: v["visual_acceptance"].__setitem__("unverified", True)),
            ]
            for name, mutate in cases:
                with self.subTest(name=name):
                    changed = copy.deepcopy(approval)
                    mutate(changed)
                    path.write_text(json.dumps(changed))
                    digest = hashlib.sha256(path.read_bytes()).hexdigest()
                    self.assertNotEqual(0, self.run_verifier(path, digest=digest, extra_args=flags).returncode)


if __name__ == "__main__":
    unittest.main()
