#!/usr/bin/env bash
set -Eeuo pipefail

# Fast, non-interactive and idempotent Remnawave Node bootstrap.
# Run:
#   sudo bash remnanode-auto-setup-v2.sh
#
# Optional env overrides:
#   NODE_DIR=/opt/remnanode
#   NODE_SERVICE=remnanode
#   NODE_IMAGE=ghcr.io/remnawave/node:latest
#   NODE_PORT=2222
#   SECRET_KEY=...
#   MTU=1300
#   QDISC=fq
#   ENABLE_SPEEDTEST=1
#   BLOCK_SMTP=1
#   BLOCK_TORRENT=1

NODE_DIR="${NODE_DIR:-/opt/remnanode}"
NODE_SERVICE="${NODE_SERVICE:-remnanode}"
NODE_IMAGE="${NODE_IMAGE:-ghcr.io/remnawave/node:latest}"
NODE_PORT="${NODE_PORT:-2222}"
SECRET_KEY="${SECRET_KEY:-}"
MTU="${MTU:-1300}"
QDISC="${QDISC:-fq}"
ENABLE_SPEEDTEST="${ENABLE_SPEEDTEST:-1}"
BLOCK_SMTP="${BLOCK_SMTP:-1}"
BLOCK_TORRENT="${BLOCK_TORRENT:-1}"
PULL_RETRIES="${PULL_RETRIES:-5}"
PULL_RETRY_SLEEP="${PULL_RETRY_SLEEP:-5}"

OUT_CHAIN="REMNANODE_OUT"
FWD_CHAIN="REMNANODE_FWD"

log() { printf '[%s] %s\n' "$(date +'%F %T')" "$*"; }
die() { printf '[%s] ERROR: %s\n' "$(date +'%F %T')" "$*" >&2; exit 1; }

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Run as root: sudo bash $0"
}

validate_config() {
  [[ "$NODE_PORT" =~ ^[0-9]+$ ]] || die "NODE_PORT must be numeric"
  [[ "$MTU" =~ ^[0-9]+$ ]] || die "MTU must be numeric"
  [[ "$PULL_RETRIES" =~ ^[0-9]+$ ]] || die "PULL_RETRIES must be numeric"
  [[ "$PULL_RETRY_SLEEP" =~ ^[0-9]+$ ]] || die "PULL_RETRY_SLEEP must be numeric"
  (( NODE_PORT >= 1 && NODE_PORT <= 65535 )) || die "NODE_PORT must be in range 1..65535"
  (( MTU >= 576 && MTU <= 9000 )) || die "MTU must be in range 576..9000"
}

apt_upgrade_and_install() {
  log "Updating system packages"
  export DEBIAN_FRONTEND=noninteractive

  if command -v debconf-set-selections >/dev/null 2>&1; then
    echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections || true
    echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections || true
  fi

  apt-get update -y
  apt-get upgrade -y
  apt-get full-upgrade -y
  apt-get autoremove --purge -y
  apt-get autoclean
  apt-get install -y \
    curl nano ca-certificates gnupg apt-transport-https dirmngr \
    ethtool iptables-persistent openssl
}

install_speedtest() {
  if [[ "$ENABLE_SPEEDTEST" != "1" ]]; then
    log "Skipping speedtest installation (ENABLE_SPEEDTEST=$ENABLE_SPEEDTEST)"
    return
  fi

  if command -v speedtest >/dev/null 2>&1; then
    log "Speedtest is already installed"
    return
  fi

  log "Installing Ookla speedtest"
  curl -fsSL https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash
  apt-get update -y
  apt-get install -y speedtest
}

install_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log "Installing Docker"
    curl -fsSL https://get.docker.com | sh
  else
    log "Docker already installed"
  fi

  systemctl enable --now docker

  if ! docker compose version >/dev/null 2>&1; then
    log "Installing docker compose plugin"
    apt-get update -y
    apt-get install -y docker-compose-plugin || die "docker compose plugin installation failed"
  fi
}

write_sysctl() {
  log "Writing sysctl tuning"
  cat >/etc/sysctl.d/99-remnanode.conf <<EOF
net.core.default_qdisc = ${QDISC}
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 10000
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_mtu_probing = 1
EOF
  sysctl --system >/dev/null
}

write_limits() {
  log "Writing file descriptor limits"
  cat >/etc/security/limits.d/99-remnanode-nofile.conf <<'EOF'
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF
}

install_network_service() {
  log "Configuring persistent MTU + qdisc service"

  cat >/usr/local/sbin/remnanode-net-tune.sh <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

MTU="${MTU:-1300}"
QDISC="${QDISC:-fq}"
IFACE="$(ip -o route show default | awk 'NR==1{print $5}')"

if [[ -z "$IFACE" ]]; then
  echo "No default interface found, skipping net tune."
  exit 0
fi

ip link set dev "$IFACE" mtu "$MTU" || true
tc qdisc replace dev "$IFACE" root "$QDISC" 2>/dev/null || true
if command -v ethtool >/dev/null 2>&1; then
  ethtool -L "$IFACE" combined "$(nproc)" 2>/dev/null || true
fi
EOF
  chmod +x /usr/local/sbin/remnanode-net-tune.sh

  cat >/etc/systemd/system/remnanode-net-tune.service <<EOF
[Unit]
Description=Remnawave network tune (MTU, qdisc, queues)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment=MTU=${MTU}
Environment=QDISC=${QDISC}
ExecStart=/usr/local/sbin/remnanode-net-tune.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now remnanode-net-tune.service
}

generate_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    tr -dc 'a-f0-9' </dev/urandom | head -c 64
  fi
}

upsert_env() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp_file
  tmp_file="$(mktemp)"

  awk -v k="$key" -v v="$value" '
    BEGIN { updated = 0 }
    $0 ~ ("^" k "=") { print k "=" v; updated = 1; next }
    { print }
    END { if (updated == 0) print k "=" v }
  ' "$file" >"$tmp_file"
  cat "$tmp_file" >"$file"
  rm -f "$tmp_file"
}

ensure_env() {
  local file="$1"
  local key="$2"
  local value="$3"
  grep -q "^${key}=" "$file" || printf '%s=%s\n' "$key" "$value" >>"$file"
}

prepare_compose() {
  local env_file compose_file
  env_file="${NODE_DIR}/.env"
  compose_file="${NODE_DIR}/docker-compose.yml"

  log "Preparing ${NODE_DIR}"
  mkdir -p "$NODE_DIR"
  touch "$env_file"

  upsert_env "$env_file" "NODE_PORT" "$NODE_PORT"
  if [[ -n "$SECRET_KEY" ]]; then
    upsert_env "$env_file" "SECRET_KEY" "$SECRET_KEY"
  else
    ensure_env "$env_file" "SECRET_KEY" "$(generate_secret)"
  fi

  if [[ ! -f "$compose_file" ]]; then
    log "docker-compose.yml not found, creating a minimal template"
    cat >"$compose_file" <<EOF
services:
  ${NODE_SERVICE}:
    image: ${NODE_IMAGE}
    container_name: ${NODE_SERVICE}
    restart: unless-stopped
    env_file:
      - .env
    ports:
      - "\${NODE_PORT}:\${NODE_PORT}"
EOF
  else
    if grep -Eqi 'ghcr\.io/remnawave/node([:@]|$)' "$compose_file"; then
      log "Compose already points to remnawave image"
    else
      log "Patching image in existing compose to ${NODE_IMAGE}"
      sed -i -E "0,/^[[:space:]]*image:[[:space:]]*.*/s##    image: ${NODE_IMAGE}#" "$compose_file"
    fi
  fi

  docker compose -f "$compose_file" config >/dev/null || die "docker-compose.yml is invalid"
}

pull_and_start() {
  log "Pulling and starting ${NODE_SERVICE}"
  cd "$NODE_DIR"

  local i
  local pulled=0
  for ((i = 1; i <= PULL_RETRIES; i++)); do
    if docker compose pull "$NODE_SERVICE"; then
      pulled=1
      break
    fi
    log "Pull retry ${i}/${PULL_RETRIES} failed, waiting ${PULL_RETRY_SLEEP}s"
    sleep "$PULL_RETRY_SLEEP"
  done
  (( pulled == 1 )) || die "Failed to pull ${NODE_SERVICE} after ${PULL_RETRIES} attempts"

  if docker compose config --services | grep -qx "$NODE_SERVICE"; then
    docker compose up -d "$NODE_SERVICE"
  else
    log "Service ${NODE_SERVICE} not found in compose, starting full stack"
    docker compose up -d
  fi

  docker compose ps
}

configure_firewall() {
  log "Configuring iptables in dedicated chains (${OUT_CHAIN}, ${FWD_CHAIN})"

  iptables -N "$OUT_CHAIN" 2>/dev/null || true
  iptables -N "$FWD_CHAIN" 2>/dev/null || true
  iptables -F "$OUT_CHAIN"
  iptables -F "$FWD_CHAIN"

  if ! iptables -C OUTPUT -j "$OUT_CHAIN" >/dev/null 2>&1; then
    iptables -I OUTPUT 1 -j "$OUT_CHAIN"
  fi
  if ! iptables -C FORWARD -j "$FWD_CHAIN" >/dev/null 2>&1; then
    iptables -I FORWARD 1 -j "$FWD_CHAIN"
  fi

  if [[ "$BLOCK_SMTP" == "1" ]]; then
    local smtp_port
    for smtp_port in 25 465 587; do
      iptables -A "$OUT_CHAIN" -p tcp --dport "$smtp_port" -j REJECT
      iptables -A "$FWD_CHAIN" -p tcp --dport "$smtp_port" -j REJECT
    done
  fi

  if [[ "$BLOCK_TORRENT" == "1" ]]; then
    iptables -A "$OUT_CHAIN" -p tcp --dport 6881:6889 -j DROP
    iptables -A "$OUT_CHAIN" -p udp --dport 6881:6889 -j DROP
    iptables -A "$FWD_CHAIN" -p tcp --dport 6881:6889 -j DROP
    iptables -A "$FWD_CHAIN" -p udp --dport 6881:6889 -j DROP

    local sig
    local signatures=(
      "BitTorrent"
      "BitTorrent protocol"
      "peer_id="
      ".torrent"
      "announce.php?passkey="
      "info_hash"
      "get_peers"
      "find_node"
    )
    for sig in "${signatures[@]}"; do
      iptables -A "$OUT_CHAIN" -m string --algo bm --string "$sig" -j DROP
      iptables -A "$FWD_CHAIN" -m string --algo bm --string "$sig" -j DROP
    done
  fi

  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null
  else
    log "netfilter-persistent not found, skipping persistent save"
  fi
}

main() {
  require_root
  validate_config
  apt_upgrade_and_install
  install_speedtest
  install_docker
  write_sysctl
  write_limits
  install_network_service
  prepare_compose
  pull_and_start
  configure_firewall

  cat <<EOF
====================================================
Done.
Node dir: ${NODE_DIR}
Node service: ${NODE_SERVICE}
Node image: ${NODE_IMAGE}
NODE_PORT: ${NODE_PORT}
MTU: ${MTU}
QDISC: ${QDISC}
Speedtest: $(command -v speedtest >/dev/null 2>&1 && echo installed || echo skipped)
Firewall SMTP block: ${BLOCK_SMTP}
Firewall torrent block: ${BLOCK_TORRENT}
Check:
  cd ${NODE_DIR} && docker compose ps
  docker logs --tail 80 ${NODE_SERVICE}
  speedtest
====================================================
EOF
}

main "$@"
