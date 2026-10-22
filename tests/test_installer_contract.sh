#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case "${BASHPID:-}" in
  '') BASHPID=$$ ;;
esac
# shellcheck disable=SC1091
source "$repo_dir/setup-remnanode.sh"

# Regression for the production failure where `docker ... version | head -n1`
# closed stdout early and pipefail converted SIGPIPE into a fatal installer
# error. The replacement must return the first line while draining all output.
sigpipe_sensitive_producer() {
  python3 - <<'PY'
import os
for number in range(1, 20001):
    try:
        os.write(1, f"line-{number}\n".encode())
    except BrokenPipeError:
        raise SystemExit(141)
PY
}
[[ "$(sigpipe_sensitive_producer | first_line)" == "line-1" ]]
if grep -F 'version | head -n1' "$repo_dir/setup-remnanode.sh" >/dev/null; then
  printf 'unsafe version/head pipeline reintroduced\n' >&2
  exit 1
fi

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

# UDP/443 Hysteria and TCP/443 xHTTP are independent sockets. In combined
# mode the xHTTP vhost also provides the ordinary HTTPS cover on the same
# domain; Nginx must still not claim UDP/QUIC.
ENABLE_XHTTP=1
EXPECT_HYSTERIA=1
HYSTERIA_PORT=443
XHTTP_DOMAIN="$MASKED_BBR_DOMAIN"
XHTTP_PATH='/stable-in-443/'
XHTTP_SOCKET='/dev/shm/xrxh-stable.socket'
render_nginx_xhttp_site >"$test_root/nginx-combined.conf"
grep -Fq '# remnanode-installer-managed-xhttp' "$test_root/nginx-combined.conf"
grep -Fq 'server_name node.example.com;' "$test_root/nginx-combined.conf"
grep -Fq 'location ^~ /stable-in-443/' "$test_root/nginx-combined.conf"
grep -Fq 'grpc_pass unix:/dev/shm/xrxh-stable.socket;' "$test_root/nginx-combined.conf"
! grep -Eqi 'listen[^;]*(quic|udp)|Alt-Svc' "$test_root/nginx-combined.conf"
validate_settings

if (XHTTP_DOMAIN='other.example.com'; validate_settings >/dev/null 2>&1); then
  printf 'mismatched combined domains unexpectedly passed validation\n' >&2
  exit 1
fi

if (NODE_INSTALLER_PIPE_INPUT=1; ask 'must fail instead of hanging' >/dev/null 2>&1); then
  printf 'piped interactive input unexpectedly reached a prompt\n' >&2
  exit 1
fi

# Reproduce the interactive choice sequence without touching the host: masked
# BBR=yes, one domain, xHTTP=yes. The xHTTP edge must reuse that domain and
# expose TCP/443 while Hysteria keeps UDP/443.
(
  load_saved_state() { :; }
  detect_legacy_xhttp() { :; }
  validate_existing_compose_overrides() { :; }
  detect_existing_secret() { :; }
  validate_secret_basic() { :; }
  ask_bool() {
    case "$1" in
      *'masked BBR'*|*'также xHTTP'*) PROMPT_VALUE=1 ;;
      *) printf 'unexpected boolean prompt: %s\n' "$1" >&2; exit 1 ;;
    esac
  }
  ask() {
    case "$1" in
      *'Домен masked BBR'*) PROMPT_VALUE='node.example.com' ;;
      *) printf 'unexpected text prompt: %s\n' "$1" >&2; exit 1 ;;
    esac
  }
  ask_secret() { PROMPT_VALUE='test-secret-not-validated'; }

  YES=0
  PANEL_IPS_INPUT='144.31.1.170'
  PANEL_IPS=''
  ENABLE_MASKED_BBR=auto
  MASKED_BBR_DOMAIN_INPUT=''
  MASKED_BBR_DOMAIN=''
  ENABLE_XHTTP=auto
  XHTTP_DOMAIN_INPUT=''
  XHTTP_DOMAIN=''
  EXPECT_HYSTERIA=0
  SECRET_VALUE=''
  PUBLIC_TCP_PORTS='80,443'
  PUBLIC_UDP_PORTS='443'
  collect_inputs
  bool_true "$ENABLE_MASKED_BBR"
  bool_true "$ENABLE_XHTTP"
  bool_true "$EXPECT_HYSTERIA"
  [[ "$MASKED_BBR_DOMAIN" == 'node.example.com' ]]
  [[ "$XHTTP_DOMAIN" == "$MASKED_BBR_DOMAIN" ]]
)

printf 'masked-BBR installer contract tests: OK\n'
