#!/usr/bin/env python3
"""Validate build-time destinations and write a private Flutter defines file."""

import argparse
import json
import os
from pathlib import Path
import re
from urllib.parse import urlsplit


class ConfigurationError(ValueError):
    pass


def build_configuration(env, require_remote=False):
    dsn = env.get("SENTRY_DSN", "").strip()
    endpoint = env.get("BETTERSTACK_LOGS_URL", "").strip()
    token = env.get("BETTERSTACK_SOURCE_TOKEN", "").strip()
    if bool(endpoint) != bool(token):
        raise ConfigurationError("BETTERSTACK_LOGS_URL and BETTERSTACK_SOURCE_TOKEN must be set together")
    if endpoint and not dsn:
        raise ConfigurationError("SENTRY_DSN is required alongside Better Stack logs")
    if require_remote and not (dsn and endpoint and token):
        raise ConfigurationError("Remote diagnostics require all three Better Stack settings")
    try:
        if dsn:
            uri = urlsplit(dsn)
            if not (
                uri.scheme == "https" and uri.hostname and uri.username and not uri.password
                and re.fullmatch(r"/\d+", uri.path) and not uri.query and not uri.fragment
                and uri.port in (None, 443)
            ):
                raise ValueError
        if endpoint:
            logs = urlsplit(endpoint)
            if not (
                logs.scheme == "https" and logs.hostname
                and logs.hostname.endswith(".betterstackdata.com")
                and not logs.username and not logs.password and logs.path in ("", "/")
                and not logs.query and not logs.fragment and logs.port in (None, 443)
                and logs.hostname == uri.hostname and re.fullmatch(r"[A-Za-z0-9_-]+", token)
            ):
                raise ValueError
    except ValueError:
        raise ConfigurationError("Invalid telemetry destination; use the Better Stack Ingest settings") from None
    return {
        "sentry_dsn": dsn,
        "betterstack_logs_url": endpoint,
        "betterstack_source_token": token,
        "telemetry_beta": bool(dsn),
    }


def write_configuration(path, configuration):
    # This file contains a write-only ingestion credential. Never upload it as an artifact.
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w") as output:
            json.dump(configuration, output)
            output.write("\n")
    except BaseException:
        Path(path).unlink(missing_ok=True)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument("--require-remote", action="store_true")
    args = parser.parse_args()
    try:
        configuration = build_configuration(os.environ, args.require_remote)
        write_configuration(args.output, configuration)
    except (ConfigurationError, OSError) as error:
        # Do not echo values or provider response bodies into CI output.
        message = str(error) if isinstance(error, ConfigurationError) else "Cannot write telemetry configuration"
        parser.exit(1, f"ERROR_CODE=TELEMETRY_CONFIGURATION_INVALID: {message}\n")
    print("Remote beta diagnostics enabled" if configuration["telemetry_beta"] else "Local diagnostics only")


if __name__ == "__main__":
    main()
