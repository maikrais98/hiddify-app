"""Private Mac TLS relay; standard library only. No production or VPN operations."""
import argparse
import base64
import http.client
import http.server
import ipaddress
import json
import os
from pathlib import Path
import re
import ssl
import subprocess
from urllib.parse import parse_qs, urlsplit

PREFIX = '/api/luma/v1/'
POST = {'auth/email/start', 'auth/email/complete', 'auth/refresh', 'auth/logout',
        'me/reauth/start', 'me/reauth/complete', 'me/sessions/revoke-all'}
NETWORKS = tuple(ipaddress.ip_network(n) for n in ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16'))

def private_ipv4(value):
    address = ipaddress.IPv4Address(value)
    if not any(address in network for network in NETWORKS):
        raise ValueError('Use the Mac Wi-Fi RFC1918 IPv4 address, never a wildcard/public address')
    return str(address)

def allowed_request(method, target):
    try:
        url = urlsplit(target)
        if url.scheme or url.netloc or url.fragment or not url.path.startswith(PREFIX):
            return False
        path = url.path[len(PREFIX):]
        if method == 'GET' and path == 'me':
            return not url.query
        if method == 'GET' and path == 'me/sessions':
            query = parse_qs(url.query, keep_blank_values=True, strict_parsing=True)
            return (len(url.query) <= 5000 and all(k in {'limit', 'cursor'} and len(v) == 1 for k, v in query.items())
                    and (not query.get('limit') or 1 <= int(query['limit'][0]) <= 100))
        return method == 'POST' and not url.query and (path in POST or re.fullmatch(
            r'(auth/transactions/[a-fA-F0-9-]{36}/cancel|me/sessions/[a-fA-F0-9-]{36}/revoke)', path) is not None)
    except ValueError:
        return False

def checked_length(value):
    if not isinstance(value, str) or not re.fullmatch(r'\d{1,5}', value):
        raise ValueError('Invalid Content-Length')
    length = int(value)
    if length > 8192:
        raise ValueError('Body too large')
    return length

class RelayServer(http.server.ThreadingHTTPServer):
    daemon_threads = True
    def __init__(self, address, upstream_port):
        self.upstream_port = upstream_port
        super().__init__(address, RelayHandler)

class RelayHandler(http.server.BaseHTTPRequestHandler):
    server_version = 'LumaLab'
    sys_version = ''
    def setup(self):
        super().setup()
        self.connection.settimeout(15)

    def log_message(self, *_):
        pass  # No URLs, headers, OTPs, tokens or bodies in access/error logs.

    def reject(self, status):
        self.send_response(status)
        self.send_header('Content-Length', '0')
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()

    def do_GET(self):
        self.forward()

    def do_POST(self):
        self.forward()

    def forward(self):
        host, port = self.server.server_address[:2]
        if (self.headers.get('Host') != f'{host}:{port}' or self.headers.get('Origin') or
                self.headers.get('Transfer-Encoding') or not allowed_request(self.command, self.path)):
            self.reject(403)
            return
        try:
            length = checked_length(self.headers.get('Content-Length', '0'))
            if self.command == 'GET' and length:
                raise ValueError('GET body')
            if self.command == 'POST' and self.headers.get_content_type() != 'application/json':
                raise ValueError('JSON required')
        except ValueError:
            self.reject(400)
            return
        upstream = http.client.HTTPConnection('127.0.0.1', self.server.upstream_port, timeout=15)
        try:
            body = self.rfile.read(length) if length else None
            if length and len(body) != length:
                self.reject(400)
                return
            headers = {'Accept': 'application/json', 'Content-Type': 'application/json'}
            for key in ('Authorization', 'Idempotency-Key'):
                if self.headers.get(key):
                    headers[key] = self.headers[key]
            upstream.request(self.command, self.path, body=body, headers=headers)
            response = upstream.getresponse()
            payload = response.read(65537)
            if len(payload) > 65536 or 300 <= response.status < 400:
                self.reject(502)
                return
            self.send_response(response.status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(payload)))
            retry = response.getheader('Retry-After')
            if retry and retry.isdigit():
                self.send_header('Retry-After', retry)
            self.end_headers()
            self.wfile.write(payload)
        except (OSError, http.client.HTTPException):
            self.reject(502)
        finally:
            upstream.close()

def prepare(directory, bind, port, openssl='openssl'):
    bind = private_ipv4(bind)
    directory = Path(directory)
    directory.mkdir(mode=0o700, parents=True, exist_ok=False)
    key, cert = directory / 'relay.key', directory / 'relay.pem'
    subprocess.run([openssl, 'req', '-x509', '-newkey', 'rsa:2048', '-sha256', '-nodes', '-days', '7',
                    '-keyout', str(key), '-out', str(cert), '-subj', '/CN=Luma U3 private lab',
                    '-addext', f'subjectAltName=IP:{bind}', '-addext', 'basicConstraints=critical,CA:TRUE',
                    '-addext', 'extendedKeyUsage=serverAuth'], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    key.chmod(0o600)
    der = ssl.PEM_cert_to_DER_cert(cert.read_text())
    config = {'LUMA_ACCOUNT_LAB': 'true', 'LUMA_ACCOUNT_BASE_URL': f'https://{bind}:{port}{PREFIX}',
              'LUMA_ACCOUNT_CERT_BASE64': base64.b64encode(der).decode('ascii')}
    (directory / 'defines.json').write_text(json.dumps(config, indent=2) + '\n')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    for name in ('prepare', 'serve'):
        command = commands.add_parser(name)
        command.add_argument('--bind', required=True, type=private_ipv4)
        command.add_argument('--port', type=int, default=55443)
        command.add_argument('--directory', type=Path, default=Path('.u3-lab'))
        if name == 'serve':
            command.add_argument('--ssh-port', type=int, default=55442)
    args = parser.parse_args()
    os.umask(0o077)
    if args.command == 'prepare':
        prepare(args.directory, args.bind, args.port)
        print('Local certificate and debug defines prepared. Valid for seven days. Private key stays on Mac.')
    else:
        config = json.loads((args.directory / 'defines.json').read_text())
        if config['LUMA_ACCOUNT_BASE_URL'] != f'https://{args.bind}:{args.port}{PREFIX}':
            parser.error('Bind address must match the prepared certificate and build defines')
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(args.directory / 'relay.pem', args.directory / 'relay.key')
        server = RelayServer((args.bind, args.port), args.ssh_port)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        print('Private TLS relay running. Ctrl-C stops it. Access logging disabled.')
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            server.server_close()

if __name__ == '__main__':
    main()
