#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
bash -n install.sh
bash -n setup-remnanode.sh
python3 - <<'PY'
import ast
from pathlib import Path
for path in Path('bin').iterdir():
    if path.is_file():
        ast.parse(path.read_text())
PY
bash tests/test_installer_contract.sh
python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 tests/run_network_guards.py
