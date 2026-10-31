#!/usr/bin/env python3
"""Use only our own lock and processes; never signal a real installer."""
import os
from pathlib import Path
import shlex
import signal
import subprocess
import tempfile
import time
import unittest

REPO = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.geteuid() == 0, 'root-owned installer lock test')
class LockTests(unittest.TestCase):
    def test_stopped_installer_resumes_rolls_back_and_releases_lock(self):
        with tempfile.TemporaryDirectory(prefix='installer-lock-') as directory:
            root = Path(directory)
            prelude = ('source ' + shlex.quote(str(REPO / 'setup-remnanode.sh')) + '\n'
                       'LOCK_FILE=' + shlex.quote(str(root / 'lock')) + '\n'
                       'LOCK_PID_FILE=' + shlex.quote(str(root / 'pid')) + '\n'
                       'INSTALLER_REPLACE_TIMEOUT=10\n')
            old = root / 'setup-remnanode.sh'
            old.write_text(prelude + '''
acquire_lock
sleep 30 &
child=$!
trap 'echo rollback >>"''' + str(root / 'rollback') + '''"; kill -CONT "$child" 2>/dev/null || true; kill -TERM "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; release_installer_lock; exit 0' TERM
kill -STOP "$child"
echo ready >"''' + str(root / 'ready') + '''"
kill -STOP "$BASHPID"
wait "$child" || true
''')
            process = subprocess.Popen(['bash', str(old)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                deadline = time.monotonic() + 5
                while not (root / 'ready').exists() and time.monotonic() < deadline:
                    time.sleep(.02)
                self.assertTrue((root / 'ready').exists())
                replacement = subprocess.run(['bash', '-c', prelude + '\nacquire_lock\necho REPLACED\nrelease_installer_lock\n'],
                                             capture_output=True, text=True, timeout=15)
                self.assertEqual(replacement.returncode, 0, replacement.stdout + replacement.stderr)
                self.assertIn('REPLACED', replacement.stdout)
                process.wait(timeout=5)
                self.assertEqual((root / 'rollback').read_text().splitlines(), ['rollback'])
            finally:
                if process.poll() is None:
                    process.send_signal(signal.SIGCONT); process.terminate(); process.wait(timeout=5)

    def test_unknown_lock_owner_is_not_killed(self):
        with tempfile.TemporaryDirectory(prefix='installer-unknown-lock-') as directory:
            root = Path(directory)
            prelude = ('source ' + shlex.quote(str(REPO / 'setup-remnanode.sh')) + '\n'
                       'LOCK_FILE=' + shlex.quote(str(root / 'lock')) + '\n'
                       'LOCK_PID_FILE=' + shlex.quote(str(root / 'pid')) + '\n')
            old = root / 'unrelated-worker.sh'
            old.write_text(prelude + 'acquire_lock\necho ready >' + shlex.quote(str(root / 'ready')) + '\nread -r -t 30 value < <(sleep 30) || true\n')
            process = subprocess.Popen(['bash', str(old)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                       start_new_session=True)
            try:
                deadline = time.monotonic() + 5
                while not (root / 'ready').exists() and time.monotonic() < deadline:
                    time.sleep(.02)
                self.assertTrue((root / 'ready').exists())
                replacement = subprocess.run(['bash', '-c', prelude + '\nacquire_lock\n'],
                                             capture_output=True, text=True, timeout=5)
                self.assertNotEqual(replacement.returncode, 0)
                self.assertIsNone(process.poll())
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM); process.wait(timeout=5)


if __name__ == '__main__':
    unittest.main()
