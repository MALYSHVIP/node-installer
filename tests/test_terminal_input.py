#!/usr/bin/env python3
"""Exercise real controlling terminals and sudo's relay, without installing a node."""
import fcntl
import os
from pathlib import Path
import pty
import re
import select
import shlex
import subprocess
import tempfile
import termios
import time
import unittest

REPO = Path(__file__).resolve().parents[1]


class TerminalTests(unittest.TestCase):
    def exercise(self, sudo, slow=True, ending=b'\r'):
        with tempfile.TemporaryDirectory(prefix='installer-terminal-') as directory:
            root = Path(directory)
            fixture = root / 'fixture.sh'
            fixture.write_text('''#!/usr/bin/env bash
source ''' + shlex.quote(str(REPO / 'setup-remnanode.sh')) + '''
load_saved_state() { :; }
detect_legacy_xhttp() { :; }
validate_existing_compose_overrides() { :; }
detect_existing_secret() { :; }
PANEL_IPS_INPUT=144.31.1.170
ENABLE_MASKED_BBR=auto
ENABLE_XHTTP=auto
SECRET_VALUE=''
PROMPT_TIMEOUT=5
collect_inputs
[[ "$MASKED_BBR_DOMAIN" == node.example.com && "$XHTTP_DOMAIN" == node.example.com ]]
[[ "$SECRET_VALUE" == AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA ]]
ask_bool 'TEST APPLY?'
bool_true "$PROMPT_VALUE"
# A real child/pipeline must own a usable terminal after the questions.
python3 -c 'import os,termios; assert os.tcgetpgrp(0)==os.getpgrp(); t=termios.tcgetattr(0); termios.tcsetattr(0,termios.TCSANOW,t); print("TTY_PIPELINE_OK")' | tee /dev/null
echo TERMINAL_TEST_OK
''')
            bootstrap = (REPO / 'install.sh').read_text()
            marker = 'if [[ -z "${BASH_SOURCE[0]:-}"'
            pos = bootstrap.index(marker)
            bootstrap = bootstrap[:pos] + '\ndownload_installer() { cp ' + shlex.quote(str(fixture)) + ' "$TMP_FILE"; }\n' + bootstrap[pos:]
            boot = root / 'bootstrap.sh'
            boot.write_text(bootstrap)
            master, slave = pty.openpty()
            def child_terminal():
                os.setsid()
                fcntl.ioctl(0, termios.TIOCSCTTY, 0)
            command = 'cat ' + shlex.quote(str(boot)) + ' | ' + ('sudo -n env PANEL_IP=144.31.1.170 ' if sudo else '') + 'bash'
            process = subprocess.Popen(['bash', '--noprofile', '--norc', '-i'], stdin=slave, stdout=slave, stderr=slave,
                                       preexec_fn=child_terminal, close_fds=True)
            os.close(slave)
            os.write(master, (command + '; exit $?\r').encode())
            answers = [value + ending for value in [b'y', b'NODE.EXAMPLE.COM', b'y', b'A' * 128, b'y']]
            output = b''
            answered = 0
            deadline = time.monotonic() + 25
            try:
                while time.monotonic() < deadline:
                    ready, _, _ = select.select([master], [], [], .1)
                    if ready:
                        try:
                            part = os.read(master, 65536)
                        except OSError:
                            break
                        if not part:
                            break
                        output += part
                        prompts = len(re.findall(rb'\[INPUT\]', output))
                        while answered < prompts and answered < len(answers):
                            
                            for byte in answers[answered]:
                                os.write(master, bytes([byte])); time.sleep(.015 if slow else 0)
                            answered += 1
                    if process.poll() is not None and not ready:
                        break
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=5)
                self.assertEqual(process.returncode, 0, output.decode(errors='replace'))
                self.assertEqual(answered, len(answers), output.decode(errors='replace'))
                self.assertIn(b'TERMINAL_TEST_OK', output)
                self.assertIn(b'TTY_PIPELINE_OK', output)
                self.assertEqual(output.count(b'NODE.EXAMPLE.COM'), 1, output.decode(errors='replace'))
            finally:
                if process.poll() is None:
                    process.kill(); process.wait()
                os.close(master)

    def test_slow_cr_interactive_pipe(self):
        self.exercise(False)

    @unittest.skipUnless(os.geteuid() == 0, 'sudo relay test requires isolated root test runner')
    def test_slow_cr_interactive_sudo_relay(self):
        self.exercise(True)

    def test_bulk_lf_pipe(self):
        self.exercise(False, slow=False, ending=b'\n')

    @unittest.skipUnless(os.geteuid() == 0, 'sudo relay test requires root')
    def test_bulk_lf_sudo_relay(self):
        self.exercise(True, slow=False, ending=b'\n')


if __name__ == '__main__':
    unittest.main()
