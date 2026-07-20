#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Запусти скрипт от root."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NODE_PORT="2222"
MTU_VALUE="${MTU_VALUE:-auto}"
NODE_IMAGE="${NODE_IMAGE:-ghcr.io/remnawave/node:2.7.0}"

NODE_ROOT="/opt/remnanode"
COMPOSE_FILE="$NODE_ROOT/docker-compose.yml"
COMPOSE_OVERRIDE_FILE="$NODE_ROOT/docker-compose.override.yml"
ENV_FILE="$NODE_ROOT/.env"
LOG_DIR="/var/log/remnanode"
OVERRIDES_DIR="$NODE_ROOT/overrides"
GENERATE_API_OVERRIDE="$OVERRIDES_DIR/generate-api-config.js"
STATS_SERVICE_OVERRIDE="$OVERRIDES_DIR/stats.service.js"
XRAY_SERVICE_OVERRIDE="$OVERRIDES_DIR/xray.service.js"
NODE_TLS_DIR="/etc/remnanode/tls"
XRAY_TLS_DIR_IN_CONTAINER="/var/lib/remnawave/configs/xray/ssl"
NODE_STATE_DIR="/var/lib/remnanode-state"
NODE_STATE_DIR_IN_CONTAINER="/var/lib/remnanode-state"

SYSCTL_FILE="/etc/sysctl.d/99-remnanode.conf"
LIMITS_FILE="/etc/security/limits.d/99-remnanode.conf"
MTU_SERVICE="/etc/systemd/system/node-mtu.service"
FIREWALL_SCRIPT="/usr/local/sbin/remnanode-firewall.sh"
FIREWALL_SERVICE="/etc/systemd/system/remnanode-firewall.service"
SPAMHAUS_EGRESS_GUARD_SCRIPT="/usr/local/sbin/remnanode-spamhaus-egress-guard.sh"
SPAMHAUS_EGRESS_GUARD_SERVICE="/etc/systemd/system/remnanode-spamhaus-egress-guard.service"
SPAMHAUS_EGRESS_GUARD_TIMER="/etc/systemd/system/remnanode-spamhaus-egress-guard.timer"
SPAMHAUS_EGRESS_GUARD_STATE_DIR="/var/lib/remnanode-spamhaus-egress-guard"
COMPOSE_SERVICE="/etc/systemd/system/remnanode-compose.service"
WATCHDOG_STATE_DIR="/var/lib/remnanode-watchdog"
WATCHDOG_SCRIPT="/usr/local/sbin/remnanode-watchdog.sh"
WATCHDOG_SERVICE="/etc/systemd/system/remnanode-watchdog.service"
WATCHDOG_TIMER="/etc/systemd/system/remnanode-watchdog.timer"
MAINTENANCE_SCRIPT="/usr/local/sbin/remnanode-nightly-cleanup.sh"
MAINTENANCE_SERVICE="/etc/systemd/system/remnanode-nightly-cleanup.service"
MAINTENANCE_TIMER="/etc/systemd/system/remnanode-nightly-cleanup.timer"
RPS_SCRIPT="/usr/local/sbin/remnanode-rps.sh"
RPS_SERVICE="/etc/systemd/system/remnanode-rps.service"
QDISC_SERVICE="/etc/systemd/system/remnanode-qdisc.service"
OFFLOAD_TUNE_SCRIPT="/usr/local/sbin/remnanode-offload-tune.sh"
OFFLOAD_TUNE_SERVICE="/etc/systemd/system/remnanode-offload-tune.service"
XHTTP_SYNC_SCRIPT="/usr/local/sbin/remnanode-xhttp-sync.sh"
XHTTP_SYNC_SERVICE="/etc/systemd/system/remnanode-xhttp-sync.service"
XHTTP_SYNC_TIMER="/etc/systemd/system/remnanode-xhttp-sync.timer"
OOM_GUARD_SCRIPT="/usr/local/sbin/remnanode-oom-guard.sh"
OOM_GUARD_SERVICE="/etc/systemd/system/remnanode-oom-guard.service"
OOM_GUARD_TIMER="/etc/systemd/system/remnanode-oom-guard.timer"
BBR_TELEMETRY_DEPS_SCRIPT="/usr/local/sbin/remnanode-bbr-telemetry-deps.sh"
BBR_TELEMETRY_DEPS_SERVICE="/etc/systemd/system/remnanode-bbr-telemetry-deps.service"
BBR_TELEMETRY_DEPS_TIMER="/etc/systemd/system/remnanode-bbr-telemetry-deps.timer"
LOGROTATE_FILE="/etc/logrotate.d/remnanode"
PANEL_IPS_FILE="/etc/cake_panel/trusted_panel_ips.txt"
SWAPFILE="/swapfile-remnanode"
SSH_STABILITY_FILE="/etc/ssh/sshd_config.d/99-remnanode-stability.conf"
RESOLVED_DROPIN_DIR="/etc/systemd/resolved.conf.d"
RESOLVED_DROPIN_FILE="$RESOLVED_DROPIN_DIR/99-remnanode.conf"
MSS_CLAMP_SCRIPT="/usr/local/sbin/remnanode-mss-clamp.sh"
MSS_CLAMP_SERVICE="/etc/systemd/system/remnanode-mss-clamp.service"
NGINX_OOM_DROPIN_DIR="/etc/systemd/system/nginx.service.d"
NGINX_OOM_DROPIN_FILE="$NGINX_OOM_DROPIN_DIR/oom-protect.conf"

CAKE_INSTALLER="$SCRIPT_DIR/cake_soft_panel/install_soft_cake_panel.sh"

NODE_IP="${NODE_IP:-}"
PANEL_IP="${PANEL_IP:-}"
SECRET_VALUE=""
APT_UPDATED=0
REBOOT_REQUIRED=0
REBOOT_SCHEDULED=0
MTU_SAFEMODE_APPLIED=0

RUN_FULL_UPGRADE="${RUN_FULL_UPGRADE:-1}"
AUTO_REBOOT="${AUTO_REBOOT:-0}"
STRICT_EGRESS_GUARD="${STRICT_EGRESS_GUARD:-1}"
SPAMHAUS_EGRESS_GUARD="${SPAMHAUS_EGRESS_GUARD:-0}"
ENSURE_CAKE_STACK="${ENSURE_CAKE_STACK:-0}"
APT_LOCK_TIMEOUT="${APT_LOCK_TIMEOUT:-900}"
XHTTP_DOMAIN="${XHTTP_DOMAIN:-}"
XHTTP_PATH="${XHTTP_PATH:-/stable-in-443/}"
XHTTP_SOCKET="${XHTTP_SOCKET:-/dev/shm/xrxh-stable.socket}"
XHTTP_SOCKET_WAIT_SECONDS="${XHTTP_SOCKET_WAIT_SECONDS:-300}"
XHTTP_ENABLE_H3="${XHTTP_ENABLE_H3:-auto}"
XRAY_LOGLEVEL="${XRAY_LOGLEVEL:-auto}"
XRAY_ACCESS_LOG="${XRAY_ACCESS_LOG:-auto}"
XRAY_SNIFF_PROFILE="${XRAY_SNIFF_PROFILE:-auto}"
NIGHTLY_CLEANUP_SCHEDULE="${NIGHTLY_CLEANUP_SCHEDULE:-*-*-* 03:00:00}"
NIGHTLY_CLEANUP_TMP_RETENTION_DAYS="${NIGHTLY_CLEANUP_TMP_RETENTION_DAYS:-3}"
NIGHTLY_CLEANUP_JOURNAL_RETENTION="${NIGHTLY_CLEANUP_JOURNAL_RETENTION:-7d}"
NIGHTLY_CLEANUP_DOCKER_PRUNE_UNTIL="${NIGHTLY_CLEANUP_DOCKER_PRUNE_UNTIL:-168h}"

log() {
  printf "\n[%s] %s\n" "$(date '+%H:%M:%S')" "$*"
}

die() {
  printf "\n[ERROR] %s\n" "$*" >&2
  exit 1
}

bool_is_true() {
  case "$(printf '%s' "${1:-0}" | tr '[:upper:]' '[:lower:]')" in
    1|y|yes|true|on) return 0 ;;
    *) return 1 ;;
  esac
}

is_ipv4() {
  local ip="${1:-}"
  local IFS=.
  local -a octets

  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  read -r -a octets <<<"$ip"
  (( ${#octets[@]} == 4 )) || return 1

  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^[0-9]+$ ]] || return 1
    (( octet >= 0 && octet <= 255 )) || return 1
  done

  return 0
}

ask() {
  local prompt="$1"
  local value=""

  if [[ -r /dev/tty ]]; then
    if ! read -r -p "$prompt" value </dev/tty; then
      die "Не удалось прочитать ввод из терминала. Запусти установку в интерактивной сессии или передай значения через env."
    fi
  else
    if ! read -r -p "$prompt" value; then
      die "Не удалось прочитать ввод. Запусти установку в интерактивной сессии или передай значения через env."
    fi
  fi

  printf '%s' "$value"
}

read_panel_ip() {
  local panel_input=""

  if [[ -n "$PANEL_IP" ]]; then
    validate_panel_ip
    return 0
  fi

  printf "\nВведи IPv4 мастер-панели.\n"
  printf "Этот IP нужен для trusted allowlist и firewall: control-порт ноды будет открыт только для панели.\n"

  while true; do
    panel_input="$(ask "PANEL_IP: ")"
    panel_input="$(printf '%s' "$panel_input" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    if is_ipv4 "$panel_input"; then
      PANEL_IP="$panel_input"
      break
    fi

    printf "Введите корректный IPv4-адрес.\n"
  done

  validate_panel_ip
}

read_optional_xhttp_domain() {
  local enable_xhttp=""
  local domain_input=""

  if [[ -n "$XHTTP_DOMAIN" ]]; then
    XHTTP_DOMAIN="$(normalize_xhttp_domain "$XHTTP_DOMAIN")"
    validate_xhttp_domain "$XHTTP_DOMAIN"
    log "xHTTP домен задан через окружение: $XHTTP_DOMAIN"
    return 0
  fi

  printf "\nНужен xHTTP для этой ноды?\n"
  while true; do
    enable_xhttp="$(ask "Enable xHTTP? (y/n): ")"
    enable_xhttp="$(printf '%s' "$enable_xhttp" | tr '[:upper:]' '[:lower:]' | tr -d '\r')"

    case "$enable_xhttp" in
      y|yes)
        break
        ;;
      n|no|"")
        log "xHTTP отключён, будет обычная установка ноды"
        return 0
        ;;
      *)
        printf "Введите y или n.\n"
        ;;
    esac
  done

  printf "\nВведи домен для xHTTP.\n"
  domain_input="$(ask "XHTTP domain: ")"
  domain_input="$(normalize_xhttp_domain "$domain_input")"

  if [[ -n "$domain_input" ]]; then
    validate_xhttp_domain "$domain_input"
    XHTTP_DOMAIN="$domain_input"
    log "xHTTP будет настроен для домена: $XHTTP_DOMAIN"
  else
    log "xHTTP домен не задан, будет обычная установка ноды"
  fi
}

append_line_once() {
  local file="$1"
  local line="$2"
  grep -qxF "$line" "$file" 2>/dev/null || printf "%s\n" "$line" >> "$file"
}

run_retry() {
  local tries="$1"
  local delay="$2"
  shift 2

  local attempt
  for ((attempt = 1; attempt <= tries; attempt++)); do
    if "$@"; then
      return 0
    fi
    if (( attempt < tries )); then
      sleep "$delay"
    fi
  done

  return 1
}

compose() {
  if [[ -f "$COMPOSE_OVERRIDE_FILE" ]]; then
    docker compose -f "$COMPOSE_FILE" -f "$COMPOSE_OVERRIDE_FILE" "$@"
  else
    docker compose -f "$COMPOSE_FILE" "$@"
  fi
}

dns_query_ok() {
  timeout 8 getent ahostsv4 archive.ubuntu.com >/dev/null 2>&1
}

default_iface() {
  ip -o route show default | awk 'NR==1 {print $5}'
}

web_egress_ok() {
  timeout 10 bash -lc 'exec 3<>/dev/tcp/91.189.91.81/80; printf "HEAD /ubuntu/ HTTP/1.0\r\nHost: archive.ubuntu.com\r\nConnection: close\r\n\r\n" >&3; head -n 1 <&3 | grep -q "HTTP/"' >/dev/null 2>&1
}

apply_runtime_mtu_safemode() {
  local iface=""
  local current_mtu=""

  if [[ "$MTU_SAFEMODE_APPLIED" == "1" ]]; then
    return 0
  fi

  iface="$(default_iface)"
  [[ -n "$iface" ]] || return 0

  current_mtu="$(ip -o link show "$iface" | awk '{for (i=1;i<=NF;i++) if ($i=="mtu") {print $(i+1); exit}}')"
  if [[ -n "$current_mtu" && "$current_mtu" -gt 1300 ]]; then
    log "Включаю временный MTU-safe mode: $iface -> 1300"
    ip link set dev "$iface" mtu 1300 || true
  fi

  MTU_SAFEMODE_APPLIED=1
}

force_static_resolv_conf() {
  log "Переключаю /etc/resolv.conf на статические DNS"

  if [[ -L /etc/resolv.conf ]]; then
    rm -f /etc/resolv.conf
  fi

  cat > /etc/resolv.conf <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 1.0.0.1
options timeout:2 attempts:2 rotate
EOF

  chmod 644 /etc/resolv.conf
}

ensure_dns() {
  local iface=""

  if dns_query_ok; then
    return 0
  fi

  log "DNS не отвечает, пробую мягкое восстановление"

  iface="$(default_iface)"
  if [[ -n "$iface" ]] && command -v resolvectl >/dev/null 2>&1; then
    resolvectl dns "$iface" 1.1.1.1 8.8.8.8 1.0.0.1 || true
    resolvectl domain "$iface" '~.' || true
  fi

  systemctl restart systemd-resolved || true

  dns_query_ok && return 0

  apply_runtime_mtu_safemode
  dns_query_ok && return 0

  force_static_resolv_conf
  dns_query_ok && return 0

  if ! web_egress_ok; then
    die "Исходящий web-трафик не работает даже по IP. Проверь сеть VPS или anti-DDoS у хостера."
  fi

  die "Web-трафик по IP работает, но DNS не поднялся даже после fallback."
}

apt_update_retry() {
  wait_for_apt_locks
  DEBIAN_FRONTEND=noninteractive apt-get update -o Acquire::Retries=5
}

apt_locks_held() {
  local lock_file=""

  for lock_file in \
    /var/lib/dpkg/lock-frontend \
    /var/lib/dpkg/lock \
    /var/lib/apt/lists/lock \
    /var/cache/apt/archives/lock
  do
    if command -v fuser >/dev/null 2>&1; then
      if fuser "$lock_file" >/dev/null 2>&1; then
        return 0
      fi
    elif command -v lslocks >/dev/null 2>&1; then
      if lslocks -o PATH 2>/dev/null | grep -qx "$lock_file"; then
        return 0
      fi
    fi
  done

  return 1
}

wait_for_apt_locks() {
  local waited=0

  while apt_locks_held; do
    if (( waited == 0 )); then
      log "Жду освобождения dpkg/apt lock"
    elif (( waited % 60 == 0 )); then
      log "dpkg/apt lock всё ещё занят уже ${waited}с"
    fi

    if (( waited >= APT_LOCK_TIMEOUT )); then
      die "dpkg/apt lock не освободился за ${APT_LOCK_TIMEOUT}с. Проверь unattended-upgrades или фоновый apt."
    fi

    sleep 5
    waited=$(( waited + 5 ))
  done
}

prepare_apt_environment() {
  local unit=""

  log "Отключаю apt-daily и unattended-upgrades до старта установки"

  for unit in \
    apt-daily.timer \
    apt-daily-upgrade.timer \
    apt-daily.service \
    apt-daily-upgrade.service \
    unattended-upgrades.service \
    packagekit.service \
    packagekit-offline-update.service \
    packagekit-offline-update.timer
  do
    systemctl disable --now "$unit" >/dev/null 2>&1 || true
  done

  for unit in \
    apt-daily.service \
    apt-daily-upgrade.service \
    unattended-upgrades.service \
    packagekit.service \
    packagekit-offline-update.service
  do
    systemctl mask "$unit" >/dev/null 2>&1 || true
  done

  wait_for_apt_locks
}

apt_install_missing() {
  local pkg=""
  local missing=()

  for pkg in "$@"; do
    if ! dpkg-query -W -f='${Status}\n' "$pkg" 2>/dev/null | grep -q 'install ok installed'; then
      missing+=("$pkg")
    fi
  done

  if (( ${#missing[@]} == 0 )); then
    return 0
  fi

  ensure_dns
  if (( APT_UPDATED == 0 )); then
    run_retry 5 5 apt_update_retry || die "Не удалось выполнить apt update"
    APT_UPDATED=1
  fi

  wait_for_apt_locks
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

mark_reboot_required() {
  [[ -f /run/reboot-required ]] && REBOOT_REQUIRED=1 || true
}

min_int() {
  if (( "$1" < "$2" )); then
    printf '%s' "$1"
  else
    printf '%s' "$2"
  fi
}

cpu_count() {
  local cpus=""
  cpus="$(nproc 2>/dev/null || true)"
  [[ "$cpus" =~ ^[0-9]+$ ]] || cpus=1
  if (( cpus < 1 )); then
    cpus=1
  fi
  printf '%s' "$cpus"
}

total_mem_mb() {
  awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo
}

adaptive_capacity_tier() {
  local cpus=0
  local mem_mb=0

  cpus="$(cpu_count)"
  mem_mb="$(total_mem_mb)"

  if (( cpus <= 1 || mem_mb < 2048 )); then
    printf 'tiny'
  elif (( cpus <= 2 || mem_mb < 4096 )); then
    printf 'small'
  elif (( cpus <= 4 || mem_mb < 8192 )); then
    printf 'medium'
  elif (( cpus <= 8 || mem_mb < 16384 )); then
    printf 'large'
  else
    printf 'xlarge'
  fi
}

current_link_mtu() {
  local iface="${1:-}"
  ip -o link show "$iface" 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="mtu") {print $(i+1); exit}}'
}

autodetect_node_ip() {
  local route_ip=""
  local service_ip=""

  if is_ipv4 "$NODE_IP"; then
    log "IP ноды задан через окружение: $NODE_IP"
    return 0
  fi

  route_ip="$(ip -4 route get 1.1.1.1 2>/dev/null | sed -nE 's/.* src ([0-9.]+).*/\1/p' | head -n1)"
  if is_ipv4 "$route_ip"; then
    NODE_IP="$route_ip"
    log "Автоопределил IP ноды по маршруту: $NODE_IP"
    return 0
  fi

  for resolver in \
    "https://api.ipify.org" \
    "https://ipv4.icanhazip.com" \
    "https://ifconfig.me/ip"
  do
    service_ip="$(curl -4fsS --max-time 6 "$resolver" 2>/dev/null | tr -d '\r\n' || true)"
    if is_ipv4 "$service_ip"; then
      NODE_IP="$service_ip"
      log "Автоопределил публичный IP ноды: $NODE_IP"
      return 0
    fi
  done

  die "Не удалось автоматически определить IPv4 ноды. Можно передать NODE_IP=... перед запуском."
}

validate_panel_ip() {
  if ! is_ipv4 "$PANEL_IP"; then
    die "Некорректный PANEL_IP=$PANEL_IP"
  fi

  log "Использую IP панели: $PANEL_IP"
}

mtu_ping_works() {
  local target="$1"
  local payload="$2"
  ping -4 -M do -c 1 -W 1 -s "$payload" "$target" >/dev/null 2>&1
}

probe_payload_ceiling() {
  local target="$1"
  local lower="$2"
  local upper="$3"
  local mid=0
  local best=0

  while (( lower <= upper )); do
    mid=$(( (lower + upper) / 2 ))
    if mtu_ping_works "$target" "$mid"; then
      best="$mid"
      lower=$(( mid + 1 ))
    else
      upper=$(( mid - 1 ))
    fi
  done

  printf '%s' "$best"
}

detect_optimal_mtu() {
  local iface=""
  local link_mtu=""
  local route_mtu=""
  local mtu_ceiling=""
  local payload_hi=0
  local payload_lo=1200
  local probe_target=""
  local candidate_payload=""
  local best_payload=""

  if [[ "$MTU_VALUE" != "auto" ]]; then
    [[ "$MTU_VALUE" =~ ^[0-9]+$ ]] || die "MTU_VALUE должен быть числом или auto"
    return 0
  fi

  iface="$(default_iface)"
  [[ -n "$iface" ]] || die "Не удалось определить основной сетевой интерфейс"

  link_mtu="$(current_link_mtu "$iface")"
  [[ "$link_mtu" =~ ^[0-9]+$ ]] || link_mtu="1500"

  route_mtu="$(ip -4 route get 1.1.1.1 2>/dev/null | sed -nE 's/.* mtu ([0-9]+).*/\1/p' | head -n1)"
  mtu_ceiling="$link_mtu"
  if [[ "$route_mtu" =~ ^[0-9]+$ ]] && (( route_mtu > 0 && route_mtu < mtu_ceiling )); then
    mtu_ceiling="$route_mtu"
  fi

  payload_hi=$(( mtu_ceiling - 28 ))
  if (( payload_hi < 1200 )); then
    payload_lo=1100
  fi
  if (( payload_hi < payload_lo )); then
    payload_lo=$(( payload_hi > 1000 ? payload_hi : 1000 ))
  fi

  for probe_target in 1.1.1.1 8.8.8.8 9.9.9.9; do
    if timeout 2 ping -4 -c 1 -W 1 "$probe_target" >/dev/null 2>&1; then
      candidate_payload="$(probe_payload_ceiling "$probe_target" "$payload_lo" "$payload_hi")"
      if [[ "$candidate_payload" =~ ^[0-9]+$ ]] && (( candidate_payload > 0 )); then
        if [[ -z "$best_payload" || "$candidate_payload" -lt "$best_payload" ]]; then
          best_payload="$candidate_payload"
        fi
      fi
    fi
  done

  if [[ "$best_payload" =~ ^[0-9]+$ ]] && (( best_payload > 0 )); then
    MTU_VALUE=$(( best_payload + 28 ))
  else
    MTU_VALUE="$mtu_ceiling"
  fi

  if (( MTU_VALUE < 1280 )); then
    MTU_VALUE=1280
  fi
  if (( MTU_VALUE > link_mtu )); then
    MTU_VALUE="$link_mtu"
  fi
  if (( MTU_VALUE > 1500 )); then
    MTU_VALUE=1500
  fi

  log "Автоопределил MTU=${MTU_VALUE} для $(default_iface)"
}

recommended_swap_mb() {
  local mem_mb=0
  mem_mb="$(total_mem_mb)"

  if xhttp_requested; then
    if (( mem_mb < 3072 )); then
      printf '6144'
    elif (( mem_mb < 6144 )); then
      printf '4096'
    elif (( mem_mb < 12288 )); then
      printf '3072'
    else
      printf '2048'
    fi
  else
    if (( mem_mb < 3072 )); then
      printf '4096'
    elif (( mem_mb < 6144 )); then
      printf '3072'
    elif (( mem_mb < 12288 )); then
      printf '2048'
    else
      printf '1024'
    fi
  fi
}

recommended_swappiness() {
  local mem_mb=0
  mem_mb="$(total_mem_mb)"

  if xhttp_requested; then
    if (( mem_mb < 3072 )); then
      printf '60'
    elif (( mem_mb < 6144 )); then
      printf '40'
    elif (( mem_mb < 12288 )); then
      printf '20'
    else
      printf '15'
    fi
  else
    if (( mem_mb < 3072 )); then
      printf '45'
    elif (( mem_mb < 6144 )); then
      printf '25'
    elif (( mem_mb < 12288 )); then
      printf '15'
    else
      printf '10'
    fi
  fi
}

recommended_vfs_cache_pressure() {
  local mem_mb=0
  mem_mb="$(total_mem_mb)"

  if xhttp_requested; then
    if (( mem_mb < 6144 )); then
      printf '120'
    elif (( mem_mb < 12288 )); then
      printf '80'
    else
      printf '60'
    fi
  else
    if (( mem_mb < 4096 )); then
      printf '80'
    else
      printf '50'
    fi
  fi
}

recommended_nginx_worker_processes() {
  printf 'auto'
}

recommended_nginx_worker_connections() {
  local mem_mb=0
  mem_mb="$(total_mem_mb)"

  if (( mem_mb <= 4096 )); then
    printf '16384'
  elif (( mem_mb < 8192 )); then
    printf '32768'
  else
    printf '65535'
  fi
}

recommended_nginx_rlimit_nofile() {
  local mem_mb=0
  mem_mb="$(total_mem_mb)"

  if (( mem_mb <= 4096 )); then
    printf '131072'
  else
    printf '262144'
  fi
}

normalized_lower() {
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'
}

resolved_xray_loglevel() {
  local value=""
  value="$(normalized_lower "$XRAY_LOGLEVEL")"

  case "$value" in
    ""|auto)
      printf 'warning'
      ;;
    debug|info|warning|error|none)
      printf '%s' "$value"
      ;;
    *)
      printf 'warning'
      ;;
  esac
}

resolved_xray_access_log() {
  local value=""
  value="$(normalized_lower "$XRAY_ACCESS_LOG")"

  case "$value" in
    ""|auto)
      printf 'none'
      ;;
    none|/dev/stdout|/dev/stderr)
      printf '%s' "$value"
      ;;
    *)
      printf 'none'
      ;;
  esac
}

resolved_xray_sniff_profile() {
  local value=""
  local cpus=0
  local mem_mb=0

  value="$(normalized_lower "$XRAY_SNIFF_PROFILE")"
  case "$value" in
    light|balanced)
      printf '%s' "$value"
      return 0
      ;;
  esac

  cpus="$(cpu_count)"
  mem_mb="$(total_mem_mb)"

  if (( cpus <= 4 || mem_mb < 8192 )); then
    printf 'light'
  else
    printf 'balanced'
  fi
}

resolved_xray_sniff_route_only() {
  local profile="${1:-}"

  case "$profile" in
    light|balanced)
      printf 'true'
      ;;
    *)
      printf 'true'
      ;;
  esac
}

resolved_xray_sniff_protocols_json() {
  local profile="${1:-}"

  case "$profile" in
    light)
      printf '["http", "tls"]'
      ;;
    balanced)
      printf '["http", "tls", "quic"]'
      ;;
    *)
      printf '["http", "tls"]'
      ;;
  esac
}

recommended_nf_conntrack_max() {
  local cpus=0
  local mem_mb=0
  cpus="$(cpu_count)"
  mem_mb="$(total_mem_mb)"

  if (( cpus <= 1 || mem_mb < 2048 )); then
    printf '131072'
  elif (( cpus <= 4 || mem_mb < 8192 )); then
    printf '262144'
  elif (( cpus <= 8 || mem_mb < 16384 )); then
    printf '524288'
  else
    printf '1048576'
  fi
}

recommended_netdev_budget() {
  local cpus=0
  cpus="$(cpu_count)"

  if (( cpus <= 1 )); then
    printf '300'
  elif (( cpus <= 2 )); then
    printf '400'
  elif (( cpus <= 4 )); then
    printf '600'
  elif (( cpus <= 8 )); then
    printf '900'
  else
    printf '1200'
  fi
}

recommended_netdev_budget_usecs() {
  local cpus=0
  cpus="$(cpu_count)"

  if (( cpus <= 1 )); then
    printf '8000'
  elif (( cpus <= 2 )); then
    printf '12000'
  elif (( cpus <= 4 )); then
    printf '16000'
  elif (( cpus <= 8 )); then
    printf '20000'
  else
    printf '24000'
  fi
}

recommended_dev_weight() {
  local cpus=0
  cpus="$(cpu_count)"

  if (( cpus <= 2 )); then
    printf '64'
  elif (( cpus <= 4 )); then
    printf '128'
  elif (( cpus <= 8 )); then
    printf '192'
  else
    printf '256'
  fi
}

recommended_rps_sock_flow_entries() {
  local cpus=0
  cpus="$(cpu_count)"

  if (( cpus <= 1 )); then
    printf '0'
  elif (( cpus <= 2 )); then
    printf '16384'
  elif (( cpus <= 4 )); then
    printf '32768'
  elif (( cpus <= 8 )); then
    printf '65536'
  else
    printf '131072'
  fi
}

recommended_rps_flow_cnt() {
  local cpus=0
  cpus="$(cpu_count)"

  if (( cpus <= 1 )); then
    printf '0'
  elif (( cpus <= 2 )); then
    printf '4096'
  elif (( cpus <= 4 )); then
    printf '8192'
  elif (( cpus <= 8 )); then
    printf '16384'
  else
    printf '32768'
  fi
}

recommended_offload_profile() {
  case "$(adaptive_capacity_tier)" in
    tiny)
      printf 'latency-lite'
      ;;
    small|medium)
      printf 'balanced'
      ;;
    *)
      printf 'throughput'
      ;;
  esac
}

recommended_tcp_keepalive_time() {
  case "$(adaptive_capacity_tier)" in
    tiny)
      printf '180'
      ;;
    small)
      printf '240'
      ;;
    medium|large)
      printf '300'
      ;;
    *)
      printf '360'
      ;;
  esac
}

recommended_tcp_keepalive_intvl() {
  case "$(adaptive_capacity_tier)" in
    tiny|small)
      printf '30'
      ;;
    medium|large)
      printf '45'
      ;;
    *)
      printf '60'
      ;;
  esac
}

recommended_tcp_keepalive_probes() {
  printf '4'
}

recommended_xhttp_keepalive_timeout() {
  case "$(adaptive_capacity_tier)" in
    tiny)
      printf '75s'
      ;;
    small)
      printf '90s'
      ;;
    medium)
      printf '120s'
      ;;
    large)
      printf '180s'
      ;;
    *)
      printf '240s'
      ;;
  esac
}

recommended_xhttp_keepalive_min_timeout() {
  case "$(adaptive_capacity_tier)" in
    tiny)
      printf '10s'
      ;;
    small)
      printf '15s'
      ;;
    medium)
      printf '20s'
      ;;
    large)
      printf '30s'
      ;;
    *)
      printf '45s'
      ;;
  esac
}

recommended_xhttp_keepalive_requests() {
  case "$(adaptive_capacity_tier)" in
    tiny)
      printf '300'
      ;;
    small)
      printf '500'
      ;;
    medium)
      printf '800'
      ;;
    large)
      printf '1200'
      ;;
    *)
      printf '2000'
      ;;
  esac
}

recommended_xhttp_client_body_timeout() {
  case "$(adaptive_capacity_tier)" in
    tiny)
      printf '90s'
      ;;
    small)
      printf '120s'
      ;;
    medium)
      printf '180s'
      ;;
    large)
      printf '240s'
      ;;
    *)
      printf '300s'
      ;;
  esac
}

recommended_xhttp_send_timeout() {
  case "$(adaptive_capacity_tier)" in
    tiny)
      printf '90s'
      ;;
    small)
      printf '120s'
      ;;
    medium)
      printf '180s'
      ;;
    large)
      printf '240s'
      ;;
    *)
      printf '300s'
      ;;
  esac
}

recommended_xhttp_grpc_read_timeout() {
  case "$(adaptive_capacity_tier)" in
    tiny)
      printf '900s'
      ;;
    small)
      printf '1200s'
      ;;
    medium)
      printf '1800s'
      ;;
    large)
      printf '2700s'
      ;;
    *)
      printf '3600s'
      ;;
  esac
}

recommended_xhttp_grpc_send_timeout() {
  case "$(adaptive_capacity_tier)" in
    tiny)
      printf '120s'
      ;;
    small)
      printf '150s'
      ;;
    medium)
      printf '180s'
      ;;
    large)
      printf '240s'
      ;;
    *)
      printf '300s'
      ;;
  esac
}

recommended_xhttp_grpc_buffer_size() {
  case "$(adaptive_capacity_tier)" in
    tiny|small)
      printf '32k'
      ;;
    medium|large)
      printf '64k'
      ;;
    *)
      printf '128k'
      ;;
  esac
}

recommended_xhttp_ssl_session_cache() {
  case "$(adaptive_capacity_tier)" in
    tiny|small)
      printf '20m'
      ;;
    medium)
      printf '30m'
      ;;
    large)
      printf '40m'
      ;;
    *)
      printf '50m'
      ;;
  esac
}

recommended_xhttp_site_ssl_session_cache() {
  case "$(adaptive_capacity_tier)" in
    tiny|small)
      printf '10m'
      ;;
    medium)
      printf '20m'
      ;;
    large)
      printf '30m'
      ;;
    *)
      printf '40m'
      ;;
  esac
}

recommended_xhttp_h3_site_ssl_session_cache() {
  case "$(adaptive_capacity_tier)" in
    tiny|small)
      printf '10m'
      ;;
    medium)
      printf '20m'
      ;;
    large)
      printf '30m'
      ;;
    *)
      printf '40m'
      ;;
  esac
}

recommended_xhttp_client_header_timeout() {
  case "$(adaptive_capacity_tier)" in
    tiny|small)
      printf '30s'
      ;;
    medium|large)
      printf '45s'
      ;;
    *)
      printf '60s'
      ;;
  esac
}

recommended_xhttp_keepalive_time() {
  case "$(adaptive_capacity_tier)" in
    tiny|small)
      printf '20m'
      ;;
    medium)
      printf '30m'
      ;;
    large)
      printf '45m'
      ;;
    *)
      printf '60m'
      ;;
  esac
}

recommended_xhttp_http2_max_concurrent_streams() {
  case "$(adaptive_capacity_tier)" in
    tiny)
      printf '64'
      ;;
    small)
      printf '96'
      ;;
    medium)
      printf '128'
      ;;
    large)
      printf '192'
      ;;
    *)
      printf '256'
      ;;
  esac
}

recommended_xhttp_http2_body_preread_size() {
  case "$(adaptive_capacity_tier)" in
    tiny|small)
      printf '32k'
      ;;
    medium|large)
      printf '64k'
      ;;
    *)
      printf '128k'
      ;;
  esac
}

recommended_xhttp_http2_recv_buffer_size() {
  case "$(adaptive_capacity_tier)" in
    tiny|small)
      printf '128k'
      ;;
    medium)
      printf '256k'
      ;;
    large|xlarge)
      printf '512k'
      ;;
  esac
}

recommended_xhttp_http2_idle_timeout() {
  case "$(adaptive_capacity_tier)" in
    tiny)
      printf '3m'
      ;;
    small)
      printf '5m'
      ;;
    medium)
      printf '10m'
      ;;
    large)
      printf '15m'
      ;;
    *)
      printf '20m'
      ;;
  esac
}

recommended_watchdog_startup_grace_seconds() {
  if xhttp_requested; then
    case "$(adaptive_capacity_tier)" in
      tiny|small)
        printf '210'
        ;;
      *)
        printf '180'
        ;;
    esac
  else
    printf '120'
  fi
}

recommended_watchdog_cooldown_seconds() {
  if xhttp_requested; then
    printf '240'
  else
    printf '180'
  fi
}

cpu_mask_hex() {
  local cpus="${1:-1}"
  [[ "$cpus" =~ ^[0-9]+$ ]] || cpus=1
  if (( cpus < 1 )); then
    cpus=1
  fi
  if (( cpus >= 63 )); then
    cpus=63
  fi
  printf '%x' $(( (1 << cpus) - 1 ))
}

ensure_swap() {
  local target_mb=0
  local current_mb=0
  local add_mb=0
  local free_root_mb=0

  target_mb="$(recommended_swap_mb)"
  current_mb="$(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo)"

  if (( current_mb >= target_mb )); then
    log "Swap уже достаточный: ${current_mb} MiB"
    return 0
  fi

  add_mb=$(( target_mb - current_mb ))
  free_root_mb="$(df -Pm / | awk 'NR==2 {print $4}')"

  if (( free_root_mb <= 1536 )); then
    log "Свободного места под swap мало (${free_root_mb} MiB), пропускаю top-up"
    return 0
  fi

  add_mb="$(min_int "$add_mb" $(( free_root_mb - 1024 )))"
  if (( add_mb < 512 )); then
    log "Полезный размер top-up swap получился слишком маленьким (${add_mb} MiB), пропускаю"
    return 0
  fi

  log "Добавляю swap top-up ${add_mb} MiB"

  swapoff "$SWAPFILE" >/dev/null 2>&1 || true
  rm -f "$SWAPFILE"
  if command -v fallocate >/dev/null 2>&1; then
    fallocate -l "${add_mb}M" "$SWAPFILE" 2>/dev/null || dd if=/dev/zero of="$SWAPFILE" bs=1M count="$add_mb" status=none
  else
    dd if=/dev/zero of="$SWAPFILE" bs=1M count="$add_mb" status=none
  fi

  chmod 600 "$SWAPFILE"
  mkswap "$SWAPFILE" >/dev/null
  swapon "$SWAPFILE"
  append_line_once /etc/fstab "$SWAPFILE none swap sw 0 0"
}

disable_noisy_services() {
  local unit=""

  log "Отключаю шумные фоновые сервисы Ubuntu"

  for unit in \
    apt-daily.timer \
    apt-daily-upgrade.timer \
    apt-daily.service \
    apt-daily-upgrade.service \
    unattended-upgrades.service \
    packagekit.service \
    packagekit-offline-update.service \
    packagekit-offline-update.timer \
    snapd.service \
    snapd.socket \
    snapd.seeded.service \
    ModemManager.service \
    multipathd.service \
    udisks2.service
  do
    systemctl disable --now "$unit" >/dev/null 2>&1 || true
  done

  for unit in \
    apt-daily.service \
    apt-daily-upgrade.service \
    unattended-upgrades.service \
    packagekit.service \
    packagekit-offline-update.service \
    snapd.service \
    snapd.socket \
    ModemManager.service \
    multipathd.service \
    udisks2.service
  do
    systemctl mask "$unit" >/dev/null 2>&1 || true
  done
}

tune_sshd() {
  log "Применяю baseline-стабилизацию SSH"

  install -d -m 0755 "$(dirname "$SSH_STABILITY_FILE")"
  cat > "$SSH_STABILITY_FILE" <<'EOF'
UseDNS no
ClientAliveInterval 30
ClientAliveCountMax 3
LoginGraceTime 20
TCPKeepAlive yes
MaxStartups 100:30:200
MaxSessions 32
EOF

  chmod 0644 "$SSH_STABILITY_FILE"
  systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1 || true
}

configure_resolved_defaults() {
  if ! command -v resolvectl >/dev/null 2>&1; then
    return 0
  fi

  install -d -m 0755 "$RESOLVED_DROPIN_DIR"
  cat > "$RESOLVED_DROPIN_FILE" <<'EOF'
[Resolve]
DNS=1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4
FallbackDNS=9.9.9.9 149.112.112.112
Domains=~.
DNSSEC=no
MulticastDNS=no
LLMNR=no
EOF

  systemctl restart systemd-resolved >/dev/null 2>&1 || true
}

write_generic_tls_links() {
  if ! xhttp_requested; then
    return 0
  fi

  install -d -m 0755 "$(dirname "$NODE_TLS_DIR")" "$NODE_TLS_DIR"

  ln -sfn "/etc/letsencrypt/live/$XHTTP_DOMAIN/fullchain.pem" "$NODE_TLS_DIR/fullchain.pem"
  ln -sfn "/etc/letsencrypt/live/$XHTTP_DOMAIN/privkey.pem" "$NODE_TLS_DIR/privkey.pem"
  ln -sfn "/etc/letsencrypt/live/$XHTTP_DOMAIN/fullchain.pem" "$NODE_TLS_DIR/cert.pem"
  ln -sfn "/etc/letsencrypt/live/$XHTTP_DOMAIN/privkey.pem" "$NODE_TLS_DIR/cert.key"

  [[ -e "$NODE_TLS_DIR/fullchain.pem" ]] || die "Не удалось подготовить generic TLS fullchain.pem для HY2/xHTTP"
  [[ -e "$NODE_TLS_DIR/privkey.pem" ]] || die "Не удалось подготовить generic TLS privkey.pem для HY2/xHTTP"
  [[ -e "$NODE_TLS_DIR/cert.pem" ]] || die "Не удалось подготовить generic TLS cert.pem для HY2/xHTTP"
  [[ -e "$NODE_TLS_DIR/cert.key" ]] || die "Не удалось подготовить generic TLS cert.key для HY2/xHTTP"
}

normalize_xhttp_domain() {
  local domain="${1:-}"

  domain="$(printf '%s' "$domain" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  domain="$(normalized_lower "$domain")"
  domain="${domain%.}"
  printf '%s' "$domain"
}

validate_xhttp_domain() {
  local domain="${1:-}"

  [[ -n "$domain" ]] || return 0

  [[ "$domain" != *" "* ]] || die "XHTTP domain содержит пробелы: $domain"
  [[ "$domain" != *$'\t'* ]] || die "XHTTP domain содержит табуляцию: $domain"

  if ! [[ "$domain" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])$ ]]; then
    die "Некорректный XHTTP domain: $domain"
  fi
}

xhttp_requested() {
  [[ -n "$XHTTP_DOMAIN" ]]
}

normalize_xhttp_path() {
  if [[ -z "$XHTTP_PATH" ]]; then
    XHTTP_PATH="/stable-in-443/"
  fi

  [[ "$XHTTP_PATH" == /* ]] || XHTTP_PATH="/$XHTTP_PATH"
  [[ "$XHTTP_PATH" == */ ]] || XHTTP_PATH="$XHTTP_PATH/"
}

validate_xhttp_settings() {
  [[ "$XHTTP_SOCKET" == /dev/shm/* ]] || die "XHTTP_SOCKET должен находиться в /dev/shm"
  [[ "$XHTTP_SOCKET" == *.socket || "$XHTTP_SOCKET" == *.sock ]] || die "XHTTP_SOCKET должен оканчиваться на .socket или .sock"
  [[ "$XHTTP_SOCKET_WAIT_SECONDS" =~ ^[0-9]+$ ]] || die "XHTTP_SOCKET_WAIT_SECONDS должен быть целым числом"
  (( XHTTP_SOCKET_WAIT_SECONDS >= 30 && XHTTP_SOCKET_WAIT_SECONDS <= 1800 )) || die "XHTTP_SOCKET_WAIT_SECONDS должен быть от 30 до 1800"
}

install_nginx_mainline_repo() {
  local distro_id=""
  local codename=""

  # shellcheck disable=SC1091
  source /etc/os-release
  distro_id="${ID:-}"
  codename="${VERSION_CODENAME:-}"
  [[ "$distro_id" == "ubuntu" ]] || die "nginx.org mainline repo поддерживается этим установщиком только на Ubuntu"
  [[ -n "$codename" ]] || die "Не удалось определить VERSION_CODENAME из /etc/os-release"

  install -d -m 0755 /etc/apt/keyrings

  if [[ ! -f /etc/apt/keyrings/nginx.gpg ]]; then
    curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /etc/apt/keyrings/nginx.gpg
    chmod 0644 /etc/apt/keyrings/nginx.gpg
  fi

  cat > /etc/apt/sources.list.d/nginx-mainline.list <<EOF
deb [signed-by=/etc/apt/keyrings/nginx.gpg] https://nginx.org/packages/mainline/ubuntu ${codename} nginx
deb-src [signed-by=/etc/apt/keyrings/nginx.gpg] https://nginx.org/packages/mainline/ubuntu ${codename} nginx
EOF
}

wait_for_xhttp_socket() {
  local tries=$(( (XHTTP_SOCKET_WAIT_SECONDS + 1) / 2 ))
  local delay=2
  local attempt=""
  local h2_socket=""

  for ((attempt = 1; attempt <= tries; attempt++)); do
    if [[ -S "$XHTTP_SOCKET" ]]; then
      printf '%s' "$XHTTP_SOCKET"
      return 0
    fi
    sleep "$delay"
  done

  return 1
}

validate_generated_xhttp_sync_script() {
  [[ -s "$XHTTP_SYNC_SCRIPT" ]] || die "xHTTP sync script не был создан"
  bash -n "$XHTTP_SYNC_SCRIPT" || die "xHTTP sync script содержит синтаксическую ошибку"

  grep -Fq 'grpc_set_header Host \$host;' "$XHTTP_SYNC_SCRIPT" || die "xHTTP sync script потерял экранирование \$host"
  grep -Fq 'return 301 https://\$host\$request_uri;' "$XHTTP_SYNC_SCRIPT" || die "xHTTP sync script потерял экранирование \$request_uri"
  grep -Fq 'location = / {' "$XHTTP_SYNC_SCRIPT" || die "xHTTP sync script потерял корневой 204-handler"
  grep -Fq 'return 204;' "$XHTTP_SYNC_SCRIPT" || die "xHTTP sync script потерял корневой 204-handler"
  grep -Fq 'return 404;' "$XHTTP_SYNC_SCRIPT" || die "xHTTP sync script потерял fallback 404-handler"
  grep -Fq 'add_header QUIC-Status \$http3 always;' "$XHTTP_SYNC_SCRIPT" || die "xHTTP sync script потерял экранирование \$http3"
}

verify_local_xhttp_h2() {
  local tries=15
  local delay=2
  local attempt=""
  local headers=""

  for ((attempt = 1; attempt <= tries; attempt++)); do
    headers="$(curl -ksS --http2 --resolve "$XHTTP_DOMAIN:443:127.0.0.1" -o /dev/null -D - "https://$XHTTP_DOMAIN$XHTTP_PATH" 2>/dev/null || true)"
    if grep -qE '^HTTP/[^ ]+ 400' <<<"$headers"; then
      return 0
    fi
    sleep "$delay"
  done

  return 1
}

write_xhttp_sync_artifacts() {
  local full_site="/etc/nginx/sites-available/remnanode-xhttp.conf"
  local h3_site="/etc/nginx/sites-available/remnanode-xhttp-h3-8443.conf"
  local keepalive_timeout=""
  local keepalive_min_timeout=""
  local keepalive_requests=""
  local client_header_timeout=""
  local client_body_timeout=""
  local send_timeout=""
  local grpc_read_timeout=""
  local grpc_send_timeout=""
  local grpc_buffer_size=""
  local site_ssl_session_cache=""
  local h3_site_ssl_session_cache=""

  keepalive_timeout="$(recommended_xhttp_keepalive_timeout)"
  keepalive_min_timeout="$(recommended_xhttp_keepalive_min_timeout)"
  keepalive_requests="$(recommended_xhttp_keepalive_requests)"
  client_header_timeout="$(recommended_xhttp_client_header_timeout)"
  client_body_timeout="$(recommended_xhttp_client_body_timeout)"
  send_timeout="$(recommended_xhttp_send_timeout)"
  grpc_read_timeout="$(recommended_xhttp_grpc_read_timeout)"
  grpc_send_timeout="$(recommended_xhttp_grpc_send_timeout)"
  grpc_buffer_size="$(recommended_xhttp_grpc_buffer_size)"
  site_ssl_session_cache="$(recommended_xhttp_site_ssl_session_cache)"
  h3_site_ssl_session_cache="$(recommended_xhttp_h3_site_ssl_session_cache)"

  cat > "$XHTTP_SYNC_SCRIPT" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

XHTTP_DOMAIN="$XHTTP_DOMAIN"
XHTTP_PATH="$XHTTP_PATH"
XHTTP_SOCKET="$XHTTP_SOCKET"
XHTTP_ENABLE_H3="$XHTTP_ENABLE_H3"
FULL_SITE="$full_site"
H3_SITE="$h3_site"
KEEPALIVE_TIMEOUT="$keepalive_timeout"
KEEPALIVE_MIN_TIMEOUT="$keepalive_min_timeout"
KEEPALIVE_REQUESTS="$keepalive_requests"
CLIENT_HEADER_TIMEOUT="$client_header_timeout"
CLIENT_BODY_TIMEOUT="$client_body_timeout"
SEND_TIMEOUT="$send_timeout"
GRPC_READ_TIMEOUT="$grpc_read_timeout"
GRPC_SEND_TIMEOUT="$grpc_send_timeout"
GRPC_BUFFER_SIZE="$grpc_buffer_size"
SITE_SSL_SESSION_CACHE="$site_ssl_session_cache"
H3_SITE_SSL_SESSION_CACHE="$h3_site_ssl_session_cache"

find_socket() {
  local pattern="\$1"
  find /dev/shm -maxdepth 1 -type s -name "\$pattern" | sort | head -n1 || true
}

render_changed() {
  local src="\$1"
  local dst="\$2"

  if [[ -f "\$dst" ]] && cmp -s "\$src" "\$dst"; then
    rm -f "\$src"
    return 1
  fi

  install -D -m 0644 "\$src" "\$dst"
  rm -f "\$src"
  return 0
}

h2_socket=""
if [[ -S "\$XHTTP_SOCKET" ]]; then
  h2_socket="\$XHTTP_SOCKET"
fi
h3_socket="\$(find_socket 'xrxh*h3*.socket')"
changed=0

if [[ -z "\$h2_socket" ]]; then
  logger -t remnanode-xhttp-sync -- "required xHTTP socket \$XHTTP_SOCKET is not ready for \$XHTTP_DOMAIN"
  exit 1
fi

tmp_full="\$(mktemp)"
tmp_h3="\$(mktemp)"

cat > "\$tmp_full" <<SITE
server {
    listen 80;
    listen [::]:80;
    server_name $XHTTP_DOMAIN;

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/html;
        default_type text/plain;
    }

    location / {
        return 301 https://\\\$host\\\$request_uri;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;

    http2 on;
    server_name $XHTTP_DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$XHTTP_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$XHTTP_DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:XHTTP_SSL:\$SITE_SSL_SESSION_CACHE;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    access_log off;

    location $XHTTP_PATH {
        client_max_body_size 0;
        client_body_timeout \$CLIENT_BODY_TIMEOUT;
        send_timeout \$SEND_TIMEOUT;
        grpc_read_timeout \$GRPC_READ_TIMEOUT;
        grpc_send_timeout \$GRPC_SEND_TIMEOUT;
        grpc_socket_keepalive on;
        grpc_buffer_size \$GRPC_BUFFER_SIZE;
        grpc_set_header Host \\\$host;
        grpc_set_header X-Real-IP \\\$remote_addr;
        grpc_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        grpc_set_header X-Forwarded-Proto https;
        grpc_pass unix:\$h2_socket;
    }

    location = / {
        default_type text/plain;
        return 204;
    }

    location / {
        return 404;
    }
}
SITE

if render_changed "\$tmp_full" "\$FULL_SITE"; then
  changed=1
fi

ln -sf "\$FULL_SITE" /etc/nginx/sites-enabled/remnanode-xhttp.conf
rm -f /etc/nginx/sites-enabled/remnanode-xhttp-http.conf

if [[ "\$(printf '%s' "\$XHTTP_ENABLE_H3" | tr '[:upper:]' '[:lower:]')" =~ ^(auto|1|y|yes|true|on)$ ]] && [[ -n "\$h3_socket" ]]; then
  cat > "\$tmp_h3" <<SITE
server {
    listen 8443 ssl;
    listen [::]:8443 ssl;
    listen 8443 quic reuseport;
    listen [::]:8443 quic reuseport;

    http2 on;
    http3 on;
    server_name $XHTTP_DOMAIN;

    add_header Alt-Svc 'h3=":8443"; ma=86400' always;
    add_header QUIC-Status \\\$http3 always;

    ssl_certificate /etc/letsencrypt/live/$XHTTP_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$XHTTP_DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:XHTTP_H3_8443_SSL:\$H3_SITE_SSL_SESSION_CACHE;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    access_log off;

    location $XHTTP_PATH {
        client_max_body_size 0;
        client_body_timeout \$CLIENT_BODY_TIMEOUT;
        send_timeout \$SEND_TIMEOUT;
        grpc_read_timeout \$GRPC_READ_TIMEOUT;
        grpc_send_timeout \$GRPC_SEND_TIMEOUT;
        grpc_socket_keepalive on;
        grpc_buffer_size \$GRPC_BUFFER_SIZE;
        grpc_set_header Host \\\$host;
        grpc_set_header X-Real-IP \\\$remote_addr;
        grpc_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        grpc_set_header X-Forwarded-Proto https;
        grpc_pass unix:\$h3_socket;
    }

    location = / {
        default_type text/plain;
        return 204;
    }

    location / {
        return 404;
    }
}
SITE
  if render_changed "\$tmp_h3" "\$H3_SITE"; then
    changed=1
  fi
  ln -sf "\$H3_SITE" /etc/nginx/sites-enabled/remnanode-xhttp-h3-8443.conf
else
  rm -f "\$tmp_h3"
  if [[ -e /etc/nginx/sites-enabled/remnanode-xhttp-h3-8443.conf || -e "\$H3_SITE" ]]; then
    changed=1
  fi
  rm -f /etc/nginx/sites-enabled/remnanode-xhttp-h3-8443.conf "\$H3_SITE"
fi

if (( changed == 0 )); then
  if ! systemctl --quiet is-active nginx; then
    nginx -t
    systemctl start nginx
    logger -t remnanode-xhttp-sync -- "xHTTP nginx was down and has been started for \$XHTTP_DOMAIN"
    exit 0
  fi
  logger -t remnanode-xhttp-sync -- "xHTTP nginx config unchanged for \$XHTTP_DOMAIN"
  exit 0
fi

nginx -t
if systemctl --quiet is-active nginx; then
  systemctl reload nginx
else
  systemctl start nginx
fi
logger -t remnanode-xhttp-sync -- "xHTTP nginx config applied for \$XHTTP_DOMAIN"
EOF

  chmod 0755 "$XHTTP_SYNC_SCRIPT"

  cat > "$XHTTP_SYNC_SERVICE" <<EOF
[Unit]
Description=RemnaNode xHTTP nginx sync
After=network-online.target nginx.service docker.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$XHTTP_SYNC_SCRIPT
EOF

  cat > "$XHTTP_SYNC_TIMER" <<'EOF'
[Unit]
Description=Retry RemnaNode xHTTP nginx sync

[Timer]
OnBootSec=2min
OnUnitActiveSec=1min
RandomizedDelaySec=10s
Persistent=true
Unit=remnanode-xhttp-sync.service

[Install]
WantedBy=timers.target
EOF
}

configure_xhttp_stack() {
  local h2_socket=""
  local h3_socket=""
  local http_site="/etc/nginx/sites-available/remnanode-xhttp-http.conf"
  local full_site="/etc/nginx/sites-available/remnanode-xhttp.conf"
  local h3_site="/etc/nginx/sites-available/remnanode-xhttp-h3-8443.conf"
  local nginx_worker_processes=""
  local nginx_worker_connections=""
  local nginx_rlimit_nofile=""
  local keepalive_timeout=""
  local keepalive_min_timeout=""
  local keepalive_requests=""
  local keepalive_time=""
  local client_header_timeout=""
  local client_body_timeout=""
  local send_timeout=""
  local grpc_read_timeout=""
  local grpc_send_timeout=""
  local grpc_buffer_size=""
  local ssl_session_cache=""
  local site_ssl_session_cache=""
  local h3_site_ssl_session_cache=""
  local http2_max_concurrent_streams=""
  local http2_body_preread_size=""
  local http2_recv_buffer_size=""

  if ! xhttp_requested; then
    return 0
  fi

  normalize_xhttp_path
  validate_xhttp_settings
  log "Включаю optional xHTTP-слой для домена $XHTTP_DOMAIN"
  log "Ожидаемый xHTTP socket: $XHTTP_SOCKET; path: $XHTTP_PATH"
  nginx_worker_processes="$(recommended_nginx_worker_processes)"
  nginx_worker_connections="$(recommended_nginx_worker_connections)"
  nginx_rlimit_nofile="$(recommended_nginx_rlimit_nofile)"
  keepalive_timeout="$(recommended_xhttp_keepalive_timeout)"
  keepalive_min_timeout="$(recommended_xhttp_keepalive_min_timeout)"
  keepalive_requests="$(recommended_xhttp_keepalive_requests)"
  keepalive_time="$(recommended_xhttp_keepalive_time)"
  client_header_timeout="$(recommended_xhttp_client_header_timeout)"
  client_body_timeout="$(recommended_xhttp_client_body_timeout)"
  send_timeout="$(recommended_xhttp_send_timeout)"
  grpc_read_timeout="$(recommended_xhttp_grpc_read_timeout)"
  grpc_send_timeout="$(recommended_xhttp_grpc_send_timeout)"
  grpc_buffer_size="$(recommended_xhttp_grpc_buffer_size)"
  ssl_session_cache="$(recommended_xhttp_ssl_session_cache)"
  site_ssl_session_cache="$(recommended_xhttp_site_ssl_session_cache)"
  h3_site_ssl_session_cache="$(recommended_xhttp_h3_site_ssl_session_cache)"
  http2_max_concurrent_streams="$(recommended_xhttp_http2_max_concurrent_streams)"
  http2_body_preread_size="$(recommended_xhttp_http2_body_preread_size)"
  http2_recv_buffer_size="$(recommended_xhttp_http2_recv_buffer_size)"
  log "Adaptive nginx xHTTP profile: workers=${nginx_worker_processes}, worker_connections=${nginx_worker_connections}, nofile=${nginx_rlimit_nofile}, keepalive=${keepalive_timeout}, grpc_read=${grpc_read_timeout}, grpc_send=${grpc_send_timeout}, offload=$(recommended_offload_profile)"

  apt_install_missing gnupg certbot
  install_nginx_mainline_repo
  run_retry 5 5 apt_update_retry || die "Не удалось выполнить apt update после добавления nginx mainline repo"
  APT_UPDATED=1
  wait_for_apt_locks
  apt-get install -y nginx

  install -d -m 0755 /etc/nginx/conf.d /etc/nginx/sites-available /etc/nginx/sites-enabled /var/www/html
  install -d -m 0755 /etc/systemd/system/nginx.service.d

  cat > /etc/systemd/system/nginx.service.d/limits.conf <<EOF
[Service]
LimitNOFILE=${nginx_rlimit_nofile}
TasksMax=infinity
EOF

  cat > /etc/systemd/system/nginx.service.d/restart-on-failure.conf <<'EOF'
[Service]
Restart=on-failure
RestartSec=2s
EOF

  cat > /etc/nginx/nginx.conf <<EOF
user www-data;
worker_processes ${nginx_worker_processes};
worker_rlimit_nofile ${nginx_rlimit_nofile};
worker_shutdown_timeout 20s;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections ${nginx_worker_connections};
    multi_accept off;
    use epoll;
}

http {
    sendfile on;
    tcp_nopush on;
    types_hash_max_size 2048;
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    access_log off;
    error_log /var/log/nginx/error.log;
    gzip on;
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF

cat > /etc/nginx/conf.d/00-tokervpn-xhttp-tuning.conf <<'EOF'
# Tokervpn xHTTP tuning
keepalive_timeout __KEEPALIVE_TIMEOUT__;
keepalive_min_timeout __KEEPALIVE_MIN_TIMEOUT__;
keepalive_requests __KEEPALIVE_REQUESTS__;
keepalive_time __KEEPALIVE_TIME__;
reset_timedout_connection on;
http2_chunk_size 32k;
http2_max_concurrent_streams __HTTP2_MAX_CONCURRENT_STREAMS__;
http2_body_preread_size __HTTP2_BODY_PREREAD_SIZE__;
http2_recv_buffer_size __HTTP2_RECV_BUFFER_SIZE__;
ssl_session_cache shared:XHTTP_GLOBAL_SSL:__SSL_SESSION_CACHE__;
ssl_session_timeout 1d;
ssl_session_tickets off;
client_header_timeout __CLIENT_HEADER_TIMEOUT__;
client_body_timeout __CLIENT_BODY_TIMEOUT__;
send_timeout __SEND_TIMEOUT__;
tcp_nodelay on;
EOF

  python3 - "$keepalive_timeout" "$keepalive_min_timeout" "$keepalive_requests" "$keepalive_time" "$client_header_timeout" "$client_body_timeout" "$send_timeout" "$ssl_session_cache" "$http2_max_concurrent_streams" "$http2_body_preread_size" "$http2_recv_buffer_size" <<'PY'
from pathlib import Path
import sys

path = Path("/etc/nginx/conf.d/00-tokervpn-xhttp-tuning.conf")
text = path.read_text()
replacements = {
    "__KEEPALIVE_TIMEOUT__": sys.argv[1],
    "__KEEPALIVE_MIN_TIMEOUT__": sys.argv[2],
    "__KEEPALIVE_REQUESTS__": sys.argv[3],
    "__KEEPALIVE_TIME__": sys.argv[4],
    "__CLIENT_HEADER_TIMEOUT__": sys.argv[5],
    "__CLIENT_BODY_TIMEOUT__": sys.argv[6],
    "__SEND_TIMEOUT__": sys.argv[7],
    "__SSL_SESSION_CACHE__": sys.argv[8],
    "__HTTP2_MAX_CONCURRENT_STREAMS__": sys.argv[9],
    "__HTTP2_BODY_PREREAD_SIZE__": sys.argv[10],
    "__HTTP2_RECV_BUFFER_SIZE__": sys.argv[11],
}
for key, value in replacements.items():
    text = text.replace(key, value)
path.write_text(text)
PY

  cat > "$http_site" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $XHTTP_DOMAIN;

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/html;
        default_type text/plain;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF

  ln -sf "$http_site" /etc/nginx/sites-enabled/remnanode-xhttp-http.conf
  systemctl daemon-reload
  nginx -t
  systemctl enable --now nginx
  systemctl restart nginx

  certbot certonly \
    --webroot -w /var/www/html \
    -d "$XHTTP_DOMAIN" \
    --agree-tos \
    --register-unsafely-without-email \
    --non-interactive \
    --keep-until-expiring

  write_generic_tls_links
  write_xhttp_sync_artifacts
  validate_generated_xhttp_sync_script
  systemctl daemon-reload
  systemctl enable remnanode-xhttp-sync.service remnanode-xhttp-sync.timer >/dev/null 2>&1 || true
  systemctl start remnanode-xhttp-sync.timer >/dev/null 2>&1 || true

  if ! h2_socket="$(wait_for_xhttp_socket)"; then
    compose logs --tail=100 -t remnanode || true
    die "Не появился обязательный socket $XHTTP_SOCKET за ${XHTTP_SOCKET_WAIT_SECONDS}s. Назначьте этой ноде inbound STABLE-IN-443 в мастер-панели и проверьте, что listen профиля равен $XHTTP_SOCKET"
  fi
  h3_socket="$(find /dev/shm -maxdepth 1 -type s -name 'xrxh*h3*.socket' | sort | head -n1 || true)"

  cat > "$full_site" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $XHTTP_DOMAIN;

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/html;
        default_type text/plain;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;

    http2 on;
    server_name $XHTTP_DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$XHTTP_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$XHTTP_DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:XHTTP_SSL:$site_ssl_session_cache;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    access_log off;

    location $XHTTP_PATH {
        client_max_body_size 0;
        client_body_timeout $client_body_timeout;
        send_timeout $send_timeout;
        grpc_read_timeout $grpc_read_timeout;
        grpc_send_timeout $grpc_send_timeout;
        grpc_socket_keepalive on;
        grpc_buffer_size $grpc_buffer_size;
        grpc_set_header Host \$host;
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_set_header X-Forwarded-Proto https;
        grpc_pass unix:$h2_socket;
    }

    location = / {
        default_type text/plain;
        return 204;
    }

    location / {
        return 404;
    }
}
EOF

  ln -sf "$full_site" /etc/nginx/sites-enabled/remnanode-xhttp.conf
  rm -f /etc/nginx/sites-enabled/remnanode-xhttp-http.conf

  if [[ "$(printf '%s' "$XHTTP_ENABLE_H3" | tr '[:upper:]' '[:lower:]')" =~ ^(auto|1|y|yes|true|on)$ ]] && [[ -n "$h3_socket" ]]; then
    cat > "$h3_site" <<EOF
server {
    listen 8443 ssl;
    listen [::]:8443 ssl;
    listen 8443 quic reuseport;
    listen [::]:8443 quic reuseport;

    http2 on;
    http3 on;
    server_name $XHTTP_DOMAIN;

    add_header Alt-Svc 'h3=":8443"; ma=86400' always;
    add_header QUIC-Status \$http3 always;

    ssl_certificate /etc/letsencrypt/live/$XHTTP_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$XHTTP_DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:XHTTP_H3_8443_SSL:$h3_site_ssl_session_cache;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    access_log off;

    location $XHTTP_PATH {
        client_max_body_size 0;
        client_body_timeout $client_body_timeout;
        send_timeout $send_timeout;
        grpc_read_timeout $grpc_read_timeout;
        grpc_send_timeout $grpc_send_timeout;
        grpc_socket_keepalive on;
        grpc_buffer_size $grpc_buffer_size;
        grpc_set_header Host \$host;
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_set_header X-Forwarded-Proto https;
        grpc_pass unix:$h3_socket;
    }

    location / {
        root /var/www/html;
        index index.html;
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
    ln -sf "$h3_site" /etc/nginx/sites-enabled/remnanode-xhttp-h3-8443.conf
  else
    rm -f /etc/nginx/sites-enabled/remnanode-xhttp-h3-8443.conf "$h3_site"
  fi

  nginx -t
  systemctl reload nginx
  if ! "$XHTTP_SYNC_SCRIPT" >/dev/null 2>&1; then
    journalctl -u remnanode-xhttp-sync.service -n 40 --no-pager || true
    die "xHTTP sync script не смог применить nginx-конфиг"
  fi
  if ! systemctl start remnanode-xhttp-sync.service >/dev/null 2>&1; then
    journalctl -u remnanode-xhttp-sync.service -n 40 --no-pager || true
    die "systemd remnanode-xhttp-sync.service завершился ошибкой"
  fi
  if ! verify_local_xhttp_h2; then
    journalctl -u remnanode-xhttp-sync.service -n 40 --no-pager || true
    die "Локальный xHTTP H2 self-test не прошёл: https://$XHTTP_DOMAIN$XHTTP_PATH не отдаёт ожидаемый HTTP 400"
  fi
  log "Локальный xHTTP H2 self-test пройден"
}

parse_secret() {
  local raw="$1"
  local value=""

  raw="$(printf '%s' "$raw" | tr -d '\r')"

  value="$(
    printf '%s\n' "$raw" | sed -nE \
      -e 's/^[[:space:]]*-[[:space:]]*(SECRET_KEY|SSL_CERT)="?([^"]+)"?[[:space:]]*$/\2/p' \
      -e 's/^[[:space:]]*(SECRET_KEY|SSL_CERT)="?([^"]+)"?[[:space:]]*$/\2/p' \
      | head -n1
  )"

  if [[ -z "$value" ]]; then
    value="$(printf '%s' "$raw" | sed \
      -e 's/^[[:space:]]*//' \
      -e 's/[[:space:]]*$//' \
      -e 's/^"//' \
      -e 's/"$//')"
  fi

  printf '%s' "$value"
}

read_manual_secret() {
  local secret_raw=""

  printf "\nВведи секрет ноды.\n"
  printf "Можно вставить любой из вариантов:\n"
  printf "  eyJ...\n"
  printf "  SECRET_KEY=\"eyJ...\"\n"
  printf "  - SECRET_KEY=\"eyJ...\"\n"
  secret_raw="$(ask "SECRET_KEY: ")"

  SECRET_VALUE="$(parse_secret "$secret_raw")"
  [[ -n "$SECRET_VALUE" ]] || die "Не удалось распознать SECRET_KEY"

  log "Секрет ноды принят"
  printf "NODE_PORT=%s\n" "$NODE_PORT"
  printf "SECRET_KEY=<hidden>, длина=%s\n" "${#SECRET_VALUE}"
}

upgrade_system() {
  if ! bool_is_true "$RUN_FULL_UPGRADE"; then
    log "Полный upgrade пропущен: RUN_FULL_UPGRADE=$RUN_FULL_UPGRADE"
    return 0
  fi

  ensure_dns
  log "Обновляю систему"
  run_retry 5 5 apt_update_retry || die "Не удалось выполнить apt update"
  APT_UPDATED=1

  wait_for_apt_locks
  apt-get -y upgrade
  wait_for_apt_locks
  apt-get -y full-upgrade
  wait_for_apt_locks
  apt-get -y autoremove --purge
  apt-get -y autoclean

  mark_reboot_required
}

install_packages() {
  log "Устанавливаю системные пакеты"
  apt_install_missing \
    ca-certificates \
    curl \
    gnupg \
    nano \
    logrotate \
    nftables \
    grep \
    sed \
    gawk \
    psmisc \
    coreutils \
    iproute2 \
    iputils-ping \
    iptables \
    openssl \
    jq \
    conntrack \
    ipset \
    util-linux \
    ethtool \
    irqbalance \
    needrestart \
    sudo \
    tar \
    python3 \
    python3-flask \
    python3-werkzeug \
    python3-gunicorn \
    gunicorn
}

docker_compose_ready() {
  command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1
}

docker_compose_plugin_pkg_available() {
  apt-cache show docker-compose-plugin >/dev/null 2>&1
}

docker_compose_v2_pkg_available() {
  apt-cache show docker-compose-v2 >/dev/null 2>&1
}

install_manual_docker_compose_plugin() {
  local arch=""
  local compose_arch=""
  local compose_version="${DOCKER_COMPOSE_VERSION:-v2.40.3}"
  local plugin_dir="/usr/local/lib/docker/cli-plugins"
  local plugin_path="$plugin_dir/docker-compose"
  local url=""
  local tmp_binary=""
  local tmp_checksum=""

  ensure_dns

  arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  case "$arch" in
    amd64|x86_64) compose_arch="x86_64" ;;
    arm64|aarch64) compose_arch="aarch64" ;;
    armhf|armv7l) compose_arch="armv7" ;;
    ppc64el|ppc64le) compose_arch="ppc64le" ;;
    s390x) compose_arch="s390x" ;;
    *) die "Неизвестная архитектура для Docker Compose plugin: $arch" ;;
  esac

  url="https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-linux-${compose_arch}"
  tmp_binary="$(mktemp)"
  tmp_checksum="$(mktemp)"

  log "docker compose plugin не найден в пакетах, ставлю вручную (${compose_version}, ${compose_arch})"
  mkdir -p "$plugin_dir"
  run_retry 5 5 curl -fsSL "$url" -o "$tmp_binary" || die "Не удалось скачать Docker Compose plugin"
  run_retry 5 5 curl -fsSL "${url}.sha256" -o "$tmp_checksum" || die "Не удалось скачать SHA-256 для Docker Compose plugin"
  (
    cd "$(dirname "$tmp_binary")"
    printf '%s  %s\n' "$(awk '{print $1}' "$tmp_checksum")" "$(basename "$tmp_binary")" | sha256sum -c -
  ) || die "SHA-256 Docker Compose plugin не совпал"
  install -m 0755 "$tmp_binary" "$plugin_path"
  rm -f "$tmp_binary" "$tmp_checksum"
  chmod 0755 "$plugin_path"
}

ensure_docker_compose() {
  if docker_compose_ready; then
    return 0
  fi

  ensure_dns
  if (( APT_UPDATED == 0 )); then
    run_retry 5 5 apt_update_retry || die "Не удалось выполнить apt update"
    APT_UPDATED=1
  fi

  if docker_compose_plugin_pkg_available; then
    apt_install_missing docker-compose-plugin || true
  fi

  if docker_compose_ready; then
    return 0
  fi

  if docker_compose_v2_pkg_available; then
    apt_install_missing docker-compose-v2 || true
  fi

  if docker_compose_ready; then
    return 0
  fi

  install_manual_docker_compose_plugin
  docker_compose_ready || die "Docker Compose plugin не установился"
}

install_docker() {
  local distro_id=""
  local codename=""
  local arch=""

  ensure_dns

  if ! command -v docker >/dev/null 2>&1; then
    log "Docker не найден, устанавливаю из официального подписанного APT-репозитория"
    # shellcheck disable=SC1091
    source /etc/os-release
    distro_id="${ID:-}"
    codename="${VERSION_CODENAME:-}"
    arch="$(dpkg --print-architecture)"
    [[ "$distro_id" == "ubuntu" ]] || die "Автоматическая установка Docker поддерживается этим установщиком только на Ubuntu"
    [[ -n "$codename" ]] || die "Не удалось определить VERSION_CODENAME для установки Docker"

    install -d -m 0755 /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod 0644 /etc/apt/keyrings/docker.asc
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' \
      "$arch" "$codename" > /etc/apt/sources.list.d/docker.list
    run_retry 5 5 apt_update_retry || die "Не удалось обновить APT после добавления Docker repository"
    APT_UPDATED=1
    wait_for_apt_locks
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || \
      die "Не удалось установить Docker из официального репозитория"
  else
    log "Docker уже установлен"
  fi

  ensure_docker_compose
  systemctl enable --now docker
  docker --version >/dev/null
  docker compose version >/dev/null
}

unit_exists() {
  systemctl cat "$1" >/dev/null 2>&1
}

maybe_enable_unit() {
  local unit="$1"
  unit_exists "$unit" || return 0
  systemctl enable "$unit" >/dev/null 2>&1 || true
}

maybe_restart_unit() {
  local unit="$1"
  unit_exists "$unit" || return 0
  systemctl restart "$unit" || true
}

has_cake_stack() {
  [[ -x /usr/local/sbin/cake_autoset.sh ]] && return 0
  unit_exists "cake-soft-panel.service" && return 0
  unit_exists "cake_autoset.timer" && return 0
  return 1
}

configure_mtu() {
  local iface=""

  detect_optimal_mtu
  iface="$(default_iface)"
  [[ -n "$iface" ]] || die "Не удалось определить основной сетевой интерфейс"

  log "Ставлю MTU $MTU_VALUE на $iface"
  ip link set dev "$iface" mtu "$MTU_VALUE" || true

  cat > "$MTU_SERVICE" <<EOF
[Unit]
Description=Set MTU $MTU_VALUE for primary interface
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ip link set dev $iface mtu $MTU_VALUE
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now node-mtu.service
}

prepare_dirs() {
  log "Создаю рабочие каталоги"
  mkdir -p "$NODE_ROOT" "$LOG_DIR" "$OVERRIDES_DIR" "$WATCHDOG_STATE_DIR" "$NODE_STATE_DIR" "$(dirname "$NODE_TLS_DIR")" "$NODE_TLS_DIR"
  chmod 755 "$NODE_ROOT" "$LOG_DIR" "$OVERRIDES_DIR" "$WATCHDOG_STATE_DIR" "$(dirname "$NODE_TLS_DIR")" "$NODE_TLS_DIR"
  chmod 700 "$NODE_STATE_DIR"
}

repair_existing_cake_stack() {
  local iface="$1"

  if has_cake_stack; then
    log "Обнаружен legacy CAKE/shaping stack, отключаю его чтобы не ломал Reality/xHTTP"

    for unit in \
      cake-soft-panel.service \
      cake-soft-panel-worker.service \
      cake-soft-panel-producer.service \
      cake_nft_policer.service \
      cake_hot_sync.service \
      cake_autoset.service \
      cake_apply_last_good.service
    do
      systemctl stop "$unit" >/dev/null 2>&1 || true
      systemctl disable "$unit" >/dev/null 2>&1 || true
      systemctl mask "$unit" >/dev/null 2>&1 || true
    done

    for unit in cake_autoset.timer cake_hot_sync.timer; do
      systemctl stop "$unit" >/dev/null 2>&1 || true
      systemctl disable "$unit" >/dev/null 2>&1 || true
      systemctl mask "$unit" >/dev/null 2>&1 || true
    done

    systemctl daemon-reload || true

    tc qdisc del dev "$iface" root 2>/dev/null || true
    tc qdisc del dev "$iface" ingress 2>/dev/null || true
    tc qdisc replace dev "$iface" root fq 2>/dev/null || true

    for ifb_dev in ifb0 ifb1; do
      tc qdisc del dev "$ifb_dev" root 2>/dev/null || true
      ip link set dev "$ifb_dev" down 2>/dev/null || true
    done

    return 0
  fi

  log "Legacy CAKE/shaping stack не найден, ничего чинить не нужно"
}

tune_kernel() {
  local swappiness_value=""
  local vfs_cache_pressure_value=""
  local netdev_budget_value=""
  local netdev_budget_usecs_value=""
  local dev_weight_value=""
  local nf_conntrack_max_value=""
  local rps_sock_flow_entries_value=""
  local tcp_keepalive_time_value=""
  local tcp_keepalive_intvl_value=""
  local tcp_keepalive_probes_value=""

  log "Настраиваю kernel baseline, BBR и лимиты"

  modprobe tcp_bbr || true

  swappiness_value="$(recommended_swappiness)"
  vfs_cache_pressure_value="$(recommended_vfs_cache_pressure)"
  netdev_budget_value="$(recommended_netdev_budget)"
  netdev_budget_usecs_value="$(recommended_netdev_budget_usecs)"
  dev_weight_value="$(recommended_dev_weight)"
  nf_conntrack_max_value="$(recommended_nf_conntrack_max)"
  rps_sock_flow_entries_value="$(recommended_rps_sock_flow_entries)"
  tcp_keepalive_time_value="$(recommended_tcp_keepalive_time)"
  tcp_keepalive_intvl_value="$(recommended_tcp_keepalive_intvl)"
  tcp_keepalive_probes_value="$(recommended_tcp_keepalive_probes)"

  cat > "$SYSCTL_FILE" <<EOF
fs.file-max = 1048576
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.core.somaxconn = 32768
net.core.dev_weight = ${dev_weight_value}
net.core.netdev_max_backlog = 16384
net.core.netdev_budget = ${netdev_budget_value}
net.core.netdev_budget_usecs = ${netdev_budget_usecs_value}
net.core.rps_sock_flow_entries = ${rps_sock_flow_entries_value}
net.core.rmem_default = 8388608
net.core.rmem_max = 67108864
net.core.wmem_default = 8388608
net.core.wmem_max = 67108864
net.core.optmem_max = 25165824
net.ipv4.ip_local_port_range = 10240 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = ${tcp_keepalive_time_value}
net.ipv4.tcp_keepalive_intvl = ${tcp_keepalive_intvl_value}
net.ipv4.tcp_keepalive_probes = ${tcp_keepalive_probes_value}
net.ipv4.tcp_max_syn_backlog = 32768
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_base_mss = 1024
net.ipv4.tcp_min_snd_mss = 536
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_rmem = 4096 131072 33554432
net.ipv4.tcp_wmem = 4096 16384 33554432
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.netfilter.nf_conntrack_max = ${nf_conntrack_max_value}
vm.swappiness = ${swappiness_value}
vm.vfs_cache_pressure = ${vfs_cache_pressure_value}
vm.page-cluster = 0
EOF

  printf "net.core.default_qdisc = fq\n" >> "$SYSCTL_FILE"

  cat > "$LIMITS_FILE" <<'EOF'
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF

  chmod 0644 "$SYSCTL_FILE" "$LIMITS_FILE"
  sysctl -p "$SYSCTL_FILE" >/dev/null || true
  systemctl enable --now irqbalance.service >/dev/null 2>&1 || true
}

write_rps_service() {
  log "Настраиваю adaptive RPS/RFS baseline под размер VPS"

  cat > "$RPS_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

iface="$(ip -o route show default | awk 'NR==1 {print $5}')"
cpus="$(nproc 2>/dev/null || echo 1)"

[[ -n "$iface" ]] || exit 0
[[ "$cpus" =~ ^[0-9]+$ ]] || cpus=1
if (( cpus < 1 )); then
  cpus=1
fi

if (( cpus <= 1 )); then
  rps_mask="0"
  rps_flow_cnt="0"
else
  if (( cpus >= 63 )); then
    cpus=63
  fi
  rps_mask="$(printf '%x' $(( (1 << cpus) - 1 )))"

  if (( cpus <= 2 )); then
    rps_flow_cnt="4096"
  elif (( cpus <= 4 )); then
    rps_flow_cnt="8192"
  elif (( cpus <= 8 )); then
    rps_flow_cnt="16384"
  else
    rps_flow_cnt="32768"
  fi
fi

for q in /sys/class/net/"$iface"/queues/rx-*; do
  [[ -d "$q" && -w "$q/rps_cpus" ]] || continue
  printf '%s\n' "$rps_mask" > "$q/rps_cpus" 2>/dev/null || true
  if [[ -w "$q/rps_flow_cnt" ]]; then
    printf '%s\n' "$rps_flow_cnt" > "$q/rps_flow_cnt" 2>/dev/null || true
  fi
done

for q in /sys/class/net/"$iface"/queues/tx-*; do
  [[ -d "$q" && -w "$q/xps_cpus" ]] || continue
  if (( cpus <= 1 )); then
    printf '1\n' > "$q/xps_cpus" 2>/dev/null || true
    continue
  fi

  q_index="${q##*-}"
  cpu_index=$(( q_index % cpus ))
  printf '%x\n' $(( 1 << cpu_index )) > "$q/xps_cpus" 2>/dev/null || true
done

exit 0
EOF

  chmod 0755 "$RPS_SCRIPT"

  cat > "$RPS_SERVICE" <<EOF
[Unit]
Description=Apply adaptive RPS/RFS tuning for RemnaNode
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$RPS_SCRIPT
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now remnanode-rps.service >/dev/null 2>&1 || true
}

write_qdisc_service() {
  log "Настраиваю persistent low-latency qdisc baseline"

  cat > "$QDISC_SERVICE" <<'EOF'
[Unit]
Description=Apply low-latency qdisc for RemnaNode
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'iface=$(ip -o route show default | awk "NR==1 {print \$5}"); [ -n "$iface" ] && /sbin/tc qdisc replace dev "$iface" root fq'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now remnanode-qdisc.service >/dev/null 2>&1 || true
}

write_offload_tune_service() {
  local offload_profile=""
  offload_profile="$(recommended_offload_profile)"

  log "Настраиваю adaptive offload-tuning для низкой задержки (${offload_profile})"

  cat > "$OFFLOAD_TUNE_SCRIPT" <<EOF
#!/usr/bin/env bash
set -euo pipefail

iface="\$(ip -o route show default | awk 'NR==1 {print \$5}')"
profile="${offload_profile}"

[[ -n "\$iface" ]] || exit 0
command -v ethtool >/dev/null 2>&1 || exit 0

case "\$profile" in
  throughput)
    ethtool -K "\$iface" gro on gso on tso on sg on rx-gro-hw on 2>/dev/null || true
    ;;
  latency-lite)
    ethtool -K "\$iface" gro off gso on tso on sg on rx-gro-hw off 2>/dev/null || true
    ;;
  *)
    ethtool -K "\$iface" gro on gso on tso on sg on rx-gro-hw off 2>/dev/null || true
    ;;
esac

exit 0
EOF

  chmod 0755 "$OFFLOAD_TUNE_SCRIPT"

  cat > "$OFFLOAD_TUNE_SERVICE" <<EOF
[Unit]
Description=Apply low-latency offload tuning for RemnaNode
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$OFFLOAD_TUNE_SCRIPT
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now remnanode-offload-tune.service >/dev/null 2>&1 || true
}

write_env_file() {
  log "Записываю .env для RemnaNode"

  cat > "$ENV_FILE" <<EOF
NODE_PORT=$NODE_PORT
APP_PORT=$NODE_PORT
NODE_IP=$NODE_IP
SECRET_KEY=$SECRET_VALUE
SSL_CERT=$SECRET_VALUE
EOF

  chmod 600 "$ENV_FILE"
}

write_compose() {
  log "Записываю рабочий docker-compose.yml для RemnaNode"

  if [[ -f "$COMPOSE_FILE" ]]; then
    cp "$COMPOSE_FILE" "$COMPOSE_FILE.bak.$(date +%F-%H%M%S)"
  fi

  cat > "$COMPOSE_FILE" <<EOF
services:
  remnanode:
    image: $NODE_IMAGE
    container_name: remnanode
    hostname: remnanode
    restart: always
    init: true
    network_mode: host
    stop_grace_period: 2m
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    env_file:
      - $ENV_FILE
    volumes:
      - /dev/shm:/dev/shm:rw
      - $LOG_DIR:/var/log/remnanode
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "5"
EOF
}

write_compose_override() {
  log "Добавляю docker-compose.override.yml для защитных override-файлов"

  cat > "$COMPOSE_OVERRIDE_FILE" <<EOF
services:
  remnanode:
    volumes:
      - $GENERATE_API_OVERRIDE:/opt/app/dist/src/common/utils/generate-api-config.js:ro
      - /etc/remnanode:/etc/remnanode:ro
      - $NODE_TLS_DIR:$XRAY_TLS_DIR_IN_CONTAINER:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - $NODE_STATE_DIR:$NODE_STATE_DIR_IN_CONTAINER
EOF
}

write_generate_api_override() {
  local xray_loglevel=""
  local xray_access_log=""
  local xray_sniff_profile=""
  local xray_sniff_route_only=""
  local xray_sniff_protocols_json=""

  xray_loglevel="$(resolved_xray_loglevel)"
  xray_access_log="$(resolved_xray_access_log)"
  xray_sniff_profile="$(resolved_xray_sniff_profile)"
  xray_sniff_route_only="$(resolved_xray_sniff_route_only "$xray_sniff_profile")"
  xray_sniff_protocols_json="$(resolved_xray_sniff_protocols_json "$xray_sniff_profile")"

  log "Записываю override generate-api-config.js с автоочисткой сиротских Unix-сокетов"
  log "Adaptive Xray profile: ${xray_sniff_profile} (loglevel=${xray_loglevel}, access=${xray_access_log}, sniff=${xray_sniff_protocols_json})"

  cat > "$GENERATE_API_OVERRIDE" <<'EOF'
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateApiConfig = void 0;
const fs = require("fs");
const sockdestroy_1 = require("sockdestroy");
const xray_1 = require("../../../libs/contract/constants/xray");
const constants_1 = require("../../../libs/contract/constants");
const generate_mtls_certs_1 = require("./generate-mtls-certs");
const get_initial_ports_1 = require("./get-initial-ports");

const BITTORRENT_RULE = {
    type: "field",
    protocol: ["bittorrent"],
    outboundTag: "BLOCK",
};

const SOCKET_DIR_PREFIX = "/dev/shm/";
const SOCKET_SUFFIXES = [".socket", ".sock"];
const ADAPTIVE_SNIFF_PROTOCOLS = __ADAPTIVE_SNIFF_PROTOCOLS__;
const ADAPTIVE_ROUTE_ONLY = __ADAPTIVE_ROUTE_ONLY__;

const ensureInboundSniffing = (inbound) => {
    if (!inbound || inbound.tag === "REMNAWAVE_API_INBOUND" || inbound.protocol === "dokodemo-door") {
        return inbound;
    }
    const sniffing = inbound.sniffing || {};
    const destOverride = Array.isArray(sniffing.destOverride)
        ? sniffing.destOverride.filter((value) => ADAPTIVE_SNIFF_PROTOCOLS.includes(value))
        : [];
    const mergedDestOverride = Array.from(new Set([...destOverride, ...ADAPTIVE_SNIFF_PROTOCOLS]));
    return {
        ...inbound,
        sniffing: {
            ...sniffing,
            enabled: true,
            routeOnly: ADAPTIVE_ROUTE_ONLY,
            destOverride: mergedDestOverride,
        },
    };
};

const normalizeUnixSocketPath = (value) => {
    if (typeof value !== "string") {
        return null;
    }
    const trimmed = value.trim();
    if (!trimmed.startsWith(SOCKET_DIR_PREFIX)) {
        return null;
    }
    const candidate = trimmed.split(",", 1)[0];
    if (!candidate || !SOCKET_SUFFIXES.some((suffix) => candidate.endsWith(suffix))) {
        return null;
    }
    return candidate;
};

const collectUnixSocketPaths = (value, found = new Set()) => {
    if (Array.isArray(value)) {
        for (const item of value) {
            collectUnixSocketPaths(item, found);
        }
        return found;
    }
    if (value && typeof value === "object") {
        for (const nestedValue of Object.values(value)) {
            collectUnixSocketPaths(nestedValue, found);
        }
        return found;
    }
    const socketPath = normalizeUnixSocketPath(value);
    if (socketPath) {
        found.add(socketPath);
    }
    return found;
};

const getActiveUnixSocketPaths = () => {
    try {
        const unixTable = fs.readFileSync("/proc/net/unix", "utf8");
        const activePaths = new Set();
        for (const line of unixTable.split("\n").slice(1)) {
            const trimmedLine = line.trim();
            if (!trimmedLine) {
                continue;
            }
            const fields = trimmedLine.split(/\s+/);
            const maybePath = fields[fields.length - 1];
            if (maybePath && maybePath.startsWith("/")) {
                activePaths.add(maybePath);
            }
        }
        return activePaths;
    }
    catch (error) {
        console.warn(`[RemnaPatch] Failed to read /proc/net/unix: ${error?.message || error}`);
        return new Set();
    }
};

const cleanupStaleUnixSocketPath = (socketPath, activePaths) => {
    if (activePaths.has(socketPath)) {
        return;
    }
    const lockPath = `${socketPath}.lock`;
    try {
        const stat = fs.lstatSync(socketPath);
        if (stat.isSocket()) {
            fs.rmSync(socketPath, { force: true });
            console.warn(`[RemnaPatch] Removed stale Unix socket: ${socketPath}`);
        }
    }
    catch (error) {
        if (error?.code !== "ENOENT") {
            console.warn(`[RemnaPatch] Failed to inspect ${socketPath}: ${error?.message || error}`);
            return;
        }
    }
    try {
        if (fs.existsSync(lockPath)) {
            fs.rmSync(lockPath, { force: true });
            console.warn(`[RemnaPatch] Removed stale socket lock: ${lockPath}`);
        }
    }
    catch (error) {
        if (error?.code !== "ENOENT") {
            console.warn(`[RemnaPatch] Failed to remove lock ${lockPath}: ${error?.message || error}`);
        }
    }
};

const cleanupStaleUnixSockets = (config) => {
    const socketPaths = collectUnixSocketPaths(config);
    if (socketPaths.size === 0) {
        return;
    }
    const activePaths = getActiveUnixSocketPaths();
    for (const socketPath of socketPaths) {
        cleanupStaleUnixSocketPath(socketPath, activePaths);
    }
};

const generateApiConfig = (args) => {
    const { config, torrentBlockerState, internal } = args;
    const policyConfig = config.policy;
    const serverCerts = (0, generate_mtls_certs_1.getServerCerts)();
    const hasCapNetAdminResult = (0, sockdestroy_1.hasCapNetAdmin)();

    const builtPolicy = {
        levels: {
            '0': {
                ...(policyConfig?.levels?.['0'] || {}),
                statsUserUplink: xray_1.XRAY_DEFAULT_POLICY_MODEL.policy.levels['0'].statsUserUplink,
                statsUserDownlink: xray_1.XRAY_DEFAULT_POLICY_MODEL.policy.levels['0'].statsUserDownlink,
                statsUserOnline: hasCapNetAdminResult,
            },
        },
        system: xray_1.XRAY_DEFAULT_POLICY_MODEL.policy.system,
    };

    const configInbounds = Array.isArray(config.inbounds) ? config.inbounds : [];
    const userInbounds = configInbounds.map(ensureInboundSniffing);
    const existingRoutingRules = Array.isArray(config.routing?.rules) ? config.routing.rules : [];
    const hasBittorrentRule = existingRoutingRules.some((rule) => {
        if (!rule || !Array.isArray(rule.protocol)) {
            return false;
        }
        return rule.protocol.includes("bittorrent");
    });
    const shouldAddLegacyBittorrentRule = !torrentBlockerState?.enabled && !hasBittorrentRule;

    const result = {
        ...config,
        log: {
            ...(config.log || {}),
            access: "__XRAY_ACCESS_LOG__",
            error: "/dev/stderr",
            loglevel: "__XRAY_LOGLEVEL__",
        },
        ...xray_1.XRAY_DEFAULT_STATS_MODEL,
        ...xray_1.XRAY_DEFAULT_API_MODEL,
        inbounds: [
            (0, xray_1.XRAY_API_INBOUND_MODEL)({
                port: (0, get_initial_ports_1.getXtlsApiPort)(),
                caCertPem: serverCerts.caCertPem,
                serverCertPem: serverCerts.serverCertPem,
                serverKeyPem: serverCerts.serverKeyPem,
            }),
            ...userInbounds,
        ],
        outbounds: [...(Array.isArray(config.outbounds) ? config.outbounds : [])],
        policy: builtPolicy,
        routing: {
            ...(config.routing || {}),
            rules: [
                xray_1.XRAY_ROUTING_RULES_MODEL,
                ...(shouldAddLegacyBittorrentRule ? [BITTORRENT_RULE] : []),
                ...existingRoutingRules,
            ],
        },
    };

    cleanupStaleUnixSockets(result);

    if (torrentBlockerState?.enabled) {
        const webhookUrl = buildWebhookUrl(internal);
        const routing = result.routing;
        result.outbounds.push(xray_1.XRAY_TORRENT_BLOCKER_OUTBOUND_MODEL);
        routing.rules.splice(1, 0, (0, xray_1.XRAY_TORRENT_BLOCKER_ROUTING_RULES_MODEL)({ webhookUrl }));
        if (torrentBlockerState.includeRuleTags.size > 0) {
            for (const rule of routing.rules) {
                if (rule.ruleTag &&
                    typeof rule.ruleTag === 'string' &&
                    torrentBlockerState.includeRuleTags.has(rule.ruleTag)) {
                    rule.webhook = {
                        url: webhookUrl,
                        deduplication: 5,
                    };
                }
            }
        }
    }

    return result;
};
exports.generateApiConfig = generateApiConfig;
const buildWebhookUrl = (internal) => {
    return `/${internal.socketPath}:${constants_1.XRAY_INTERNAL_FULL_WEBHOOK_PATH}?token=${internal.token}`;
};
EOF

  python3 - "$GENERATE_API_OVERRIDE" "$xray_loglevel" "$xray_access_log" "$xray_sniff_route_only" "$xray_sniff_protocols_json" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
replacements = {
    "__XRAY_LOGLEVEL__": sys.argv[2],
    "__XRAY_ACCESS_LOG__": sys.argv[3],
    "__ADAPTIVE_ROUTE_ONLY__": sys.argv[4],
    "__ADAPTIVE_SNIFF_PROTOCOLS__": sys.argv[5],
}
for key, value in replacements.items():
    text = text.replace(key, value)
path.write_text(text)
PY

  chmod 0644 "$GENERATE_API_OVERRIDE"
}

write_xray_service_override() {
  log "Удаляю устаревший xray.service.js override; используется штатная реализация из $NODE_IMAGE"
  rm -f "$XRAY_SERVICE_OVERRIDE"
  return 0

  cat > "$XRAY_SERVICE_OVERRIDE" <<'EOF'
"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") {
        r = Reflect.decorate(decorators, target, key, desc);
    }
    else {
        for (var i = decorators.length - 1; i >= 0; i--) {
            if (d = decorators[i]) {
                r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
            }
        }
    }
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") {
        return Reflect.metadata(k, v);
    }
};
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); };
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.XrayService = void 0;
const node_child_process_1 = require("node:child_process");
const node_util_1 = require("node:util");
const node_fs_promises_1 = require("node:fs/promises");
const enhanced_ms_1 = __importDefault(require("enhanced-ms"));
const p_retry_1 = __importDefault(require("p-retry"));
const semver_1 = __importDefault(require("semver"));
const common_1 = require("@nestjs/common");
const cqrs_1 = require("@nestjs/cqrs");
const config_1 = require("@nestjs/config");
const xtls_sdk_nestjs_1 = require("@remnawave/xtls-sdk-nestjs");
const xtls_sdk_1 = require("@remnawave/xtls-sdk");
const get_system_stats_1 = require("../../common/utils/get-system-stats");
const generate_api_config_1 = require("../../common/utils/generate-api-config");
const constants_1 = require("../../libs/contracts/constants");
const models_1 = require("./models");
const get_interface_stats_query_1 = require("../network-stats/queries/get-interface-stats/get-interface-stats.query");
const reset_plugins_command_1 = require("../_plugin/commands/reset-plugins/reset-plugins.command");
const get_torrent_blocker_state_1 = require("../_plugin/queries/get-torrent-blocker-state");
const internal_service_1 = require("../internal/internal.service");
const xray_process_service_1 = require("./xray-process.service");
const XRAY_LOG_FILE = "/var/log/xray/current";
const XRAY_STATE_DIR = "/var/lib/remnanode-state";
const LAST_START_XRAY_FILE = `${XRAY_STATE_DIR}/last-start-xray.json`;
const PERSISTED_RECOVERY_IP = "persisted-recovery";
const PERSISTED_RECOVERY_DELAY_MS = 5000;
const execFileAsync = (0, node_util_1.promisify)(node_child_process_1.execFile);
let XrayService = class XrayService {
    constructor(xtlsSdk, xrayProcess, internalService, configService, queryBus, commandBus) {
        this.xtlsSdk = xtlsSdk;
        this.xrayProcess = xrayProcess;
        this.internalService = internalService;
        this.configService = configService;
        this.queryBus = queryBus;
        this.commandBus = commandBus;
        this.logger = new common_1.Logger(XrayService.name);
        this.xrayVersion = null;
        this.isXrayOnline = false;
        this.isXrayStartedProccesing = false;
        this.nodeVersion = "0.0.0";
        this.internal = {
            socketPath: this.configService.getOrThrow("INTERNAL_SOCKET_PATH"),
            token: this.configService.getOrThrow("INTERNAL_REST_TOKEN"),
            xtlsApiSocketPath: this.configService.getOrThrow("XTLS_API_SOCKET_PATH"),
        };
        this.xrayPath = "/usr/local/bin/xray";
        this.xrayVersion = null;
        this.isXrayStartedProccesing = false;
        this.disableHashedSetCheck = this.configService.getOrThrow("DISABLE_HASHED_SET_CHECK");
    }
    async onApplicationBootstrap() {
        try {
            this.xrayVersion = this.getXrayVersionFromEnv();
            this.nodeVersion = process.env.RWNODE_VERSION || "0.0.0";
            if (!this.xrayProcess.isControlAvailable()) {
                this.logger.error("s6 xray control socket not found, exiting...");
                process.exit(1);
            }
        }
        catch (error) {
            this.logger.error(`Error in Application Bootstrap: ${error}`);
        }
        this.isXrayOnline = false;
        setTimeout(() => {
            this.restorePersistedXrayState().catch((error) => {
                const message = error instanceof Error ? error.message : String(error);
                this.logger.error(`Persisted Xray recovery failed: ${message}`);
            });
        }, PERSISTED_RECOVERY_DELAY_MS);
    }
    async startXray(body, ip) {
        const interfaceStats = await this.queryBus.execute(new get_interface_stats_query_1.GetInterfaceStatsQuery());
        const tm = performance.now();
        const system = {
            info: (0, get_system_stats_1.getSystemInfo)(),
            stats: (0, get_system_stats_1.getSystemStats)(),
            interface: interfaceStats,
        };
        if (this.isXrayStartedProccesing) {
            this.logger.warn("Request already in progress");
            return {
                isOk: true,
                response: new models_1.StartXrayResponseModel(false, this.xrayVersion, "Request already in progress", {
                    version: this.nodeVersion,
                }, system),
            };
        }
        this.isXrayStartedProccesing = true;
        try {
            if (this.isXrayOnline && !this.disableHashedSetCheck && !(body === null || body === void 0 ? void 0 : body.internals.forceRestart)) {
                const { isOk } = await this.xtlsSdk.stats.getSysStats();
                let shouldRestart = false;
                if (isOk) {
                    shouldRestart = this.internalService.isNeedRestartCore(body.internals.hashes);
                }
                else {
                    this.isXrayOnline = false;
                    shouldRestart = true;
                    this.logger.warn("Xray Core health check failed, restarting...");
                }
                if (!shouldRestart) {
                    await this.persistLastStartXrayBody(body, "reused-running-config");
                    return {
                        isOk: true,
                        response: new models_1.StartXrayResponseModel(true, this.xrayVersion, null, {
                            version: this.nodeVersion,
                        }, system),
                    };
                }
            }
            if (body === null || body === void 0 ? void 0 : body.internals.forceRestart) {
                this.logger.warn("Force restart requested");
            }
            const isTorrentBlockerEnabled = await this.queryBus.execute(new get_torrent_blocker_state_1.GetTorrentBlockerStateQuery());
            const fullConfig = (0, generate_api_config_1.generateApiConfig)({
                config: body.xrayConfig,
                torrentBlockerState: isTorrentBlockerEnabled,
                internal: this.internal,
            });
            await this.internalService.extractUsersFromConfig(body.internals.hashes, fullConfig);
            const xrayProcess = await this.restartXrayProcess();
            if (xrayProcess.error) {
                this.logger.error(`Failed to (re)start Xray process via s6: ${xrayProcess.error}`);
                return {
                    isOk: true,
                    response: new models_1.StartXrayResponseModel(false, null, xrayProcess.error, { version: this.nodeVersion }, system),
                };
            }
            const isStarted = await this.getXrayInternalStatus();
            if (!isStarted) {
                this.isXrayOnline = false;
                this.logger.error(`Xray Core v${this.xrayVersion} failed to start.`, {
                    timestamp: new Date().toISOString(),
                    ...constants_1.KNOWN_ERRORS.XRAY_FAILED_TO_START,
                });
                await this.dumpTailBlock(XRAY_LOG_FILE, 5);
                return {
                    isOk: true,
                    response: new models_1.StartXrayResponseModel(isStarted, this.xrayVersion, "Xray Core did not become ready in time", {
                        version: this.nodeVersion,
                    }, system),
                };
            }
            this.isXrayOnline = true;
            await this.persistLastStartXrayBody(body, "xray-started");
            this.logger.log(`✔ XRay Core v${this.xrayVersion} is up and running.`);
            return {
                isOk: true,
                response: new models_1.StartXrayResponseModel(isStarted, this.xrayVersion, null, {
                    version: this.nodeVersion,
                }, system),
            };
        }
        catch (error) {
            let errorMessage = null;
            if (error instanceof Error) {
                errorMessage = error.message;
            }
            this.logger.error(`Failed to start Xray: ${errorMessage}`);
            return {
                isOk: true,
                response: new models_1.StartXrayResponseModel(false, null, errorMessage, {
                    version: this.nodeVersion,
                }, system),
            };
        }
        finally {
            this.logger.log(`Attempt to start XTLS took: ${(0, enhanced_ms_1.default)(performance.now() - tm, {
                extends: "short",
                includeMs: true,
            })} (IP: ${ip})`);
            this.isXrayStartedProccesing = false;
        }
    }
    async stopXray(args) {
        const { withPluginCleanup = false, withOnlineCheck = false } = args;
        try {
            if (withPluginCleanup) {
                await this.commandBus.execute(new reset_plugins_command_1.ResetPluginsCommand());
            }
            if (withOnlineCheck && !this.isXrayOnline) {
                await this.clearPersistedXrayState();
                return {
                    isOk: true,
                    response: new models_1.StopXrayResponseModel(true),
                };
            }
            await this.killAllXrayProcesses();
            this.isXrayOnline = false;
            this.internalService.cleanup();
            await this.clearPersistedXrayState();
            return {
                isOk: true,
                response: new models_1.StopXrayResponseModel(true),
            };
        }
        catch (error) {
            this.logger.error(`Failed to stop Xray Process: ${error}`);
            return {
                isOk: true,
                response: new models_1.StopXrayResponseModel(false),
            };
        }
    }
    async getNodeHealthCheck() {
        try {
            return {
                isOk: true,
                response: new models_1.GetNodeHealthCheckResponseModel(true, this.isXrayOnline, this.xrayVersion, this.nodeVersion),
            };
        }
        catch (error) {
            this.logger.error(`Failed to get node health check: ${error}`);
            return {
                isOk: true,
                response: new models_1.GetNodeHealthCheckResponseModel(false, false, null, this.nodeVersion),
            };
        }
    }
    async killAllXrayProcesses() {
        try {
            await this.xrayProcess.stop();
            this.logger.log("s6: Xray process stopped.");
        }
        catch (error) {
            this.logger.log(`s6: Failed to stop Xray process. Error: ${error}`);
        }
    }
    getXrayVersionFromEnv() {
        const version = semver_1.default.valid(semver_1.default.coerce(process.env.XRAY_CORE_VERSION));
        if (version) {
            this.xrayVersion = version;
        }
        return version;
    }
    getXrayInfo() {
        const version = this.getXrayVersionFromEnv();
        if (version) {
            this.xrayVersion = version;
        }
        return {
            version: version,
            path: this.xrayPath,
        };
    }
    async getXrayInternalStatus() {
        const tm = performance.now();
        try {
            return await (0, p_retry_1.default)(async () => {
                const { isOk, message } = await this.xtlsSdk.stats.getSysStats();
                if (!isOk) {
                    throw new Error(message);
                }
                return true;
            }, {
                retries: 30,
                minTimeout: 100,
                maxTimeout: 2000,
                factor: 1.5,
                onFailedAttempt: (context) => {
                    this.logger.warn(`▸ XRay Core status check, ${context.attemptNumber}/${context.attemptNumber + context.retriesLeft} · elapsed ${(0, enhanced_ms_1.default)(performance.now() - tm, {
                        extends: "short",
                        includeMs: true,
                    })} · retrying in ${context.retryDelay}ms`);
                },
            });
        }
        catch (error) {
            this.logger.error(`Failed to get Xray internal status: ${error}`);
            return false;
        }
    }
    async restartXrayProcess() {
        try {
            await this.xrayProcess.restart();
            return { error: null };
        }
        catch (error) {
            return {
                error: error instanceof Error ? error.message : "Unknown error",
            };
        }
    }
    async tailLogLines(path, n = 10) {
        try {
            const { stdout } = await execFileAsync("tail", ["-n", String(n), path]);
            return stdout.split("\n").filter(Boolean);
        }
        catch {
            return [];
        }
    }
    async dumpTailBlock(path, lines) {
        const tail = await this.tailLogLines(path, lines);
        if (tail.length === 0) {
            return;
        }
        this.logger.error([
            "Xray Core Log Tail",
            `${"─".repeat(8)} ${path} (${tail.length} lines) ${"─".repeat(8)}`,
            ...tail.map((line) => `│ ${line}`),
        ].join("\n"));
    }
    isPersistableStartBody(body) {
        return Boolean(body &&
            typeof body === "object" &&
            body.xrayConfig &&
            body.internals &&
            Array.isArray(body.internals.hashes));
    }
    async persistLastStartXrayBody(body, reason) {
        try {
            if (!this.isPersistableStartBody(body)) {
                return;
            }
            await (0, node_fs_promises_1.mkdir)(XRAY_STATE_DIR, { recursive: true, mode: 0o700 });
            const payload = {
                savedAt: new Date().toISOString(),
                reason,
                body,
            };
            await (0, node_fs_promises_1.writeFile)(LAST_START_XRAY_FILE, JSON.stringify(payload), {
                encoding: "utf8",
                mode: 0o600,
            });
        }
        catch (error) {
            const message = error instanceof Error ? error.message : String(error);
            this.logger.warn(`Failed to persist Xray start payload: ${message}`);
        }
    }
    async readPersistedXrayBody() {
        try {
            const raw = await (0, node_fs_promises_1.readFile)(LAST_START_XRAY_FILE, "utf8");
            const parsed = JSON.parse(raw);
            const body = (parsed === null || parsed === void 0 ? void 0 : parsed.body) || parsed;
            if (!this.isPersistableStartBody(body)) {
                this.logger.warn("Persisted Xray payload is invalid, skipping bootstrap recovery.");
                return null;
            }
            return body;
        }
        catch (error) {
            if (error && typeof error === "object" && error.code === "ENOENT") {
                return null;
            }
            const message = error instanceof Error ? error.message : String(error);
            this.logger.warn(`Failed to read persisted Xray payload: ${message}`);
            return null;
        }
    }
    async clearPersistedXrayState() {
        try {
            await (0, node_fs_promises_1.unlink)(LAST_START_XRAY_FILE);
        }
        catch (error) {
            if (error && typeof error === "object" && error.code === "ENOENT") {
                return;
            }
            const message = error instanceof Error ? error.message : String(error);
            this.logger.warn(`Failed to clear persisted Xray payload: ${message}`);
        }
    }
    async probeXrayInternalStatusOnce() {
        try {
            const { isOk } = await this.xtlsSdk.stats.getSysStats();
            return Boolean(isOk);
        }
        catch {
            return false;
        }
    }
    async restorePersistedXrayState() {
        if (this.isXrayStartedProccesing || this.isXrayOnline) {
            return;
        }
        const cachedBody = await this.readPersistedXrayBody();
        if (!cachedBody) {
            this.logger.log("No persisted Xray payload found, bootstrap recovery skipped.");
            return;
        }
        const alreadyOnline = await this.probeXrayInternalStatusOnce();
        if (alreadyOnline) {
            this.isXrayOnline = true;
            this.logger.log("Xray already online, bootstrap recovery skipped.");
            return;
        }
        const cachedHashes = Array.isArray(cachedBody === null || cachedBody === void 0 ? void 0 : cachedBody.internals.hashes) ? cachedBody.internals.hashes.length : 0;
        this.logger.warn(`Xray is offline after bootstrap, replaying persisted start payload (${cachedHashes} hashes).`);
        const response = await this.startXray(cachedBody, PERSISTED_RECOVERY_IP);
        if (response === null || response === void 0 ? void 0 : response.response.isStarted) {
            this.logger.log("Persisted Xray recovery completed successfully.");
            return;
        }
        const message = (response === null || response === void 0 ? void 0 : response.response.message) || "Unknown persisted recovery error";
        this.logger.error(`Persisted Xray recovery did not start core: ${message}`);
    }
};
exports.XrayService = XrayService;
exports.XrayService = XrayService = __decorate([
    (0, common_1.Injectable)(),
    __param(0, (0, xtls_sdk_nestjs_1.InjectXtls)()),
    __metadata("design:paramtypes", [xtls_sdk_1.XtlsApi,
        xray_process_service_1.XrayProcessService,
        internal_service_1.InternalService,
        config_1.ConfigService,
        cqrs_1.QueryBus,
        cqrs_1.CommandBus])
], XrayService);
EOF

  chmod 0644 "$XRAY_SERVICE_OVERRIDE"
}

write_stats_service_override() {
  log "Удаляю устаревший stats.service.js override; используется штатная статистика из $NODE_IMAGE"
  rm -f "$STATS_SERVICE_OVERRIDE"
  return 0

  base64 -d <<'EOF' | gzip -dc > "$STATS_SERVICE_OVERRIDE"
H4sIABZsGWoC/+Uc/XObOPb3/BVa304NVwcn0+7MntM017TpjmfaZjdO5/Ym9bgY5IQNBhaJpLms//d7+gIEApPUbXO9TGtj6X3p6b2npyeglxGMCE0Dj/b2
tq7cFM1mPvbi1KUY7SOLXgQEPXqE2LdTdNnor7/QIos8GsQRsmRznJIBom56jukAXeKbAfIx8Wx0u4XgjxH3gCb0Z0scUeKEODqnFwOUQquHnqEn6ECioxFH
Rfv7+yjKwhA6xG90PP8De9QBmOPr6Nc0TnBKb15BXxokIIBVYm9LKiDGHpcgWMCAbhIcL9AJXoRAhzPoxZxmj49T63YKVTA4NeCezUWuAq1Rg5ABh6DwRZwi
i+kjADIFllQI2ka7e9D1fB/twPf2ts0l9zXYs2AqpLCU5nwrZSP20HP5UxOB92ltNp/EVIiVYpqlkUQGPaTsQ+rax4sgwkrXVbIDRmKlbGeJqeu71DXYjuqq
2M7lAF0pE7n7BBX8qhMkBlSFE+xKAidu6i4N0vL2iqi8bRz5+NOgmAklu2RYQGuWeFsg6AosaNp7aFXIFSyTOKWv8MLNQmqQT+uvyLmM/YpUrIkhwxfgYvI2
9rMQvPiAtYBh3KKeL0j1RrxplatoQl1KJji9Cjw8293bMhsF/sTEAbvvFeR7A6B75YYZHiGaZhitQPES0CmTheFdxYEP1r7lxRGhKJkt3WS2C+2VgVop/jML
Umz1km0A6dm2QvEugtCfJWnsYUI4ag6qdfUKjHi5jCMd9J8RJvQPMhR9Jdg/U9IACT0F3CcakhnxL2eit4KS4mXkXrtXeMjgtgFuW8AZCKzDLFDAlmbkhlC8
nBGmVB3VcYbwT4xnmNEgJENA2BYI2xyhrBL4dCMzDfgXBnOmm4imrkeHOXRBAEwHAlwFeyhadYmDiOJ04YJNCaH/zHB6U2MbYXodp5dCziGDCbAYQI4v+wxt
DqepswX/S2Htmc3D2LvE6SzF3BxnXpxBa5X9LAmz8yDSGEsK25LCtqSwzSkUzLgskRvOiHKdCm0FkF84EpLRCGEJrHiI7odsxQxdQnQo4fPMRCb+pQjsXAeH
GZEroOQlEUTjwg3DuetdHkchuPQkchNyEbOYw1beNpCjTwmMhrxgsDttgBAmlgHBGkmupjTzWESUEg9yaQdVSVU8Y388AkoUIKkNN+9XlABAV0EOUeEAgEbt
rPhnGJ+fY7bcRvg6jxzOG95q6VPjRO4Sy9XeJTeRxwzvZRwtgvMsxf7hPD1auuCHVnlMuf8BFMuRrt2AGsVkmc/vqXsjCFr2XoUE5rSloBNMyxA87VDmOQd7
9REspYLpgSObCDo4QGfTsnBqaZYQBw7EUhp7cYh+gFW3f8FiSRq4/SqOlIoGUYb3tJ7VVgWGDT4MWFbI50HyIZgC8jk5cGTnXk2mH16koA0nIPzbknD2fUUp
qUiQ4hqSRA00mQii+8DhqjcB8byPz4vj+j6YSwqDkmgSy96rYa0axCyu5OIuNLAAH7MEF7tsucIE5xmsgWB6r6V/Ks/UjJCmNxXpKzZVMssmm67PkBy5zG1Z
nrZjUpIczC2Keeh4D9GQjMAQByhjl/8K6MU44S0sOVlnTCUiudzWzkBlFo7Mdmwp3UCqyZJzuP/cIGFdPTpPCIUJXGBdUTI8OWJJArUxoWR4hKaMSJ57Rsrc
xBVhsPLjS5bqFS0spz1wxGibTK+k3SL8tltbBY1LuM5CuSJc6l00iNEqQsXYWeYISvUyttZ6NyP0ZGeHp491rS+CEKIP9o+1GS/NvyMgrMM4DrEbGSzUQGKt
ueYBmydDl4ovn3LubC9Vl3I5DmIZ5pnHEI2Q4v7czLvsLo0zrrlRhTz4gGUxt+KWzi5kGBo0ktOdUKdnxlp1MZjNen0Zp93tDVO+kRhwiwJgvWoLAal7/VKE
fggGPHUQQoyTNwGhVvOMsrxihD6yQT5//vzHWy7nCi6F7j4OWrwfVtIRS84Ibpishviz1sy4EM2cAzZ5cssIQ2ZZtMU0BDnG7coWhngWJAMEySydYBxNueIt
pseiEcSzP8PIOkSlWzkQIXDd2rrEqF1DjGrUn2bvJmvcavfA8i8V4SouDUMpBxKdYml8xbiEoiycpkVdQ8uZRRrsXLtpZH08PDzJ8305HgSZ4RxDaxBif4TA
Rhmp1Udj5P7s4NlNufePfd1jXk2b4hMc/E3sueE4uXpKOqVacUaTjNd7IGpVahoO/oS916DZCYQp2+oPyRz2pkHSH6Cz/nYMX/3tp+wTksyUfUOCd82/vTjB
7OI8jOdu2J8y0wWbjX3IQ0eon9HFz/0m01X7CCFZTUcOScKAWv0PUd+ud3Jli9wElM0uHIgBS8uWaMMP5PHQPnsyNeBWlu0G4l7gi5lkF0qYYd8+25mWk+r7
2vhrbsmIxmwuYRcIk4nGv149hbGw3AN2C7lZ5L7QbPcVldpmq+EeAHNMLzANPGZtY/81ZPfjxGJBMeDFwg62FCTvMlbaDBKlF6dvOxBmMg9blut5vPpIRcCF
n+jZM/RzZKPH6DA4H0fUAvQ5zAAHsgdoJzIPx/rHjv4XAQnO3HZoLHc7LXNx25molEtooI14SZFNoaSDAkPhu3loqrhzPZFUCA4J/oPXbnXOph32MXeJBxlJ
RUzIbVKEhjc8NLA40c/8pKP7y0osButLGuoJlQ0zXwBguyxkLgeG5gR6yS1gX4QG/gNiwpyk3r71YfLYhvDgE5pfE1Zq2//gP2bt/Prp0ycf5sOGpPoHTtBu
TtgM5YCGDIILezZAINkYfBCEGidTkJtzaOCeW8OFSyyOwev0WjOnZ29CRDlTvMIgqK63rii+nmC49NkEv3XphbMI4zi1XrkUO9AJXjJkac2O2fFLhQfJXWZ0
pTDFk7ktY9Y4Ki3468JdfXEWiZqeJ47KI1pNK2v0JtaDPJogLfvplvYY/H5Vq9RAkCnVaerBKp85mLJingqK/AyNyd1Q1n30iCM/Qy1AeWHXNgfnFlSTiteI
JKvDd+clEU0s12Np+aaxMqZJ44B5RpZFZK9he9im9H1EavpZg1Murpf88THa/WkGHmm0rDqTVWUUiyACbjeWdbcBmAr41W3jHeerYvO1qtg89m+6LNL3rbox
+g7L8Evl+rLB6kU3diRerrm1VTDNhTygIo5BBw37UEF9xBdadY7m/FKX/ERCvmUwliaVKgTWWbQWTxoFbxP6vgLzIsQmN6McQILtPfBxVYx+wk9heQ3I2qCt
A1lJ03BesqaYbDLs2jKoMAx5VwcnaClDOY5TOoN2jk5Ojk8mzusX4zdHr2anx7Nfjk5nk39PTo/ezianL04ndzT00tEsOybmStJ1qc4KeW6dUWwxI2g5r2Z2
Mdbo/cY6LNuYTZNivmVKXz+8d3S7sC0jJXnq/JIdOnccwZqjbzaSUwFyKCBOSjzMo9qwg5WG3RLkBg3GRTXhR62HIcXAGsqKBsNq4gs2W5pXM73cekYV6zPw
eRCxscFHP88/14VDnuyKyMUr1hsMiS/CsEb9ewyO7ydHJ5PPiI2uR4Or/BRNTy6y8mlapYSawWY/uuT3A+wwvfFGP76OimaDvkvcOh64LSpZeu1Qur53Mu/O
q4ScuH7413L8Vt8ZvidBdK7vCikO8RIzy2VVkh9vO/BcqUI6V/bH+57KrMs21yc6xBCGW+XnG//i6KzlHEuV1sV51poDJA7MjWuEdtvBlLmN0E4z4Mq+91HS
F0+aTTovucj/+sLQGJvWrQtjcT+QiN3UPR+gTS8PTRzuvkTUW9SNVffcMn7mgjB+d3j8/t2rey0JGzbxspJ1I28Yv4AfIaM61bdZNUUsMCOrfjO2CjhmXNH7
HWZuLbayzkWPM/qlfbSRxUacNJbUv42XHr8/fTBuqum5i58q1VX9RbXnF3dz1Rz9Pr6aI3+3ztpmMuu8FXZDMhh/ue2WicFmdlxfbdGcPAR3rKqyrfyrbuH+
ThaiyT1tW0WwL2fcRg6brycI3X/TgoIKMw/FF3TNt56FKMj/Z294GS/nsEX37+gJt1Jq9qmizwAxtY5UWk5esURqtYmFoM4zn2XFNJ/Mrly7emh5hNxBteHx
hrI8vEUT5tusUC+P3x6O3x09iIRRszHdI8vKzFengT6b34+jtk1Kl9q3vAM847fAdHFTDpmQjd5tXr3LXEjTepu5vL28bjfme8oCLnHlpnA5FHbTcvm2cBos
MQxkmUybqooAVWsr3Q8EtsrunrByQujv4o6mlpuDvlB5T6i84iDJZ1s9f8aKdZQejxe/WS29L56d77POvgc8+xDAUQ7PLxzWzqF/+sr3NZhUcja96/0L3+xu
gE7idzr1ku7YbW3mZwN3eMiELYdFpd66Nbul/sicut0zK4r7jDL3Qs4Pf+JPgReEx76AMB99Z2KUax7Lif+fHsdpdpqv/DTOd/Yczk/rHhVUNq5sstvzM83P
DT6MA0ztiaANnWCOf11/iGng+3BOMU0RunUED/dw0DiUsgU++ERigx7wBXOSjdjMBvKVDWnrq5niHTTUkBKZUgpYnsumJEcDrer5Elhw+/bZ7lTdVbxqfMdQ
+WcnINNbV4p3oFlnnCN/MEe9EGQcMR9x5yG2LTlm+SopBsb+194QJHF+h3bAyZHyF1b1fEyC82jEqTCvJL0BOiveE+QwzBdJUGhYvKzI+U29S2VLuwtNeyeN
M9bfLjK1t6YDbdBgTcPh3xCJs9TDb90kgTXi/cmbfZE8SULOHzxF3PovkN6Yc05OAAA=
EOF

  python3 - "$STATS_SERVICE_OVERRIDE" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()

replacements = [
    (
        re.compile(
            r"async buildBbrFallbackSnapshot\(\) \{.*?^\s+getLocalIpv4s\(\) \{",
            re.S | re.M,
        ),
        """async buildBbrFallbackSnapshot() {
        try {
            const conntrackUsers = this.buildConntrackFallbackUsers();
            return {
                onlineUsers: conntrackUsers.map((user) => user.email),
                usersWithIps: conntrackUsers,
            };
        }
        catch (error) {
            this.logger.warn(`BBR fallback online probe failed: ${error}`);
            return { onlineUsers: [], usersWithIps: [] };
        }
    }
    getLocalIpv4s() {""",
        "buildBbrFallbackSnapshot",
    ),
    (
        re.compile(
            r"const output = \(0, child_process_1\.execFileSync\)\('/usr/sbin/conntrack', \['-L', '-p', 'udp'\], \{ encoding: 'utf8' \}\);"
        ),
        "const output = (0, child_process_1.execFileSync)('/usr/sbin/conntrack', ['-L', '-p', 'udp', '--dport', '443'], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });",
        "conntrack command",
    ),
    (
        re.compile(
            r"if \(!localIps\.has\(dstIp\) \|\| localIps\.has\(srcIp\)\) \{\n\s+continue;\n\s+\}"
        ),
        """if (!line.includes('[ASSURED]') || !localIps.has(dstIp) || localIps.has(srcIp)) {
                    continue;
                }""",
        "conntrack assured filter",
    ),
    (
        re.compile(r"this\.fallbackOnlineSnapshotExpiresAt = Date\.now\(\) \+ 15_000;"),
        "this.fallbackOnlineSnapshotExpiresAt = Date.now() + 20_000;",
        "fallback cache TTL",
    ),
    (
        re.compile(
            r"async getUsersStats\(reset\) \{.*?^\s+async getInboundStats\(tag, reset\) \{",
            re.S | re.M,
        ),
        """async getUsersStats(reset) {
        const buildBbrFallbackUsers = async () => {
            const fallbackSnapshot = await this.getBbrFallbackUsers();
            return fallbackSnapshot.onlineUsers.map((email) => ({
                username: email,
                uplink: 1,
                downlink: 0,
            }));
        };
        const mergeActiveUsers = (activeUsers, fallbackUsers) => {
            if (fallbackUsers.length === 0) {
                return activeUsers;
            }
            const seen = new Set(activeUsers.map((user) => String(user.username)));
            const mergedUsers = [...activeUsers];
            for (const fallbackUser of fallbackUsers) {
                const username = String(fallbackUser.username);
                if (seen.has(username)) {
                    continue;
                }
                seen.add(username);
                mergedUsers.push(fallbackUser);
            }
            return mergedUsers;
        };
        try {
            const fallbackUsersPromise = buildBbrFallbackUsers();
            const response = await Promise.race([
                this.xtlsSdk.stats.getAllUsersStats(reset),
                new Promise((resolve) => setTimeout(() => resolve({ isOk: false, timeout: true }), 2000)),
            ]);
            const fallbackUsers = await fallbackUsersPromise;
            if (!response?.isOk || !response.data) {
                if (fallbackUsers.length > 0) {
                    const suffix = response?.timeout ? ' (after Xray stats timeout)' : ' (after stats failure)';
                    this.logger.warn(`Using BBR fallback telemetry${suffix} for ${fallbackUsers.length} online users`);
                    return {
                        isOk: true,
                        response: new models_1.GetUsersStatsResponseModel(fallbackUsers),
                    };
                }
                if (response?.timeout) {
                    this.logger.warn('Xray user stats timed out and no BBR fallback users were available');
                }
                else {
                    this.logger.warn(response);
                }
                return {
                    isOk: false,
                    ...constants_1.ERRORS.FAILED_TO_GET_USERS_STATS,
                };
            }
            const activeUsers = response.data.users.filter((user) => user.uplink !== 0 || user.downlink !== 0);
            const mergedUsers = mergeActiveUsers(activeUsers, fallbackUsers);
            if (fallbackUsers.length > 0) {
                this.logger.warn(`Merged ${fallbackUsers.length} BBR fallback users with ${activeUsers.length} Xray active users`);
            }
            return {
                isOk: true,
                response: new models_1.GetUsersStatsResponseModel(mergedUsers),
            };
        }
        catch (error) {
            this.logger.error(error);
            const fallbackUsers = await buildBbrFallbackUsers();
            if (fallbackUsers.length > 0) {
                this.logger.warn(`Using BBR fallback telemetry (after exception) for ${fallbackUsers.length} online users`);
                return {
                    isOk: true,
                    response: new models_1.GetUsersStatsResponseModel(fallbackUsers),
                };
            }
            return {
                isOk: false,
                ...constants_1.ERRORS.FAILED_TO_GET_USERS_STATS,
            };
        }
    }
    async getInboundStats(tag, reset) {""",
        "getUsersStats",
    ),
    (
        re.compile(
            r"async getUsersIpList\(\) \{.*?^\s+extractOnlineUserId\(raw\) \{",
            re.S | re.M,
        ),
        """async getUsersIpList() {
        try {
            const fallbackSnapshotPromise = this.getBbrFallbackUsers();
            const onlineUsersResponse = await Promise.race([
                this.xtlsSdk.stats.rawClient.getAllOnlineUsers({}),
                new Promise((resolve) => setTimeout(() => resolve({ timeout: true, users: [] }), 2000)),
            ]);
            if (onlineUsersResponse?.timeout) {
                const fallbackSnapshot = await fallbackSnapshotPromise;
                this.logger.warn(`Using BBR fallback IP telemetry after Xray online user list timeout for ${fallbackSnapshot.usersWithIps.length} online users`);
                return {
                    isOk: true,
                    response: new models_1.GetUsersIpListResponseModel(fallbackSnapshot.usersWithIps),
                };
            }
            const { users } = onlineUsersResponse;
            const onlineUsers = new Set(users.map((stat) => this.extractOnlineUserId(stat)));
            const usersIps = await (0, p_map_1.default)(onlineUsers, async (email) => {
                try {
                    const { ips } = await this.xtlsSdk.stats.rawClient.getStatsOnlineIpList({
                        name: `user>>>${email}>>>online`,
                        reset: true,
                    });
                    return {
                        email,
                        ips: Object.entries(ips).map(([ip, lastSeen]) => ({ ip, lastSeen })),
                    };
                }
                catch {
                    return { email, ips: [] };
                }
            }, { concurrency: 50 });
            const filteredUsers = usersIps.filter((user) => user.ips.length > 0);
            if (filteredUsers.length === 0) {
                const fallbackSnapshot = await fallbackSnapshotPromise;
                if (fallbackSnapshot.usersWithIps.length > 0) {
                    this.logger.warn(`Using BBR fallback IP telemetry for ${fallbackSnapshot.usersWithIps.length} online users`);
                    return {
                        isOk: true,
                        response: new models_1.GetUsersIpListResponseModel(fallbackSnapshot.usersWithIps),
                    };
                }
            }
            return {
                isOk: true,
                response: new models_1.GetUsersIpListResponseModel(filteredUsers),
            };
        }
        catch (error) {
            this.logger.error(error);
            const fallbackSnapshot = await this.getBbrFallbackUsers();
            return {
                isOk: true,
                response: new models_1.GetUsersIpListResponseModel(fallbackSnapshot.usersWithIps),
            };
        }
    }
    extractOnlineUserId(raw) {""",
        "getUsersIpList",
    ),
]

for pattern, replacement, label in replacements:
    text, count = pattern.subn(replacement, text, count=1)
    if count != 1:
        raise SystemExit(f"failed to patch {label} in stats.service override")

path.write_text(text)
PY

  chmod 0644 "$STATS_SERVICE_OVERRIDE"
}

write_logrotate() {
  log "Настраиваю logrotate для логов RemnaNode"

  cat > "$LOGROTATE_FILE" <<'EOF'
/var/log/remnanode/*.log {
    size 50M
    rotate 5
    compress
    missingok
    notifempty
    copytruncate
}
EOF
}

write_compose_service() {
  local spamhaus_after=""
  local spamhaus_wants=""

  log "Создаю systemd unit для автоподъема ноды после reboot"

  if bool_is_true "$SPAMHAUS_EGRESS_GUARD"; then
    spamhaus_after=" remnanode-spamhaus-egress-guard.service"
    spamhaus_wants=" remnanode-spamhaus-egress-guard.service"
  fi

  cat > "$COMPOSE_SERVICE" <<EOF
[Unit]
Description=Remnawave node compose
Requires=docker.service
After=docker.service network-online.target node-mtu.service remnanode-firewall.service$spamhaus_after
Wants=network-online.target$spamhaus_wants

[Service]
Type=oneshot
WorkingDirectory=$NODE_ROOT
ExecStart=/usr/bin/docker compose -f $COMPOSE_FILE -f $COMPOSE_OVERRIDE_FILE up -d remnanode
ExecStop=/usr/bin/docker compose -f $COMPOSE_FILE -f $COMPOSE_OVERRIDE_FILE stop remnanode
RemainAfterExit=yes
TimeoutStartSec=0
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
EOF
}

write_watchdog() {
  log "Создаю smart-watchdog для auto-heal ноды"

  cat > "$WATCHDOG_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
LOCK_DIR=/run/remnanode-watchdog.lock
STATE_DIR=/var/lib/remnanode-watchdog
COOLDOWN_FILE="$STATE_DIR/last_restart_epoch"
COOLDOWN_SECONDS=__COOLDOWN_SECONDS__
CONTAINER_NAME=remnanode
HOST_PORT=2222
XRAY_API_PORT=61000
CHECK_TIMEOUT=12
STARTUP_GRACE_SECONDS=__STARTUP_GRACE_SECONDS__
SYSTEM_BOOT_GRACE_SECONDS=600

log() {
  logger -t remnanode-watchdog -- "$*"
  echo "$*"
}

run_with_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "${CHECK_TIMEOUT}s" "$@"
  else
    "$@"
  fi
}

restart_container() {
  local reason="$1"
  local now last=0
  now="$(date +%s)"
  mkdir -p "$STATE_DIR"
  if [[ -f "$COOLDOWN_FILE" ]]; then
    read -r last < "$COOLDOWN_FILE" || last=0
  fi
  if [[ "$last" =~ ^[0-9]+$ ]] && (( now - last < COOLDOWN_SECONDS )); then
    log "restart skipped due cooldown: ${reason}"
    return 0
  fi
  echo "$now" > "$COOLDOWN_FILE"
  log "restarting ${CONTAINER_NAME}: ${reason}"
  docker restart "$CONTAINER_NAME" >/dev/null
}

container_pid() {
  docker inspect -f '{{.State.Pid}}' "$CONTAINER_NAME" 2>/dev/null || true
}

container_nsenter() {
  local pid="$1"
  shift
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  (( pid > 1 )) || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  run_with_timeout nsenter -t "$pid" "$@"
}

host_port_listening() {
  ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq "(^|.*:|.*\\])${HOST_PORT}$"
}

container_tcp_port_listening() {
  local pid=""
  local port="$1"
  pid="$(container_pid)"
  container_nsenter "$pid" -n ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq "(^|.*:|.*\\])${port}$"
}

container_started_recently() {
  local started_at started_epoch now
  started_at="$(docker inspect -f '{{.State.StartedAt}}' "$CONTAINER_NAME" 2>/dev/null || true)"
  if [[ -z "$started_at" || "$started_at" == "0001-01-01T00:00:00Z" ]]; then
    return 1
  fi
  started_epoch="$(date -d "$started_at" +%s 2>/dev/null || true)"
  now="$(date +%s)"
  if [[ "$started_epoch" =~ ^[0-9]+$ ]] && (( now - started_epoch < STARTUP_GRACE_SECONDS )); then
    return 0
  fi
  return 1
}

system_booted_recently() {
  local uptime_seconds=0
  uptime_seconds="$(cut -d. -f1 /proc/uptime 2>/dev/null || echo 0)"
  [[ "$uptime_seconds" =~ ^[0-9]+$ ]] || return 1
  (( uptime_seconds < SYSTEM_BOOT_GRACE_SECONDS ))
}

cleanup_lock() {
  rmdir "$LOCK_DIR" >/dev/null 2>&1 || true
}

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  exit 0
fi
trap cleanup_lock EXIT

if ! command -v docker >/dev/null 2>&1; then
  log "docker not found"
  exit 0
fi

container_status="$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || true)"
if [[ "$container_status" != "running" ]]; then
  restart_container "container status=${container_status:-missing}"
  exit 0
fi

if container_started_recently; then
  log "startup grace active for ${CONTAINER_NAME}; skipping checks"
  exit 0
fi

if system_booted_recently; then
  log "system boot grace active for ${CONTAINER_NAME}; skipping checks"
  exit 0
fi

if ! host_port_listening; then
  restart_container "tcp port ${HOST_PORT} is not listening on host"
  exit 0
fi

if ! container_tcp_port_listening "$XRAY_API_PORT"; then
  restart_container "xray api port ${XRAY_API_PORT} is not listening inside container"
  exit 0
fi

exit 0
EOF

  python3 - "$(recommended_watchdog_cooldown_seconds)" "$(recommended_watchdog_startup_grace_seconds)" <<'PY'
from pathlib import Path
import sys

path = Path("/usr/local/sbin/remnanode-watchdog.sh")
text = path.read_text()
text = text.replace("__COOLDOWN_SECONDS__", sys.argv[1])
text = text.replace("__STARTUP_GRACE_SECONDS__", sys.argv[2])
path.write_text(text)
PY

  chmod 0755 "$WATCHDOG_SCRIPT"

  cat > "$WATCHDOG_SERVICE" <<'EOF'
[Unit]
Description=RemnaNode watchdog
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/remnanode-watchdog.sh
EOF

  cat > "$WATCHDOG_TIMER" <<'EOF'
[Unit]
Description=Run RemnaNode watchdog every minute

[Timer]
OnBootSec=5min
OnUnitActiveSec=1min
RandomizedDelaySec=10s
Persistent=true
Unit=remnanode-watchdog.service

[Install]
WantedBy=timers.target
EOF
}

write_oom_guard() {
  log "Настраиваю anti-OOM protection для RemnaNode и xHTTP"

  cat > "$OOM_GUARD_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

protect_pid() {
  local pid="$1"
  local adj="$2"

  [[ "$pid" =~ ^[0-9]+$ ]] || return 0
  [[ -w "/proc/$pid/oom_score_adj" ]] || return 0
  printf '%s\n' "$adj" > "/proc/$pid/oom_score_adj" 2>/dev/null || true
}

while read -r pid comm args; do
  [[ -n "${pid:-}" ]] || continue

  case "$comm" in
    rw-core|xray)
      protect_pid "$pid" -800
      continue
      ;;
    nginx)
      protect_pid "$pid" 600
      continue
      ;;
  esac

  case "$args" in
    *"dist/src/main"*|*"MainThread"*)
      protect_pid "$pid" -800
      ;;
  esac
done < <(ps -eo pid=,comm=,args= 2>/dev/null)
EOF

  chmod 0755 "$OOM_GUARD_SCRIPT"

  cat > "$OOM_GUARD_SERVICE" <<EOF
[Unit]
Description=RemnaNode anti-OOM guard
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$OOM_GUARD_SCRIPT
EOF

  cat > "$OOM_GUARD_TIMER" <<'EOF'
[Unit]
Description=Re-apply RemnaNode anti-OOM guard

[Timer]
OnBootSec=3min
OnUnitActiveSec=1min
RandomizedDelaySec=10s
Persistent=true
Unit=remnanode-oom-guard.service

[Install]
WantedBy=timers.target
EOF

  if xhttp_requested; then
    install -d -m 0755 "$NGINX_OOM_DROPIN_DIR"
    cat > "$NGINX_OOM_DROPIN_FILE" <<'EOF'
[Service]
OOMScoreAdjust=600
EOF
  fi
}

write_bbr_telemetry_deps() {
  log "Настраиваю guard для BBR telemetry deps внутри remnanode"

  cat > "$BBR_TELEMETRY_DEPS_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

for _ in $(seq 1 60); do
  if docker ps --format '{{.Names}}' | grep -qx remnanode; then
    docker exec remnanode sh -lc "apk info -e conntrack-tools >/dev/null 2>&1 || apk add --no-cache conntrack-tools >/dev/null" || true
    exit 0
  fi
  sleep 2
done

exit 0
EOF

  chmod 0755 "$BBR_TELEMETRY_DEPS_SCRIPT"

  cat > "$BBR_TELEMETRY_DEPS_SERVICE" <<EOF
[Unit]
Description=Ensure conntrack-tools exists inside remnanode for BBR telemetry fallback
After=docker.service remnanode-compose.service
Wants=docker.service remnanode-compose.service

[Service]
Type=oneshot
ExecStart=$BBR_TELEMETRY_DEPS_SCRIPT
EOF

  cat > "$BBR_TELEMETRY_DEPS_TIMER" <<'EOF'
[Unit]
Description=Periodic guard for remnanode BBR telemetry dependencies

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Persistent=true
Unit=remnanode-bbr-telemetry-deps.service

[Install]
WantedBy=timers.target
EOF
}

write_nightly_cleanup() {
  log "Настраиваю ночную auto-cleanup задачу для ноды"

  cat > "$MAINTENANCE_SCRIPT" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
LOCK_FILE=/run/remnanode-nightly-cleanup.lock
TMP_RETENTION_DAYS=${NIGHTLY_CLEANUP_TMP_RETENTION_DAYS}
JOURNAL_RETENTION=${NIGHTLY_CLEANUP_JOURNAL_RETENTION}
DOCKER_PRUNE_UNTIL=${NIGHTLY_CLEANUP_DOCKER_PRUNE_UNTIL}

log() {
  logger -t remnanode-nightly-cleanup -- "\$*"
  echo "\$*"
}

cleanup_tmp_dir() {
  local dir="\$1"
  [[ -d "\$dir" ]] || return 0

  find "\$dir" -mindepth 1 -xdev -type f -mtime "+\${TMP_RETENTION_DAYS}" -delete 2>/dev/null || true
  find "\$dir" -mindepth 1 -xdev -type d -empty -mtime "+\${TMP_RETENTION_DAYS}" -delete 2>/dev/null || true
}

exec 9>"\$LOCK_FILE"
if ! flock -n 9; then
  log "cleanup уже запущен, пропускаю повторный старт"
  exit 0
fi

log "Старт ночной очистки RemnaNode"

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get -y autoremove --purge >/dev/null 2>&1 || true
  apt-get -y autoclean >/dev/null 2>&1 || true
  apt-get -y clean >/dev/null 2>&1 || true
fi

if command -v journalctl >/dev/null 2>&1; then
  journalctl --vacuum-time="\$JOURNAL_RETENTION" >/dev/null 2>&1 || true
fi

cleanup_tmp_dir /tmp
cleanup_tmp_dir /var/tmp

if command -v docker >/dev/null 2>&1; then
  docker container prune -f --filter "until=\$DOCKER_PRUNE_UNTIL" >/dev/null 2>&1 || true
  docker image prune -af --filter "until=\$DOCKER_PRUNE_UNTIL" >/dev/null 2>&1 || true
  docker network prune -f --filter "until=\$DOCKER_PRUNE_UNTIL" >/dev/null 2>&1 || true
  docker builder prune -af --filter "until=\$DOCKER_PRUNE_UNTIL" >/dev/null 2>&1 || true
fi

log "Ночная очистка RemnaNode завершена"
EOF

  chmod 0755 "$MAINTENANCE_SCRIPT"

  cat > "$MAINTENANCE_SERVICE" <<EOF
[Unit]
Description=Nightly cleanup for RemnaNode
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$MAINTENANCE_SCRIPT
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF

  cat > "$MAINTENANCE_TIMER" <<EOF
[Unit]
Description=Run nightly cleanup for RemnaNode

[Timer]
OnCalendar=$NIGHTLY_CLEANUP_SCHEDULE
RandomizedDelaySec=15min
Persistent=true
Unit=remnanode-nightly-cleanup.service

[Install]
WantedBy=timers.target
EOF
}

pull_and_start_node() {
  local i=""
  local stale_ids=""

  log "Скачиваю образ ноды"
  for i in 1 2 3 4 5; do
    if compose pull remnanode; then
      break
    fi
    sleep 5
  done

  stale_ids="$(
    docker ps -aq \
      --filter name='^remnanode$' \
      --filter name='^remnanode-old' \
      2>/dev/null || true
  )"
  if [[ -n "$stale_ids" ]]; then
    log "Удаляю старые контейнеры RemnaNode перед перезапуском"
    docker rm -f $stale_ids >/dev/null 2>&1 || true
  fi

  log "Запускаю ноду"
  compose up -d --force-recreate remnanode
}

write_trusted_panel_ip() {
  if [[ -z "$PANEL_IP" ]]; then
    return 0
  fi

  if getent group cakepanel >/dev/null 2>&1; then
    install -d -m 0770 -o root -g cakepanel /etc/cake_panel
    touch "$PANEL_IPS_FILE"
    append_line_once "$PANEL_IPS_FILE" "$PANEL_IP"
    chown root:cakepanel "$PANEL_IPS_FILE"
    chmod 0640 "$PANEL_IPS_FILE"
  fi
}

write_firewall() {
  local extra_forward_rules=""
  local extra_output_rules=""
  local torrent_ports="6881-6999, 51413, 51414, 6969, 2710, 8999"
  local botnet_block_ips="46.165.199.7, 46.165.199.9, 64.62.203.97, 64.62.203.98, 85.17.70.16, 85.17.70.38, 85.17.155.52, 85.17.155.53, 178.162.202.96, 178.162.202.97"

  [[ -n "$PANEL_IP" ]] || die "IP панели пустой, firewall настроить нельзя"

  log "Настраиваю nftables: порт ${NODE_PORT}/tcp только для панели $PANEL_IP"

  extra_output_rules=$'    # Block known PacketSDK/Hola botnet destinations seen in abuse reports\n'"    ip daddr { $botnet_block_ips } tcp dport {80,443} drop"$'\n'"    ip daddr { $botnet_block_ips } udp dport {80,443} drop"

  if bool_is_true "$STRICT_EGRESS_GUARD"; then
    extra_forward_rules=$(cat <<EOF
    tcp dport { $torrent_ports } drop
    udp dport { $torrent_ports } drop
EOF
)
    extra_output_rules+=$(cat <<EOF

    tcp dport {25,465,587} reject with icmpx type admin-prohibited
    tcp dport { $torrent_ports } drop
    udp dport { $torrent_ports } drop
EOF
)
  fi

  cat > "$FIREWALL_SCRIPT" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

PANEL_IP="$PANEL_IP"
NODE_PORT="$NODE_PORT"

nft delete table inet remnanode_guard 2>/dev/null || true

nft -f - <<'NFT'
table inet remnanode_guard {
  chain input {
    type filter hook input priority -5; policy accept;
    tcp dport $NODE_PORT ip saddr $PANEL_IP accept
    tcp dport $NODE_PORT drop
  }

  chain forward {
    type filter hook forward priority -5; policy accept;
$extra_forward_rules
  }

  chain output {
    type filter hook output priority -5; policy accept;
$extra_output_rules
  }
}
NFT

modprobe xt_string >/dev/null 2>&1 || true

setup_string_chain() {
  local bin="\$1"
  command -v "\$bin" >/dev/null 2>&1 || return 0

  "\$bin" -w -N REMNANODE_TORRENT_GUARD 2>/dev/null || true
  "\$bin" -w -F REMNANODE_TORRENT_GUARD

  for pattern in \
    "BitTorrent protocol" \
    "BitComet" \
    "peer_id=" \
    "info_hash" \
    "announce_peer" \
    "find_node" \
    "get_peers" \
    "announce.php?passkey=" \
    "magnet:?xt=urn:btih:" \
    "urn:btih:" \
    ".torrent"
  do
    "\$bin" -w -A REMNANODE_TORRENT_GUARD -m string --algo bm --string "\$pattern" -j DROP
  done

  "\$bin" -w -C OUTPUT -j REMNANODE_TORRENT_GUARD 2>/dev/null || "\$bin" -w -I OUTPUT 1 -j REMNANODE_TORRENT_GUARD
  "\$bin" -w -C FORWARD -j REMNANODE_TORRENT_GUARD 2>/dev/null || "\$bin" -w -I FORWARD 1 -j REMNANODE_TORRENT_GUARD
}

setup_string_chain iptables
setup_string_chain ip6tables
EOF

  chmod 700 "$FIREWALL_SCRIPT"

  cat > "$FIREWALL_SERVICE" <<'EOF'
[Unit]
Description=Remnawave firewall
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/remnanode-firewall.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now remnanode-firewall.service
}

write_spamhaus_egress_guard() {
  if ! bool_is_true "$SPAMHAUS_EGRESS_GUARD"; then
    log "Spamhaus DROP/EDROP egress guard отключен: SPAMHAUS_EGRESS_GUARD=$SPAMHAUS_EGRESS_GUARD"
    systemctl disable --now remnanode-spamhaus-egress-guard.timer >/dev/null 2>&1 || true
    systemctl disable --now remnanode-spamhaus-egress-guard.service >/dev/null 2>&1 || true
    nft delete table inet remnanode_spamhaus_egress_guard 2>/dev/null || true
    return 0
  fi

  log "Настраиваю автоматический Spamhaus DROP/EDROP egress guard"

  install -d -m 0755 "$SPAMHAUS_EGRESS_GUARD_STATE_DIR"

  cat > "$SPAMHAUS_EGRESS_GUARD_SCRIPT" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

STATE_DIR="$SPAMHAUS_EGRESS_GUARD_STATE_DIR"
TABLE="remnanode_spamhaus_egress_guard"
SET_NAME="drop_v4"
URLS=(
  "https://www.spamhaus.org/drop/drop.txt"
  "https://www.spamhaus.org/drop/edrop.txt"
)

mkdir -p "\$STATE_DIR"
tmpdir="\$(mktemp -d)"
cleanup() { rm -rf "\$tmpdir"; }
trap cleanup EXIT

raw="\$tmpdir/raw.txt"
cidrs="\$tmpdir/cidrs.txt"
nftfile="\$tmpdir/rules.nft"

fetch_url() {
  local url="\$1"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 10 --max-time 40 "\$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- --timeout=40 "\$url"
  else
    python3 - "\$url" <<'PY'
import sys
import urllib.request

url = sys.argv[1]
with urllib.request.urlopen(url, timeout=40) as response:
    sys.stdout.buffer.write(response.read())
PY
  fi
}

: > "\$raw"
for url in "\${URLS[@]}"; do
  fetch_url "\$url" >> "\$raw"
  printf '\\n' >> "\$raw"
done

awk '
  /^[[:space:]]*;/ { next }
  /^[[:space:]]*$/ { next }
  {
    cidr=\$1
    sub(/[[:space:]]*;.*/, "", cidr)
    if (cidr ~ /^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+\\/[0-9]+$/) print cidr
  }
' "\$raw" | sort -u > "\$cidrs"

python3 - "\$cidrs" <<'PY'
import ipaddress
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
items = [line.strip() for line in path.read_text().splitlines() if line.strip()]
if len(items) < 100:
    raise SystemExit(f"too few Spamhaus networks parsed: {len(items)}")

networks = [ipaddress.ip_network(item, strict=False) for item in items]
collapsed = sorted(ipaddress.collapse_addresses(networks), key=lambda network: int(network.network_address))
path.write_text("\\n".join(str(network) for network in collapsed) + "\\n")
PY

{
  if nft list table inet "\$TABLE" >/dev/null 2>&1; then
    echo "delete table inet \$TABLE"
  fi

  echo "table inet \$TABLE {"
  echo "  set \$SET_NAME {"
  echo "    type ipv4_addr"
  echo "    flags interval"
  echo "    elements = {"
  sed 's/$/,/' "\$cidrs" | sed '$ s/,$//'
  echo "    }"
  echo "  }"
  echo "  chain output {"
  echo "    type filter hook output priority -6; policy accept;"
  echo "    ip daddr @\$SET_NAME counter reject with icmpx type admin-prohibited"
  echo "  }"
  echo "  chain forward {"
  echo "    type filter hook forward priority -6; policy accept;"
  echo "    ip daddr @\$SET_NAME counter reject with icmpx type admin-prohibited"
  echo "  }"
  echo "}"
} > "\$nftfile"

nft -f "\$nftfile"
install -m 0644 "\$cidrs" "\$STATE_DIR/drop_v4.cidrs"
printf '%s\\n' "\$(date -u +%Y-%m-%dT%H:%M:%SZ) count=\$(wc -l < "\$cidrs")" > "\$STATE_DIR/last_update"
EOF

  chmod 0755 "$SPAMHAUS_EGRESS_GUARD_SCRIPT"

  cat > "$SPAMHAUS_EGRESS_GUARD_SERVICE" <<EOF
[Unit]
Description=RemnaNode Spamhaus DROP/EDROP egress guard
After=network-online.target remnanode-firewall.service
Wants=network-online.target
Before=remnanode-compose.service

[Service]
Type=oneshot
ExecStart=$SPAMHAUS_EGRESS_GUARD_SCRIPT

[Install]
WantedBy=multi-user.target
EOF

  cat > "$SPAMHAUS_EGRESS_GUARD_TIMER" <<'EOF'
[Unit]
Description=Refresh RemnaNode Spamhaus DROP/EDROP egress guard

[Timer]
OnBootSec=2min
OnUnitActiveSec=12h
AccuracySec=30min
RandomizedDelaySec=20min
Persistent=true
Unit=remnanode-spamhaus-egress-guard.service

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable remnanode-spamhaus-egress-guard.service >/dev/null 2>&1 || true
  systemctl enable --now remnanode-spamhaus-egress-guard.timer >/dev/null 2>&1 || true
  if ! systemctl start remnanode-spamhaus-egress-guard.service; then
    log "Предупреждение: Spamhaus guard не смог обновиться сейчас, timer повторит попытку позже"
  fi
}

write_mss_clamp() {
  log "Настраиваю консервативный TCP MSS clamp для LTE/Wi-Fi сетей"

  cat > "$MSS_CLAMP_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

IPT_BIN="$(command -v iptables 2>/dev/null || true)"
[[ -n "$IPT_BIN" ]] || exit 0

apply_rule() {
  local chain="$1"
  local sport="$2"
  "$IPT_BIN" -t mangle -C "$chain" -p tcp --sport "$sport" --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1360 2>/dev/null || \
  "$IPT_BIN" -t mangle -A "$chain" -p tcp --sport "$sport" --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1360
}

apply_rule OUTPUT 443
apply_rule OUTPUT 8443
apply_rule OUTPUT 2222
EOF

  chmod 0755 "$MSS_CLAMP_SCRIPT"

  cat > "$MSS_CLAMP_SERVICE" <<'EOF'
[Unit]
Description=Apply RemnaNode TCP MSS clamp
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/remnanode-mss-clamp.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now remnanode-mss-clamp.service >/dev/null 2>&1 || true
}

enable_boot_services() {
  systemctl daemon-reload
  systemctl reset-failed >/dev/null 2>&1 || true

  if [[ -f "$COMPOSE_SERVICE" ]]; then
    systemctl enable --now remnanode-compose.service
  fi

  if [[ -f "$MTU_SERVICE" ]]; then
    systemctl enable --now node-mtu.service
  fi

  if [[ -f "$FIREWALL_SERVICE" ]]; then
    systemctl enable --now remnanode-firewall.service
  fi

  if [[ -f "$SPAMHAUS_EGRESS_GUARD_TIMER" ]]; then
    systemctl enable --now remnanode-spamhaus-egress-guard.timer
    systemctl start remnanode-spamhaus-egress-guard.service >/dev/null 2>&1 || true
  fi

  if [[ -f "$MSS_CLAMP_SERVICE" ]]; then
    systemctl enable --now remnanode-mss-clamp.service
  fi

  if [[ -f "$WATCHDOG_TIMER" ]]; then
    systemctl enable --now remnanode-watchdog.timer
    systemctl start remnanode-watchdog.service >/dev/null 2>&1 || true
  fi

  if [[ -f "$MAINTENANCE_TIMER" ]]; then
    systemctl enable --now remnanode-nightly-cleanup.timer
  fi

  if [[ -f "$RPS_SERVICE" ]]; then
    systemctl enable --now remnanode-rps.service
  fi

  if [[ -f "$QDISC_SERVICE" ]]; then
    systemctl enable --now remnanode-qdisc.service
  fi

  if [[ -f "$OFFLOAD_TUNE_SERVICE" ]]; then
    systemctl enable --now remnanode-offload-tune.service
  fi

  if [[ -f "$XHTTP_SYNC_TIMER" ]]; then
    systemctl enable --now remnanode-xhttp-sync.timer
    systemctl start remnanode-xhttp-sync.service >/dev/null 2>&1 || true
  fi

  if [[ -f "$OOM_GUARD_TIMER" ]]; then
    systemctl enable --now remnanode-oom-guard.timer
    systemctl start remnanode-oom-guard.service >/dev/null 2>&1 || true
  fi

  if [[ -f "$BBR_TELEMETRY_DEPS_TIMER" ]]; then
    systemctl enable --now remnanode-bbr-telemetry-deps.timer
    systemctl start remnanode-bbr-telemetry-deps.service >/dev/null 2>&1 || true
  fi

  if [[ -f "$WATCHDOG_TIMER" ]]; then
    systemctl is-active remnanode-watchdog.timer >/dev/null 2>&1 || log "Предупреждение: remnanode-watchdog.timer не активен"
  fi

  if [[ -f "$XHTTP_SYNC_TIMER" ]]; then
    systemctl is-active remnanode-xhttp-sync.timer >/dev/null 2>&1 || log "Предупреждение: remnanode-xhttp-sync.timer не активен"
  fi

  if [[ -f "$OOM_GUARD_TIMER" ]]; then
    systemctl is-active remnanode-oom-guard.timer >/dev/null 2>&1 || log "Предупреждение: remnanode-oom-guard.timer не активен"
  fi

  if [[ -f "$BBR_TELEMETRY_DEPS_TIMER" ]]; then
    systemctl is-active remnanode-bbr-telemetry-deps.timer >/dev/null 2>&1 || log "Предупреждение: remnanode-bbr-telemetry-deps.timer не активен"
  fi

  if [[ -f "$SPAMHAUS_EGRESS_GUARD_TIMER" ]]; then
    systemctl is-active remnanode-spamhaus-egress-guard.timer >/dev/null 2>&1 || log "Предупреждение: remnanode-spamhaus-egress-guard.timer не активен"
  fi
}

schedule_reboot_if_required() {
  mark_reboot_required

  if ! bool_is_true "$AUTO_REBOOT"; then
    return 0
  fi

  if (( REBOOT_REQUIRED == 0 )); then
    return 0
  fi

  log "Обнаружен /run/reboot-required, планирую reboot через 20 секунд"

  if command -v systemd-run >/dev/null 2>&1; then
    systemd-run --unit remnanode-postinstall-reboot --on-active=20 /usr/bin/systemctl reboot >/dev/null
  else
    shutdown -r +1 "Reboot required after Remnanode install" >/dev/null 2>&1 || true
  fi

  REBOOT_SCHEDULED=1
}

show_result() {
  log "Готово. Итоговое состояние"

  docker --version || true
  docker compose version || true

  printf "\nIP ноды: %s\n" "$NODE_IP"
  printf "IP панели: %s\n" "$PANEL_IP"
  printf "Порт ноды: %s\n" "$NODE_PORT"
  printf "MTU: %s\n" "$MTU_VALUE"
  printf "Swap total: %s MiB\n" "$(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo)"
  printf "Adaptive Xray profile: %s\n" "$(resolved_xray_sniff_profile)"
  printf "Xray loglevel/access: %s / %s\n" "$(resolved_xray_loglevel)" "$(resolved_xray_access_log)"
  printf "Nightly cleanup: %s\n" "$NIGHTLY_CLEANUP_SCHEDULE"

  printf "\nКонтейнер:\n"
  compose ps || true

  printf "\nСлушающие порты:\n"
  ss -tulpn | grep -E ":(443|${NODE_PORT})\\b" || true

  printf "\nSystemd:\n"
  systemctl is-active docker.service remnanode-compose.service remnanode-firewall.service remnanode-spamhaus-egress-guard.timer remnanode-mss-clamp.service remnanode-watchdog.timer remnanode-nightly-cleanup.timer remnanode-rps.service remnanode-qdisc.service remnanode-offload-tune.service remnanode-oom-guard.timer remnanode-bbr-telemetry-deps.timer 2>/dev/null || true

  printf "\nПоследние логи ноды:\n\n"
  compose logs --tail=40 -t remnanode || true

  printf "\nПолезные файлы:\n"
  printf -- "- %s\n" "$COMPOSE_FILE"
  printf -- "- %s\n" "$COMPOSE_OVERRIDE_FILE"
  printf -- "- %s\n" "$ENV_FILE"
  printf -- "- %s\n" "$COMPOSE_SERVICE"
  printf -- "- %s\n" "$FIREWALL_SERVICE"
  printf -- "- %s\n" "$SPAMHAUS_EGRESS_GUARD_SERVICE"
  printf -- "- %s\n" "$SPAMHAUS_EGRESS_GUARD_TIMER"
  printf -- "- %s\n" "$GENERATE_API_OVERRIDE"
  printf -- "- %s\n" "$NODE_STATE_DIR"
  printf -- "- %s\n" "$WATCHDOG_TIMER"
  printf -- "- %s\n" "$MAINTENANCE_SCRIPT"
  printf -- "- %s\n" "$MAINTENANCE_TIMER"
  printf -- "- %s\n" "$RPS_SERVICE"
  printf -- "- %s\n" "$QDISC_SERVICE"
  printf -- "- %s\n" "$OFFLOAD_TUNE_SERVICE"
  printf -- "- %s\n" "$OOM_GUARD_SERVICE"
  printf -- "- %s\n" "$OOM_GUARD_TIMER"
  printf -- "- %s\n" "$BBR_TELEMETRY_DEPS_SERVICE"
  printf -- "- %s\n" "$BBR_TELEMETRY_DEPS_TIMER"
  if xhttp_requested; then
    printf -- "- %s\n" "$XHTTP_SYNC_TIMER"
  fi

  if (( REBOOT_REQUIRED == 1 )); then
    printf "\nСистема просит reboot после установки.\n"
    if (( REBOOT_SCHEDULED == 1 )); then
      printf "Reboot уже запланирован автоматически.\n"
    else
      printf "Автоматический reboot по умолчанию отключен, поэтому reboot нужно выполнить вручную только если он действительно нужен.\n"
    fi
  fi

  printf "\nВажно:\n"
  printf "Control-порт %s/tcp открыт только для панели %s.\n" "$NODE_PORT" "$PANEL_IP"
  printf "IP ноды и MTU определяются автоматически, руками нужны PANEL_IP и SECRET_KEY.\n"
  printf "Очистка сиротских Unix-сокетов для Xray включена из коробки.\n"
  printf "Smart-watchdog с grace-period и auto-heal уже включен.\n"
  printf "Swap top-up, adaptive memory/network baseline и стабилизация SSH уже включены.\n"
  printf "Adaptive anti-OOM protection для rw-core/xHTTP уже включена.\n"
  printf "Консервативный DNS/MSS/MTU baseline для LTE/Wi-Fi уже включен.\n"
  printf "Adaptive fq/qdisc, RPS/XPS и offload-tuning под слабые и сильные VPS уже включены.\n"
  printf "Анти-торрент защита усилена по портам и сигнатурам протокола.\n"
  if bool_is_true "$SPAMHAUS_EGRESS_GUARD"; then
    printf "Spamhaus DROP/EDROP egress guard включен и обновляется автоматически.\n"
  else
    printf "Spamhaus DROP/EDROP egress guard отключен переменной SPAMHAUS_EGRESS_GUARD=0.\n"
  fi
  printf "Legacy CAKE/shaping stack больше не поднимается и не должен мешать Reality/xHTTP.\n"
}

main() {
  local iface=""

  autodetect_node_ip
  read_panel_ip
  read_optional_xhttp_domain
  read_manual_secret

  prepare_apt_environment
  upgrade_system
  install_packages
  install_docker
  configure_resolved_defaults
  configure_mtu
  ensure_swap
  disable_noisy_services
  tune_sshd
  prepare_dirs

  iface="$(default_iface)"
  [[ -n "$iface" ]] || die "Не удалось определить основной сетевой интерфейс"

  repair_existing_cake_stack "$iface"
  tune_kernel
  write_rps_service
  write_qdisc_service
  write_offload_tune_service
  write_env_file
  write_compose
  write_compose_override
  write_generate_api_override
  write_xray_service_override
  write_stats_service_override
  write_logrotate
  write_compose_service
  write_watchdog
  write_oom_guard
  write_bbr_telemetry_deps
  write_nightly_cleanup
  write_trusted_panel_ip
  write_firewall
  write_spamhaus_egress_guard
  write_mss_clamp
  pull_and_start_node
  configure_xhttp_stack
  enable_boot_services
  schedule_reboot_if_required
  show_result
}

main "$@"
