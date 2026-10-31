#!/usr/bin/env python3
import base64
import contextlib
import hashlib
import io
import json
from pathlib import Path
import runpy
import subprocess
import tempfile
import time
import unittest

REPO = Path(__file__).resolve().parents[1]


class PullTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='ip-pull-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        module = runpy.run_path(str(REPO / 'bin/remnanode-ssh-peers-pull'))
        self.g = module['sync_locked'].__globals__
        self.g['STATE_FILE'] = self.root / 'state.json'
        self.g['MASTER_MODE'] = self.root / 'no-master-mode'
        self.g['PUBLIC_KEY'] = self.root / 'public.pem'
        self.g['TOKEN_FILE'] = self.root / 'token'
        self.g['NODE_IP_FILE'] = self.root / 'ip'
        self.payload = {'version': 1, 'generation': 10, 'issued_at': int(time.time()) - 1,
                        'expires_at': int(time.time()) + 3600, 'peers': ['1.1.1.1', '8.8.8.8']}
        self.calls = []
        self.g['node_identity'] = lambda: ('1.1.1.1', b'x' * 32)
        self.g['send_ack'] = lambda *a: self.calls.append(('ack', a[-1]))
        self.g['verify_signature'] = lambda payload, signature: json.dumps(payload, sort_keys=True, separators=(',', ':')).encode()
        self.g['fetch_manifest'] = lambda *a: json.dumps({'payload': self.payload, 'signature': 'test'}).encode()
        self.g['run'] = lambda *a, **k: self.calls.append((a[1] if len(a) > 1 else a[0], k.get('input_bytes')))
        self.g['trusted_file'] = lambda p: None  # Root ownership is checked separately by installer safety tests.

    def sync(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.g['sync_locked']()

    def test_new_generation_applies_and_acknowledges(self):
        self.sync()
        self.assertIn(('apply', b'1.1.1.1\n8.8.8.8\n'), self.calls)
        self.assertIn(('install-hooks', None), self.calls)
        self.assertIn(('ack', 'applied'), self.calls)

    def test_same_generation_is_verified_without_reapply(self):
        self.sync(); self.calls.clear(); self.sync()
        self.assertIn(('verify', None), self.calls)
        self.assertFalse(any(c[0] == 'apply' for c in self.calls))

    def test_same_generation_repairs_missing_runtime_rules(self):
        self.sync(); self.calls.clear()
        original = self.g['run']
        def missing(*a, **k):
            if a[1] == 'verify':
                raise RuntimeError('missing runtime')
            return original(*a, **k)
        self.g['run'] = missing; self.sync()
        self.assertTrue(any(c[0] == 'apply' for c in self.calls))

    def test_older_generation_is_refused(self):
        self.sync(); self.calls.clear(); self.payload['generation'] -= 1
        with self.assertRaisesRegex(ValueError, 'rollback'):
            self.sync()
        self.assertEqual(self.calls, [])

    def test_generation_collision_is_refused(self):
        self.sync(); self.payload['expires_at'] += 1
        with self.assertRaisesRegex(ValueError, 'collision'):
            self.sync()

    def test_expired_list_is_refused(self):
        self.payload['expires_at'] = int(time.time()) - 1
        with self.assertRaises(ValueError):
            self.sync()

    def test_removed_self_is_refused(self):
        self.payload['peers'] = ['8.8.8.8', '9.9.9.9']
        with self.assertRaises(ValueError):
            self.sync()

    def test_private_peers_are_refused(self):
        self.payload['peers'].append('192.168.0.1')
        with self.assertRaises(ValueError):
            self.sync()

    def test_duplicate_peers_are_refused(self):
        self.payload['peers'].append('1.1.1.1')
        with self.assertRaises(ValueError):
            self.sync()

    def test_real_ed25519_signature_and_tamper(self):
        subprocess.run(['openssl', 'genpkey', '-algorithm', 'ED25519', '-out', str(self.root / 'key.pem')], check=True, capture_output=True)
        pub = subprocess.check_output(['openssl', 'pkey', '-in', str(self.root / 'key.pem'), '-pubout'])
        self.g['PUBLIC_KEY'].write_bytes(pub)
        self.g['PUBLIC_KEY_SHA256'] = hashlib.sha256(pub).hexdigest()
        canonical = json.dumps(self.payload, sort_keys=True, separators=(',', ':')).encode()
        (self.root / 'payload').write_bytes(canonical)
        sig = subprocess.check_output(['openssl', 'pkeyutl', '-sign', '-rawin', '-inkey', str(self.root / 'key.pem'), '-in', str(self.root / 'payload')])
        fresh = runpy.run_path(str(REPO / 'bin/remnanode-ssh-peers-pull'))
        g = fresh['verify_signature'].__globals__
        g['PUBLIC_KEY'] = self.g['PUBLIC_KEY']; g['PUBLIC_KEY_SHA256'] = self.g['PUBLIC_KEY_SHA256']
        # These generated test files are owned by the CI user; the production path remains root-only.
        g['trusted_file'] = lambda p: None
        self.assertEqual(g['verify_signature'](self.payload, base64.b64encode(sig)), canonical)
        tampered = {**self.payload, 'generation': 11}
        with self.assertRaises(RuntimeError):
            g['verify_signature'](tampered, base64.b64encode(sig))


if __name__ == '__main__':
    unittest.main()
