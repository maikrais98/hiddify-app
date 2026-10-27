import importlib.util
from pathlib import Path
import unittest
import base64
import http.client
import http.server
import json
import os
import shutil
import socket
import ssl
import tempfile
import threading

MODULE = Path(__file__).resolve().parents[2] / 'tools' / 'u3_lab.py'
spec = importlib.util.spec_from_file_location('u3_lab', MODULE)
lab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lab)

class RelayContractTest(unittest.TestCase):
    def test_explicit_private_ipv4_only(self):
        self.assertEqual(lab.private_ipv4('192.168.1.5'), '192.168.1.5')
        for value in ['0.0.0.0', '127.0.0.1', '8.8.8.8', 'localhost', '::', '100.64.1.2']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                lab.private_ipv4(value)

    def test_api_allowlist(self):
        for method, path in [('POST', 'auth/email/start'), ('GET', 'me'),
                             ('GET', 'me/sessions?limit=20&cursor=abc'),
                             ('POST', 'me/sessions/revoke-all')]:
            self.assertTrue(lab.allowed_request(method, '/api/luma/v1/' + path))
        for method, path in [('GET', '/'), ('CONNECT', '/api/luma/v1/me'),
                             ('POST', '/api/luma/v1/me'), ('GET', 'https://evil/api/luma/v1/me'),
                             ('GET', '/api/luma/v1/../me'), ('GET', '/api/luma/v1/%6de'),
                             ('GET', '/api/luma/v1/me?refresh_token=secret'),
                             ('GET', '/api/luma/v1/me/sessions?token=secret')]:
            self.assertFalse(lab.allowed_request(method, path), path)

    def test_request_body_size_is_bounded(self):
        self.assertEqual(lab.checked_length('8192'), 8192)
        for value in ['8193', '-1', 'abc', None, '1,2']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                lab.checked_length(value)

    def test_real_tls_relay_forwards_only_selected_headers_and_checks_certificate(self):
        openssl = shutil.which('openssl') or 'C:/Program Files/Git/usr/bin/openssl.exe'
        self.assertTrue(Path(openssl).exists(), 'OpenSSL required for the TLS test')
        received = []
        class Upstream(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass
            def do_POST(self):
                received.append((self.path, dict(self.headers), self.rfile.read(int(self.headers['Content-Length']))))
                payload = b'{"ok":true}'
                self.send_response(202)
                self.send_header('Content-Length', str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
        upstream = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Upstream)
        threading.Thread(target=upstream.serve_forever, daemon=True).start()
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp) / 'material'
            lab.prepare(directory, '192.168.1.5', 55443, openssl)
            config = json.loads((directory / 'defines.json').read_text())
            self.assertEqual(base64.b64decode(config['LUMA_ACCOUNT_CERT_BASE64']),
                             ssl.PEM_cert_to_DER_cert((directory / 'relay.pem').read_text()))
            self.assertNotIn('PRIVATE KEY', json.dumps(config))
            relay = lab.RelayServer(('127.0.0.1', 0), upstream.server_port)
            server_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            server_context.load_cert_chain(directory / 'relay.pem', directory / 'relay.key')
            relay.socket = server_context.wrap_socket(relay.socket, server_side=True)
            threading.Thread(target=relay.serve_forever, daemon=True).start()
            try:
                trusted = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
                trusted.load_verify_locations(directory / 'relay.pem')
                # Wrong IP SAN and a default trust store both reject this isolated certificate.
                for context, hostname in [(trusted, '127.0.0.1'), (ssl.create_default_context(), '192.168.1.5')]:
                    with socket.create_connection(relay.server_address, timeout=5) as raw:
                        with self.assertRaises(ssl.SSLCertVerificationError):
                            context.wrap_socket(raw, server_hostname=hostname)
                def connection():
                    conn = http.client.HTTPConnection(*relay.server_address, timeout=5)
                    raw = socket.create_connection(relay.server_address, timeout=5)
                    conn.sock = trusted.wrap_socket(raw, server_hostname='192.168.1.5')
                    return conn
                conn = connection()
                conn.request('POST', '/api/luma/v1/auth/email/start', b'{}',
                             {'Content-Type': 'application/json', 'Cookie': 'do-not-forward',
                              'Authorization': 'Bearer synthetic'})
                response = conn.getresponse()
                self.assertEqual(response.status, 202)
                self.assertEqual(response.getheader('Cache-Control'), 'no-store')
                self.assertEqual(response.read(), b'{"ok":true}')
                conn.close()
                self.assertEqual(received[0][2], b'{}')
                self.assertNotIn('Cookie', received[0][1])
                self.assertEqual(received[0][1]['Authorization'], 'Bearer synthetic')
                conn = connection()
                conn.request('GET', '/api/luma/v1/me', headers={'Origin': 'https://untrusted.test'})
                self.assertEqual(conn.getresponse().status, 403)
                conn.close()
                self.assertEqual(len(received), 1)
            finally:
                relay.shutdown()
                relay.server_close()
                upstream.shutdown()
                upstream.server_close()

if __name__ == '__main__':
    unittest.main()
