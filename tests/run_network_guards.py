#!/usr/bin/env python3
"""Build real installer writers and execute them only in a disposable network namespace."""
import ast
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'setup-remnanode.sh').read_text()
runner = ROOT / 'tests/netns_guard_runner.py'
harness = runner.read_text()
functions = {'write_firewall': 'remove_bittorrent_string_runtime',
             'write_spamhaus_egress_guard': 'write_outbound_ssh_guard',
             'write_outbound_ssh_guard': 'write_dns_reflection_guard',
             'write_dns_reflection_guard': 'write_bittorrent_guard',
             'write_bittorrent_guard': 'configure_antiabuse_guards'}
tree = ast.parse(harness)
def definition(name):
    node = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == name)
    return '\n'.join(harness.splitlines()[node.lineno - 1:node.end_lineno])
bundle = {'version': re.search(r'^INSTALLER_VERSION="([^"]+)"', source, re.M)[1],
          'functions': {a: source[source.index('\n'+a+'() {')+1:source.index('\n'+b+'() {')]
                        for a, b in functions.items()},
          'peers_source': (ROOT / 'bin/remnanode-ssh-peers').read_text(),
          'server_source': definition('server'), 'connect_source': definition('connect')}
if os.geteuid() != 0:
    raise SystemExit('Run this test as root; it creates its own disposable network namespace.')
result = subprocess.run(['unshare', '-n', 'python3', str(runner)],
                        input=json.dumps(bundle), text=True, capture_output=True, timeout=180)
if result.returncode:
    raise SystemExit(result.stderr[-4000:])
data = json.loads(result.stdout)
print(json.dumps(data, indent=2))
if data['tests'] != data['passed']:
    raise SystemExit(1)
