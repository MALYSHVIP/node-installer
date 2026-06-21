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
NODE_TLS_DIR="/etc/remnanode/tls"
XRAY_TLS_DIR_IN_CONTAINER="/var/lib/remnawave/configs/xray/ssl"

SYSCTL_FILE="/etc/sysctl.d/99-remnanode.conf"
LIMITS_FILE="/etc/security/limits.d/99-remnanode.conf"
MTU_SERVICE="/etc/systemd/system/node-mtu.service"
FIREWALL_SCRIPT="/usr/local/sbin/remnanode-firewall.sh"
FIREWALL_SERVICE="/etc/systemd/system/remnanode-firewall.service"
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
ENSURE_CAKE_STACK="${ENSURE_CAKE_STACK:-0}"
APT_LOCK_TIMEOUT="${APT_LOCK_TIMEOUT:-900}"
XHTTP_DOMAIN="${XHTTP_DOMAIN:-}"
XHTTP_PATH="${XHTTP_PATH:-/xhttp-universal/}"
XHTTP_ENABLE_H3="${XHTTP_ENABLE_H3:-auto}"
CERTBOT_RETRY_TRIES="${CERTBOT_RETRY_TRIES:-6}"
CERTBOT_RETRY_BASE_DELAY="${CERTBOT_RETRY_BASE_DELAY:-10}"
CERTBOT_RETRY_MAX_DELAY="${CERTBOT_RETRY_MAX_DELAY:-60}"
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

certbot_retry_after_seconds() {
  local retry_after=""

  retry_after="$(
    tail -n 160 /var/log/letsencrypt/letsencrypt.log 2>/dev/null \
      | sed -n 's/.*Retry-After: \([0-9][0-9]*\).*/\1/p' \
      | tail -n1 || true
  )"

  if [[ "$retry_after" =~ ^[0-9]+$ ]] && (( retry_after > 0 )); then
    printf '%s' "$retry_after"
    return 0
  fi

  return 1
}

certbot_transient_failure() {
  local output_file="${1:-}"
  local pattern='Service busy; retry later|acme\.errors\.ClientError: <Response \[500\]>|HTTP 500|Response \[500\]'

  if [[ -n "$output_file" && -f "$output_file" ]] && grep -Eiq "$pattern" "$output_file"; then
    return 0
  fi

  if tail -n 160 /var/log/letsencrypt/letsencrypt.log 2>/dev/null | grep -Eiq "$pattern"; then
    return 0
  fi

  return 1
}

issue_xhttp_certificate() {
  local tries="$CERTBOT_RETRY_TRIES"
  local base_delay="$CERTBOT_RETRY_BASE_DELAY"
  local max_delay="$CERTBOT_RETRY_MAX_DELAY"
  local certbot_output=""
  local attempt=1
  local retry_after=""
  local sleep_for=""

  certbot_output="$(mktemp)"

  while (( attempt <= tries )); do
    log "Пытаюсь выпустить сертификат для $XHTTP_DOMAIN (попытка ${attempt}/${tries})"

    if certbot certonly \
      --webroot -w /var/www/html \
      -d "$XHTTP_DOMAIN" \
      --agree-tos \
      --register-unsafely-without-email \
      --non-interactive \
      --keep-until-expiring >"$certbot_output" 2>&1; then
      cat "$certbot_output"
      rm -f "$certbot_output"
      return 0
    fi

    cat "$certbot_output" >&2

    if ! certbot_transient_failure "$certbot_output"; then
      rm -f "$certbot_output"
      return 1
    fi

    if (( attempt >= tries )); then
      break
    fi

    sleep_for=$(( base_delay * attempt ))
    if retry_after="$(certbot_retry_after_seconds)"; then
      if (( retry_after > sleep_for )); then
        sleep_for="$retry_after"
      fi
    fi
    if (( sleep_for > max_delay )); then
      sleep_for="$max_delay"
    fi
    if (( sleep_for < 5 )); then
      sleep_for=5
    fi

    log "Let's Encrypt временно занят, жду ${sleep_for}с и повторяю"
    sleep "$sleep_for"
    : >"$certbot_output"
    attempt=$(( attempt + 1 ))
  done

  rm -f "$certbot_output"
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
  local mem_mb=0
  local cpus=0
  mem_mb="$(total_mem_mb)"
  cpus="$(nproc 2>/dev/null || echo 1)"

  if (( mem_mb <= 4096 || cpus <= 2 )); then
    printf '1'
  elif (( mem_mb < 8192 || cpus <= 4 )); then
    printf '2'
  else
    printf 'auto'
  fi
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
  local cpus=0
  local mem_mb=0

  cpus="$(cpu_count)"
  mem_mb="$(total_mem_mb)"

  if (( cpus <= 2 || mem_mb < 3072 )); then
    printf 'balanced'
  else
    printf 'aggressive'
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
    XHTTP_PATH="/xhttp-universal/"
  fi

  [[ "$XHTTP_PATH" == /* ]] || XHTTP_PATH="/$XHTTP_PATH"
  [[ "$XHTTP_PATH" == */ ]] || XHTTP_PATH="$XHTTP_PATH/"
}

install_nginx_mainline_repo() {
  install -d -m 0755 /etc/apt/keyrings

  if [[ ! -f /etc/apt/keyrings/nginx.gpg ]]; then
    curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /etc/apt/keyrings/nginx.gpg
    chmod 0644 /etc/apt/keyrings/nginx.gpg
  fi

  cat > /etc/apt/sources.list.d/nginx-mainline.list <<'EOF'
deb [signed-by=/etc/apt/keyrings/nginx.gpg] http://nginx.org/packages/mainline/ubuntu jammy nginx
deb-src [signed-by=/etc/apt/keyrings/nginx.gpg] http://nginx.org/packages/mainline/ubuntu jammy nginx
EOF
}

wait_for_xhttp_socket() {
  local tries=30
  local delay=2
  local attempt=""
  local h2_socket=""

  for ((attempt = 1; attempt <= tries; attempt++)); do
    h2_socket="$(find /dev/shm -maxdepth 1 -type s -name 'xrxh*.socket' ! -name '*h3*' | sort | head -n1 || true)"
    if [[ -n "$h2_socket" ]]; then
      printf '%s' "$h2_socket"
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

  cat > "$XHTTP_SYNC_SCRIPT" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

XHTTP_DOMAIN="$XHTTP_DOMAIN"
XHTTP_PATH="$XHTTP_PATH"
XHTTP_ENABLE_H3="$XHTTP_ENABLE_H3"
FULL_SITE="$full_site"
H3_SITE="$h3_site"

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

h2_socket="\$(find /dev/shm -maxdepth 1 -type s -name 'xrxh*.socket' ! -name '*h3*' | sort | head -n1 || true)"
h3_socket="\$(find_socket 'xrxh*h3*.socket')"
changed=0

if [[ -z "\$h2_socket" ]]; then
  logger -t remnanode-xhttp-sync -- "xHTTP socket is not ready yet for \$XHTTP_DOMAIN"
  exit 0
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
    ssl_session_cache shared:XHTTP_SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    access_log off;

    location $XHTTP_PATH {
        client_max_body_size 0;
        client_body_timeout 10m;
        grpc_read_timeout 1h;
        grpc_send_timeout 10m;
        grpc_socket_keepalive on;
        grpc_buffer_size 64k;
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
    ssl_session_cache shared:XHTTP_H3_8443_SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    access_log off;

    location $XHTTP_PATH {
        client_max_body_size 0;
        client_body_timeout 10m;
        grpc_read_timeout 1h;
        grpc_send_timeout 10m;
        grpc_socket_keepalive on;
        grpc_buffer_size 64k;
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

  if ! xhttp_requested; then
    return 0
  fi

  normalize_xhttp_path
  log "Включаю optional xHTTP-слой для домена $XHTTP_DOMAIN"
  nginx_worker_processes="$(recommended_nginx_worker_processes)"
  nginx_worker_connections="$(recommended_nginx_worker_connections)"
  nginx_rlimit_nofile="$(recommended_nginx_rlimit_nofile)"
  log "Adaptive nginx xHTTP profile: workers=${nginx_worker_processes}, worker_connections=${nginx_worker_connections}, nofile=${nginx_rlimit_nofile}"

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
keepalive_timeout 300s;
keepalive_min_timeout 30s;
keepalive_requests 1000;
reset_timedout_connection on;
http2_chunk_size 32k;
ssl_session_cache shared:XHTTP_GLOBAL_SSL:50m;
ssl_session_timeout 1d;
ssl_session_tickets off;
client_body_timeout 10m;
send_timeout 10m;
tcp_nodelay on;
EOF

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

  issue_xhttp_certificate || die "Не удалось выпустить сертификат Let's Encrypt для $XHTTP_DOMAIN"

  write_generic_tls_links
  write_xhttp_sync_artifacts
  validate_generated_xhttp_sync_script
  systemctl daemon-reload
  systemctl enable remnanode-xhttp-sync.service remnanode-xhttp-sync.timer >/dev/null 2>&1 || true
  systemctl start remnanode-xhttp-sync.timer >/dev/null 2>&1 || true

  if ! h2_socket="$(wait_for_xhttp_socket)"; then
    log "xHTTP H2 socket пока не появился в /dev/shm; xHTTP auto-sync подготовлен и будет ждать конфиг от мастер-панели"
    systemctl start remnanode-xhttp-sync.service >/dev/null 2>&1 || true
    return 0
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
    ssl_session_cache shared:XHTTP_SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    access_log off;

    location $XHTTP_PATH {
        client_max_body_size 0;
        client_body_timeout 10m;
        grpc_read_timeout 1h;
        grpc_send_timeout 10m;
        grpc_socket_keepalive on;
        grpc_buffer_size 64k;
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
    ssl_session_cache shared:XHTTP_H3_8443_SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    access_log off;

    location $XHTTP_PATH {
        client_max_body_size 0;
        client_body_timeout 10m;
        grpc_read_timeout 1h;
        grpc_send_timeout 10m;
        grpc_socket_keepalive on;
        grpc_buffer_size 64k;
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

  log "docker compose plugin не найден в пакетах, ставлю вручную (${compose_version}, ${compose_arch})"
  mkdir -p "$plugin_dir"
  run_retry 5 5 curl -fsSL "$url" -o "$plugin_path" || die "Не удалось скачать Docker Compose plugin"
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
  ensure_dns

  if ! command -v docker >/dev/null 2>&1; then
    log "Docker не найден, устанавливаю"
    run_retry 5 5 bash -lc "curl -fsSL https://get.docker.com | sh" || die "Не удалось установить Docker"
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
  mkdir -p "$NODE_ROOT" "$LOG_DIR" "$OVERRIDES_DIR" "$WATCHDOG_STATE_DIR" "$(dirname "$NODE_TLS_DIR")" "$NODE_TLS_DIR"
  chmod 755 "$NODE_ROOT" "$LOG_DIR" "$OVERRIDES_DIR" "$WATCHDOG_STATE_DIR" "$(dirname "$NODE_TLS_DIR")" "$NODE_TLS_DIR"
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

  log "Настраиваю kernel baseline, BBR и лимиты"

  modprobe tcp_bbr || true

  swappiness_value="$(recommended_swappiness)"
  vfs_cache_pressure_value="$(recommended_vfs_cache_pressure)"
  netdev_budget_value="$(recommended_netdev_budget)"
  netdev_budget_usecs_value="$(recommended_netdev_budget_usecs)"
  dev_weight_value="$(recommended_dev_weight)"
  nf_conntrack_max_value="$(recommended_nf_conntrack_max)"
  rps_sock_flow_entries_value="$(recommended_rps_sock_flow_entries)"

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
net.ipv4.tcp_keepalive_time = 120
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
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
  aggressive)
    ethtool -K "\$iface" gro off gso off tso off sg off rx-gro-hw off 2>/dev/null || true
    ;;
  *)
    ethtool -K "\$iface" gro off gso off tso off rx-gro-hw off 2>/dev/null || true
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
  log "Добавляю docker-compose.override.yml для override-файлов ноды"

  cat > "$COMPOSE_OVERRIDE_FILE" <<EOF
services:
  remnanode:
    volumes:
      - $GENERATE_API_OVERRIDE:/opt/app/dist/src/common/utils/generate-api-config.js:ro
      - /etc/remnanode:/etc/remnanode:ro
      - $NODE_TLS_DIR:$XRAY_TLS_DIR_IN_CONTAINER:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
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
  log "Создаю systemd unit для автоподъема ноды после reboot"

  cat > "$COMPOSE_SERVICE" <<EOF
[Unit]
Description=Remnawave node compose
Requires=docker.service
After=docker.service network-online.target node-mtu.service remnanode-firewall.service
Wants=network-online.target

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
COOLDOWN_SECONDS=180
CONTAINER_NAME=remnanode
HOST_PORT=2222
XRAY_API_PORT=61000
CHECK_TIMEOUT=12
STARTUP_GRACE_SECONDS=90
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

  if [[ -f "$WATCHDOG_TIMER" ]]; then
    systemctl is-active remnanode-watchdog.timer >/dev/null 2>&1 || log "Предупреждение: remnanode-watchdog.timer не активен"
  fi

  if [[ -f "$XHTTP_SYNC_TIMER" ]]; then
    systemctl is-active remnanode-xhttp-sync.timer >/dev/null 2>&1 || log "Предупреждение: remnanode-xhttp-sync.timer не активен"
  fi

  if [[ -f "$OOM_GUARD_TIMER" ]]; then
    systemctl is-active remnanode-oom-guard.timer >/dev/null 2>&1 || log "Предупреждение: remnanode-oom-guard.timer не активен"
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
  systemctl is-active docker.service remnanode-compose.service remnanode-firewall.service remnanode-mss-clamp.service remnanode-watchdog.timer remnanode-nightly-cleanup.timer remnanode-rps.service remnanode-qdisc.service remnanode-offload-tune.service remnanode-oom-guard.timer 2>/dev/null || true

  printf "\nПоследние логи ноды:\n\n"
  compose logs --tail=40 -t remnanode || true

  printf "\nПолезные файлы:\n"
  printf -- "- %s\n" "$COMPOSE_FILE"
  printf -- "- %s\n" "$COMPOSE_OVERRIDE_FILE"
  printf -- "- %s\n" "$ENV_FILE"
  printf -- "- %s\n" "$COMPOSE_SERVICE"
  printf -- "- %s\n" "$FIREWALL_SERVICE"
  printf -- "- %s\n" "$GENERATE_API_OVERRIDE"
  printf -- "- %s\n" "$WATCHDOG_TIMER"
  printf -- "- %s\n" "$MAINTENANCE_SCRIPT"
  printf -- "- %s\n" "$MAINTENANCE_TIMER"
  printf -- "- %s\n" "$RPS_SERVICE"
  printf -- "- %s\n" "$QDISC_SERVICE"
  printf -- "- %s\n" "$OFFLOAD_TUNE_SERVICE"
  printf -- "- %s\n" "$OOM_GUARD_SERVICE"
  printf -- "- %s\n" "$OOM_GUARD_TIMER"
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
  write_logrotate
  write_compose_service
  write_watchdog
  write_oom_guard
  write_nightly_cleanup
  write_trusted_panel_ip
  write_firewall
  write_mss_clamp
  pull_and_start_node
  configure_xhttp_stack
  enable_boot_services
  schedule_reboot_if_required
  show_result
}

main "$@"
