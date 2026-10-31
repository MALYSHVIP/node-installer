#!/usr/bin/env python3
"""Certificate proof validation, with synthetic credentials and no live endpoints."""
import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
IP = '8.8.8.8'
TOKEN = '12' * 32


def run(*args, data=None):
    return subprocess.run(args, input=data, capture_output=True, check=True).stdout


class EnrollmentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='enroll-fixture-')
        cls.root = Path(cls.temp.name)
        for name in ('ca', 'other'):
            run('openssl', 'req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256',
                '-nodes', '-keyout', str(cls.root / (name + '.key')), '-out', str(cls.root / (name + '.pem')),
                '-days', '1', '-subj', '/CN=Enrollment test CA')
        run('openssl', 'req', '-new', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256',
            '-nodes', '-keyout', str(cls.root / 'node.key'), '-out', str(cls.root / 'node.csr'),
            '-subj', '/CN=Enrollment test node')
        (cls.root / 'ext').write_text('basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=serverAuth\n')
        run('openssl', 'x509', '-req', '-in', str(cls.root / 'node.csr'), '-CA', str(cls.root / 'ca.pem'),
            '-CAkey', str(cls.root / 'ca.key'), '-CAcreateserial', '-days', '1',
            '-extfile', str(cls.root / 'ext'), '-out', str(cls.root / 'node.pem'))
        cls.cert = (cls.root / 'node.pem').read_text()

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def request(self, method='GET', data=None, ip=IP, peers=None, ca='ca.pem', raw=None):
        script = "define('REMNANODE_ENROLL_LIBRARY_ONLY', true);require $argv[1];$x=json_decode(stream_get_contents(STDIN),true);echo json_encode(enrollmentReply($x['server'],$x['body'],$x['tokens'],$x['peers'],$argv[2]));"
        body = raw if raw is not None else json.dumps(data) if data is not None else ''
        value = {'server': {'REQUEST_METHOD': method, 'REMOTE_ADDR': ip, 'HTTP_X_FORWARDED_FOR': IP},
                 'body': body, 'tokens': {IP: TOKEN}, 'peers': peers if peers is not None else [IP]}
        return json.loads(run('php', '-r', script, str(REPO / 'monitor/enroll.php'), str(self.root / ca),
                              data=json.dumps(value).encode()))

    def payload(self):
        status, challenge = self.request()
        self.assertEqual(status, 200)
        signed = 'node-enroll-v1\n{ip}\n{time}\n{nonce}\n{challenge}'.format(**challenge).encode()
        proof = run('openssl', 'dgst', '-sha256', '-sign', str(self.root / 'node.key'), data=signed)
        return {**challenge, 'certificate': self.cert, 'proof': base64.b64encode(proof).decode()}

    def test_valid_proof(self):
        status, value = self.request('POST', self.payload())
        self.assertEqual(status, 200)
        self.assertEqual(value['token'], TOKEN)
        self.assertEqual(value['ip'], IP)

    def test_unknown_source_cannot_enroll(self):
        self.assertEqual(self.request(ip='1.1.1.1')[0], 403)

    def test_forwarded_header_cannot_replace_source(self):
        self.assertEqual(self.request('POST', self.payload(), ip='1.1.1.1')[0], 403)

    def test_removed_peer_cannot_enroll(self):
        self.assertEqual(self.request('POST', self.payload(), peers=[])[0], 403)

    def test_wrong_ca(self):
        self.assertEqual(self.request('POST', self.payload(), ca='other.pem')[0], 403)

    def test_invalid_proof(self):
        data = self.payload(); data['proof'] = base64.b64encode(b'wrong').decode()
        self.assertEqual(self.request('POST', data)[0], 403)

    def test_changed_ip(self):
        data = self.payload(); data['ip'] = '1.1.1.1'
        self.assertEqual(self.request('POST', data)[0], 403)

    def test_changed_nonce(self):
        data = self.payload(); data['nonce'] = '00' * 32
        self.assertEqual(self.request('POST', data)[0], 403)

    def test_expired_challenge(self):
        data = self.payload(); data['time'] = '1000000000'
        self.assertEqual(self.request('POST', data)[0], 403)

    def test_invalid_certificate(self):
        data = self.payload(); data['certificate'] = 'invalid'
        self.assertEqual(self.request('POST', data)[0], 403)

    def test_body_limit(self):
        self.assertEqual(self.request('POST', raw='x' * 16385)[0], 413)

    def test_wrong_method(self):
        self.assertEqual(self.request('DELETE')[0], 405)


if __name__ == '__main__':
    unittest.main()
