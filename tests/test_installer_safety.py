"""Offline tests; mutating commands are mocked. BASH_BIN must be Bash >= 4.4."""
import hashlib
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest

SCRIPT = (Path(__file__).resolve().parents[1] / "setup-remnanode.sh").resolve()
BASH = os.environ.get("BASH_BIN", "bash")


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="remnanode-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def shell(self, code, ok=True):
        prelude = f"""
source {shlex.quote(str(SCRIPT))}
trap - ERR INT TERM
T={shlex.quote(str(self.root))}
systemctl() {{ echo UNEXPECTED_SYSTEMCTL >&2; return 90; }}
docker() {{ echo UNEXPECTED_DOCKER >&2; return 90; }}
nft() {{ echo UNEXPECTED_NFT >&2; return 90; }}
apt-get() {{ echo UNEXPECTED_APT >&2; return 90; }}
swapon() {{ return 1; }}
sleep() {{ :; }}
"""
        r = subprocess.run([BASH, "-c", prelude + code], capture_output=True, text=True, timeout=20)
        if ok:
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        else:
            self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertNotIn("UNEXPECTED_", r.stderr)
        return r

    def test_udp_defaults_never_shrink_existing_buffers(self):
        self.shell("""
SYSCTL_FILE="$T/sysctl.conf"
sysctl() {
 if [[ "$1" == -p ]]; then return 0; fi
 case "$2" in
  net.core.rmem_default) echo 16777216;;
  net.core.wmem_default) echo 4194304;;
  net.core.rmem_max|net.core.wmem_max) echo 134217728;;
  net.core.netdev_max_backlog|net.ipv4.tcp_max_syn_backlog) echo 65536;;
  net.ipv4.tcp_available_congestion_control) echo 'reno cubic bbr';;
  net.ipv4.tcp_congestion_control) echo bbr;;
  *) echo 0;;
 esac
}
modprobe() { :; }
EXPECT_HYSTERIA=1
configure_minimal_sysctl
grep -qx 'net.core.rmem_default = 16777216' "$SYSCTL_FILE"
grep -qx 'net.core.wmem_default = 4194304' "$SYSCTL_FILE"
grep -qx 'net.core.rmem_max = 134217728' "$SYSCTL_FILE"
grep -qx 'net.core.wmem_max = 134217728' "$SYSCTL_FILE"
grep -qx 'net.core.netdev_max_backlog = 65536' "$SYSCTL_FILE"
""")

    def test_syntax(self):
        subprocess.run([BASH, "-n", str(SCRIPT)], check=True)

    def test_help_without_root(self):
        output = subprocess.check_output([BASH, str(SCRIPT), "--help"], text=True)
        self.assertIn("Node 3.4.2", output)
        self.assertIn("видимым вводом", output)

    def test_visible_secret_prompt(self):
        self.shell("declare -f ask_secret | grep -q 'ask \"SECRET_KEY'; ! declare -f ask_secret | grep -q 'read -rs'")

    def test_booleans(self):
        self.shell("""
for v in 1 true TRUE yes on; do bool_valid "$v"; bool_true "$v"; done
for v in 0 false FALSE no off; do bool_valid "$v"; ! bool_true "$v"; done
! bool_valid garbage
""")

    def test_ports(self):
        self.shell("""
for v in '' 443 1,65535 443,8000-9000; do validate_ports_csv "$v"; done
port_in_csv 8450 '443,8000-9000'
! port_in_csv 9001 '443,8000-9000'
for v in 0 65536 ,443 443, 443,,80 00080 9000-8000 1-2-3 999999999999999999999999999; do
  ! validate_ports_csv "$v" || exit 2
done
""")

    def test_domains(self):
        self.shell("""
validate_domain node.example.com
validate_domain xn--e1afmkfd.xn--p1ai
for v in .example.com example..com -node.example.com node-.example.com 'node;evil.com'; do
  ! validate_domain "$v" || exit 2
done
""")

    def test_ips(self):
        self.shell("""
validate_ipv4_cidr_basic 192.0.2.2
validate_ipv4_cidr_basic 192.0.2.0/24
validate_ipv6_cidr_basic 2001:db8::1/128
for v in 256.0.0.1 192.0.2.1/ 192.0.2.1/08 192.0.2.1/99 0.0.0.0/0; do
  ! validate_ipv4_cidr_basic "$v" || exit 2
done
! validate_ipv6_cidr_basic ::/0
PANEL_IPS='192.0.2.2 2001:db8::1/128'; validate_panel_ips_strict
""")

    def test_no_world_open_api(self):
        for ip in ["0.0.0.0/0", "::/0", "0.0.0.0", "ff00::/8", "2001:::5"]:
            with self.subTest(ip=ip):
                self.shell(f"PANEL_IPS={shlex.quote(ip)}; validate_panel_ips_strict", ok=False)

    def test_defaults(self):
        self.shell("""
[[ "$NODE_VERSION" == 3.4.2 && "$MIN_XRAY_VERSION" == 26.7.28 ]]
[[ "$ENABLE_QUIC_TUNING" == 0 && "$ENABLE_OUTBOUND_SSH_GUARD" == 1 ]]
[[ "$ENABLE_DNS_REFLECTION_GUARD" == 1 && "$EXPECT_HYSTERIA" == 0 ]]
ENABLE_XHTTP=0; ENABLE_MASKED_BBR=0; validate_settings
""")

    def test_bad_settings(self):
        for code in [
            "NODE_VERSION=2.8.0", "NODE_VERSION=4.0.0", "NODE_VERSION=3.4.2-beta",
            "NODE_IMAGE_INPUT=remnawave/node:latest", "NODE_IMAGE_INPUT=remnawave/node:2.8.0",
            "NODE_IMAGE_INPUT=evil.example/node:3.4.2", "NODE_PORT=443; PUBLIC_TCP_PORTS=443",
            "NODE_PORT=999999999999999999999999", "NODE_IMAGE_INPUT='image;touch /tmp/evil'",
        ]:
            with self.subTest(code=code):
                self.shell("ENABLE_XHTTP=0; " + code + "; validate_settings", ok=False)

    def test_explicit_official_image(self):
        self.shell("ENABLE_XHTTP=0; ENABLE_MASKED_BBR=0; NODE_IMAGE_INPUT=remnawave/node:3.4.2; validate_settings")

    def test_repair_does_not_restore_old_release(self):
        self.shell("""
STATE_FILE="$T/state"; INSTALLER_CONFIG="$T/absent"
printf 'SAVED_NODE_VERSION=2.8.0\nSAVED_NODE_IMAGE=remnawave/node:2.8.0\nSAVED_NODE_PORT=3333\nSAVED_ENABLE_OUTBOUND_SSH_GUARD=1\n' >"$STATE_FILE"
require_trusted_root_file() { :; }
MODE=repair; load_saved_state
[[ "$NODE_VERSION" == 3.4.2 && -z "$NODE_IMAGE_INPUT" && "$NODE_PORT" == 3333 ]]
[[ "$ENABLE_OUTBOUND_SSH_GUARD" == 1 ]]
NODE_PORT=4444; NODE_PORT_EXPLICIT=1; load_saved_state
[[ "$NODE_PORT" == 4444 ]]
""")

    def test_apt_failures_are_not_success(self):
        r = self.shell("""
prepare_package_network() { :; }
apt_log_path_for_attempt() { printf '%s/apt.log' "$T"; }
apt_output_contains_dns_error() { return 1; }
apt-get() { printf 'try\n' >>"$T/attempts"; echo 'mock failure'; return 100; }
apt_retry update
""", ok=False)
        self.assertEqual(r.returncode, 100)
        self.assertEqual((self.root / "attempts").read_text().count("try"), 4)

    def test_apt_success(self):
        self.shell("""
prepare_package_network() { :; }
apt_log_path_for_attempt() { printf '%s/apt.log' "$T"; }
apt-get() { echo mock-success; return 0; }
apt_retry update
""")

    def test_dry_run_no_backup(self):
        self.shell("""
DRY_RUN=1
collect_inputs() { :; }
validate_panel_ips_strict() { :; }
validate_secret_payload() { :; }
preflight_host() { :; }
print_plan() { :; }
create_backup() { exit 88; }
run_install
""")

    def test_dry_run_no_lock(self):
        self.shell("""
uname() { echo Linux; }
require_root() { :; }
assert_local_docker_context() { :; }
acquire_lock() { exit 88; }
run_install() { [[ "$DRY_RUN" == 1 ]]; }
main update --dry-run
""")

    def test_docker_no_socket_activation(self):
        r = self.shell("""
docker() { [[ "$*" == 'context show' ]] || exit 91; echo default; }
systemctl() { [[ "$*" == 'is-active --quiet docker.service' ]] || exit 91; return 3; }
assert_local_docker_context
""", ok=False)
        self.assertIn("остановлен", r.stderr)

    def test_remote_docker_rejected(self):
        self.shell("DOCKER_HOST=tcp://192.0.2.1:2375; assert_local_docker_context", ok=False)

    def test_render_compose(self):
        r = self.shell("""
SECRET_VALUE=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
SELECTED_IMAGE=ghcr.io/remnawave/node:3.4.2
ENABLE_XHTTP=1
ENV_FILE="$T/old.env"
printf 'NFTABLES_LOGGING=false\nSNI_VERIFICATION=true\nCUSTOM_CORE_URL=https://bad.invalid/xray\n' >"$ENV_FILE"
docker() { [[ "$1" == compose ]]; }
render_node_files
cp "$STAGE_DIR/docker-compose.yml" "$T/compose.yml"
cp "$STAGE_DIR/.env" "$T/rendered.env"
""")
        import yaml
        node = yaml.safe_load((self.root / "compose.yml").read_text())["services"]["remnanode"]
        self.assertEqual(node["image"], "ghcr.io/remnawave/node:3.4.2")
        self.assertEqual(node["network_mode"], "host")
        self.assertEqual(node["cap_add"], ["NET_ADMIN"])
        self.assertIn("/dev/shm:/dev/shm:rw", node["volumes"])
        self.assertNotIn("privileged", node)
        self.assertNotIn("entrypoint", node)
        env = (self.root / "rendered.env").read_text()
        self.assertIn("NFTABLES_LOGGING=false", env)
        self.assertIn("SNI_VERIFICATION=true", env)
        self.assertNotIn("CUSTOM_CORE_URL", env)
        self.assertEqual((self.root / "rendered.env").stat().st_mode & 0o777, 0o600)
        self.assertNotIn("AAAA", r.stdout + r.stderr)

    def test_activation_scoped_to_node(self):
        self.shell("""
SELECTED_IMAGE_ID=sha256:111; SELECTED_IMAGE=remnawave/node:3.4.2
container_needs_recreate() { return 0; }
docker() {
  if [[ "$1 $2" == 'image inspect' ]]; then echo sha256:111; return 0; fi
  printf '%s\n' "$*" >"$T/activation"
}
activate_node
grep -q -- '--pull never remnanode' "$T/activation"
! grep -q -- '--remove-orphans' "$T/activation"
""")

    def test_changed_image_rejected(self):
        self.shell("SELECTED_IMAGE_ID=sha256:111; docker() { echo sha256:222; }; activate_node", ok=False)

    def test_secret_redacted(self):
        self.shell("""
ENV_FILE="$T/env"
printf 'SECRET_KEY=private-base64-value\n' >"$ENV_FILE"
printf 'hello private-base64-value\nSECRET_KEY=other-value\nnormal line\n' | redact_log_stream >"$T/log"
! grep -q 'private-base64-value\\|other-value' "$T/log"
grep -q 'normal line' "$T/log"
""")

    def test_profile_readiness(self):
        self.shell("PROFILE_VERIFIED=1; profile_not_ready 'missing socket'; [[ $PROFILE_VERIFIED == 0 ]]")
        self.shell("REQUIRE_PROFILE_READY=1; profile_not_ready 'missing socket'", ok=False)

    def test_http2_not_http1(self):
        self.shell("curl() { printf 'HTTP/1.1 400 Bad Request\\r\\n'; }; ! verify_local_xhttp_h2_edge")
        self.shell("curl() { printf 'HTTP/2 400\\r\\n'; }; verify_local_xhttp_h2_edge")

    def backup_fixture(self, version=3):
        folder = self.root / "backup"
        folder.mkdir()
        (folder / "manifest.env").write_text(f"BACKUP_FORMAT={version}\nHAD_NODE_ROOT=0\nHAD_CONTAINER=0\nHAD_SYSTEM_FILES=0\n")
        (folder / "sysctl-runtime.tsv").touch()
        if version == 3:
            (folder / "SHA256SUMS").write_text("".join(
                f"{hashlib.sha256((folder / name).read_bytes()).hexdigest()}  {name}\n"
                for name in ["manifest.env", "sysctl-runtime.tsv"]))
        return shlex.quote(str(folder))

    def shim(self):
        return """
require_trusted_root_file() { :; }
sha256sum() {
  if [[ "$1" == --check ]]; then command shasum -a 256 -c "$3"; else command shasum -a 256 "$@"; fi
}
"""

    def test_dry_rollback(self):
        folder = self.backup_fixture()
        r = self.shell(self.shim() + f"DRY_RUN=1; rollback_from_backup {folder}")
        self.assertIn("Изменений нет", r.stdout)

    def test_corrupt_backup(self):
        folder = self.backup_fixture()
        with (self.root / "backup/manifest.env").open("a") as f:
            f.write("# corrupted\n")
        r = self.shell(self.shim() + f"rollback_from_backup {folder}", ok=False)
        self.assertIn("checksum mismatch", r.stderr)

    def test_missing_checksums(self):
        folder = self.backup_fixture()
        (self.root / "backup/SHA256SUMS").unlink()
        r = self.shell(self.shim() + f"rollback_from_backup {folder}", ok=False)
        self.assertIn("без SHA256SUMS", r.stderr)

    def test_legacy_backup(self):
        folder = self.backup_fixture(2)
        r = self.shell(self.shim() + f"DRY_RUN=1; rollback_from_backup {folder}")
        self.assertIn("Legacy backup", r.stderr)

    def test_backup_atomic_checksums(self):
        self.shell(self.shim() + """
BACKUP_ROOT="$T/backups"; NODE_ROOT="$T/absent"
docker() { return 1; }
legacy_units() { :; }; managed_units() { :; }
backup_system_paths() { BACKUP_HAS_SYSTEM_FILES=0; }
backup_sysctl_runtime() { : >"$BACKUP_DIR/sysctl-runtime.tsv"; }
create_backup
[[ "$MUTATION_STARTED" == 1 && -z "$BACKUP_STAGE_DIR" ]]
[[ -f "$BACKUP_DIR/SHA256SUMS" ]]
grep -qx 'BACKUP_FORMAT=3' "$BACKUP_DIR/manifest.env"
""")

    def test_generated_shell_syntax(self):
        blocks = re.findall(r"<<('?EOF'?)\n(#!/usr/bin/env bash\n.*?)\nEOF", SCRIPT.read_text(), re.S)
        self.assertGreaterEqual(len(blocks), 9)
        for index, (delimiter, content) in enumerate(blocks):
            if delimiter == "EOF":
                content = re.sub(r"\\([$\\])", r"\1", content)
            r = subprocess.run([BASH, "-n"], input=content, text=True, capture_output=True)
            self.assertEqual(r.returncode, 0, f"script #{index}: {r.stderr}")

    def test_embedded_python_syntax(self):
        blocks = re.findall(r"<<'PY'\n(.*?)\nPY", SCRIPT.read_text(), re.S)
        self.assertGreaterEqual(len(blocks), 5)
        for index, content in enumerate(blocks):
            compile(content, f"embedded-python-{index}", "exec")



    def test_subshell_failure_rolls_back_once(self):
        self.shell("""
MUTATION_STARTED=1; BACKUP_DIR="$T/backup"
rollback_from_backup() { printf 'rollback\\n' >>"$T/rollback-count"; }
trap 'on_error $? $LINENO' ERR
out="$(false)"
""", ok=False)
        self.assertEqual((self.root / "rollback-count").read_text().splitlines(), ["rollback"])

    def test_subshell_cannot_clean_parent_stage(self):
        self.shell("""
STAGE_DIR="$T/stage"; mkdir "$STAGE_DIR"
ignored="$(cleanup_stage)"
[[ -d "$STAGE_DIR" ]]
""")

    def test_state_preserves_empty_ports(self):
        self.shell("""
STATE_FILE="$T/state"; INSTALLER_CONFIG="$T/absent"
printf "SAVED_PUBLIC_TCP_PORTS=''\nSAVED_PUBLIC_UDP_PORTS=''\n" >"$STATE_FILE"
require_trusted_root_file() { :; }
load_saved_state
[[ -z "$PUBLIC_TCP_PORTS" && -z "$PUBLIC_UDP_PORTS" ]]
""")

    def test_profile_option_conflict(self):
        self.shell("ENABLE_XHTTP=0; REQUIRE_PROFILE_READY=1; VERIFY_PROFILE_TRANSPORTS=0; validate_settings", ok=False)

    def test_root_file_permissions(self):
        self.shell("""
touch "$T/file"
stat() { case "$2" in %u) echo 0;; %a) echo 600;; esac; }
require_trusted_root_file "$T/file"
""")
        self.shell("""
touch "$T/file"
stat() { case "$2" in %u) echo 0;; %a) echo 666;; esac; }
require_trusted_root_file "$T/file"
""", ok=False)

    def test_real_pki_secret(self):
        self.shell("""
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$T/ca.key" -out "$T/ca.pem" -days 365 -subj /CN=TestCA >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -keyout "$T/node.key" -out "$T/node.csr" -subj /CN=TestNode >/dev/null 2>&1
openssl x509 -req -in "$T/node.csr" -CA "$T/ca.pem" -CAkey "$T/ca.key" -CAcreateserial -out "$T/node.pem" -days 365 >/dev/null 2>&1
openssl pkey -in "$T/ca.key" -pubout -out "$T/jwt.pem" >/dev/null 2>&1
SECRET_VALUE="$(python3 -c '
import base64,json,pathlib,sys
p=pathlib.Path(sys.argv[1])
d={k:(p/f).read_text() for k,f in dict(caCertPem="ca.pem",jwtPublicKey="jwt.pem",nodeCertPem="node.pem",nodeKeyPem="node.key").items()}
print(base64.b64encode(json.dumps(d).encode()).decode())
' "$T")"
sha256sum() { command shasum -a 256; }
validate_secret_basic
validate_secret_payload
[[ -z "$SECRET_CHECK_DIR" ]]
""")

    def test_invalid_pki_secret(self):
        self.shell("SECRET_VALUE=not-real-pki; validate_secret_payload", ok=False)

if __name__ == "__main__":
    unittest.main()
