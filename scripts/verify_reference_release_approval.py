#!/usr/bin/env python3
"""Verify a digest-pinned owner approval for a TestFlight reference release."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import NoReturn


SCHEMA = "blizzard-release-reference-approval/v1"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
SOURCE_SHA_RE = re.compile(r"^[0-9a-f]{40}$")
VERSION_RE = re.compile(r"^[0-9]+(?:\.[0-9]+){1,2}$")


class ApprovalError(ValueError):
    pass


def fail(message: str) -> NoReturn:
    print(f"ERROR_CODE=REFERENCE_APPROVAL_INVALID: {message}", file=sys.stderr)
    raise SystemExit(1)


def positive_integer(value: str) -> int:
    if not re.fullmatch(r"[1-9][0-9]*", value):
        raise argparse.ArgumentTypeError("must be a positive integer")
    return int(value)


def exact_keys(value: object, expected: set[str], label: str) -> dict[str, object]:
    if not isinstance(value, dict):
        raise ApprovalError(f"{label} must be an object")
    actual = set(value)
    if actual != expected:
        raise ApprovalError(f"{label} keys do not match the approval contract")
    return value


def verify(args: argparse.Namespace) -> None:
    approval_path = Path(args.approval)
    raw = approval_path.read_bytes()
    if not SHA256_RE.fullmatch(args.expected_approval_sha256):
        raise ApprovalError("expected approval digest is invalid")
    if hashlib.sha256(raw).hexdigest() != args.expected_approval_sha256:
        raise ApprovalError("approval digest mismatch")

    try:
        approval = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ApprovalError("approval is not valid UTF-8 JSON") from error

    approval = exact_keys(
        approval,
        {
            "schema",
            "decision",
            "approval_label",
            "source_sha",
            "marketing_version",
            "minimum_build_number",
            "approver",
            "visual_acceptance",
            "reference_scope",
        },
        "approval",
    )
    approver = exact_keys(
        approval["approver"],
        {"identity", "role", "approval", "created_at"},
        "approver",
    )
    visual = exact_keys(
        approval["visual_acceptance"],
        {"status", "design_parity_claimed", "reason"},
        "visual_acceptance",
    )

    expected = {
        "schema": SCHEMA,
        "decision": "publish-as-reference",
        "approval_label": "explicit OWNER APPROVAL",
        "source_sha": args.expected_source_sha,
        "marketing_version": args.expected_version,
        "minimum_build_number": args.expected_minimum_build_number,
    }
    for key, value in expected.items():
        if approval[key] != value:
            raise ApprovalError(f"{key} mismatch")

    if not SOURCE_SHA_RE.fullmatch(args.expected_source_sha):
        raise ApprovalError("expected source SHA is invalid")
    if not VERSION_RE.fullmatch(args.expected_version):
        raise ApprovalError("expected version is invalid")
    if args.requested_build_number < approval["minimum_build_number"]:
        raise ApprovalError("requested build is below the approved minimum")

    if approver != {
        "identity": args.expected_approver,
        "role": "owner",
        "approval": "explicit",
        "created_at": approver["created_at"],
    }:
        raise ApprovalError("approver identity or authority mismatch")
    try:
        created_at = datetime.fromisoformat(str(approver["created_at"]).replace("Z", "+00:00"))
    except ValueError as error:
        raise ApprovalError("approval timestamp is invalid") from error
    if not str(approver["created_at"]).endswith("Z") or created_at.utcoffset() is None or created_at.utcoffset().total_seconds() != 0:
        raise ApprovalError("approval timestamp must be UTC with a Z suffix")

    if visual["status"] != "waived-by-owner":
        raise ApprovalError("visual acceptance is not explicitly waived by owner")
    if visual["design_parity_claimed"] is not False:
        raise ApprovalError("approval must not claim design parity")
    if not isinstance(visual["reason"], str) or not visual["reason"].strip():
        raise ApprovalError("visual waiver reason is required")
    if not isinstance(approval["reference_scope"], str) or not approval["reference_scope"].strip():
        raise ApprovalError("reference scope is required")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--approval", required=True)
    parser.add_argument("--expected-approval-sha256", required=True)
    parser.add_argument("--expected-source-sha", required=True)
    parser.add_argument("--expected-version", required=True)
    parser.add_argument("--expected-minimum-build-number", required=True, type=positive_integer)
    parser.add_argument("--requested-build-number", required=True, type=positive_integer)
    parser.add_argument("--expected-approver", required=True)
    return parser.parse_args()


def main() -> None:
    try:
        verify(parse_args())
    except (ApprovalError, OSError) as error:
        fail(str(error))
    print("reference release approval verified")


if __name__ == "__main__":
    main()
