import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[2] / "scripts"
sys.path.insert(0, str(SCRIPTS))
import prepare_telemetry as prepare
import setup_betterstack as setup


def settings():
    return {
        "SENTRY_DSN": "https://test@s1.us-west-2a.betterstackdata.com/2",
        "BETTERSTACK_LOGS_URL": "https://s1.us-west-2a.betterstackdata.com",
        "BETTERSTACK_SOURCE_TOKEN": "test",
    }


class BuildConfigurationTest(unittest.TestCase):
    def test_complete_configuration_enables_beta_and_round_trips_without_output(self):
        result = prepare.build_configuration(settings(), require_remote=True)
        self.assertTrue(result["telemetry_beta"])
        self.assertEqual(result["sentry_dsn"], settings()["SENTRY_DSN"])
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "telemetry.json"
            output.write_text("old")
            output.chmod(0o644)
            prepare.write_configuration(output, result)
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)
            self.assertEqual(json.loads(output.read_text()), result)

    def test_unconfigured_build_stays_local_unless_remote_is_required(self):
        self.assertFalse(prepare.build_configuration({})["telemetry_beta"])
        with self.assertRaises(prepare.ConfigurationError):
            prepare.build_configuration({}, require_remote=True)

    def test_partial_or_mismatched_settings_fail_before_build(self):
        for removed in settings():
            value = settings()
            del value[removed]
            with self.subTest(removed=removed), self.assertRaises(prepare.ConfigurationError):
                prepare.build_configuration(value)
        value = settings()
        value["BETTERSTACK_LOGS_URL"] = "https://another.betterstackdata.com"
        with self.assertRaises(prepare.ConfigurationError):
            prepare.build_configuration(value)

    def test_rejects_destinations_that_can_redirect_or_expose_credentials(self):
        for url in ["http://s1.betterstackdata.com", "https://bad.invalid", "https://s1.betterstackdata.com/path",
                    "https://s1.betterstackdata.com?key=CANARY", "https://s1.betterstackdata.com:444"]:
            value = settings()
            value["BETTERSTACK_LOGS_URL"] = url
            with self.subTest(url=url), self.assertRaises(prepare.ConfigurationError):
                prepare.build_configuration(value)

    def test_error_output_does_not_echo_credential_values(self):
        with tempfile.TemporaryDirectory() as directory:
            env = {**os.environ, **settings(), "SENTRY_DSN": "PRIVATE_CANARY"}
            result = subprocess.run(
                [sys.executable, str(SCRIPTS / "prepare_telemetry.py"), "--output", f"{directory}/defines.json"],
                env=env, capture_output=True, text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("PRIVATE_CANARY", result.stdout + result.stderr)
            self.assertFalse(Path(directory, "defines.json").exists())


class FakeAPI:
    def __init__(self):
        self.sources = []
        self.applications = []
        self.posts = []

    def list(self, url):
        return self.applications if "errors.betterstack" in url else self.sources

    def request(self, url, body=None):
        self.posts.append((url, body))
        rows = self.applications if "errors.betterstack" in url else self.sources
        resource = {"id": str(2 if rows is self.applications else 1), "attributes": {
            **body, "team_id": 42, "token": "test", "ingesting_host": "s1.us-west-2a.betterstackdata.com",
        }}
        rows.append(resource)
        return {"data": resource}


class SetupTest(unittest.TestCase):
    def test_dry_run_does_not_create_or_change_resources(self):
        api = FakeAPI()
        self.assertEqual(setup.configure(api, 42, "team"), {"source": "create", "application": "create"})
        self.assertEqual(api.posts, [])

    def test_repeated_apply_reuses_both_resources_and_preserves_free_retention(self):
        api = FakeAPI()
        first = setup.configure(api, 42, "team", apply=True)
        second = setup.configure(api, 42, "team", apply=True)
        self.assertEqual(first, second)
        self.assertEqual(len(api.posts), 2)
        self.assertEqual(api.posts[1][1]["correlate_with_source_id"], "1")
        self.assertNotIn("logs_retention", api.posts[0][1])
        self.assertEqual(prepare.build_configuration(first, require_remote=True)["telemetry_beta"], True)

    def test_wrong_existing_correlation_is_rejected_without_replacing_resources(self):
        api = FakeAPI()
        setup.configure(api, 42, "team", apply=True)
        api.applications[0]["attributes"]["correlate_with_source_id"] = "other"
        with self.assertRaises(setup.SetupError):
            setup.configure(api, 42, "team", apply=True)
        self.assertEqual(len(api.posts), 2)

    def test_github_receives_only_ingestion_settings_over_stdin(self):
        calls = []
        def run(command, **kwargs):
            calls.append((command, kwargs))
            return subprocess.CompletedProcess(command, 0)
        values = settings()
        setup.sync_github(values, "owner/repo", ["release-signing", "release-publish"], run=run)
        self.assertEqual(len(calls), 6)
        for command, kwargs in calls:
            self.assertNotIn(values[command[3]], command)
            self.assertEqual(kwargs["input"], values[command[3]])
            self.assertIn("--env", command)


if __name__ == "__main__":
    unittest.main()
