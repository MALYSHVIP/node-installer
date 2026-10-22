#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case "${BASHPID:-}" in
  '') BASHPID=$$ ;;
esac
# shellcheck disable=SC1091
source "$repo_dir/setup-remnanode.sh"

test_root="$(mktemp -d /tmp/remnanode-masked-bbr-test.XXXXXX)"
trap 'rm -rf -- "$test_root"' EXIT
STATE_DIR="$test_root/state"
HYSTERIA_MASQUERADE_FILE="$STATE_DIR/hysteria-masquerade.json"
MASKED_BBR_CONTRACT_FILE="$STATE_DIR/masked-bbr-contract.json"
MASKED_BBR_PASSWORD_FILE="$STATE_DIR/masked-bbr-password"
MASKED_BBR_DOMAIN="node.example.com"
ENABLE_MASKED_BBR=1
TLS_DIR="/etc/remnanode/tls"
COVER_ROOT="/var/www/remnanode-cover"
NGINX_ACME_ROOT="/var/www/remnanode-acme"

# Runtime requires root ownership. The repository test runs as the checkout
# owner and verifies the same regular-file and permission invariants below.
require_trusted_root_file() {
  [[ -f "$1" && ! -L "$1" ]]
}

mkdir -p "$STATE_DIR"
python3 - "$HYSTERIA_MASQUERADE_FILE" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
path.write_text(json.dumps({
    'type': 'string', 'statusCode': 200, 'content': '<html>cover</html>',
    'headers': {'Content-Type': 'text/html; charset=utf-8'}
}), encoding='utf-8')
PY

write_masked_bbr_contract >/dev/null
first_password="$(cat "$MASKED_BBR_PASSWORD_FILE")"
write_masked_bbr_contract >/dev/null
second_password="$(cat "$MASKED_BBR_PASSWORD_FILE")"
[[ "$first_password" == "$second_password" ]]

python3 - "$MASKED_BBR_CONTRACT_FILE" "$MASKED_BBR_PASSWORD_FILE" <<'PY'
import json, pathlib, stat, sys
contract_path, password_path = map(pathlib.Path, sys.argv[1:])
contract = json.loads(contract_path.read_text(encoding='utf-8'))
stream = contract['streamSettings']
mask = stream['finalmask']['udp']
assert contract['schema'] == 'tokervpn-remnawave-masked-bbr/v1'
assert stream['network'] == 'hysteria'
assert stream['security'] == 'tls'
assert stream['tlsSettings']['alpn'] == ['h3']
assert stream['finalmask']['quicParams'] == {
    'congestion': 'bbr', 'disablePathMTUDiscovery': True
}
assert len(mask) == 1 and mask[0]['type'] == 'salamander'
assert mask[0]['settings']['password'] == password_path.read_text(encoding='utf-8').strip()
assert 'packetSize' not in mask[0]['settings']
assert stat.S_IMODE(contract_path.stat().st_mode) == 0o600
assert stat.S_IMODE(password_path.stat().st_mode) == 0o600
PY

nginx() {
  if [[ "${1:-}" == -v ]]; then
    printf 'nginx version: nginx/1.28.0\n' >&2
  fi
}
render_nginx_masked_bbr_site >"$test_root/nginx.conf"
grep -Fq '# remnanode-installer-managed-masked-bbr-cover' "$test_root/nginx.conf"
grep -Fq 'server_name node.example.com;' "$test_root/nginx.conf"
grep -Fq 'listen 443 ssl;' "$test_root/nginx.conf"
! grep -Eqi 'listen[^;]*(quic|udp)|Alt-Svc' "$test_root/nginx.conf"

printf 'masked-BBR installer contract tests: OK\n'
