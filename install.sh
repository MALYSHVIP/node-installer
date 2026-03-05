#!/usr/bin/env bash
set -Eeuo pipefail

# Usage example:
# sudo bash install.sh
# GitHub raw install example:
# curl -fsSL https://raw.githubusercontent.com/<USER>/<REPO>/<BRANCH>/install.sh -o /tmp/install.sh && sudo bash /tmp/install.sh
# sudo PANEL_IPS_CSV="203.0.113.10" \
#      ADMIN_IPS_CSV="198.51.100.20,198.51.100.21" \
#      SSH_PORT=22 PANEL_PORT=8080 NODE_API_PORT=2222 \
#      CLIENT_TCP_PORTS_CSV="80,443,8443" CLIENT_UDP_PORTS_CSV="443,8443" \
#      bash install.sh
# Optional MTU tuning:
# sudo TARGET_MTU=1200 AUTO_SET_MTU=1 bash install.sh
# Optional XHTTP prep:
# sudo ENABLE_XHTTP_PREP=1 ENABLE_MY_REMNAWAVE_REPO_SYNC=1 bash install.sh

export DEBIAN_FRONTEND=noninteractive

log() { printf '[%s] %s\n' "$(date +'%F %T')" "$*"; }
err() { printf '[%s] ERROR: %s\n' "$(date +'%F %T')" "$*" >&2; }
die() { err "$*"; exit 1; }

[[ ${EUID:-0} -eq 0 ]] || die "Run as root: sudo bash $0"

SSH_PORT="${SSH_PORT:-22}"
PANEL_PORT="${PANEL_PORT:-8080}"
NODE_API_PORT="${NODE_API_PORT:-2222}"
NET_IFACE="${NET_IFACE:-}"
TARGET_MTU="${TARGET_MTU:-1200}"
AUTO_SET_MTU="${AUTO_SET_MTU:-1}"
AUTO_DETECT_TRUSTED_IPS="${AUTO_DETECT_TRUSTED_IPS:-1}"
ENABLE_XHTTP_PREP="${ENABLE_XHTTP_PREP:-0}"
ENABLE_MY_REMNAWAVE_REPO_SYNC="${ENABLE_MY_REMNAWAVE_REPO_SYNC:-0}"
MY_REMNAWAVE_REPO_URL="${MY_REMNAWAVE_REPO_URL:-https://github.com/legiz-ru/my-remnawave}"
MY_REMNAWAVE_REPO_REF="${MY_REMNAWAVE_REPO_REF:-main}"
MY_REMNAWAVE_REPO_DIR="${MY_REMNAWAVE_REPO_DIR:-/opt/my-remnawave}"
XHTTP_WORKDIR="${XHTTP_WORKDIR:-/opt/remnawave-xhttp}"
XHTTP_TAG="${XHTTP_TAG:-Sweden_XHTTP}"
XHTTP_PATH="${XHTTP_PATH:-/xhttppath/}"
XHTTP_SOCKET="${XHTTP_SOCKET:-/dev/shm/xrxh.socket}"
XHTTP_ENABLE_NGINX="${XHTTP_ENABLE_NGINX:-1}"
XHTTP_NGINX_SNIPPET="${XHTTP_NGINX_SNIPPET:-/etc/nginx/snippets/remnawave-xhttp-location.conf}"
XHTTP_AUTO_CREATE_SITE="${XHTTP_AUTO_CREATE_SITE:-0}"
XHTTP_SERVER_NAME="${XHTTP_SERVER_NAME:-}"
XHTTP_TLS_CERT="${XHTTP_TLS_CERT:-}"
XHTTP_TLS_KEY="${XHTTP_TLS_KEY:-}"

# Public ports for clients (games/UDP/TUN)
CLIENT_TCP_PORTS_CSV="${CLIENT_TCP_PORTS_CSV:-80,443,8443}"
CLIENT_UDP_PORTS_CSV="${CLIENT_UDP_PORTS_CSV:-443,8443}"

# Trusted IP defaults (can be overridden via env)
# Remnawave panel:
#   144.31.1.170, 46.17.45.67
# Admin:
#   144.31.2.170, 5.35.115.66
DEFAULT_PANEL_IPS_CSV="144.31.1.170,46.17.45.67"
DEFAULT_ADMIN_IPS_CSV="144.31.2.170,5.35.115.66"
PANEL_IPS_CSV="${PANEL_IPS_CSV:-$DEFAULT_PANEL_IPS_CSV}"
ADMIN_IPS_CSV="${ADMIN_IPS_CSV:-$DEFAULT_ADMIN_IPS_CSV}"

trim() {
  local s="$1"
  s="${s#${s%%[![:space:]]*}}"
  s="${s%${s##*[![:space:]]}}"
  printf '%s' "$s"
}

csv_to_array() {
  local csv="$1"
  local -n out_ref="$2"
  out_ref=()
  IFS=',' read -r -a raw <<< "$csv"
  local item
  for item in "${raw[@]}"; do
    item="$(trim "$item")"
    [[ -n "$item" ]] && out_ref+=("$item")
  done
}

join_by_comma() {
  local -n arr_ref="$1"
  local out=""
  local x
  for x in "${arr_ref[@]}"; do
    [[ -n "$out" ]] && out+=", "
    out+="$x"
  done
  printf '%s' "$out"
}

only_ports_csv() {
  local csv="$1"
  local -n out_ref="$2"
  out_ref=()
  local arr=()
  csv_to_array "$csv" arr
  local p
  for p in "${arr[@]}"; do
    [[ "$p" =~ ^[0-9]{1,5}$ ]] || die "Invalid port in CSV: $p"
    (( p >= 1 && p <= 65535 )) || die "Port out of range: $p"
    out_ref+=("$p")
  done
}

split_ips() {
  local -n all_ref="$1"
  local -n v4_ref="$2"
  local -n v6_ref="$3"
  v4_ref=()
  v6_ref=()
  local ip
  for ip in "${all_ref[@]}"; do
    if [[ "$ip" == *:* ]]; then
      v6_ref+=("$ip")
    else
      v4_ref+=("$ip")
    fi
  done
}

dedupe_array() {
  local -n in_ref="$1"
  local -n out_ref="$2"
  out_ref=()
  local -A seen=()
  local item
  for item in "${in_ref[@]}"; do
    [[ -n "$item" ]] || continue
    if [[ -z "${seen[$item]:-}" ]]; then
      seen["$item"]=1
      out_ref+=("$item")
    fi
  done
}

detect_default_interface() {
  local iface=""
  iface="$(ip -o route show to default 2>/dev/null | awk 'NR==1{print $5}')"
  if [[ -z "$iface" ]]; then
    iface="$(ip -o -6 route show to default 2>/dev/null | awk 'NR==1{print $5}')"
  fi
  printf '%s' "$iface"
}

auto_detect_trusted_ips() {
  local -n out_ref="$1"
  out_ref=()

  local candidates=()
  if [[ -n "${SSH_CLIENT:-}" ]]; then
    candidates+=("${SSH_CLIENT%% *}")
  fi
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    candidates+=("${SSH_CONNECTION%% *}")
  fi

  local uniq=()
  dedupe_array candidates uniq
  out_ref=("${uniq[@]}")
}

ensure_line_once() {
  local file="$1"
  local line="$2"
  grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

install_base_packages() {
  log "System update/upgrade"
  apt update
  apt upgrade -y
  apt full-upgrade -y
  apt autoremove --purge -y
  apt autoclean

  log "Installing required packages"
  apt install -y curl nano ca-certificates nftables jq iproute2 speedtest-cli git
}

install_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log "Installing Docker"
    curl -fsSL https://get.docker.com | sh
  else
    log "Docker already installed"
  fi

  systemctl enable --now docker
  docker --version

  if ! docker compose version >/dev/null 2>&1; then
    apt install -y docker-compose-plugin
  fi
  docker compose version
}

set_interface_mtu() {
  local iface="$1"
  local mtu="$2"

  [[ "$AUTO_SET_MTU" == "1" ]] || {
    log "AUTO_SET_MTU=0, skipping MTU setup"
    return 0
  }

  [[ -n "$iface" ]] || {
    log "Default interface not detected, skipping MTU setup"
    return 0
  }

  [[ "$mtu" =~ ^[0-9]{3,5}$ ]] || die "Invalid TARGET_MTU: $mtu"
  (( mtu >= 576 && mtu <= 9000 )) || die "TARGET_MTU out of range: $mtu"

  local ip_bin current_mtu
  ip_bin="$(command -v ip || true)"
  [[ -n "$ip_bin" ]] || die "'ip' binary not found"

  current_mtu="$(cat "/sys/class/net/$iface/mtu" 2>/dev/null || true)"
  if [[ "$current_mtu" == "$mtu" ]]; then
    log "MTU already set on $iface: $mtu"
  else
    log "Setting MTU $mtu on interface $iface"
    "$ip_bin" link set dev "$iface" mtu "$mtu"
  fi

  cat >/etc/systemd/system/node-mtu.service <<EOF
[Unit]
Description=Set MTU for primary interface
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$ip_bin link set dev $iface mtu $mtu
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now node-mtu.service
  log "MTU persistence installed: iface=$iface mtu=$mtu"
}

normalize_xhttp_path() {
  local p="$1"
  [[ -n "$p" ]] || p="/xhttppath/"
  [[ "$p" == /* ]] || p="/$p"
  [[ "$p" == */ ]] || p="$p/"
  printf '%s' "$p"
}

sync_my_remnawave_repo() {
  [[ "$ENABLE_MY_REMNAWAVE_REPO_SYNC" == "1" ]] || return 0
  log "Syncing my-remnawave repo: $MY_REMNAWAVE_REPO_URL ($MY_REMNAWAVE_REPO_REF)"
  mkdir -p "$(dirname "$MY_REMNAWAVE_REPO_DIR")"
  if [[ -d "$MY_REMNAWAVE_REPO_DIR/.git" ]]; then
    git -C "$MY_REMNAWAVE_REPO_DIR" fetch --all --prune
    git -C "$MY_REMNAWAVE_REPO_DIR" checkout "$MY_REMNAWAVE_REPO_REF"
    git -C "$MY_REMNAWAVE_REPO_DIR" pull --ff-only
  else
    git clone --depth 1 --branch "$MY_REMNAWAVE_REPO_REF" "$MY_REMNAWAVE_REPO_URL" "$MY_REMNAWAVE_REPO_DIR"
  fi
}

setup_xhttp_prep() {
  [[ "$ENABLE_XHTTP_PREP" == "1" ]] || return 0
  local xhttp_path
  xhttp_path="$(normalize_xhttp_path "$XHTTP_PATH")"

  log "Preparing XHTTP templates in $XHTTP_WORKDIR"
  mkdir -p "$XHTTP_WORKDIR"

  cat >"$XHTTP_WORKDIR/inbound-xhttp.json" <<EOF
{
  "tag": "$XHTTP_TAG",
  "listen": "$XHTTP_SOCKET,0666",
  "protocol": "vless",
  "settings": {
    "clients": [],
    "fallbacks": [],
    "decryption": "none"
  },
  "sniffing": {
    "enabled": true,
    "destOverride": ["http", "tls", "quic"]
  },
  "streamSettings": {
    "network": "xhttp",
    "xhttpSettings": {
      "mode": "auto",
      "path": "$xhttp_path",
      "extra": {
        "noSSEHeader": true,
        "xPaddingBytes": "100-1000",
        "scMaxBufferedPosts": 30,
        "scMaxEachPostBytes": 1000000,
        "scStreamUpServerSecs": "20-80"
      }
    }
  }
}
EOF

  cat >"$XHTTP_WORKDIR/host-extra-xhttp.json" <<EOF
{
  "xmux": {
    "cMaxReuseTimes": 0,
    "maxConcurrency": "16-32",
    "maxConnections": 0,
    "hKeepAlivePeriod": 0,
    "hMaxRequestTimes": "600-900",
    "hMaxReusableSecs": "1800-3000"
  },
  "noGRPCHeader": false,
  "xPaddingBytes": "100-1000",
  "scMaxEachPostBytes": 1000000,
  "scMinPostsIntervalMs": 30,
  "scStreamUpServerSecs": "20-80",
  "downloadSettings": {
    "network": "xhttp",
    "xhttpSettings": {
      "path": "$xhttp_path"
    }
  }
}
EOF

  cat >"$XHTTP_WORKDIR/remnanode-compose.yml" <<'EOF'
services:
  remnanode:
    image: remnawave/node:latest
    container_name: remnanode
    hostname: remnanode
    restart: always
    env_file:
      - .env-node
    volumes:
      - /dev/shm:/dev/shm
    network_mode: host
EOF

  if [[ "$XHTTP_ENABLE_NGINX" == "1" ]]; then
    log "Installing/configuring nginx for XHTTP reverse-proxy snippet"
    apt install -y nginx
    mkdir -p "$(dirname "$XHTTP_NGINX_SNIPPET")"
    cat >"$XHTTP_NGINX_SNIPPET" <<EOF
# Include this inside your TLS server block:
# include $XHTTP_NGINX_SNIPPET;
location $xhttp_path {
    client_max_body_size 0;
    grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    client_body_timeout 5m;
    grpc_read_timeout 315;
    grpc_send_timeout 5m;
    grpc_pass unix:$XHTTP_SOCKET;
}
EOF

    if [[ "$XHTTP_AUTO_CREATE_SITE" == "1" ]]; then
      [[ -n "$XHTTP_SERVER_NAME" ]] || die "XHTTP_AUTO_CREATE_SITE=1 requires XHTTP_SERVER_NAME"
      [[ -n "$XHTTP_TLS_CERT" && -n "$XHTTP_TLS_KEY" ]] || die "XHTTP_AUTO_CREATE_SITE=1 requires XHTTP_TLS_CERT and XHTTP_TLS_KEY"
      [[ -f "$XHTTP_TLS_CERT" ]] || die "TLS cert not found: $XHTTP_TLS_CERT"
      [[ -f "$XHTTP_TLS_KEY" ]] || die "TLS key not found: $XHTTP_TLS_KEY"
      cat >/etc/nginx/conf.d/remnawave-xhttp.conf <<EOF
server {
    listen 443 ssl http2;
    server_name $XHTTP_SERVER_NAME;
    ssl_certificate $XHTTP_TLS_CERT;
    ssl_certificate_key $XHTTP_TLS_KEY;
    include $XHTTP_NGINX_SNIPPET;
}
EOF
    fi

    nginx -t
    systemctl enable --now nginx
    systemctl reload nginx
  fi
}

apply_bbr_and_udp_tuning() {
  log "Applying BBR + UDP/TUN tuning"
  cat >/etc/sysctl.d/99-node-gaming.conf <<'SYSCTL'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# Better UDP stability for games/tunnels
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.ipv4.udp_rmem_min=16384
net.ipv4.udp_wmem_min=16384

# TCP stability on heterogeneous links
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_fastopen=3
SYSCTL

  sysctl --system >/dev/null
  log "TCP CC: $(sysctl -n net.ipv4.tcp_congestion_control), qdisc: $(sysctl -n net.core.default_qdisc)"
}

apply_limits() {
  log "Applying nofile limits"
  ensure_line_once /etc/security/limits.conf "* soft nofile 65535"
  ensure_line_once /etc/security/limits.conf "* hard nofile 65535"
}

install_speedtest_helper() {
  log "Installing speedtest helper"
  cat >/usr/local/bin/node-speedtest.sh <<'SPEED'
#!/usr/bin/env bash
set -Eeuo pipefail
if command -v speedtest >/dev/null 2>&1; then
  exec speedtest --accept-license --accept-gdpr
elif command -v speedtest-cli >/dev/null 2>&1; then
  exec speedtest-cli --secure
else
  echo "No speedtest binary found (speedtest or speedtest-cli)." >&2
  exit 1
fi
SPEED
  chmod +x /usr/local/bin/node-speedtest.sh
  /usr/local/bin/node-speedtest.sh || true
}

write_nft_rules() {
  local trusted_v4_csv="$1"
  local trusted_v6_csv="$2"
  local client_tcp_csv="$3"
  local client_udp_csv="$4"

  mkdir -p /etc/nftables.d

  {
    echo "table inet node_guard {"

    if [[ -n "$trusted_v4_csv" ]]; then
      echo "  set trusted_v4 {"
      echo "    type ipv4_addr"
      echo "    elements = { $trusted_v4_csv }"
      echo "  }"
    fi

    if [[ -n "$trusted_v6_csv" ]]; then
      echo "  set trusted_v6 {"
      echo "    type ipv6_addr"
      echo "    elements = { $trusted_v6_csv }"
      echo "  }"
    fi

    echo ""
    echo "  set client_tcp_ports { type inet_service; elements = { $client_tcp_csv } }"
    echo "  set client_udp_ports { type inet_service; elements = { $client_udp_csv } }"
    echo "  set smtp_ports       { type inet_service; elements = { 25, 26, 465, 587, 2525, 1025, 8025 } }"
    echo "  set torrent_ports    { type inet_service; elements = { 2710, 51413, 6969, 6881-6999 } }"
    echo ""

    echo "  chain input {"
    echo "    type filter hook input priority 0; policy drop;"
    echo "    ct state established,related accept"
    echo "    iif \"lo\" accept"
    echo "    ip protocol icmp accept"
    echo "    ip6 nexthdr icmpv6 accept"

    if [[ -n "$trusted_v4_csv" ]]; then
      echo "    ip saddr @trusted_v4 tcp dport { $SSH_PORT, $PANEL_PORT, $NODE_API_PORT } accept"
    fi
    if [[ -n "$trusted_v6_csv" ]]; then
      echo "    ip6 saddr @trusted_v6 tcp dport { $SSH_PORT, $PANEL_PORT, $NODE_API_PORT } accept"
    fi

    if [[ -n "$trusted_v4_csv" || -n "$trusted_v6_csv" ]]; then
      echo "    tcp dport { $SSH_PORT, $PANEL_PORT, $NODE_API_PORT } drop"
    else
      echo "    tcp dport { $SSH_PORT, $PANEL_PORT, $NODE_API_PORT } accept"
    fi
    echo "    tcp dport @client_tcp_ports accept"
    echo "    udp dport @client_udp_ports accept"
    echo "  }"

    echo ""
    echo "  chain forward {"
    echo "    type filter hook forward priority 0; policy accept;"
    echo "    ct state established,related accept"
    echo "    tcp dport @smtp_ports reject with icmpx type admin-prohibited"
    echo "    udp dport @smtp_ports reject with icmpx type admin-prohibited"
    echo "    tcp dport @torrent_ports reject with icmpx type admin-prohibited"
    echo "    udp dport @torrent_ports reject with icmpx type admin-prohibited"
    echo "  }"

    echo ""
    echo "  chain output {"
    echo "    type filter hook output priority 0; policy accept;"
    echo "    tcp dport @smtp_ports reject with icmpx type admin-prohibited"
    echo "    udp dport @smtp_ports reject with icmpx type admin-prohibited"
    echo "    tcp dport @torrent_ports reject with icmpx type admin-prohibited"
    echo "    udp dport @torrent_ports reject with icmpx type admin-prohibited"
    echo "  }"

    echo "}"
  } >/etc/nftables.d/40-node-guard.nft

  if ! grep -q 'include "/etc/nftables.d/\*.nft"' /etc/nftables.conf; then
    printf '\ninclude "/etc/nftables.d/*.nft"\n' >> /etc/nftables.conf
  fi

  systemctl enable --now nftables
  nft -f /etc/nftables.conf
}

main() {
  local panel_ips=() admin_ips=() trusted_ips=() auto_ips=()
  local trusted_v4=() trusted_v6=()
  local client_tcp_ports=() client_udp_ports=()
  local detected_iface=""

  csv_to_array "$PANEL_IPS_CSV" panel_ips
  csv_to_array "$ADMIN_IPS_CSV" admin_ips

  if [[ "${#panel_ips[@]}" -eq 0 && "${#admin_ips[@]}" -eq 0 && "$AUTO_DETECT_TRUSTED_IPS" == "1" ]]; then
    auto_detect_trusted_ips auto_ips
    if [[ "${#auto_ips[@]}" -gt 0 ]]; then
      admin_ips=("${auto_ips[@]}")
      log "Auto-detected trusted admin IPs from SSH: ${admin_ips[*]}"
    else
      log "Trusted IPs were not provided and SSH source IP not found"
      log "Management ports will be open to all addresses"
    fi
  fi

  trusted_ips=("${panel_ips[@]}" "${admin_ips[@]}")
  if [[ "${#trusted_ips[@]}" -eq 0 ]]; then
    log "Trusted IP list is empty: firewall will allow management ports from anywhere"
  fi

  split_ips trusted_ips trusted_v4 trusted_v6

  only_ports_csv "$CLIENT_TCP_PORTS_CSV" client_tcp_ports
  only_ports_csv "$CLIENT_UDP_PORTS_CSV" client_udp_ports

  local trusted_v4_csv trusted_v6_csv client_tcp_csv client_udp_csv
  trusted_v4_csv="$(join_by_comma trusted_v4)"
  trusted_v6_csv="$(join_by_comma trusted_v6)"
  client_tcp_csv="$(join_by_comma client_tcp_ports)"
  client_udp_csv="$(join_by_comma client_udp_ports)"

  detected_iface="$NET_IFACE"
  if [[ -z "$detected_iface" ]]; then
    detected_iface="$(detect_default_interface)"
  fi
  if [[ -n "$detected_iface" ]]; then
    log "Primary network interface: $detected_iface"
  else
    log "Primary network interface not detected"
  fi

  install_base_packages
  install_docker
  sync_my_remnawave_repo
  setup_xhttp_prep
  set_interface_mtu "$detected_iface" "$TARGET_MTU"
  apply_bbr_and_udp_tuning
  apply_limits
  install_speedtest_helper
  write_nft_rules "$trusted_v4_csv" "$trusted_v6_csv" "$client_tcp_csv" "$client_udp_csv"

  log "Done"
  if [[ "${#trusted_ips[@]}" -gt 0 ]]; then
    log "Trusted panel/admin IPs: ${trusted_ips[*]}"
  else
    log "Trusted panel/admin IPs: not set (management ports open to all)"
  fi
  log "Interface: ${detected_iface:-unknown}"
  log "TARGET_MTU: $TARGET_MTU (AUTO_SET_MTU=$AUTO_SET_MTU)"
  log "XHTTP prep: ENABLE_XHTTP_PREP=$ENABLE_XHTTP_PREP, ENABLE_MY_REMNAWAVE_REPO_SYNC=$ENABLE_MY_REMNAWAVE_REPO_SYNC"
  log "XHTTP artifacts: $XHTTP_WORKDIR"
  log "Open client TCP ports: $client_tcp_csv"
  log "Open client UDP ports: $client_udp_csv"
  log "Blocked outbound: SMTP + BitTorrent"
  log "Check: nft list table inet node_guard"
}

main "$@"
