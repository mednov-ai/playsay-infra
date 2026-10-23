"""Fixed-scope authenticated JSON; secrets never appear in argv, URLs or logs."""
import hashlib
import hmac
import http.client
import socket
import ssl
import json
import re
import secrets
import time
import urllib.error
import urllib.request
from collections import OrderedDict
from threading import Lock

from .model import Deferred

LIMIT = 65536
ROLES = frozenset(('ax41', 'selectel', 'prod', 'dev'))
PATHS = frozenset(('/state', '/readiness', '/snapshot', '/activity', '/lease/claim', '/lease/fence',
                   '/lease/step', '/lease/assert', '/lease/preflight', '/lease/verify', '/lease/heartbeat', '/lease/complete-step', '/lease/release',
                   '/fence/close', '/fence/hold', '/fence/open'))


def mac(key, method, path, timestamp, nonce, body):
    value = '\n'.join((method, path, timestamp, nonce, hashlib.sha256(body).hexdigest())).encode()
    return hmac.new(bytes.fromhex(key), value, hashlib.sha256).hexdigest()


class Authenticator:
    def __init__(self, keys, journal=None):
        if not keys or any(k not in ROLES or not re.fullmatch('[0-9a-f]{64}', v) for k, v in keys.items()):
            raise ValueError('invalid_key_inventory')
        self.keys = keys
        self.journal = journal
        self.nonces = OrderedDict()
        self.lock = Lock()

    def verify(self, method, path, headers, body, now):
        actor = headers.get('X-Honey-Actor', '')
        stamp = headers.get('X-Honey-Time', '')
        nonce = headers.get('X-Honey-Nonce', '')
        supplied = headers.get('X-Honey-MAC', '')
        if method not in ('GET', 'POST') or path not in PATHS or len(body) > LIMIT:
            raise Deferred('request_invalid')
        if actor not in self.keys or not re.fullmatch('[0-9]{1,12}', stamp) or abs(now-int(stamp)) > 30:
            raise Deferred('authentication_failed')
        if not re.fullmatch('[0-9a-f]{32}', nonce) or not re.fullmatch('[0-9a-f]{64}', supplied):
            raise Deferred('authentication_failed')
        if not hmac.compare_digest(mac(self.keys[actor], method, path, stamp, nonce, body), supplied):
            raise Deferred('authentication_failed')
        if self.journal is not None:
            with self.journal.locked('auth') as seen:
                for token in list(seen):
                    if seen[token] < now-60:del seen[token]
                token=actor+':'+nonce
                if token in seen or len(seen)>=4096:raise Deferred('request_replayed_or_busy')
                seen[token]=now
            return actor
        with self.lock:
            for token in list(self.nonces):
                if self.nonces[token] < now-60:
                    del self.nonces[token]
            token = (actor, nonce)
            if token in self.nonces or len(self.nonces) >= 4096:
                raise Deferred('request_replayed_or_busy')
            self.nonces[token] = now
        return actor


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise Deferred('control_redirect_rejected')


class FixedHTTPS(urllib.request.HTTPSHandler):
    """Connect to declared peer IP while retaining normal hostname/SNI verification."""
    def __init__(self, hostname, address):
        super().__init__(context=ssl.create_default_context())
        self.hostname, self.address = hostname, address

    def https_open(self, request):
        def connection(host, **kwargs):
            if host != self.hostname:
                raise Deferred('control_destination_mismatch')
            result = http.client.HTTPSConnection(host, **kwargs)
            result._create_connection = lambda address, timeout, source_address=None: socket.create_connection(
                (self.address, address[1]), timeout, source_address)
            return result
        return self.do_open(connection, request, context=self._context)


class Client:
    def __init__(self, endpoint, actor, key, address=None):
        # This local nginx endpoint is reached through fixed TLS routes by deployment.
        # Only loopback is permitted for plaintext (local agent), never a remote host.
        from urllib.parse import urlsplit
        parsed = urlsplit(endpoint)
        if parsed.username or parsed.password or parsed.query or parsed.fragment:
            raise ValueError('invalid_endpoint')
        if parsed.scheme != 'https' and not (parsed.scheme == 'http' and parsed.hostname == '127.0.0.1'):
            raise ValueError('unprotected_endpoint')
        self.endpoint, self.actor, self.key = endpoint.rstrip('/'), actor, key
        handlers = [urllib.request.ProxyHandler({}), NoRedirect()]
        if parsed.scheme == 'https':
            if parsed.hostname != 'ops.honey.school' or address not in ('65.109.55.110', '94.102.89.213'):
                raise ValueError('undeclared_control_destination')
            handlers.append(FixedHTTPS(parsed.netloc, address))
        self.opener = urllib.request.build_opener(*handlers)

    def request(self, path, data=None):
        if path not in PATHS:
            raise ValueError('unknown_path')
        method = 'GET' if data is None else 'POST'
        body = b'' if data is None else json.dumps(data, separators=(',', ':'), allow_nan=False).encode()
        stamp, nonce = str(int(time.time())), secrets.token_hex(16)
        headers = {'Content-Type': 'application/json', 'X-Honey-Actor': self.actor,
                   'X-Honey-Time': stamp, 'X-Honey-Nonce': nonce,
                   'X-Honey-MAC': mac(self.key, method, path, stamp, nonce, body)}
        req = urllib.request.Request(self.endpoint+path, method=method, headers=headers,
                                     data=None if data is None else body)
        try:
            with self.opener.open(req, timeout=10) as response:
                value = response.read(LIMIT+1)
            if len(value) > LIMIT:
                raise Deferred('response_oversized')
            result = json.loads(value)
            if not isinstance(result, dict):
                raise Deferred('response_invalid')
            return result
        except urllib.error.HTTPError as error:
            try:
                value=json.loads(error.read(LIMIT+1))
                code=value.get('error','')
                if isinstance(code,str) and re.fullmatch('[a-z_]{1,80}',code):raise Deferred(code)
            except (ValueError,AttributeError):pass
            raise Deferred('control_unavailable') from error
        except (OSError, ValueError, urllib.error.URLError) as error:
            raise Deferred('control_unavailable') from error
