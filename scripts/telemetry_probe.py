#!/usr/bin/env python3
"""Send one closed ingestion probe; never print configuration or response data."""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import secrets
import socket
import ssl
from urllib import request, error

from prepare_telemetry import ConfigurationError, build_configuration


class NoRedirect(request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def post_once(endpoint, token, body):
    req = request.Request(endpoint, data=body, method="POST", headers={
        "Authorization": "Bearer " + token,
        "Content-Type": "application/json",
    })
    try:
        with request.build_opener(NoRedirect()).open(req, timeout=5) as response:
            return response.status
    except error.HTTPError as failure:
        # Redirects are terminal too. Never forward the credential or read bodies.
        return failure.code


def run_probe(env, *, source_sha, version, target_build, event_id=None,
              now=lambda: datetime.now(timezone.utc), post=post_once):
    event_id = secrets.token_hex(8) if event_id is None else event_id
    timestamp = now().astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
    receipt = {
        "schema": "blizzard-ingest-probe-receipt/v1",
        "code": "INVALID_PROBE_PROVENANCE",
        "event_id": event_id if re.fullmatch(r"[0-9a-f]{16}", str(event_id)) else None,
        "source_sha": source_sha if re.fullmatch(r"[0-9a-f]{40}", str(source_sha)) else None,
        "version": version if re.fullmatch(r"\d{1,3}\.\d{1,3}\.\d{1,3}", str(version)) else None,
        "target_build_number": target_build if re.fullmatch(r"[1-9][0-9]{0,8}", str(target_build)) else None,
        "expected_source_id": 2805644,
        "timestamp": timestamp,
        "http_status": None,
        "attempt_count": 0,
        "payload_bytes": 0,
    }
    if any(receipt[key] is None for key in ("event_id", "source_sha", "version", "target_build_number")):
        return receipt
    try:
        config = build_configuration(env, require_remote=True)
    except ConfigurationError:
        receipt["code"] = "TELEMETRY_CONFIGURATION_INVALID"
        return receipt
    body = json.dumps({
        "schema": "blizzard-ingest-probe/v1",
        "origin": "release_controller",
        "event": "ingest_probe",
        "event_id": event_id,
        "dt": timestamp,
        "source_sha": source_sha,
        "app_version": version,
        # Deliberately distinct from a device's build_number field.
        "target_build_number": target_build,
        "level": "info",
        "message": "ingest_probe",
    }, separators=(",", ":")).encode("utf-8")
    if len(body) > 1024:
        receipt["code"] = "PROBE_PAYLOAD_TOO_LARGE"
        return receipt
    receipt["payload_bytes"] = len(body)
    receipt["attempt_count"] = 1
    try:
        status = post(config["betterstack_logs_url"], config["betterstack_source_token"], body)
        if not isinstance(status, int) or isinstance(status, bool) or not 100 <= status <= 599:
            receipt["code"] = "TRANSPORT_OTHER"
            return receipt
        receipt["http_status"] = status
        receipt["code"] = ("INGEST_ACCEPTED" if 200 <= status < 300 else
                           "HTTP_RETRYABLE" if status in (408, 429) or status >= 500 else "HTTP_REJECTED")
    except Exception as failure:
        reason = failure.reason if isinstance(failure, error.URLError) else failure
        receipt["code"] = ("TRANSPORT_TIMEOUT" if isinstance(reason, (TimeoutError, socket.timeout)) else
                           "TRANSPORT_TLS" if isinstance(reason, ssl.SSLError) else
                           "TRANSPORT_NETWORK" if isinstance(reason, (OSError, error.URLError)) or
                           isinstance(failure, error.URLError) else "TRANSPORT_OTHER")
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--target-build", required=True)
    parser.add_argument("--receipt", required=True)
    args = parser.parse_args()
    receipt = run_probe(os.environ, source_sha=args.source_sha, version=args.version,
                        target_build=args.target_build)
    try:
        descriptor = os.open(Path(args.receipt), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(descriptor, "w") as output:
            json.dump(receipt, output, sort_keys=True)
            output.write("\n")
    except OSError:
        print(json.dumps({"code": "PROBE_RECEIPT_WRITE_FAILED"}))
        return 1
    print(json.dumps(receipt, sort_keys=True))
    return 0 if receipt["code"] == "INGEST_ACCEPTED" else 1


if __name__ == "__main__":
    raise SystemExit(main())
