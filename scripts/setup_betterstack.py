#!/usr/bin/env python3
"""Create/reuse WIR telemetry resources and install ingestion settings with gh."""

import argparse
import getpass
import json
import os
import subprocess
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


class SetupError(RuntimeError):
    pass


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class BetterStack:
    def __init__(self, token):
        self.token = token

    def request(self, url, body=None):
        destination = urlsplit(url)
        if (destination.scheme != "https" or destination.netloc not in {
            "telemetry.betterstack.com", "errors.betterstack.com",
        }):
            raise SetupError("Invalid Better Stack API destination")
        data = None if body is None else json.dumps(body).encode()
        request = Request(url, data=data, headers={
            "Authorization": f"Bearer {self.token}", "Content-Type": "application/json",
        })
        try:
            with build_opener(NoRedirect()).open(request, timeout=30) as response:
                return json.load(response)
        except HTTPError as error:
            raise SetupError(f"Better Stack API rejected the request (HTTP {error.code})") from None
        except (URLError, ValueError):
            raise SetupError("Cannot reach Better Stack API or decode its response") from None

    def list(self, base):
        url = base
        rows = []
        seen = set()
        while url:
            if (url in seen or urlsplit(url).netloc != urlsplit(base).netloc
                    or urlsplit(url).scheme != "https"):
                raise SetupError("Invalid API pagination")
            seen.add(url)
            result = self.request(url)
            rows.extend(result["data"])
            url = result.get("links", {}).get("next")
        return rows


def find_resource(rows, team_id, name):
    matches = [row for row in rows if str(row["attributes"].get("team_id")) == str(team_id)
               and row["attributes"]["name"] == name]
    if len(matches) > 1:
        raise SetupError("Multiple WIR Baseline resources found; select the correct resource in Better Stack")
    return matches[0] if matches else None


def configure(api, team_id, team_name, region=None, apply=False):
    sources_url = "https://telemetry.betterstack.com/api/v2/sources"
    applications_url = "https://errors.betterstack.com/api/v2/applications"
    name = "WIR Baseline"
    source = find_resource(api.list(sources_url), team_id, name)
    application = find_resource(api.list(applications_url), team_id, name)
    if source and source["attributes"]["platform"] != "http":
        raise SetupError("Existing WIR Baseline source has a different platform")
    if not apply:
        return {"source": "reuse" if source else "create", "application": "reuse" if application else "create"}
    if not source:
        body = {"name": name, "platform": "http", "team_name": team_name}
        if region:
            body["data_region"] = region
        source = api.request(sources_url, body)["data"]
    if not application:
        application = api.request(applications_url, {
            "name": name, "platform": "flutter_errors", "team_name": team_name,
            "correlate_with_source_id": str(source["id"]),
        })["data"]
    attrs = application["attributes"]
    if (attrs["platform"] != "flutter_errors"
            or str(attrs.get("correlate_with_source_id")) != str(source["id"])):
        raise SetupError("Existing application is not Flutter or is linked to a different source")
    if source["attributes"].get("ingesting_paused") or attrs.get("ingesting_paused"):
        raise SetupError("WIR Baseline ingestion is paused; resume it in Better Stack first")
    source_attrs = source["attributes"]
    return {
        "SENTRY_DSN": f"https://{attrs['token']}@{attrs['ingesting_host']}/{application['id']}",
        "BETTERSTACK_LOGS_URL": f"https://{source_attrs['ingesting_host']}",
        "BETTERSTACK_SOURCE_TOKEN": source_attrs["token"],
    }


def sync_github(settings, repository, environments, run=subprocess.run):
    targets = environments or [None]
    for environment in targets:
        for name, value in settings.items():
            command = ["gh", "secret", "set", name, "--repo", repository]
            if environment:
                command += ["--env", environment]
            # stdin keeps ingestion keys out of command arguments and output.
            result = run(command, input=value, text=True, capture_output=True, check=False)
            if result.returncode:
                raise SetupError(f"Could not set GitHub setting {name}; check gh access")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--team-id", required=True, type=int)
    parser.add_argument("--team-name", required=True)
    parser.add_argument("--region")
    parser.add_argument("--repository", required=True)
    parser.add_argument("--environment", action="append", default=[])
    parser.add_argument("--apply", action="store_true", help="Create missing resources and set GitHub secrets")
    args = parser.parse_args()
    try:
        if args.apply:
            result = subprocess.run(["gh", "auth", "status"], capture_output=True, check=False)
            if result.returncode:
                raise SetupError("Run gh auth login before applying setup")
        token = os.environ.get("BETTERSTACK_API_TOKEN") or getpass.getpass("Better Stack Telemetry API token: ")
        if not token:
            raise SetupError("A Better Stack Telemetry API token is required")
        settings = configure(BetterStack(token), args.team_id, args.team_name, args.region, args.apply)
        if args.apply:
            from prepare_telemetry import build_configuration
            build_configuration(settings, require_remote=True)
            sync_github(settings, args.repository, args.environment)
            print("WIR Baseline configured. Ingestion settings saved to GitHub; API token not saved.")
        else:
            print(json.dumps(settings, indent=2))
            print("Dry run only. Add --apply to configure resources and GitHub.")
    except (SetupError, OSError, ValueError, KeyError) as error:
        message = str(error) if isinstance(error, SetupError) else "Setup failed; check configuration and gh installation"
        print(f"ERROR_CODE=BETTERSTACK_SETUP_FAILED: {message}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
