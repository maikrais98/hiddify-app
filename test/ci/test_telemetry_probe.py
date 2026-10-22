import importlib.util
import json
from pathlib import Path
import socket
import ssl
import sys
import unittest
from unittest.mock import patch
from datetime import datetime, timezone
from urllib.error import HTTPError, URLError


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
ENV = {
    "SENTRY_DSN": "https://fixture@s1.betterstackdata.com/1",
    "BETTERSTACK_LOGS_URL": "https://s1.betterstackdata.com",
    "BETTERSTACK_SOURCE_TOKEN": "fixture-token-not-a-secret",
}


class TelemetryProbeTest(unittest.TestCase):
    def load_probe(self):
        path = ROOT / "scripts/telemetry_probe.py"
        self.assertTrue(path.exists(), "The bounded ingestion probe is not implemented")
        spec = importlib.util.spec_from_file_location("telemetry_probe", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def run_probe(self, module, post, env=None, **changes):
        values = dict(source_sha="a" * 40, version="0.0.1", target_build="22",
                      event_id="0123456789abcdef",
                      now=lambda: datetime(2026, 10, 22, 18, tzinfo=timezone.utc))
        values.update(changes)
        return module.run_probe(ENV if env is None else env, post=post, **values)

    def test_one_closed_probe_does_not_impersonate_a_device_build(self):
        module = self.load_probe()
        calls = []
        def post(url, token, body):
            calls.append((url, token, body))
            return 202
        receipt = self.run_probe(module, post)
        self.assertEqual(len(calls), 1)
        event = json.loads(calls[0][2])
        self.assertEqual(set(event), {"schema", "origin", "event", "event_id", "dt",
                                     "source_sha", "app_version", "target_build_number", "level", "message"})
        self.assertEqual(event["origin"], "release_controller")
        self.assertNotIn("build_number", event)
        self.assertEqual(event["event_id"], receipt["event_id"])
        self.assertLessEqual(len(calls[0][2]), 1024)
        self.assertEqual(receipt["code"], "INGEST_ACCEPTED")
        self.assertEqual(receipt["http_status"], 202)
        self.assertEqual(receipt["attempt_count"], 1)
        self.assertEqual(receipt["expected_source_id"], 2805644)
        self.assertNotIn(ENV["BETTERSTACK_SOURCE_TOKEN"], json.dumps(receipt))
        self.assertNotIn(ENV["SENTRY_DSN"], json.dumps(receipt))

    def test_invalid_configuration_does_not_send_or_echo_values(self):
        module = self.load_probe()
        for env in ({}, {**ENV, "BETTERSTACK_LOGS_URL": "https://wrong.example/?token=fixture-secret"}):
            with self.subTest(env_present=bool(env)):
                calls = []
                receipt = self.run_probe(module, lambda *args: calls.append(args), env=env)
                self.assertEqual(calls, [])
                self.assertEqual(receipt["code"], "TELEMETRY_CONFIGURATION_INVALID")
                self.assertEqual(receipt["attempt_count"], 0)
                self.assertNotIn("fixture-secret", json.dumps(receipt))

    def test_invalid_release_provenance_does_not_send(self):
        module = self.load_probe()
        for changes in ({"source_sha": "invalid"}, {"target_build": "0"}, {"event_id": "bad"}):
            calls = []
            receipt = self.run_probe(module, lambda *args: calls.append(args), **changes)
            self.assertEqual(calls, [])
            self.assertEqual(receipt["code"], "INVALID_PROBE_PROVENANCE")

    def test_rejection_and_retryable_responses_never_retry(self):
        module = self.load_probe()
        for status, code in ((302, "HTTP_REJECTED"), (401, "HTTP_REJECTED"),
                             (402, "HTTP_REJECTED"), (403, "HTTP_REJECTED"),
                             (429, "HTTP_RETRYABLE"), (503, "HTTP_RETRYABLE")):
            calls = []
            def post(*args):
                calls.append(args)
                return status
            receipt = self.run_probe(module, post)
            self.assertEqual(len(calls), 1)
            self.assertEqual(receipt["code"], code)
            self.assertEqual(receipt["http_status"], status)

    def test_transport_errors_are_closed_and_not_retried(self):
        module = self.load_probe()
        for error, code in ((TimeoutError("fixture-private"), "TRANSPORT_TIMEOUT"),
                            (socket.gaierror("fixture-private"), "TRANSPORT_NETWORK"),
                            (ssl.SSLError("fixture-private"), "TRANSPORT_TLS"),
                            (URLError(TimeoutError("fixture-private")), "TRANSPORT_TIMEOUT")):
            calls = []
            def post(*args):
                calls.append(args)
                raise error
            receipt = self.run_probe(module, post)
            self.assertEqual(len(calls), 1)
            self.assertEqual(receipt["code"], code)
            self.assertNotIn("fixture-private", json.dumps(receipt))

    def test_real_transport_refuses_redirect_and_sets_five_second_timeout(self):
        module = self.load_probe()
        with patch.object(module.request, "build_opener") as factory:
            factory.return_value.open.side_effect = HTTPError("https://s1.betterstackdata.com", 302,
                                                              "fixture-private", {}, None)
            status = module.post_once(ENV["BETTERSTACK_LOGS_URL"], ENV["BETTERSTACK_SOURCE_TOKEN"], b"{}")
            self.assertEqual(status, 302)
            args, kwargs = factory.return_value.open.call_args
            self.assertEqual(kwargs["timeout"], 5)
            self.assertEqual(args[0].get_method(), "POST")
            handler = factory.call_args.args[0]
            self.assertIsNone(handler.redirect_request(args[0], None, 302, "", {}, "https://wrong.example"))


if __name__ == "__main__":
    unittest.main()
