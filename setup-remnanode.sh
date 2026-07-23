#!/usr/bin/env bash
set -Eeuo pipefail

# RemnaNode production installer for Remnawave Panel 2.8.x.
# Supported hosts: Ubuntu/Debian, systemd, linux/amd64 or linux/arm64.
# The installer deliberately does not patch files inside the RemnaNode image.

umask 027
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

INSTALLER_VERSION="3.1.0"
DEFAULT_NODE_VERSION="2.8.0"
PANEL_COMPAT_VERSION="2.8.1"

NODE_ROOT="/opt/remnanode"
COMPOSE_FILE="$NODE_ROOT/docker-compose.yml"
ENV_FILE="$NODE_ROOT/.env"
TLS_DIR="/etc/remnanode/tls"
LOG_DIR="/var/log/remnanode"
STATE_DIR="/var/lib/remnanode-installer"
STATE_FILE="$STATE_DIR/state.env"
BACKUP_ROOT="/var/backups/remnanode"
LOCK_FILE="/run/lock/remnanode-installer.lock"

SYSCTL_FILE="/etc/sysctl.d/99-remnanode.conf"
LOGROTATE_FILE="/etc/logrotate.d/remnanode"
FIREWALL_SCRIPT="/usr/local/sbin/remnanode-firewall.sh"
FIREWALL_SERVICE="/etc/systemd/system/remnanode-firewall.service"
INSTALLER_CONFIG="/etc/remnanode-installer.conf"
PANEL_IPS_FILE="/etc/cake_panel/trusted_panel_ips.txt"
MAINTENANCE_SCRIPT="/usr/local/sbin/remnanode-maintenance.sh"
MAINTENANCE_SERVICE="/etc/systemd/system/remnanode-maintenance.service"
MAINTENANCE_TIMER="/etc/systemd/system/remnanode-maintenance.timer"
XHTTP_GUARD_SCRIPT="/usr/local/sbin/remnanode-xhttp-socket-guard.sh"
XHTTP_GUARD_SERVICE="/etc/systemd/system/remnanode-xhttp-socket-guard.service"
XHTTP_GUARD_TIMER="/etc/systemd/system/remnanode-xhttp-socket-guard.timer"
XHTTP_GUARD_MARKER="/run/remnanode-xhttp-guard.last-restart"
JOURNALD_DROPIN="/etc/systemd/journald.conf.d/60-remnanode-limits.conf"
LEGACY_REBOOT_MARKER="$STATE_DIR/legacy-runtime-boot-id"

NGINX_SITE_AVAILABLE="/etc/nginx/sites-available/remnanode-xhttp.conf"
NGINX_SITES_ENABLED_SITE="/etc/nginx/sites-enabled/remnanode-xhttp.conf"
NGINX_CONF_D_SITE="/etc/nginx/conf.d/remnanode-xhttp.conf"
NGINX_SITE_ENABLED="$NGINX_SITES_ENABLED_SITE"
NGINX_BOOTSTRAP_AVAILABLE="/etc/nginx/sites-available/remnanode-acme-bootstrap.conf"
NGINX_SITES_ENABLED_BOOTSTRAP="/etc/nginx/sites-enabled/remnanode-acme-bootstrap.conf"
NGINX_CONF_D_BOOTSTRAP="/etc/nginx/conf.d/remnanode-acme-bootstrap.conf"
NGINX_BOOTSTRAP_ENABLED="$NGINX_SITES_ENABLED_BOOTSTRAP"
NGINX_ACME_ROOT="/var/www/remnanode-acme"
CERT_DEPLOY_HOOK="/etc/letsencrypt/renewal-hooks/deploy/50-remnanode-tls"
NGINX_CAPACITY_DROPIN="/etc/systemd/system/nginx.service.d/60-remnanode-capacity.conf"
NGINX_LOCK_FILE="/run/lock/remnanode-nginx.lock"

MODE="install"
YES="${YES:-0}"
DRY_RUN="${DRY_RUN:-0}"
BACKUP_REQUEST="${BACKUP_REQUEST:-}"

# Preserve the distinction between "unset" and an explicitly supplied default.
NODE_VERSION_EXPLICIT="${NODE_VERSION+x}"
NODE_IMAGE_EXPLICIT="${NODE_IMAGE+x}"
NODE_PORT_EXPLICIT="${NODE_PORT+x}"
ENABLE_XHTTP_EXPLICIT="${ENABLE_XHTTP+x}"
XHTTP_PATH_EXPLICIT="${XHTTP_PATH+x}"
XHTTP_SOCKET_EXPLICIT="${XHTTP_SOCKET+x}"
MANAGE_FIREWALL_EXPLICIT="${MANAGE_FIREWALL+x}"
PUBLIC_TCP_PORTS_EXPLICIT="${PUBLIC_TCP_PORTS+x}"
PUBLIC_UDP_PORTS_EXPLICIT="${PUBLIC_UDP_PORTS+x}"
BLOCK_SMTP_EGRESS_EXPLICIT="${BLOCK_SMTP_EGRESS+x}"
BLOCK_SMTP_FORWARD_EXPLICIT="${BLOCK_SMTP_FORWARD+x}"
SMTP_EGRESS_PORTS_EXPLICIT="${SMTP_EGRESS_PORTS+x}"
ENABLE_BBR_EXPLICIT="${ENABLE_BBR+x}"
AUTO_SWAP_EXPLICIT="${AUTO_SWAP+x}"
ENABLE_MAINTENANCE_EXPLICIT="${ENABLE_MAINTENANCE+x}"
BACKUP_RETENTION_EXPLICIT="${BACKUP_RETENTION+x}"
JOURNAL_MAX_USE_EXPLICIT="${JOURNAL_MAX_USE+x}"
JOURNAL_RETENTION_EXPLICIT="${JOURNAL_RETENTION+x}"
EXPECT_HYSTERIA_EXPLICIT="${EXPECT_HYSTERIA+x}"
HYSTERIA_PORT_EXPLICIT="${HYSTERIA_PORT+x}"

NODE_VERSION="${NODE_VERSION:-$DEFAULT_NODE_VERSION}"
NODE_IMAGE_INPUT="${NODE_IMAGE:-}"
NODE_PORT="${NODE_PORT:-2222}"
PANEL_IPS_INPUT="${PANEL_IPS:-${PANEL_IP:-}}"
SECRET_FILE="${SECRET_FILE:-}"
SECRET_INPUT="${SECRET_KEY:-}"

ENABLE_XHTTP="${ENABLE_XHTTP:-auto}"
XHTTP_DOMAIN_INPUT="${XHTTP_DOMAIN:-}"
XHTTP_PATH="${XHTTP_PATH:-/stable-in-443/}"
XHTTP_SOCKET="${XHTTP_SOCKET:-/dev/shm/xrxh-stable.socket}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-}"
TLS_CERT_FILE="${TLS_CERT_FILE:-}"
TLS_KEY_FILE="${TLS_KEY_FILE:-}"

MANAGE_FIREWALL="${MANAGE_FIREWALL:-1}"
PUBLIC_TCP_PORTS="${PUBLIC_TCP_PORTS:-443}"
PUBLIC_UDP_PORTS="${PUBLIC_UDP_PORTS:-443}"
BLOCK_SMTP_EGRESS="${BLOCK_SMTP_EGRESS:-1}"
BLOCK_SMTP_FORWARD="${BLOCK_SMTP_FORWARD:-0}"
SMTP_EGRESS_PORTS="${SMTP_EGRESS_PORTS:-25,465,587,2525}"
ENABLE_BBR="${ENABLE_BBR:-1}"
AUTO_SWAP="${AUTO_SWAP:-1}"
ENABLE_MAINTENANCE="${ENABLE_MAINTENANCE:-1}"
BACKUP_RETENTION="${BACKUP_RETENTION:-5}"
JOURNAL_MAX_USE="${JOURNAL_MAX_USE:-256M}"
JOURNAL_RETENTION="${JOURNAL_RETENTION:-14day}"
REQUIRE_NODE_PLUGINS="${REQUIRE_NODE_PLUGINS:-1}"
VERIFY_PROFILE_TRANSPORTS="${VERIFY_PROFILE_TRANSPORTS:-1}"
REQUIRE_PROFILE_READY="${REQUIRE_PROFILE_READY:-0}"
EXPECT_HYSTERIA="${EXPECT_HYSTERIA:-1}"
HYSTERIA_PORT="${HYSTERIA_PORT:-443}"
PROFILE_WAIT_SECONDS="${PROFILE_WAIT_SECONDS:-30}"
ALLOW_OLD_KERNEL="${ALLOW_OLD_KERNEL:-0}"
ALLOW_LOW_MEMORY="${ALLOW_LOW_MEMORY:-0}"
ALLOW_NO_NET_ADMIN="${ALLOW_NO_NET_ADMIN:-0}"
ALLOW_CUSTOM_IMAGE="${ALLOW_CUSTOM_IMAGE:-0}"
RUN_SYSTEM_UPGRADE="${RUN_SYSTEM_UPGRADE:-0}"
STABILITY_SECONDS="${STABILITY_SECONDS:-30}"
APT_LOCK_TIMEOUT="${APT_LOCK_TIMEOUT:-600}"

PANEL_IPS=""
XHTTP_DOMAIN=""
SECRET_VALUE=""
SELECTED_IMAGE=""
STAGE_DIR=""
SECRET_CHECK_DIR=""
ROLLBACK_STAGE_DIR=""
BACKUP_STAGE_DIR=""
BACKUP_DIR=""
MUTATION_STARTED=0
ROLLBACK_RUNNING=0
INSTALL_CHANGED=0
LEGACY_DETECTED=0
LEGACY_RUNTIME_TUNING_DETECTED=0
CERTBOT_MANAGED=0
CERTBOT_LINEAGE_DIR=""
TLS_CHANGED=0
BACKUP_HAS_SYSTEM_FILES=0
TLS_MIN_VALID_SECONDS=604800
NGINX_RESTART_REQUIRED=0
NGINX_LOCK_FD=""

log() {
  printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

warn() {
  printf '\n[WARN] %s\n' "$*" >&2
}

die() {
  printf '\n[ERROR] %s\n' "$*" >&2
  if [[ "${MUTATION_STARTED:-0}" == "1" && "${ROLLBACK_RUNNING:-0}" == "0" ]] && \
     declare -F on_error >/dev/null 2>&1; then
    on_error 1 "${BASH_LINENO[0]:-unknown}"
  fi
  exit 1
}

bool_true() {
  case "$(printf '%s' "${1:-0}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

bool_valid() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|y|on|0|false|no|n|off) return 0 ;;
    *) return 1 ;;
  esac
}

trim() {
  local value="${1:-}"
  value="${value//$'\r'/}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

ask() {
  local prompt="$1"
  local value=""
  if [[ -r /dev/tty ]]; then
    read -r -p "$prompt" value </dev/tty || return 1
  else
    read -r -p "$prompt" value || return 1
  fi
  printf '%s' "$value"
}

ask_secret() {
  local value=""
  if [[ -r /dev/tty ]]; then
    read -r -s -p "SECRET_KEY из карточки ноды: " value </dev/tty || return 1
    printf '\n' >/dev/tty
  else
    read -r -s -p "SECRET_KEY из карточки ноды: " value || return 1
    printf '\n' >&2
  fi
  printf '%s' "$value"
}

usage() {
  cat <<'EOF'
RemnaNode installer 3.x for Panel 2.8.x / Node 2.8.0

Usage:
  setup-remnanode.sh [install|update|repair|status|rollback] [options]

Options:
  --panel-ip IP             IP/CIDR мастер-панели; можно повторять
  --panel-ips "LIST"        IPv4/IPv6/CIDR через запятую или пробел
  --node-port PORT          Control API port, default: 2222
  --node-version VERSION    Pinned Node version, default: 2.8.0
  --image IMAGE             Official image override
  --xhttp-domain DOMAIN     Настроить Nginx/TLS для xHTTP
  --xhttp-path PATH         Default: /stable-in-443/
  --xhttp-socket PATH       Default: /dev/shm/xrxh-stable.socket
  --no-xhttp                Удалить legacy xHTTP-конфиг этого installer
  --no-hysteria             Не требовать и не проверять Hysteria/UDP
  --no-firewall             Отключить весь firewall installer (control + SMTP guard)
  --allow-smtp              Не блокировать исходящие SMTP-порты
  --block-smtp-forward      Также блокировать SMTP в FORWARD (dedicated gateway)
  --no-bbr                  Не применять минимальный BBR sysctl
  --no-swap                 Не создавать небольшой swap на low-RAM VPS
  --no-maintenance          Не ставить безопасную еженедельную гигиену
  --allow-old-kernel        Разрешить kernel < 5.7 без Node Plugins
  --allow-low-memory        Разрешить RAM ниже 768 MiB
  --allow-no-net-admin      Не считать отсутствие NET_ADMIN ошибкой
  --upgrade-system          Выполнить обычный apt-get upgrade
  --backup PATH             Backup для команды rollback
  --dry-run                 Только проверить и показать план
  --yes                     Не задавать подтверждающие вопросы
  -h, --help                Показать справку

Secrets:
  Передайте SECRET_FILE=/root/node-secret.txt или вставьте SECRET_KEY в
  скрытом интерактивном запросе. Не передавайте secret аргументом процесса.

Compatible one-line command:
  curl -fsSL https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh | sudo env PANEL_IP=144.31.1.170 bash
EOF
}

need_arg() {
  [[ $# -ge 2 && -n "${2:-}" ]] || die "Для $1 требуется значение"
}

parse_args() {
  local panel_cli=""

  if [[ $# -gt 0 ]]; then
    case "$1" in
      install|update|repair|status|rollback)
        MODE="$1"
        shift
        ;;
    esac
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --panel-ip)
        need_arg "$@"
        panel_cli+=" ${2}"
        shift 2
        ;;
      --panel-ips)
        need_arg "$@"
        panel_cli+=" ${2}"
        shift 2
        ;;
      --node-port)
        need_arg "$@"
        NODE_PORT="$2"
        NODE_PORT_EXPLICIT=1
        shift 2
        ;;
      --node-version)
        need_arg "$@"
        NODE_VERSION="$2"
        NODE_VERSION_EXPLICIT=1
        shift 2
        ;;
      --image)
        need_arg "$@"
        NODE_IMAGE_INPUT="$2"
        NODE_IMAGE_EXPLICIT=1
        shift 2
        ;;
      --xhttp-domain)
        need_arg "$@"
        XHTTP_DOMAIN_INPUT="$2"
        ENABLE_XHTTP=1
        ENABLE_XHTTP_EXPLICIT=1
        shift 2
        ;;
      --xhttp-path)
        need_arg "$@"
        XHTTP_PATH="$2"
        XHTTP_PATH_EXPLICIT=1
        shift 2
        ;;
      --xhttp-socket)
        need_arg "$@"
        XHTTP_SOCKET="$2"
        XHTTP_SOCKET_EXPLICIT=1
        shift 2
        ;;
      --no-xhttp)
        ENABLE_XHTTP=0
        ENABLE_XHTTP_EXPLICIT=1
        XHTTP_DOMAIN_INPUT=""
        shift
        ;;
      --no-hysteria)
        EXPECT_HYSTERIA=0
        EXPECT_HYSTERIA_EXPLICIT=1
        shift
        ;;
      --no-firewall)
        MANAGE_FIREWALL=0
        MANAGE_FIREWALL_EXPLICIT=1
        shift
        ;;
      --allow-smtp)
        BLOCK_SMTP_EGRESS=0
        BLOCK_SMTP_EGRESS_EXPLICIT=1
        BLOCK_SMTP_FORWARD=0
        BLOCK_SMTP_FORWARD_EXPLICIT=1
        shift
        ;;
      --block-smtp-forward)
        BLOCK_SMTP_FORWARD=1
        BLOCK_SMTP_FORWARD_EXPLICIT=1
        shift
        ;;
      --no-bbr)
        ENABLE_BBR=0
        ENABLE_BBR_EXPLICIT=1
        shift
        ;;
      --no-swap)
        AUTO_SWAP=0
        AUTO_SWAP_EXPLICIT=1
        shift
        ;;
      --no-maintenance)
        ENABLE_MAINTENANCE=0
        ENABLE_MAINTENANCE_EXPLICIT=1
        shift
        ;;
      --allow-old-kernel)
        ALLOW_OLD_KERNEL=1
        shift
        ;;
      --allow-low-memory)
        ALLOW_LOW_MEMORY=1
        shift
        ;;
      --allow-no-net-admin)
        ALLOW_NO_NET_ADMIN=1
        shift
        ;;
      --upgrade-system)
        RUN_SYSTEM_UPGRADE=1
        shift
        ;;
      --backup)
        need_arg "$@"
        BACKUP_REQUEST="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --yes|-y)
        YES=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Неизвестный аргумент: $1"
        ;;
    esac
  done

  if [[ -n "$(trim "$panel_cli")" ]]; then
    PANEL_IPS_INPUT="$panel_cli"
  fi
}

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "Запустите installer от root (через sudo)."
}

acquire_lock() {
  command -v flock >/dev/null 2>&1 || \
    die "Нужен flock из пакета util-linux (apt-get install util-linux)."
  install -d -m 0755 "$(dirname "$LOCK_FILE")"
  exec 9>"$LOCK_FILE"
  flock -n 9 || die "Другой экземпляр installer уже запущен."
}

version_ge() {
  local have="$1"
  local need="$2"
  [[ "$(printf '%s\n%s\n' "$need" "$have" | sort -V | head -n1)" == "$need" ]]
}

free_mb_for_path() {
  local path="$1"
  while [[ ! -e "$path" && "$path" != "/" ]]; do
    path="$(dirname "$path")"
  done
  df -Pm -- "$path" 2>/dev/null | awk 'NR == 2 {print $4}'
}

filesystem_device_for_path() {
  local path="$1"
  while [[ ! -e "$path" && "$path" != "/" ]]; do
    path="$(dirname "$path")"
  done
  df -P -- "$path" 2>/dev/null | awk 'NR == 2 {print $1}'
}

normalize_panel_ips() {
  local raw="${1:-}"
  local token=""
  local result=""

  raw="${raw//,/ }"
  raw="${raw//$'\n'/ }"
  for token in $raw; do
    token="$(trim "$token")"
    [[ -n "$token" ]] || continue
    case " $result " in
      *" $token "*) ;;
      *) result+=" $token" ;;
    esac
  done
  printf '%s' "$(trim "$result")"
}

validate_ipv4_cidr_basic() {
  local value="$1"
  local ip="${value%%/*}"
  local prefix=""
  local IFS=.
  local -a parts=()
  local part=""

  [[ "$value" == */* ]] && prefix="${value##*/}"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  read -r -a parts <<<"$ip"
  for part in "${parts[@]}"; do
    [[ "$part" =~ ^[0-9]+$ ]] || return 1
    (( 10#$part >= 0 && 10#$part <= 255 )) || return 1
  done
  if [[ -n "$prefix" ]]; then
    [[ "$prefix" =~ ^[0-9]+$ ]] || return 1
    (( prefix >= 0 && prefix <= 32 )) || return 1
  fi
}

validate_ipv6_cidr_basic() {
  local value="$1"
  local ip="${value%%/*}"
  local prefix=""
  [[ "$value" == */* ]] && prefix="${value##*/}"
  [[ "$ip" == *:* && "$ip" =~ ^[0-9A-Fa-f:.]+$ ]] || return 1
  if [[ -n "$prefix" ]]; then
    [[ "$prefix" =~ ^[0-9]+$ ]] || return 1
    (( prefix >= 0 && prefix <= 128 )) || return 1
  fi
}

validate_panel_ips_basic() {
  local value=""
  [[ -n "$PANEL_IPS" ]] || die "Не задан PANEL_IP/PANEL_IPS."
  for value in $PANEL_IPS; do
    validate_ipv4_cidr_basic "$value" || validate_ipv6_cidr_basic "$value" || \
      die "Некорректный IP/CIDR панели: $value"
  done
}

validate_panel_ips_strict() {
  local -a panel_items=()
  read -r -a panel_items <<<"$PANEL_IPS"
  printf '%s\n' "${panel_items[@]}" | python3 -c '
import ipaddress, sys
for line in sys.stdin:
    value = line.strip()
    if not value:
        continue
    try:
        ipaddress.ip_network(value, strict=False)
    except ValueError as exc:
        raise SystemExit(f"invalid panel IP/CIDR {value}: {exc}")
' || die "Строгая проверка PANEL_IPS не пройдена."
}

normalize_domain() {
  local value
  value="$(trim "${1:-}")"
  value="${value#http://}"
  value="${value#https://}"
  value="${value%%/*}"
  value="${value%.}"
  printf '%s' "$value" | tr '[:upper:]' '[:lower:]'
}

validate_domain() {
  local domain="$1"
  [[ ${#domain} -le 253 ]] || return 1
  [[ "$domain" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] || return 1
  [[ "$domain" == *.* ]] || return 1
  [[ "$domain" != *..* ]] || return 1
}

normalize_xhttp_path() {
  XHTTP_PATH="$(trim "$XHTTP_PATH")"
  [[ "$XHTTP_PATH" == /* ]] || XHTTP_PATH="/$XHTTP_PATH"
  [[ "$XHTTP_PATH" == */ ]] || XHTTP_PATH="$XHTTP_PATH/"
}

validate_xhttp() {
  validate_domain "$XHTTP_DOMAIN" || die "Некорректный XHTTP_DOMAIN: $XHTTP_DOMAIN"
  normalize_xhttp_path
  [[ "$XHTTP_PATH" =~ ^/[A-Za-z0-9._~/-]+/$ ]] || die "Некорректный XHTTP_PATH."
  [[ "$XHTTP_PATH" != *..* && "$XHTTP_PATH" != *//* ]] || die "Опасный XHTTP_PATH."
  [[ "$XHTTP_SOCKET" =~ ^/dev/shm/[A-Za-z0-9._-]+\.(socket|sock)$ ]] || \
    die "XHTTP_SOCKET должен быть безопасным socket-файлом непосредственно в /dev/shm."
}

validate_ports_csv() {
  local list="$1"
  local item=""
  local first=""
  local last=""
  local -a items=()
  [[ -z "$list" ]] && return 0
  [[ "$list" =~ ^[0-9,-]+$ ]] || return 1
  IFS=',' read -r -a items <<<"$list"
  for item in "${items[@]}"; do
    if [[ "$item" == *-* ]]; then
      first="${item%-*}"
      last="${item#*-}"
      [[ "$first" =~ ^[0-9]+$ && "$last" =~ ^[0-9]+$ ]] || return 1
      (( 10#$first >= 1 && 10#$first <= 10#$last && 10#$last <= 65535 )) || return 1
    else
      [[ "$item" =~ ^[0-9]+$ ]] || return 1
      (( 10#$item >= 1 && 10#$item <= 65535 )) || return 1
    fi
  done
}

port_in_csv() {
  local needle="$1"
  local list="$2"
  local item=""
  local first=""
  local last=""
  local -a items=()
  [[ -z "$list" ]] && return 1
  validate_ports_csv "$list" || return 1
  IFS=',' read -r -a items <<<"$list"
  for item in "${items[@]}"; do
    if [[ "$item" == *-* ]]; then
      first="${item%-*}"
      last="${item#*-}"
      (( 10#$needle >= 10#$first && 10#$needle <= 10#$last )) && return 0
    elif (( 10#$needle == 10#$item )); then
      return 0
    fi
  done
  return 1
}

validate_settings() {
  local setting=""
  for setting in YES DRY_RUN ENABLE_XHTTP MANAGE_FIREWALL BLOCK_SMTP_EGRESS \
    BLOCK_SMTP_FORWARD ENABLE_BBR AUTO_SWAP ENABLE_MAINTENANCE REQUIRE_NODE_PLUGINS \
    VERIFY_PROFILE_TRANSPORTS REQUIRE_PROFILE_READY EXPECT_HYSTERIA ALLOW_OLD_KERNEL \
    ALLOW_LOW_MEMORY ALLOW_NO_NET_ADMIN ALLOW_CUSTOM_IMAGE RUN_SYSTEM_UPGRADE; do
    bool_valid "${!setting}" || die "$setting должен быть boolean (0/1, true/false, yes/no)."
  done
  [[ "$NODE_PORT" =~ ^[0-9]+$ ]] || die "NODE_PORT должен быть числом."
  NODE_PORT=$((10#$NODE_PORT))
  (( NODE_PORT >= 1024 && NODE_PORT <= 65535 )) || die "NODE_PORT должен быть 1024..65535."
  [[ "$NODE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9._-]+)?$ ]] || \
    die "Некорректный NODE_VERSION."
  [[ "$STABILITY_SECONDS" =~ ^[0-9]+$ ]] || die "STABILITY_SECONDS должен быть числом."
  STABILITY_SECONDS=$((10#$STABILITY_SECONDS))
  (( STABILITY_SECONDS >= 10 && STABILITY_SECONDS <= 600 )) || \
    die "STABILITY_SECONDS должен быть 10..600."
  validate_ports_csv "$PUBLIC_TCP_PORTS" || die "Некорректный PUBLIC_TCP_PORTS."
  validate_ports_csv "$PUBLIC_UDP_PORTS" || die "Некорректный PUBLIC_UDP_PORTS."
  validate_ports_csv "$SMTP_EGRESS_PORTS" || die "Некорректный SMTP_EGRESS_PORTS."
  if { bool_true "$BLOCK_SMTP_EGRESS" || bool_true "$BLOCK_SMTP_FORWARD"; } && \
     [[ -z "$SMTP_EGRESS_PORTS" ]]; then
    die "При BLOCK_SMTP_EGRESS=1 список SMTP_EGRESS_PORTS не может быть пустым."
  fi
  [[ "$HYSTERIA_PORT" =~ ^[0-9]+$ ]] || die "HYSTERIA_PORT должен быть числом."
  HYSTERIA_PORT=$((10#$HYSTERIA_PORT))
  (( HYSTERIA_PORT >= 1 && HYSTERIA_PORT <= 65535 )) || die "HYSTERIA_PORT должен быть 1..65535."
  if bool_true "$EXPECT_HYSTERIA" && ! port_in_csv "$HYSTERIA_PORT" "$PUBLIC_UDP_PORTS"; then
    if [[ -n "$PUBLIC_UDP_PORTS" ]]; then
      PUBLIC_UDP_PORTS="$HYSTERIA_PORT,$PUBLIC_UDP_PORTS"
    else
      PUBLIC_UDP_PORTS="$HYSTERIA_PORT"
    fi
  fi
  [[ "$PROFILE_WAIT_SECONDS" =~ ^[0-9]+$ ]] || die "PROFILE_WAIT_SECONDS должен быть числом."
  PROFILE_WAIT_SECONDS=$((10#$PROFILE_WAIT_SECONDS))
  (( PROFILE_WAIT_SECONDS >= 0 && PROFILE_WAIT_SECONDS <= 300 )) || \
    die "PROFILE_WAIT_SECONDS должен быть 0..300."
  [[ "$BACKUP_RETENTION" =~ ^[0-9]+$ ]] || die "BACKUP_RETENTION должен быть числом."
  BACKUP_RETENTION=$((10#$BACKUP_RETENTION))
  (( BACKUP_RETENTION >= 2 && BACKUP_RETENTION <= 50 )) || \
    die "BACKUP_RETENTION должен быть 2..50."
  [[ "$JOURNAL_MAX_USE" =~ ^[1-9][0-9]*[KMG]$ ]] || die "JOURNAL_MAX_USE: пример 256M."
  [[ "$JOURNAL_RETENTION" =~ ^[1-9][0-9]*(s|min|h|day|week|month|year)$ ]] || \
    die "JOURNAL_RETENTION: пример 14day."
  if port_in_csv "$NODE_PORT" "$PUBLIC_TCP_PORTS"; then
    die "NODE_PORT $NODE_PORT нельзя включать в PUBLIC_TCP_PORTS: control API должен быть доступен только панели."
  fi

  if [[ -n "$NODE_IMAGE_INPUT" ]] && ! bool_true "$ALLOW_CUSTOM_IMAGE"; then
    [[ "$NODE_IMAGE_INPUT" == "ghcr.io/remnawave/node:"* || "$NODE_IMAGE_INPUT" == "remnawave/node:"* ]] || \
      die "Разрешены только официальные образы Remnawave. Для своего image задайте ALLOW_CUSTOM_IMAGE=1."
  fi
}

load_saved_state() {
  local state_source=""

  if [[ -r "$STATE_FILE" ]]; then
    state_source="$STATE_FILE"
  elif [[ -r "$INSTALLER_CONFIG" ]]; then
    state_source="$INSTALLER_CONFIG"
  fi
  if [[ -n "$state_source" ]]; then
    # shellcheck disable=SC1090
    source "$state_source"
  fi

  [[ -n "$PANEL_IPS_INPUT" ]] || PANEL_IPS_INPUT="${SAVED_PANEL_IPS:-}"
  [[ -n "$XHTTP_DOMAIN_INPUT" ]] || XHTTP_DOMAIN_INPUT="${SAVED_XHTTP_DOMAIN:-}"
  [[ -n "$NODE_PORT_EXPLICIT" || -z "${SAVED_NODE_PORT:-}" ]] || NODE_PORT="$SAVED_NODE_PORT"
  [[ -n "$ENABLE_XHTTP_EXPLICIT" || -z "${SAVED_ENABLE_XHTTP:-}" ]] || ENABLE_XHTTP="$SAVED_ENABLE_XHTTP"
  [[ -n "$XHTTP_PATH_EXPLICIT" || -z "${SAVED_XHTTP_PATH:-}" ]] || XHTTP_PATH="$SAVED_XHTTP_PATH"
  [[ -n "$XHTTP_SOCKET_EXPLICIT" || -z "${SAVED_XHTTP_SOCKET:-}" ]] || XHTTP_SOCKET="$SAVED_XHTTP_SOCKET"
  [[ -n "$MANAGE_FIREWALL_EXPLICIT" || -z "${SAVED_MANAGE_FIREWALL:-}" ]] || MANAGE_FIREWALL="$SAVED_MANAGE_FIREWALL"
  [[ -n "$PUBLIC_TCP_PORTS_EXPLICIT" || -z "${SAVED_PUBLIC_TCP_PORTS:-}" ]] || PUBLIC_TCP_PORTS="$SAVED_PUBLIC_TCP_PORTS"
  [[ -n "$PUBLIC_UDP_PORTS_EXPLICIT" || -z "${SAVED_PUBLIC_UDP_PORTS:-}" ]] || PUBLIC_UDP_PORTS="$SAVED_PUBLIC_UDP_PORTS"
  [[ -n "$BLOCK_SMTP_EGRESS_EXPLICIT" || -z "${SAVED_BLOCK_SMTP_EGRESS:-}" ]] || BLOCK_SMTP_EGRESS="$SAVED_BLOCK_SMTP_EGRESS"
  [[ -n "$BLOCK_SMTP_FORWARD_EXPLICIT" || -z "${SAVED_BLOCK_SMTP_FORWARD:-}" ]] || BLOCK_SMTP_FORWARD="$SAVED_BLOCK_SMTP_FORWARD"
  [[ -n "$SMTP_EGRESS_PORTS_EXPLICIT" || -z "${SAVED_SMTP_EGRESS_PORTS:-}" ]] || SMTP_EGRESS_PORTS="$SAVED_SMTP_EGRESS_PORTS"
  [[ -n "$ENABLE_BBR_EXPLICIT" || -z "${SAVED_ENABLE_BBR:-}" ]] || ENABLE_BBR="$SAVED_ENABLE_BBR"
  [[ -n "$AUTO_SWAP_EXPLICIT" || -z "${SAVED_AUTO_SWAP:-}" ]] || AUTO_SWAP="$SAVED_AUTO_SWAP"
  [[ -n "$ENABLE_MAINTENANCE_EXPLICIT" || -z "${SAVED_ENABLE_MAINTENANCE:-}" ]] || ENABLE_MAINTENANCE="$SAVED_ENABLE_MAINTENANCE"
  [[ -n "$BACKUP_RETENTION_EXPLICIT" || -z "${SAVED_BACKUP_RETENTION:-}" ]] || BACKUP_RETENTION="$SAVED_BACKUP_RETENTION"
  [[ -n "$JOURNAL_MAX_USE_EXPLICIT" || -z "${SAVED_JOURNAL_MAX_USE:-}" ]] || JOURNAL_MAX_USE="$SAVED_JOURNAL_MAX_USE"
  [[ -n "$JOURNAL_RETENTION_EXPLICIT" || -z "${SAVED_JOURNAL_RETENTION:-}" ]] || JOURNAL_RETENTION="$SAVED_JOURNAL_RETENTION"
  [[ -n "$EXPECT_HYSTERIA_EXPLICIT" || -z "${SAVED_EXPECT_HYSTERIA:-}" ]] || EXPECT_HYSTERIA="$SAVED_EXPECT_HYSTERIA"
  [[ -n "$HYSTERIA_PORT_EXPLICIT" || -z "${SAVED_HYSTERIA_PORT:-}" ]] || HYSTERIA_PORT="$SAVED_HYSTERIA_PORT"

  if [[ "$MODE" == "repair" ]]; then
    [[ -n "$NODE_VERSION_EXPLICIT" || -z "${SAVED_NODE_VERSION:-}" ]] || NODE_VERSION="$SAVED_NODE_VERSION"
    [[ -n "$NODE_IMAGE_EXPLICIT" || -z "${SAVED_NODE_IMAGE:-}" ]] || NODE_IMAGE_INPUT="$SAVED_NODE_IMAGE"
  fi
}

detect_legacy_xhttp() {
  local site="/etc/nginx/sites-available/remnanode-xhttp.conf"
  local detected=""
  [[ -n "$XHTTP_DOMAIN_INPUT" || ! -r "$site" ]] && return 0
  detected="$(awk '$1 == "server_name" {gsub(/;/, "", $2); print $2; exit}' "$site" 2>/dev/null || true)"
  if validate_domain "$detected" 2>/dev/null; then
    XHTTP_DOMAIN_INPUT="$detected"
  fi
}

is_known_legacy_compose_override() {
  local override_file="$1"
  [[ -f "$override_file" && -r "$override_file" ]] || return 1
  grep -Eq '(/opt/remnanode/overrides/|/opt/app/dist/src/common/utils/generate-api-config\.js|/opt/app/dist/src/modules/stats/stats\.service\.js|/opt/app/dist/src/modules/xray-core/xray\.service\.js|:[[:space:]]*/usr/local/bin/(xray|rw-core)(:|[[:space:]]|$))' \
    "$override_file"
}

validate_existing_compose_overrides() {
  local override_file=""
  local -a override_files=(
    "$NODE_ROOT/docker-compose.override.yml"
    "$NODE_ROOT/docker-compose.override.yaml"
  )

  for override_file in "${override_files[@]}"; do
    [[ -e "$override_file" || -L "$override_file" ]] || continue
    if is_known_legacy_compose_override "$override_file"; then
      LEGACY_DETECTED=1
      warn "Найдена известная legacy-подмена $(basename "$override_file"); после backup она будет удалена, а контейнер пересоздан."
      continue
    fi
    die "Найден неизвестный $override_file. Установщик не удаляет пользовательские Compose override автоматически: сохраните его отдельно и перенесите нужные параметры в новый основной compose после ручной проверки."
  done
}

detect_existing_secret() {
  local value=""

  if [[ -n "$SECRET_FILE" ]]; then
    [[ -r "$SECRET_FILE" ]] || die "SECRET_FILE недоступен: $SECRET_FILE"
    value="$(tr -d '\r\n' <"$SECRET_FILE")"
  elif [[ -n "$SECRET_INPUT" ]]; then
    value="$SECRET_INPUT"
  elif [[ -r "$ENV_FILE" ]]; then
    value="$(sed -n 's/^SECRET_KEY=//p' "$ENV_FILE" | head -n1)"
  elif command -v docker >/dev/null 2>&1 && docker inspect remnanode >/dev/null 2>&1; then
    value="$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' remnanode 2>/dev/null | sed -n 's/^SECRET_KEY=//p' | head -n1)"
  fi

  value="$(trim "$value")"
  value="${value#SECRET_KEY=}"
  if [[ "$value" == \"*\" && "$value" == *\" ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
    value="${value:1:${#value}-2}"
  fi

  SECRET_VALUE="$value"
  unset SECRET_KEY SECRET_INPUT
}

validate_secret_basic() {
  [[ -n "$SECRET_VALUE" ]] || die "SECRET_KEY пустой."
  [[ "$SECRET_VALUE" != *$'\n'* && "$SECRET_VALUE" != *$'\r'* ]] || die "SECRET_KEY содержит перенос строки."
  [[ "$SECRET_VALUE" =~ ^[A-Za-z0-9_+/=-]+$ ]] || die "SECRET_KEY содержит недопустимые символы."
  (( ${#SECRET_VALUE} >= 128 )) || die "SECRET_KEY слишком короткий для Node 2.8.0."
}

validate_secret_payload() {
  local check_dir=""
  local cert_public=""
  local key_public=""
  check_dir="$(mktemp -d /tmp/remnanode-secret-check.XXXXXX)"
  SECRET_CHECK_DIR="$check_dir"
  chmod 0700 "$check_dir"

  if ! printf '%s' "$SECRET_VALUE" | python3 -c '
import base64, json, os, sys
out = sys.argv[1]
raw = sys.stdin.buffer.read().strip()
try:
    raw += b"=" * (-len(raw) % 4)
    try:
        decoded = base64.b64decode(raw, validate=True)
    except Exception:
        decoded = base64.urlsafe_b64decode(raw)
    payload = json.loads(decoded.decode("utf-8"))
except Exception:
    raise SystemExit(1)
files = {
    "caCertPem": "ca.pem",
    "jwtPublicKey": "jwt-public.pem",
    "nodeCertPem": "node-cert.pem",
    "nodeKeyPem": "node-key.pem",
}
if not isinstance(payload, dict) or any(not isinstance(payload.get(k), str) or not payload[k].strip() for k in files):
    raise SystemExit(1)
for key, name in files.items():
    path = os.path.join(out, name)
    value = payload[key].replace("\\n", "\n").replace("\r\n", "\n")
    with open(path, "x", encoding="utf-8", newline="\n") as handle:
        handle.write(value)
    os.chmod(path, 0o600)
' "$check_dir"
  then
    rm -rf "$check_dir"
    SECRET_CHECK_DIR=""
    die "SECRET_KEY не является валидным payload RemnaNode 2.8.0. Скопируйте его заново из панели."
  fi

  if ! openssl x509 -in "$check_dir/ca.pem" -checkend "$TLS_MIN_VALID_SECONDS" -noout >/dev/null 2>&1 || \
     ! openssl x509 -in "$check_dir/node-cert.pem" -checkend "$TLS_MIN_VALID_SECONDS" -noout >/dev/null 2>&1 || \
     ! openssl pkey -in "$check_dir/node-key.pem" -noout >/dev/null 2>&1 || \
     ! openssl pkey -pubin -in "$check_dir/jwt-public.pem" -noout >/dev/null 2>&1 || \
     ! openssl verify -CAfile "$check_dir/ca.pem" "$check_dir/node-cert.pem" >/dev/null 2>&1; then
    rm -rf "$check_dir"
    SECRET_CHECK_DIR=""
    die "Сертификаты/ключи SECRET_KEY повреждены, просрочены или не образуют доверенную цепочку."
  fi

  cert_public="$(openssl x509 -in "$check_dir/node-cert.pem" -pubkey -noout | \
    openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
  key_public="$(openssl pkey -in "$check_dir/node-key.pem" -pubout -outform DER 2>/dev/null | \
    sha256sum | awk '{print $1}')"
  rm -rf "$check_dir"
  SECRET_CHECK_DIR=""
  [[ -n "$cert_public" && "$cert_public" == "$key_public" ]] || \
    die "nodeCertPem и nodeKeyPem в SECRET_KEY не образуют пару."
}

collect_inputs() {
  local answer=""

  load_saved_state
  detect_legacy_xhttp
  validate_existing_compose_overrides

  PANEL_IPS="$(normalize_panel_ips "$PANEL_IPS_INPUT")"
  if [[ -z "$PANEL_IPS" && -r /etc/cake_panel/trusted_panel_ips.txt ]]; then
    PANEL_IPS="$(normalize_panel_ips "$(tr '\n' ' ' </etc/cake_panel/trusted_panel_ips.txt)")"
  fi
  if [[ -z "$PANEL_IPS" ]]; then
    bool_true "$YES" && die "В non-interactive режиме нужен PANEL_IP/PANEL_IPS."
    PANEL_IPS="$(normalize_panel_ips "$(ask 'IP или CIDR мастер-панели: ')")"
  fi
  validate_panel_ips_basic

  if [[ "$ENABLE_XHTTP" == "auto" ]]; then
    if [[ -n "$XHTTP_DOMAIN_INPUT" ]]; then
      ENABLE_XHTTP=1
    elif bool_true "$YES"; then
      ENABLE_XHTTP=0
    else
      answer="$(ask 'Настроить xHTTP через Nginx/TLS? [y/N]: ' || true)"
      bool_true "$answer" && ENABLE_XHTTP=1 || ENABLE_XHTTP=0
    fi
  fi

  if bool_true "$ENABLE_XHTTP"; then
    XHTTP_DOMAIN="$(normalize_domain "$XHTTP_DOMAIN_INPUT")"
    if [[ -z "$XHTTP_DOMAIN" ]]; then
      bool_true "$YES" && die "Для xHTTP нужен XHTTP_DOMAIN."
      XHTTP_DOMAIN="$(normalize_domain "$(ask 'Домен xHTTP: ')")"
    fi
    validate_xhttp
    if ! port_in_csv 80 "$PUBLIC_TCP_PORTS"; then
      if [[ -n "$PUBLIC_TCP_PORTS" ]]; then
        PUBLIC_TCP_PORTS="80,$PUBLIC_TCP_PORTS"
      else
        PUBLIC_TCP_PORTS="80"
      fi
    fi
    if ! port_in_csv 443 "$PUBLIC_TCP_PORTS"; then
      if [[ -n "$PUBLIC_TCP_PORTS" ]]; then
        PUBLIC_TCP_PORTS="443,$PUBLIC_TCP_PORTS"
      else
        PUBLIC_TCP_PORTS="443"
      fi
    fi
  else
    XHTTP_DOMAIN=""
  fi

  if bool_true "$EXPECT_HYSTERIA" && ! bool_true "$ENABLE_XHTTP"; then
    if [[ -n "$TLS_CERT_FILE" || -n "$TLS_KEY_FILE" ]]; then
      [[ -n "$TLS_CERT_FILE" && -n "$TLS_KEY_FILE" ]] || \
        die "Для Hysteria нужно задать и TLS_CERT_FILE, и TLS_KEY_FILE."
    elif [[ ! -r "$TLS_DIR/fullchain.pem" || ! -r "$TLS_DIR/privkey.pem" ]]; then
      die "Hysteria требует TLS. Включите xHTTP с доменом, задайте TLS_CERT_FILE/TLS_KEY_FILE или используйте --no-hysteria."
    fi
  fi
  detect_existing_secret
  if [[ -z "$SECRET_VALUE" ]]; then
    bool_true "$YES" && die "В non-interactive режиме нужен SECRET_FILE или SECRET_KEY."
    SECRET_VALUE="$(ask_secret)"
  fi
  validate_secret_basic
  validate_settings
}

preflight_host() {
  local os_id=""
  local os_like=""
  local arch=""
  local kernel=""
  local mem_mb=""
  local cpu_count=""
  local free_mb=""
  local existing_node_mb=0
  local swap_reserve_mb=0
  local required_free_mb=1536
  local current_swap_mb=0
  local control_listener=""
  local image_reserve_mb=0
  local image_size_bytes=0
  local backup_free_mb=0
  local backup_need_mb=256
  local opt_free_mb=0
  local docker_free_mb=0
  local docker_root="/var/lib/docker"
  local backup_device=""
  local docker_device=""

  [[ -r /etc/os-release ]] || die "Не удалось определить ОС."
  # shellcheck disable=SC1091
  source /etc/os-release
  os_id="${ID:-}"
  os_like="${ID_LIKE:-}"
  case " $os_id $os_like " in
    *" ubuntu "*|*" debian "*) ;;
    *) die "Поддерживаются только Ubuntu и Debian. Обнаружено: ${PRETTY_NAME:-unknown}" ;;
  esac

  [[ "$(tr -d '\n' </proc/1/comm 2>/dev/null || true)" == "systemd" ]] || \
    die "Требуется systemd как PID 1."

  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64|aarch64|arm64) ;;
    *) die "RemnaNode 2.8.0 не публикуется для архитектуры $arch." ;;
  esac

  kernel="$(uname -r | cut -d- -f1)"
  if ! version_ge "$kernel" "5.7"; then
    if bool_true "$ALLOW_OLD_KERNEL"; then
      warn "Kernel $kernel ниже 5.7: Node запустится, но nftables plugins могут не работать."
    else
      die "Kernel $kernel ниже 5.7. Обновите kernel или задайте ALLOW_OLD_KERNEL=1."
    fi
  fi

  mem_mb="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
  cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc)"
  free_mb="$(df -Pm / | awk 'NR==2 {print $4}')"
  current_swap_mb="$(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo)"
  if bool_true "$AUTO_SWAP"; then
    if (( mem_mb < 1536 && current_swap_mb < 512 )); then
      swap_reserve_mb=1024
    elif (( mem_mb < 2048 && current_swap_mb == 0 )); then
      swap_reserve_mb=512
    fi
  fi
  if [[ -d "$NODE_ROOT" ]]; then
    existing_node_mb="$(du -sm "$NODE_ROOT" 2>/dev/null | awk '{print $1}' || printf '0')"
    [[ "$existing_node_mb" =~ ^[0-9]+$ ]] || existing_node_mb=0
  fi
  if command -v docker >/dev/null 2>&1 && docker inspect remnanode >/dev/null 2>&1; then
    image_size_bytes="$(docker image inspect --format '{{.Size}}' "$(docker inspect --format '{{.Image}}' remnanode)" 2>/dev/null || printf '0')"
    [[ "$image_size_bytes" =~ ^[0-9]+$ ]] || image_size_bytes=0
    image_reserve_mb=$(((image_size_bytes + 1048575) / 1048576))
  fi
  required_free_mb=$((required_free_mb + swap_reserve_mb + existing_node_mb + image_reserve_mb))
  backup_need_mb=$((backup_need_mb + existing_node_mb + image_reserve_mb))
  (( cpu_count >= 1 )) || die "Нужен минимум 1 CPU."
  if (( mem_mb < 768 )) && ! bool_true "$ALLOW_LOW_MEMORY"; then
    die "RAM ${mem_mb} MiB ниже безопасного минимума. Нужен VPS от 1 GiB или ALLOW_LOW_MEMORY=1."
  fi
  (( free_mb >= required_free_mb )) || \
    die "Недостаточно места: свободно ${free_mb} MiB, безопасный минимум сейчас ${required_free_mb} MiB (image/packages/backup/swap)."

  backup_free_mb="$(free_mb_for_path "$BACKUP_ROOT" || printf '0')"
  opt_free_mb="$(free_mb_for_path "$NODE_ROOT" || printf '0')"
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    docker_root="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || printf '/var/lib/docker')"
  fi
  docker_free_mb="$(free_mb_for_path "$docker_root" || printf '0')"
  backup_device="$(filesystem_device_for_path "$BACKUP_ROOT" || true)"
  docker_device="$(filesystem_device_for_path "$docker_root" || true)"
  if [[ -n "$backup_device" && "$backup_device" == "$docker_device" ]]; then
    backup_need_mb=$((backup_need_mb + 1024))
  fi
  [[ "$backup_free_mb" =~ ^[0-9]+$ ]] || backup_free_mb=0
  [[ "$opt_free_mb" =~ ^[0-9]+$ ]] || opt_free_mb=0
  [[ "$docker_free_mb" =~ ^[0-9]+$ ]] || docker_free_mb=0
  (( backup_free_mb >= backup_need_mb )) || \
    die "Недостаточно места на filesystem backup: ${backup_free_mb} MiB, требуется около ${backup_need_mb} MiB ($BACKUP_ROOT)."
  (( opt_free_mb >= 256 )) || die "На filesystem $NODE_ROOT осталось меньше 256 MiB."
  (( docker_free_mb >= 1024 )) || \
    die "На Docker filesystem ($docker_root) нужно минимум 1024 MiB свободного места."

  if command -v timedatectl >/dev/null 2>&1; then
    if [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)" == "no" ]]; then
      warn "NTP пока не синхронизирован. Неверное время может ломать mTLS."
    fi
  fi

  if bool_true "$MANAGE_FIREWALL" && systemctl is-active --quiet firewalld.service 2>/dev/null; then
    die "Обнаружен активный firewalld. Отключите его или запустите с --no-firewall и настройте ${NODE_PORT}/tcp вручную."
  fi
  if command -v docker >/dev/null 2>&1 && ! docker info >/dev/null 2>&1; then
    die "Docker установлен, но daemon недоступен. Безопасный backup существующего контейнера невозможен; запустите Docker и повторите."
  fi
  if command -v ss >/dev/null 2>&1; then
    control_listener="$(ss -H -ltnp "( sport = :$NODE_PORT )" 2>/dev/null | head -n1 || true)"
    if [[ -n "$control_listener" ]] && \
       { ! command -v docker >/dev/null 2>&1 || ! docker inspect remnanode >/dev/null 2>&1; }; then
      die "Control port $NODE_PORT уже занят посторонним процессом: $control_listener"
    fi
  fi

  log "Preflight: ${PRETTY_NAME:-$os_id}, kernel=$kernel, arch=$arch, CPU=$cpu_count, RAM=${mem_mb}MiB, free=${free_mb}MiB"
}

print_plan() {
  log "План установки"
  printf '  mode:             %s\n' "$MODE"
  printf '  panel compatible: %s\n' "$PANEL_COMPAT_VERSION"
  printf '  node version:     %s\n' "$NODE_VERSION"
  printf '  node port:        %s/tcp\n' "$NODE_PORT"
  printf '  panel sources:    %s\n' "$PANEL_IPS"
  printf '  firewall:         %s\n' "$MANAGE_FIREWALL"
  printf '  public TCP ports: %s\n' "${PUBLIC_TCP_PORTS:-none}"
  printf '  public UDP ports: %s\n' "${PUBLIC_UDP_PORTS:-none}"
  if bool_true "$MANAGE_FIREWALL"; then
    printf '  SMTP anti-abuse:  OUTPUT=%s FORWARD=%s (tcp/%s)\n' "$BLOCK_SMTP_EGRESS" "$BLOCK_SMTP_FORWARD" "$SMTP_EGRESS_PORTS"
  else
    printf '  SMTP anti-abuse:  disabled together with installer firewall\n'
  fi
  printf '  BBR baseline:     %s\n' "$ENABLE_BBR"
  printf '  automatic swap:   %s\n' "$AUTO_SWAP"
  printf '  safe maintenance: %s (keep %s backups)\n' "$ENABLE_MAINTENANCE" "$BACKUP_RETENTION"
  printf '  native plugins:   %s\n' "$REQUIRE_NODE_PLUGINS"
  printf '  Hysteria check:   udp/%s\n' "$HYSTERIA_PORT"
  if bool_true "$ENABLE_XHTTP"; then
    printf '  xHTTP domain:     %s\n' "$XHTTP_DOMAIN"
    printf '  xHTTP path:       %s\n' "$XHTTP_PATH"
    printf '  xHTTP socket:     %s\n' "$XHTTP_SOCKET"
    printf '  xHTTP transport:  HTTP/2 over TLS (HTTP/3 disabled)\n'
  else
    printf '  xHTTP module:     disabled\n'
  fi
  printf '  secret:           valid-looking, length=%s (hidden)\n' "${#SECRET_VALUE}"
}

apt_retry() {
  local attempt=1
  local max=4
  until apt-get -o "DPkg::Lock::Timeout=$APT_LOCK_TIMEOUT" "$@"; do
    (( attempt >= max )) && return 1
    warn "apt-get $* не выполнен, повтор $attempt/$max"
    sleep $((attempt * 4))
    ((attempt++))
  done
}

install_base_packages() {
  log "Устанавливаю минимальные зависимости"
  apt_retry update
  apt_retry install -y --no-install-recommends \
    ca-certificates curl gnupg iproute2 iptables nftables openssl \
    python3 procps kmod logrotate tar gzip util-linux

  if bool_true "$RUN_SYSTEM_UPGRADE"; then
    log "Выполняю opt-in обновление пакетов ОС"
    apt_retry upgrade -y
  fi
}

ensure_docker() {
  local installer=""

  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    systemctl enable docker.service >/dev/null || die "Не удалось включить Docker при загрузке."
    systemctl start docker.service >/dev/null || die "Не удалось запустить Docker."
    docker info >/dev/null 2>&1 || die "Docker daemon недоступен после запуска."
    return 0
  fi

  log "Устанавливаю Docker Engine и Compose plugin официальным способом"
  installer="$(mktemp /tmp/get-docker.XXXXXX.sh)"
  curl -fsSL --retry 4 --retry-delay 3 https://get.docker.com -o "$installer"
  sh "$installer"
  rm -f "$installer"
  systemctl enable docker.service >/dev/null
  systemctl start docker.service
  docker info >/dev/null 2>&1 || die "Docker daemon недоступен после установки."
  docker compose version >/dev/null 2>&1 || die "Docker Compose v2 не установлен."
}

legacy_paths() {
  cat <<'EOF'
/usr/local/sbin/remnanode-watchdog.sh
/etc/systemd/system/remnanode-watchdog.service
/etc/systemd/system/remnanode-watchdog.timer
/usr/local/sbin/remnanode-bbr-telemetry-deps.sh
/etc/systemd/system/remnanode-bbr-telemetry-deps.service
/etc/systemd/system/remnanode-bbr-telemetry-deps.timer
/usr/local/sbin/remnanode-oom-guard.sh
/etc/systemd/system/remnanode-oom-guard.service
/etc/systemd/system/remnanode-oom-guard.timer
/usr/local/sbin/remnanode-nightly-cleanup.sh
/etc/systemd/system/remnanode-nightly-cleanup.service
/etc/systemd/system/remnanode-nightly-cleanup.timer
/usr/local/sbin/remnanode-rps.sh
/etc/systemd/system/remnanode-rps.service
/etc/systemd/system/remnanode-qdisc.service
/usr/local/sbin/remnanode-offload-tune.sh
/etc/systemd/system/remnanode-offload-tune.service
/usr/local/sbin/remnanode-mss-clamp.sh
/etc/systemd/system/remnanode-mss-clamp.service
/usr/local/sbin/remnanode-spamhaus-egress-guard.sh
/etc/systemd/system/remnanode-spamhaus-egress-guard.service
/etc/systemd/system/remnanode-spamhaus-egress-guard.timer
/usr/local/sbin/remnanode-xhttp-sync.sh
/etc/systemd/system/remnanode-xhttp-sync.service
/etc/systemd/system/remnanode-xhttp-sync.timer
/etc/systemd/system/remnanode-compose.service
/etc/systemd/system/node-mtu.service
/etc/systemd/system/nginx.service.d/oom-protect.conf
/etc/systemd/system/nginx.service.d/limits.conf
/etc/systemd/system/nginx.service.d/restart-on-failure.conf
/etc/nginx/conf.d/00-tokervpn-xhttp-tuning.conf
/etc/nginx/sites-available/remnanode-xhttp-http.conf
/etc/nginx/sites-enabled/remnanode-xhttp-http.conf
/etc/nginx/sites-available/remnanode-xhttp-h3-8443.conf
/etc/nginx/sites-enabled/remnanode-xhttp-h3-8443.conf
/etc/ssh/sshd_config.d/99-remnanode-stability.conf
/etc/systemd/resolved.conf.d/99-remnanode.conf
/etc/security/limits.d/99-remnanode.conf
EOF
}

legacy_units() {
  cat <<'EOF'
remnanode-watchdog.timer
remnanode-watchdog.service
remnanode-bbr-telemetry-deps.timer
remnanode-bbr-telemetry-deps.service
remnanode-oom-guard.timer
remnanode-oom-guard.service
remnanode-nightly-cleanup.timer
remnanode-nightly-cleanup.service
remnanode-rps.service
remnanode-qdisc.service
remnanode-offload-tune.service
remnanode-mss-clamp.service
remnanode-spamhaus-egress-guard.timer
remnanode-spamhaus-egress-guard.service
remnanode-xhttp-sync.timer
remnanode-xhttp-sync.service
remnanode-compose.service
node-mtu.service
EOF
}

managed_units() {
  cat <<'EOF'
remnanode-maintenance.timer
remnanode-xhttp-socket-guard.timer
remnanode-xhttp-socket-guard.service
remnanode-firewall.service
docker.service
docker.socket
containerd.service
nginx.service
certbot.timer
EOF
}

backup_system_paths() {
  local -a relative=()
  local path=""
  BACKUP_HAS_SYSTEM_FILES=0

  while IFS= read -r path; do
    [[ -e "$path" || -L "$path" ]] || continue
    relative+=("${path#/}")
  done < <(legacy_paths)

  for path in \
    "$SYSCTL_FILE" "$LOGROTATE_FILE" "$FIREWALL_SCRIPT" "$FIREWALL_SERVICE" \
    "$INSTALLER_CONFIG" "$STATE_FILE" "$NGINX_SITE_AVAILABLE" "$NGINX_SITES_ENABLED_SITE" \
    "$NGINX_CONF_D_SITE" "$NGINX_BOOTSTRAP_AVAILABLE" "$NGINX_SITES_ENABLED_BOOTSTRAP" \
    "$NGINX_CONF_D_BOOTSTRAP" \
    "$CERT_DEPLOY_HOOK" "$NGINX_CAPACITY_DROPIN" "$MAINTENANCE_SCRIPT" "$MAINTENANCE_SERVICE" \
    "$MAINTENANCE_TIMER" "$XHTTP_GUARD_SCRIPT" "$XHTTP_GUARD_SERVICE" "$XHTTP_GUARD_TIMER" \
    "$JOURNALD_DROPIN" "$LEGACY_REBOOT_MARKER" "$TLS_DIR" "$PANEL_IPS_FILE" \
    /etc/fstab /etc/nginx/nginx.conf /etc/ufw/user.rules /etc/ufw/user6.rules; do
    [[ -e "$path" || -L "$path" ]] || continue
    case " ${relative[*]} " in
      *" ${path#/} "*) ;;
      *) relative+=("${path#/}") ;;
    esac
  done

  if (( ${#relative[@]} > 0 )); then
    tar -C / -czf "$BACKUP_DIR/system-files.tgz" "${relative[@]}"
    chmod 0600 "$BACKUP_DIR/system-files.tgz"
    BACKUP_HAS_SYSTEM_FILES=1
  fi
}

managed_sysctl_keys() {
  cat <<'EOF'
fs.file-max
net.core.somaxconn
net.core.netdev_max_backlog
net.core.rmem_max
net.core.wmem_max
net.ipv4.ip_local_port_range
net.ipv4.tcp_keepalive_time
net.ipv4.tcp_keepalive_intvl
net.ipv4.tcp_keepalive_probes
net.ipv4.tcp_max_syn_backlog
net.ipv4.tcp_mtu_probing
net.ipv4.tcp_rmem
net.ipv4.tcp_wmem
net.ipv4.udp_rmem_min
net.ipv4.udp_wmem_min
net.netfilter.nf_conntrack_max
net.core.default_qdisc
net.ipv4.tcp_congestion_control
EOF
}

managed_sysctl_key_allowed() {
  local wanted="$1"
  local key=""
  while IFS= read -r key; do
    [[ "$wanted" == "$key" ]] && return 0
  done < <(managed_sysctl_keys)
  return 1
}

backup_sysctl_runtime() {
  local key=""
  local value=""
  : >"$BACKUP_DIR/sysctl-runtime.tsv"
  while IFS= read -r key; do
    value="$(sysctl -n "$key" 2>/dev/null || true)"
    [[ -n "$value" && "$value" != *$'\n'* ]] || continue
    # Linux renders vector sysctls such as tcp_rmem with tabs. Normalize the
    # separators so the TSV backup keeps the complete value and rollback can
    # restore it as one quoted sysctl assignment.
    value="$(printf '%s' "$value" | tr '\t' ' ' | tr -s ' ')"
    value="$(trim "$value")"
    [[ -n "$value" && "$value" != *$'\t'* ]] || continue
    printf '%s\t%s\n' "$key" "$value" >>"$BACKUP_DIR/sysctl-runtime.tsv"
  done < <(managed_sysctl_keys)
  chmod 0600 "$BACKUP_DIR/sysctl-runtime.tsv"
}

create_backup() {
  local timestamp=""
  local final_backup=""
  local previous_image=""
  local previous_image_id=""
  local had_node_root=0
  local had_container=0
  local was_running=0
  local had_swap_file=0
  local was_swap_active=0
  local unit=""
  local previous_legacy_enabled_units=""
  local previous_legacy_active_units=""
  local previous_managed_enabled_units=""
  local previous_managed_active_units=""
  local had_image_archive=0

  install -d -m 0700 "$BACKUP_ROOT"
  while :; do
    timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
    final_backup="$BACKUP_ROOT/$timestamp"
    [[ -e "$final_backup" ]] || break
    sleep 1
  done
  BACKUP_STAGE_DIR="$BACKUP_ROOT/.partial-$timestamp-$$"
  BACKUP_DIR="$BACKUP_STAGE_DIR"
  install -d -m 0700 "$BACKUP_DIR"

  if [[ -d "$NODE_ROOT" ]]; then
    had_node_root=1
    tar -C / -czf "$BACKUP_DIR/node-root.tgz" \
      --exclude='opt/remnanode/backups' \
      --exclude='opt/remnanode/*.bak.*' \
      opt/remnanode
    chmod 0600 "$BACKUP_DIR/node-root.tgz"
  fi

  if command -v docker >/dev/null 2>&1 && docker inspect remnanode >/dev/null 2>&1; then
    had_container=1
    previous_image="$(docker inspect --format '{{.Config.Image}}' remnanode 2>/dev/null || true)"
    previous_image_id="$(docker inspect --format '{{.Image}}' remnanode 2>/dev/null || true)"
    [[ "$(docker inspect --format '{{.State.Running}}' remnanode 2>/dev/null || true)" == "true" ]] && was_running=1
    [[ -n "$previous_image" && -n "$previous_image_id" ]] || \
      die "Не удалось определить точный image существующего remnanode для backup."
    docker image save "$previous_image_id" | gzip -1 >"$BACKUP_DIR/previous-image.tar.gz"
    chmod 0600 "$BACKUP_DIR/previous-image.tar.gz"
    gzip -t "$BACKUP_DIR/previous-image.tar.gz"
    had_image_archive=1
  fi
  if [[ "$had_container" == "1" && ! -r "$COMPOSE_FILE" ]]; then
    die "Найден контейнер remnanode без $COMPOSE_FILE; безопасный автоматический rollback невозможен."
  fi
  if [[ -r "$NODE_ROOT/docker-compose.override.yml" && -r "$NODE_ROOT/docker-compose.override.yaml" ]]; then
    die "Одновременно найдены docker-compose.override.yml и .yaml; нельзя однозначно сохранить runtime для rollback."
  fi
  [[ -e /swapfile-remnanode ]] && had_swap_file=1
  if command -v swapon >/dev/null 2>&1 && \
     swapon --show=NAME --noheadings 2>/dev/null | grep -Fxq /swapfile-remnanode; then
    was_swap_active=1
  fi

  while IFS= read -r unit; do
    if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
      previous_legacy_enabled_units+=" $unit"
    fi
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
      previous_legacy_active_units+=" $unit"
    fi
  done < <(legacy_units)
  previous_legacy_enabled_units="$(trim "$previous_legacy_enabled_units")"
  previous_legacy_active_units="$(trim "$previous_legacy_active_units")"
  while IFS= read -r unit; do
    if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
      previous_managed_enabled_units+=" $unit"
    fi
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
      previous_managed_active_units+=" $unit"
    fi
  done < <(managed_units)
  previous_managed_enabled_units="$(trim "$previous_managed_enabled_units")"
  previous_managed_active_units="$(trim "$previous_managed_active_units")"

  backup_system_paths
  backup_sysctl_runtime

  {
    printf 'BACKUP_FORMAT=%q\n' "2"
    printf 'CREATED_AT=%q\n' "$timestamp"
    printf 'HAD_NODE_ROOT=%q\n' "$had_node_root"
    printf 'HAD_CONTAINER=%q\n' "$had_container"
    printf 'WAS_RUNNING=%q\n' "$was_running"
    printf 'HAD_SWAP_FILE=%q\n' "$had_swap_file"
    printf 'WAS_SWAP_ACTIVE=%q\n' "$was_swap_active"
    printf 'PREVIOUS_IMAGE=%q\n' "$previous_image"
    printf 'PREVIOUS_IMAGE_ID=%q\n' "$previous_image_id"
    printf 'HAD_IMAGE_ARCHIVE=%q\n' "$had_image_archive"
    printf 'HAD_SYSTEM_FILES=%q\n' "$BACKUP_HAS_SYSTEM_FILES"
    printf 'PREVIOUS_LEGACY_ENABLED_UNITS=%q\n' "$previous_legacy_enabled_units"
    printf 'PREVIOUS_LEGACY_ACTIVE_UNITS=%q\n' "$previous_legacy_active_units"
    printf 'PREVIOUS_MANAGED_ENABLED_UNITS=%q\n' "$previous_managed_enabled_units"
    printf 'PREVIOUS_MANAGED_ACTIVE_UNITS=%q\n' "$previous_managed_active_units"
  } >"$BACKUP_DIR/manifest.env"
  chmod 0600 "$BACKUP_DIR/manifest.env"

  mv "$BACKUP_DIR" "$final_backup"
  BACKUP_STAGE_DIR=""
  BACKUP_DIR="$final_backup"

  MUTATION_STARTED=1
  log "Backup создан: $BACKUP_DIR"
}

remove_known_current_files_for_rollback() {
  local path=""
  rm -f -- "$SYSCTL_FILE" "$LOGROTATE_FILE" "$FIREWALL_SCRIPT" "$FIREWALL_SERVICE" \
    "$INSTALLER_CONFIG" "$STATE_FILE" "$NGINX_SITE_AVAILABLE" "$NGINX_SITES_ENABLED_SITE" \
    "$NGINX_CONF_D_SITE" "$NGINX_BOOTSTRAP_AVAILABLE" "$NGINX_SITES_ENABLED_BOOTSTRAP" \
    "$NGINX_CONF_D_BOOTSTRAP" \
    "$CERT_DEPLOY_HOOK" "$NGINX_CAPACITY_DROPIN" "$MAINTENANCE_SCRIPT" "$MAINTENANCE_SERVICE" \
    "$MAINTENANCE_TIMER" "$XHTTP_GUARD_SCRIPT" "$XHTTP_GUARD_SERVICE" "$XHTTP_GUARD_TIMER" \
    "$JOURNALD_DROPIN" "$LEGACY_REBOOT_MARKER"
  while IFS= read -r path; do
    rm -f -- "$path"
  done < <(legacy_paths)
}

remove_remnanode_container_gracefully() {
  command -v docker >/dev/null 2>&1 || return 0
  docker inspect remnanode >/dev/null 2>&1 || return 0
  docker stop --time 45 remnanode >/dev/null 2>&1 || true
  docker rm remnanode >/dev/null 2>&1 || docker rm -f remnanode >/dev/null 2>&1 || true
  ! docker inspect remnanode >/dev/null 2>&1
}

cleanup_native_plugin_tables_without_node() {
  if command -v docker >/dev/null 2>&1 && docker inspect remnanode >/dev/null 2>&1; then
    return 0
  fi
  command -v nft >/dev/null 2>&1 || return 0
  nft delete table ip remnanode >/dev/null 2>&1 || true
  nft delete table ip6 remnanode6 >/dev/null 2>&1 || true
}

rollback_from_backup() {
  local backup="$1"
  local had_node_root=0
  local failed_copy=""
  local failed_copy_archive=""
  local had_container=0
  local was_running=0
  local previous_image=""
  local previous_image_id=""
  local had_swap_file=0
  local was_swap_active=0
  local rollback_failed=0
  local actual_image_id=""
  local previous_legacy_enabled_units=""
  local previous_legacy_active_units=""
  local previous_managed_enabled_units=""
  local previous_managed_active_units=""
  local unit=""
  local backup_format=""
  local had_image_archive=0
  local had_system_files=0
  local image_ready=1
  local staged_node_root=""
  local -a rollback_compose_args=()
  local sysctl_key=""
  local sysctl_value=""
  local sysctl_extra=""

  [[ -r "$backup/manifest.env" ]] || die "Некорректный backup: $backup"
  ROLLBACK_RUNNING=1
  # shellcheck disable=SC1090
  source "$backup/manifest.env"
  backup_format="${BACKUP_FORMAT:-}"
  had_node_root="${HAD_NODE_ROOT:-0}"
  had_container="${HAD_CONTAINER:-0}"
  was_running="${WAS_RUNNING:-0}"
  previous_image="${PREVIOUS_IMAGE:-}"
  previous_image_id="${PREVIOUS_IMAGE_ID:-}"
  had_swap_file="${HAD_SWAP_FILE:-0}"
  was_swap_active="${WAS_SWAP_ACTIVE:-0}"
  previous_legacy_enabled_units="${PREVIOUS_LEGACY_ENABLED_UNITS:-}"
  previous_legacy_active_units="${PREVIOUS_LEGACY_ACTIVE_UNITS:-}"
  previous_managed_enabled_units="${PREVIOUS_MANAGED_ENABLED_UNITS:-}"
  previous_managed_active_units="${PREVIOUS_MANAGED_ACTIVE_UNITS:-}"
  had_image_archive="${HAD_IMAGE_ARCHIVE:-0}"
  had_system_files="${HAD_SYSTEM_FILES:-0}"

  [[ "$backup_format" == "2" ]] || \
    die "Backup schema $backup_format не поддерживается этим installer; нужен format 2."
  for unit in "$had_node_root" "$had_container" "$was_running" "$had_swap_file" \
    "$was_swap_active" "$had_image_archive" "$had_system_files"; do
    [[ "$unit" == "0" || "$unit" == "1" ]] || die "Manifest backup содержит некорректный boolean."
  done
  [[ "$had_container" == "0" || "$had_node_root" == "1" ]] || \
    die "Manifest inconsistent: container был без node root."
  [[ "$was_running" == "0" || "$had_container" == "1" ]] || \
    die "Manifest inconsistent: running state без container."
  [[ "$was_swap_active" == "0" || "$had_swap_file" == "1" ]] || \
    die "Manifest inconsistent: active swap без swap file."
  [[ "$had_image_archive" == "$had_container" ]] || \
    die "Manifest inconsistent: image archive не совпадает с container state."
  if [[ "$had_node_root" == "1" ]]; then
    [[ -r "$backup/node-root.tgz" ]] || die "Backup неполный: отсутствует node-root.tgz."
    tar -tzf "$backup/node-root.tgz" >/dev/null || die "Backup повреждён: node-root.tgz не читается."
  fi
  if [[ "$had_system_files" == "1" ]]; then
    [[ -r "$backup/system-files.tgz" ]] || die "Backup неполный: отсутствует system-files.tgz."
    tar -tzf "$backup/system-files.tgz" >/dev/null || die "Backup повреждён: system-files.tgz не читается."
  fi
  if [[ "$had_container" == "1" ]]; then
    [[ -n "$previous_image" && -n "$previous_image_id" && "$had_image_archive" == "1" ]] || \
      die "Backup контейнера не содержит точный image/digest archive."
    [[ -r "$backup/previous-image.tar.gz" ]] || die "Backup неполный: отсутствует previous-image.tar.gz."
    gzip -t "$backup/previous-image.tar.gz" || die "Backup повреждён: previous-image.tar.gz не читается."
    command -v docker >/dev/null 2>&1 || die "Для восстановления контейнера нужен уже установленный Docker."
    docker compose version >/dev/null 2>&1 || die "Для восстановления контейнера нужен Docker Compose v2."
  fi
  if [[ -r "$backup/sysctl-runtime.tsv" ]]; then
    while IFS=$'\t' read -r sysctl_key sysctl_value sysctl_extra; do
      [[ -n "$sysctl_key" && -n "$sysctl_value" && -z "$sysctl_extra" ]] || \
        die "Backup содержит повреждённый sysctl-runtime.tsv."
      managed_sysctl_key_allowed "$sysctl_key" || \
        die "Backup содержит неожиданный sysctl key: $sysctl_key"
    done <"$backup/sysctl-runtime.tsv"
  fi

  log "Выполняю rollback из $backup"
  if [[ "$had_node_root" == "1" ]]; then
    ROLLBACK_STAGE_DIR="$(mktemp -d /opt/.remnanode-rollback.XXXXXX)"
    chmod 0700 "$ROLLBACK_STAGE_DIR"
    tar -C "$ROLLBACK_STAGE_DIR" -xzf "$backup/node-root.tgz"
    staged_node_root="$ROLLBACK_STAGE_DIR/opt/remnanode"
    [[ -d "$staged_node_root" ]] || die "Backup node-root.tgz не содержит opt/remnanode."
    if [[ "$had_container" == "1" ]]; then
      [[ -r "$staged_node_root/docker-compose.yml" ]] || \
        die "Backup контейнера не содержит docker-compose.yml; переключение файлов отменено."
    fi
    if [[ -r "$staged_node_root/docker-compose.override.yml" && \
          -r "$staged_node_root/docker-compose.override.yaml" ]]; then
      die "Backup содержит два неоднозначных Compose override; автоматический rollback остановлен до переключения файлов."
    fi
  fi
  if [[ -d "$NODE_ROOT" ]]; then
    failed_copy="$(dirname "$NODE_ROOT")/remnanode.failed-$(date -u +%Y%m%dT%H%M%SZ)-$$"
    mv "$NODE_ROOT" "$failed_copy"
  fi

  if [[ "$had_node_root" == "1" ]]; then
    mv "$staged_node_root" "$NODE_ROOT"
    rm -rf -- "$ROLLBACK_STAGE_DIR"
    ROLLBACK_STAGE_DIR=""
  else
    install -d -m 0750 "$NODE_ROOT"
  fi

  systemctl disable --now remnanode-maintenance.timer >/dev/null 2>&1 || true
  systemctl disable --now remnanode-xhttp-socket-guard.timer >/dev/null 2>&1 || true
  systemctl stop remnanode-xhttp-socket-guard.service >/dev/null 2>&1 || true
  rm -f -- "$XHTTP_GUARD_MARKER"
  systemctl disable remnanode-firewall.service >/dev/null 2>&1 || true
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl stop remnanode-firewall.service >/dev/null 2>&1 || true
  cleanup_installer_ufw_rules || true
  cleanup_installer_iptables_runtime || true
  remove_known_current_files_for_rollback
  rm -rf -- "$TLS_DIR"
  rm -f -- "$PANEL_IPS_FILE"
  if [[ "$had_system_files" == "1" ]]; then
    tar -C / -xzf "$backup/system-files.tgz"
  fi

  if command -v docker >/dev/null 2>&1 && ! docker info >/dev/null 2>&1; then
    systemctl start docker.service >/dev/null 2>&1 || rollback_failed=1
  fi

  if [[ "$had_swap_file" == "0" ]]; then
    if swapon --show=NAME --noheadings 2>/dev/null | grep -Fxq /swapfile-remnanode; then
      if swapoff /swapfile-remnanode >/dev/null 2>&1; then
        rm -f /swapfile-remnanode
      else
        warn "Rollback: не удалось отключить созданный swap."
        rollback_failed=1
      fi
    else
      rm -f /swapfile-remnanode
    fi
  elif [[ "$was_swap_active" == "1" ]]; then
    swapon --show=NAME --noheadings 2>/dev/null | grep -Fxq /swapfile-remnanode || \
      swapon /swapfile-remnanode >/dev/null 2>&1 || rollback_failed=1
  fi

  systemctl daemon-reload || rollback_failed=1
  if [[ "$had_container" == "1" && "$had_node_root" == "1" && -r "$COMPOSE_FILE" ]]; then
    rollback_compose_args=(-f "$COMPOSE_FILE")
    if [[ -r "$NODE_ROOT/docker-compose.override.yml" ]]; then
      rollback_compose_args+=(-f "$NODE_ROOT/docker-compose.override.yml")
    elif [[ -r "$NODE_ROOT/docker-compose.override.yaml" ]]; then
      rollback_compose_args+=(-f "$NODE_ROOT/docker-compose.override.yaml")
    fi
    if ! docker image inspect "$previous_image_id" >/dev/null 2>&1; then
      docker load -i "$backup/previous-image.tar.gz" >/dev/null 2>&1 || image_ready=0
    fi
    if ! docker image inspect "$previous_image_id" >/dev/null 2>&1; then
      image_ready=0
      rollback_failed=1
    fi
    if (( image_ready == 1 )); then
      docker tag "$previous_image_id" "$previous_image" >/dev/null 2>&1 || rollback_failed=1
      if ! docker compose --project-directory "$NODE_ROOT" "${rollback_compose_args[@]}" \
        up -d --force-recreate; then
        rollback_failed=1
      fi
      if [[ "$was_running" == "0" ]]; then
        docker stop remnanode >/dev/null 2>&1 || rollback_failed=1
      fi
      if ! docker inspect remnanode >/dev/null 2>&1; then
        rollback_failed=1
      else
        actual_image_id="$(docker inspect --format '{{.Image}}' remnanode 2>/dev/null || true)"
        [[ "$actual_image_id" == "$previous_image_id" ]] || rollback_failed=1
        if [[ "$was_running" == "1" && "$(docker inspect --format '{{.State.Running}}' remnanode 2>/dev/null || true)" != "true" ]]; then
          rollback_failed=1
        fi
      fi
    else
      remove_remnanode_container_gracefully || rollback_failed=1
      cleanup_native_plugin_tables_without_node
    fi
  else
    remove_remnanode_container_gracefully || rollback_failed=1
    cleanup_native_plugin_tables_without_node
    [[ "$had_container" == "0" ]] || rollback_failed=1
  fi
  if command -v nginx >/dev/null 2>&1 && ! nginx -t >/dev/null 2>&1; then
    rollback_failed=1
  fi
  if command -v ufw >/dev/null 2>&1 && LC_ALL=C ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw reload >/dev/null 2>&1 || rollback_failed=1
  fi
  if systemctl is-active --quiet systemd-resolved.service 2>/dev/null; then
    systemctl restart systemd-resolved.service >/dev/null 2>&1 || rollback_failed=1
  fi
  for unit in $previous_legacy_enabled_units; do
    systemctl enable "$unit" >/dev/null 2>&1 || rollback_failed=1
  done
  for unit in $previous_legacy_active_units; do
    systemctl start "$unit" >/dev/null 2>&1 || rollback_failed=1
  done
  while IFS= read -r unit; do
    if [[ " $previous_managed_enabled_units " == *" $unit "* ]]; then
      systemctl enable "$unit" >/dev/null 2>&1 || rollback_failed=1
    else
      systemctl disable "$unit" >/dev/null 2>&1 || true
    fi
    if [[ " $previous_managed_active_units " == *" $unit "* ]]; then
      case "$unit" in
        remnanode-firewall.service|docker.service|docker.socket|containerd.service)
          # Docker infrastructure may already be serving the restored node;
          # start is idempotent, while restart would interrupt it.
          systemctl start "$unit" >/dev/null 2>&1 || rollback_failed=1
          ;;
        *)
          systemctl restart "$unit" >/dev/null 2>&1 || rollback_failed=1
          ;;
      esac
    else
      systemctl stop "$unit" >/dev/null 2>&1 || true
    fi
  done < <(managed_units)
  while IFS= read -r unit; do
    if [[ " $previous_managed_active_units " == *" $unit "* ]]; then
      systemctl is-active --quiet "$unit" || rollback_failed=1
    elif systemctl is-active --quiet "$unit"; then
      rollback_failed=1
    fi
    if [[ " $previous_managed_enabled_units " == *" $unit "* ]]; then
      systemctl is-enabled --quiet "$unit" || rollback_failed=1
    elif systemctl is-enabled --quiet "$unit"; then
      rollback_failed=1
    fi
  done < <(managed_units)
  # Keep the temporary control-port boundary until the previous firewall is
  # confirmed. A restored remnanode firewall may atomically replace the same
  # nft table; another active firewall gets priority before we remove ours.
  if [[ " $previous_managed_active_units " == *" remnanode-firewall.service "* ]]; then
    if ! systemctl is-active --quiet remnanode-firewall.service; then
      rollback_failed=1
      warn "Rollback: предыдущий firewall не активен; временная control-port защита сохранена."
    elif grep -Fq 'table inet remnanode_installer' "$FIREWALL_SCRIPT" 2>/dev/null; then
      if ! nft list table inet remnanode_installer >/dev/null 2>&1; then
        rollback_failed=1
        warn "Rollback: предыдущий firewall не создал ожидаемую nft table."
      fi
    else
      command -v nft >/dev/null 2>&1 && \
        nft delete table inet remnanode_installer >/dev/null 2>&1 || true
    fi
  else
    command -v nft >/dev/null 2>&1 && \
      nft delete table inet remnanode_installer >/dev/null 2>&1 || true
  fi
  systemctl restart systemd-journald.service >/dev/null 2>&1 || true
  sysctl --system >/dev/null 2>&1 || true
  if [[ -r "$backup/sysctl-runtime.tsv" ]]; then
    while IFS=$'\t' read -r sysctl_key sysctl_value sysctl_extra; do
      sysctl -w "$sysctl_key=$sysctl_value" >/dev/null 2>&1 || rollback_failed=1
    done <"$backup/sysctl-runtime.tsv"
  fi
  if [[ -n "$failed_copy" && -d "$failed_copy" ]]; then
    failed_copy_archive="$backup/failed-node-root.tgz"
    tar -C "$(dirname "$failed_copy")" -czf "$failed_copy_archive" "$(basename "$failed_copy")"
    chmod 0600 "$failed_copy_archive"
    rm -rf -- "$failed_copy"
    failed_copy=""
  fi
  ROLLBACK_RUNNING=0
  if (( rollback_failed != 0 )); then
    warn "Rollback восстановил файлы, но одна или несколько служб не вернулись в ожидаемое состояние."
    return 1
  fi
  log "Rollback завершён. Неудачная конфигурация сохранена в ${failed_copy_archive:-не создана}."
}

on_error() {
  local rc="$1"
  local line="$2"
  trap - ERR INT TERM
  printf '\n[ERROR] Installer остановлен на строке %s (код %s).\n' "$line" "$rc" >&2
  if [[ "$MUTATION_STARTED" == "1" && "$ROLLBACK_RUNNING" == "0" && -n "$BACKUP_DIR" ]]; then
    rollback_from_backup "$BACKUP_DIR"
  fi
  exit "$rc"
}

cleanup_stage() {
  [[ -z "$STAGE_DIR" || ! -d "$STAGE_DIR" ]] || rm -rf "$STAGE_DIR"
  [[ -z "$SECRET_CHECK_DIR" || ! -d "$SECRET_CHECK_DIR" ]] || rm -rf "$SECRET_CHECK_DIR"
  [[ -z "$ROLLBACK_STAGE_DIR" || ! -d "$ROLLBACK_STAGE_DIR" ]] || rm -rf "$ROLLBACK_STAGE_DIR"
  [[ -z "$BACKUP_STAGE_DIR" || ! -d "$BACKUP_STAGE_DIR" ]] || rm -rf "$BACKUP_STAGE_DIR"
}

trap 'on_error $? $LINENO' ERR
trap 'on_error 130 $LINENO' INT TERM
trap cleanup_stage EXIT

stop_legacy_units() {
  local path=""
  local unit=""
  local -a units=()
  mapfile -t units < <(legacy_units)

  if [[ -r "$SYSCTL_FILE" ]] && \
     grep -Eq 'net\.core\.(dev_weight|netdev_budget|rps_sock_flow_entries)|tcp_(base_mss|min_snd_mss|max_tw_buckets)|vm\.(page-cluster|vfs_cache_pressure)' "$SYSCTL_FILE"; then
    LEGACY_DETECTED=1
    LEGACY_RUNTIME_TUNING_DETECTED=1
  fi

  # A disabled legacy unit may no longer be visible as active, while its
  # global OS changes still remain. Detect known files as well, so migration
  # restores distro security timers and reports the one-time reboot need.
  while IFS= read -r path; do
    [[ -e "$path" || -L "$path" ]] || continue
    LEGACY_DETECTED=1
    case "$path" in
      /usr/local/sbin/remnanode-rps.sh|/etc/systemd/system/remnanode-rps.service|\
      /etc/systemd/system/remnanode-qdisc.service|/usr/local/sbin/remnanode-offload-tune.sh|\
      /etc/systemd/system/remnanode-offload-tune.service|/usr/local/sbin/remnanode-mss-clamp.sh|\
      /etc/systemd/system/remnanode-mss-clamp.service|/etc/systemd/system/node-mtu.service|\
      /etc/ssh/sshd_config.d/99-remnanode-stability.conf|/etc/systemd/resolved.conf.d/99-remnanode.conf)
        LEGACY_RUNTIME_TUNING_DETECTED=1
        ;;
    esac
  done < <(legacy_paths)

  for unit in "${units[@]}"; do
    if systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q .; then
      LEGACY_DETECTED=1
      systemctl disable --now "$unit" >/dev/null 2>&1 || true
    fi
  done

  # Old releases forced public resolvers globally. Remove only that known
  # drop-in before apt/Docker downloads; the backup can restore it on rollback.
  if [[ -e /etc/systemd/resolved.conf.d/99-remnanode.conf ]]; then
    rm -f /etc/systemd/resolved.conf.d/99-remnanode.conf
    if systemctl is-active --quiet systemd-resolved.service 2>/dev/null; then
      systemctl restart systemd-resolved.service || \
        warn "Legacy DNS drop-in удалён, но systemd-resolved не перезапустился."
    fi
  fi
}

cleanup_legacy_firewall_runtime() {
  local bin=""
  nft delete table inet remnanode_guard >/dev/null 2>&1 || true
  nft delete table inet remnanode_spamhaus_egress_guard >/dev/null 2>&1 || true

  for bin in iptables ip6tables; do
    command -v "$bin" >/dev/null 2>&1 || continue
    while "$bin" -w 3 -C OUTPUT -j REMNANODE_TORRENT_GUARD >/dev/null 2>&1; do
      "$bin" -w 3 -D OUTPUT -j REMNANODE_TORRENT_GUARD || break
    done
    while "$bin" -w 3 -C FORWARD -j REMNANODE_TORRENT_GUARD >/dev/null 2>&1; do
      "$bin" -w 3 -D FORWARD -j REMNANODE_TORRENT_GUARD || break
    done
    "$bin" -w 3 -F REMNANODE_TORRENT_GUARD >/dev/null 2>&1 || true
    "$bin" -w 3 -X REMNANODE_TORRENT_GUARD >/dev/null 2>&1 || true
  done
}

cleanup_legacy_files() {
  local path=""
  local override_file=""
  local legacy_runtime_file=""
  local -a override_files=(
    "$NODE_ROOT/docker-compose.override.yml"
    "$NODE_ROOT/docker-compose.override.yaml"
  )
  local -a legacy_runtime_files=(
    "$NODE_ROOT/overrides/generate-api-config.js"
    "$NODE_ROOT/overrides/stats.service.js"
    "$NODE_ROOT/overrides/xray.service.js"
  )
  log "Удаляю только известные legacy-подмены и restart-таймеры старого installer"
  stop_legacy_units
  cleanup_legacy_firewall_runtime
  while IFS= read -r path; do
    [[ "$path" == "$NGINX_SITE_AVAILABLE" || "$path" == "$NGINX_SITE_ENABLED" ]] && continue
    rm -f -- "$path"
  done < <(legacy_paths)

  for override_file in "${override_files[@]}"; do
    [[ -e "$override_file" || -L "$override_file" ]] || continue
    is_known_legacy_compose_override "$override_file" || \
      die "Отказ удалять неизвестный Compose override: $override_file"
    rm -f -- "$override_file"
    INSTALL_CHANGED=1
    LEGACY_DETECTED=1
  done

  for legacy_runtime_file in "${legacy_runtime_files[@]}"; do
    [[ -e "$legacy_runtime_file" || -L "$legacy_runtime_file" ]] || continue
    rm -f -- "$legacy_runtime_file"
    INSTALL_CHANGED=1
    LEGACY_DETECTED=1
  done
  rmdir "$NODE_ROOT/overrides" >/dev/null 2>&1 || true
  systemctl daemon-reload
}

prepare_directories() {
  install -d -m 0750 "$NODE_ROOT" "$TLS_DIR" "$LOG_DIR" "$STATE_DIR"
  install -d -m 0700 "$BACKUP_ROOT"
}

configure_small_swap() {
  local mem_mb=""
  local swap_mb=""
  local target_mb=0
  local swap_file="/swapfile-remnanode"

  bool_true "$AUTO_SWAP" || return 0
  mem_mb="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
  swap_mb="$(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo)"

  if (( mem_mb < 1536 && swap_mb < 512 )); then
    target_mb=1024
  elif (( mem_mb < 2048 && swap_mb == 0 )); then
    target_mb=512
  else
    return 0
  fi

  if swapon --show=NAME --noheadings 2>/dev/null | grep -Fxq "$swap_file"; then
    log "Swap $swap_file уже активен; не изменяю его на работающей системе."
    return 0
  fi
  if [[ -e "$swap_file" ]]; then
    warn "$swap_file уже существует, но не активен; не перезаписываю чужой файл."
    return 0
  fi

  log "Low-RAM VPS: пробую создать безопасный swap ${target_mb}MiB"
  if [[ "$(stat -f -c %T / 2>/dev/null || true)" == "btrfs" ]]; then
    touch "$swap_file"
    chattr +C "$swap_file" >/dev/null 2>&1 || true
  fi
  if ! fallocate -l "${target_mb}M" "$swap_file" 2>/dev/null; then
    dd if=/dev/zero of="$swap_file" bs=1M count="$target_mb" status=none
  fi
  chmod 0600 "$swap_file"
  mkswap "$swap_file" >/dev/null
  if swapon "$swap_file"; then
    grep -Fq "$swap_file none swap sw 0 0" /etc/fstab || \
      printf '%s\n' "$swap_file none swap sw 0 0" >>/etc/fstab
  else
    warn "Provider запрещает swapon; продолжаю без swap."
    rm -f "$swap_file"
  fi
}

configure_minimal_sysctl() {
  local bbr_available=0
  local tmp=""
  local mem_mb=""
  local socket_max=8388608
  local netdev_backlog=4096
  local syn_backlog=4096
  local conntrack_target=131072
  local conntrack_current=0

  mem_mb="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
  if (( mem_mb >= 4096 )); then
    socket_max=33554432
    netdev_backlog=32768
    syn_backlog=16384
    conntrack_target=524288
  elif (( mem_mb >= 1536 )); then
    socket_max=16777216
    netdev_backlog=16384
    syn_backlog=8192
    conntrack_target=262144
  fi

  tmp="$(mktemp)"
  {
    printf '# Managed by RemnaNode installer %s\n' "$INSTALLER_VERSION"
    printf 'fs.file-max = 2097152\n'
    printf 'net.core.somaxconn = %s\n' "$syn_backlog"
    printf 'net.core.netdev_max_backlog = %s\n' "$netdev_backlog"
    printf 'net.core.rmem_max = %s\n' "$socket_max"
    printf 'net.core.wmem_max = %s\n' "$socket_max"
    printf 'net.ipv4.ip_local_port_range = 10240 65535\n'
    printf 'net.ipv4.tcp_keepalive_time = 600\n'
    printf 'net.ipv4.tcp_keepalive_intvl = 30\n'
    printf 'net.ipv4.tcp_keepalive_probes = 5\n'
    printf 'net.ipv4.tcp_max_syn_backlog = %s\n' "$syn_backlog"
    printf 'net.ipv4.tcp_mtu_probing = 1\n'
    printf 'net.ipv4.tcp_rmem = 4096 131072 %s\n' "$socket_max"
    printf 'net.ipv4.tcp_wmem = 4096 65536 %s\n' "$socket_max"
    printf 'net.ipv4.udp_rmem_min = 16384\n'
    printf 'net.ipv4.udp_wmem_min = 16384\n'
  } >"$tmp"

  if [[ -r /proc/sys/net/netfilter/nf_conntrack_max ]]; then
    conntrack_current="$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || printf '0')"
    [[ "$conntrack_current" =~ ^[0-9]+$ ]] || conntrack_current=0
    (( conntrack_current > conntrack_target )) && conntrack_target="$conntrack_current"
    printf 'net.netfilter.nf_conntrack_max = %s\n' "$conntrack_target" >>"$tmp"
  fi

  if bool_true "$ENABLE_BBR"; then
    modprobe tcp_bbr >/dev/null 2>&1 || true
    if sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
      bbr_available=1
      {
        printf 'net.core.default_qdisc = fq\n'
        printf 'net.ipv4.tcp_congestion_control = bbr\n'
      } >>"$tmp"
    else
      warn "Kernel не предоставляет BBR; оставляю congestion control провайдера."
    fi
  fi

  install -m 0644 "$tmp" "$SYSCTL_FILE"
  rm -f "$tmp"
  if ! sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1; then
    warn "Provider запретил часть sysctl; Node продолжит работать с системными значениями."
  fi
  if (( bbr_available == 1 )); then
    [[ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)" == "bbr" ]] || \
      warn "BBR доступен, но provider не разрешил сделать его активным."
  fi
  log "Adaptive network baseline: RAM=${mem_mb}MiB, socket-max=$socket_max, backlog=$netdev_backlog"
}

write_logrotate() {
  # Rotate only explicit *.log files written by Xray profiles. Internal
  # supervisor/s6 streams and Docker json logs have their own bounded stores.
  cat >"$LOGROTATE_FILE" <<EOF
$LOG_DIR/*.log {
    size 50M
    rotate 5
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
  chmod 0644 "$LOGROTATE_FILE"
}

configure_log_hygiene_and_maintenance() {
  if ! bool_true "$ENABLE_MAINTENANCE"; then
    systemctl disable --now remnanode-maintenance.timer >/dev/null 2>&1 || true
    rm -f "$MAINTENANCE_SCRIPT" "$MAINTENANCE_SERVICE" "$MAINTENANCE_TIMER"
    if [[ -e "$JOURNALD_DROPIN" ]]; then
      rm -f "$JOURNALD_DROPIN"
      systemctl restart systemd-journald.service
    fi
    systemctl daemon-reload
    return 0
  fi

  install -d -m 0755 /etc/systemd/journald.conf.d
  cat >"$JOURNALD_DROPIN" <<EOF
[Journal]
SystemMaxUse=$JOURNAL_MAX_USE
RuntimeMaxUse=64M
MaxRetentionSec=$JOURNAL_RETENTION
Compress=yes
RateLimitIntervalSec=30s
RateLimitBurst=20000
EOF
  chmod 0644 "$JOURNALD_DROPIN"
  systemctl restart systemd-journald.service

  cat >"$MAINTENANCE_SCRIPT" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
BACKUP_ROOT="$BACKUP_ROOT"
BACKUP_RETENTION=$BACKUP_RETENTION
LOCK_FILE="$LOCK_FILE"

exec 9>"\$LOCK_FILE"
flock -n 9 || exit 0

logger -t remnanode-maintenance -- "safe maintenance started"

# Bounded logs and distro-defined temporary-file policy. No Docker image,
# network, volume or working-container pruning is performed.
journalctl --vacuum-time="$JOURNAL_RETENTION" --vacuum-size="$JOURNAL_MAX_USE" >/dev/null 2>&1 || true
systemd-tmpfiles --clean >/dev/null 2>&1 || true
apt-get clean >/dev/null 2>&1 || true
find /tmp -maxdepth 1 -type d -name 'remnanode-stage.*' -mtime +2 -exec rm -rf -- {} + 2>/dev/null || true
find "\$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name '.partial-*' -mtime +2 -exec rm -rf -- {} + 2>/dev/null || true

mapfile -t backups < <(
  find "\$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null |
    grep -E '^[0-9]{8}T[0-9]{6}Z\$' | sort -r
)
if (( \${#backups[@]} > BACKUP_RETENTION )); then
  for ((i = BACKUP_RETENTION; i < \${#backups[@]}; i++)); do
    candidate="\$BACKUP_ROOT/\${backups[i]}"
    [[ "\$candidate" == "\$BACKUP_ROOT/"* ]] && rm -rf -- "\$candidate"
  done
fi

disk_used="\$(df -P / | awk 'NR == 2 {gsub(/%/, "", \$5); print \$5}')"
if [[ "\$disk_used" =~ ^[0-9]+\$ ]] && (( disk_used >= 90 )); then
  logger -p daemon.warning -t remnanode-maintenance -- "root filesystem usage is \${disk_used}%"
fi
if ! docker inspect -f '{{.State.Running}}' remnanode 2>/dev/null | grep -qx true; then
  logger -p daemon.warning -t remnanode-maintenance -- "remnanode container is not running; Docker restart policy remains responsible for recovery"
fi
if docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' remnanode 2>/dev/null | grep -qx unhealthy; then
  logger -p daemon.warning -t remnanode-maintenance -- "remnanode API healthcheck is unhealthy; no blind restart was performed"
fi

logger -t remnanode-maintenance -- "safe maintenance completed"
EOF
  chmod 0700 "$MAINTENANCE_SCRIPT"

  cat >"$MAINTENANCE_SERVICE" <<EOF
[Unit]
Description=Safe bounded maintenance for RemnaNode
After=docker.service

[Service]
Type=oneshot
ExecStart=$MAINTENANCE_SCRIPT
Nice=10
IOSchedulingClass=idle
EOF

  cat >"$MAINTENANCE_TIMER" <<EOF
[Unit]
Description=Weekly safe maintenance for RemnaNode

[Timer]
OnCalendar=weekly
RandomizedDelaySec=2h
Persistent=true
Unit=remnanode-maintenance.service

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now remnanode-maintenance.timer >/dev/null
}

cleanup_installer_ufw_rules() {
  local keep_comment="${1:-}"
  local line=""
  local number=""
  local attempt=0
  local deleted=0
  command -v ufw >/dev/null 2>&1 || return 0
  LC_ALL=C ufw status 2>/dev/null | grep -q '^Status: active' || return 0

  while :; do
    if [[ -n "$keep_comment" ]]; then
      line="$(LC_ALL=C ufw status numbered 2>/dev/null | \
        grep -F 'remnanode-installer' | grep -Fv "$keep_comment" | head -n1 || true)"
    else
      line="$(LC_ALL=C ufw status numbered 2>/dev/null | grep -F 'remnanode-installer' | head -n1 || true)"
    fi
    number="$(sed -n 's/^\[ *\([0-9][0-9]*\)\].*/\1/p' <<<"$line")"
    [[ -n "$number" ]] || break
    deleted=0
    for attempt in 1 2 3; do
      if ufw --force delete "$number" >/dev/null 2>&1; then
        deleted=1
        break
      fi
      sleep "$attempt"
    done
    if (( deleted == 0 )); then
      warn "Не удалось удалить старое UFW rule №$number после 3 попыток."
      return 1
    fi
  done
}

cleanup_installer_iptables_runtime() {
  local bin=""
  local chain=""
  local hook=""

  # Remove rules from short-lived 3.0.x builds that used iptables chains.
  for bin in iptables ip6tables; do
    command -v "$bin" >/dev/null 2>&1 || continue
    for hook in INPUT OUTPUT FORWARD; do
      for chain in RWNODE_CTL RWNODE_EGRESS; do
        while "$bin" -w 3 -C "$hook" -j "$chain" >/dev/null 2>&1; do
          "$bin" -w 3 -D "$hook" -j "$chain" || break
        done
      done
    done
    for chain in RWNODE_CTL RWNODE_EGRESS; do
      "$bin" -w 3 -F "$chain" >/dev/null 2>&1 || true
      "$bin" -w 3 -X "$chain" >/dev/null 2>&1 || true
    done
  done
}

cleanup_installer_firewall_runtime() {
  command -v nft >/dev/null 2>&1 && \
    nft delete table inet remnanode_installer >/dev/null 2>&1 || true
  cleanup_installer_ufw_rules
  cleanup_installer_iptables_runtime
}

write_firewall() {
  local source=""
  local ipv4_elements=""
  local ipv6_elements=""
  local ipv4_elements_line=""
  local ipv6_elements_line=""
  local public_tcp_rule=""
  local public_udp_rule=""
  local smtp_output_rule=""
  local smtp_forward_rule=""
  local nft_tcp_ports="${PUBLIC_TCP_PORTS//,/, }"
  local nft_udp_ports="${PUBLIC_UDP_PORTS//,/, }"
  local nft_smtp_ports="${SMTP_EGRESS_PORTS//,/, }"
  local ufw_comment=""

  ufw_comment="remnanode-installer-$(printf '%s|' "$PANEL_IPS" "$NODE_PORT" "$PUBLIC_TCP_PORTS" \
    "$PUBLIC_UDP_PORTS" | sha256sum | cut -c1-12)"

  if ! bool_true "$MANAGE_FIREWALL"; then
    systemctl disable remnanode-firewall.service >/dev/null 2>&1 || true
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl stop remnanode-firewall.service >/dev/null 2>&1 || true
    cleanup_installer_firewall_runtime
    rm -f "$FIREWALL_SCRIPT" "$FIREWALL_SERVICE"
    systemctl daemon-reload
    warn "Firewall installer полностью отключён: нет allowlist для ${NODE_PORT}/tcp и нет SMTP guard. Настройте оба ограничения на уровне provider firewall."
    return 0
  fi

  for source in $PANEL_IPS; do
    if [[ "$source" == *:* ]]; then
      [[ -z "$ipv6_elements" ]] || ipv6_elements+=", "
      ipv6_elements+="$source"
    else
      [[ -z "$ipv4_elements" ]] || ipv4_elements+=", "
      ipv4_elements+="$source"
    fi
  done
  [[ -z "$ipv4_elements" ]] || ipv4_elements_line="        elements = { $ipv4_elements };"
  [[ -z "$ipv6_elements" ]] || ipv6_elements_line="        elements = { $ipv6_elements };"
  [[ -z "$nft_tcp_ports" ]] || public_tcp_rule="        tcp dport { $nft_tcp_ports } accept"
  [[ -z "$nft_udp_ports" ]] || public_udp_rule="        udp dport { $nft_udp_ports } accept"
  if bool_true "$BLOCK_SMTP_EGRESS"; then
    smtp_output_rule="        tcp dport { $nft_smtp_ports } reject with tcp reset"
  fi
  if bool_true "$BLOCK_SMTP_FORWARD"; then
    smtp_forward_rule="        tcp dport { $nft_smtp_ports } reject with tcp reset"
  fi

  cat >"$FIREWALL_SCRIPT" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

RULES="\$(mktemp)"
cleanup() { rm -f "\$RULES"; }
trap cleanup EXIT

if nft list table inet remnanode_installer >/dev/null 2>&1; then
  printf '%s\n' 'delete table inet remnanode_installer' >"\$RULES"
fi

cat >>"\$RULES" <<'NFT'
table inet remnanode_installer {
    set panel_v4 {
        type ipv4_addr;
        flags interval;
        auto-merge;
$ipv4_elements_line
    }

    set panel_v6 {
        type ipv6_addr;
        flags interval;
        auto-merge;
$ipv6_elements_line
    }

    chain input {
        type filter hook input priority -5; policy accept;
        iifname "lo" tcp dport $NODE_PORT accept
$public_tcp_rule
$public_udp_rule
        ip saddr @panel_v4 tcp dport $NODE_PORT accept
        ip6 saddr @panel_v6 tcp dport $NODE_PORT accept
        tcp dport $NODE_PORT drop
    }

    chain output {
        type filter hook output priority -5; policy accept;
$smtp_output_rule
    }

    chain forward {
        type filter hook forward priority -5; policy accept;
$smtp_forward_rule
    }
}
NFT

nft -c -f "\$RULES"
nft -f "\$RULES"

# nft is the primary safety boundary and is applied first. UFW is then kept in
# sync because a later UFW base chain may otherwise still block public ports.
if command -v ufw >/dev/null 2>&1 && LC_ALL=C ufw status 2>/dev/null | grep -q '^Status: active'; then
  for source in $PANEL_IPS; do
    if [[ "\$source" == *:* ]] && grep -Eq '^[[:space:]]*IPV6[[:space:]]*=[[:space:]]*(no|false|0)' /etc/default/ufw 2>/dev/null; then
      logger -p daemon.warning -t remnanode-firewall -- "skip IPv6 UFW rule while UFW IPv6 support is disabled: \$source"
      continue
    fi
    ufw allow proto tcp from "\$source" to any port "$NODE_PORT" comment '$ufw_comment' >/dev/null
  done
  IFS=',' read -r -a tcp_ports <<<"$PUBLIC_TCP_PORTS"
  for port in "\${tcp_ports[@]}"; do
    [[ -n "\$port" ]] || continue
    ufw allow "\${port//-/:}/tcp" comment '$ufw_comment' >/dev/null
  done
  IFS=',' read -r -a udp_ports <<<"$PUBLIC_UDP_PORTS"
  for port in "\${udp_ports[@]}"; do
    [[ -n "\$port" ]] || continue
    ufw allow "\${port//-/:}/udp" comment '$ufw_comment' >/dev/null
  done
fi
EOF
  chmod 0700 "$FIREWALL_SCRIPT"

  cat >"$FIREWALL_SERVICE" <<EOF
[Unit]
Description=RemnaNode control allowlist and anti-abuse egress guard
After=network-online.target ufw.service
Wants=network-online.target
Before=docker.service

[Service]
Type=oneshot
ExecStart=$FIREWALL_SCRIPT
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
RequiredBy=docker.service
EOF

  # Keep the old nft table enforcing the control-port policy until the new
  # ruleset passes nft -c and replaces it atomically inside the service.
  cleanup_installer_iptables_runtime
  systemctl daemon-reload
  systemctl enable remnanode-firewall.service >/dev/null
  if systemctl is-active --quiet remnanode-firewall.service; then
    "$FIREWALL_SCRIPT"
  else
    systemctl start remnanode-firewall.service
  fi
  nft list table inet remnanode_installer >/dev/null
  cleanup_installer_ufw_rules "$ufw_comment"
}

check_xhttp_port_conflicts() {
  local line=""
  command -v ss >/dev/null 2>&1 || return 0
  line="$(ss -H -ltnp '( sport = :443 )' 2>/dev/null | head -n1 || true)"
  if [[ -n "$line" && "$line" != *nginx* ]]; then
    die "TCP/443 уже занят не Nginx: $line"
  fi
  line="$(ss -H -ltnp '( sport = :80 )' 2>/dev/null | head -n1 || true)"
  if [[ -n "$line" && "$line" != *nginx* ]]; then
    die "TCP/80 уже занят не Nginx, Certbot webroot невозможен: $line"
  fi
}

hysteria_listener_line() {
  ss -H -lunp "( sport = :$HYSTERIA_PORT )" 2>/dev/null | head -n1 || true
}

hysteria_listener_is_expected() {
  local line="${1:-}"
  [[ "$line" == *xray* || "$line" == *rw-core* || "$line" == *remnanode* ]]
}

check_hysteria_port_conflicts() {
  local line=""
  bool_true "$EXPECT_HYSTERIA" || return 0
  command -v ss >/dev/null 2>&1 || return 0
  line="$(hysteria_listener_line)"
  [[ -n "$line" ]] || return 0
  if [[ "$line" == *users:* ]] && ! hysteria_listener_is_expected "$line"; then
    die "UDP/$HYSTERIA_PORT уже занят не RemnaNode/Xray: $line"
  fi
}

tune_nginx_capacity() {
  local mem_mb=""
  local target=4096
  local current=""
  local tmp_dropin=""

  mem_mb="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
  (( mem_mb >= 4096 )) && target=16384 || true
  (( mem_mb >= 1536 && mem_mb < 4096 )) && target=8192 || true

  current="$(awk '$1 == "worker_connections" {gsub(/;/, "", $2); print $2; exit}' /etc/nginx/nginx.conf 2>/dev/null || true)"
  if [[ "$current" =~ ^[0-9]+$ ]] && (( current < target )); then
    sed -E -i "0,/^[[:space:]]*worker_connections[[:space:]]+[0-9]+;/s//        worker_connections $target;/" /etc/nginx/nginx.conf
    NGINX_RESTART_REQUIRED=1
  elif [[ ! "$current" =~ ^[0-9]+$ ]]; then
    warn "Не нашёл стандартный worker_connections в nginx.conf; глобальный Nginx не переписываю."
  fi

  install -d -m 0755 "$(dirname "$NGINX_CAPACITY_DROPIN")"
  tmp_dropin="$(mktemp)"
  cat >"$tmp_dropin" <<'EOF'
[Service]
LimitNOFILE=262144
Restart=on-failure
RestartSec=2s
EOF
  if [[ ! -r "$NGINX_CAPACITY_DROPIN" ]] || ! cmp -s "$tmp_dropin" "$NGINX_CAPACITY_DROPIN"; then
    install -m 0644 "$tmp_dropin" "$NGINX_CAPACITY_DROPIN"
    NGINX_RESTART_REQUIRED=1
  fi
  rm -f "$tmp_dropin"
  chmod 0644 "$NGINX_CAPACITY_DROPIN"
  systemctl daemon-reload
}

select_nginx_include_target() {
  local sites_probe="/etc/nginx/sites-enabled/zz-remnanode-include-probe-$$.conf"
  local confd_probe="/etc/nginx/conf.d/zz-remnanode-include-probe-$$.conf"
  local dump=""
  local conflicts=0

  install -d -m 0755 /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/nginx/conf.d
  # Remove only installer-owned enabled entries while probing the real include
  # topology. The running Nginx master keeps serving its already loaded config.
  rm -f "$NGINX_SITES_ENABLED_SITE" "$NGINX_CONF_D_SITE" \
    "$NGINX_SITES_ENABLED_BOOTSTRAP" "$NGINX_CONF_D_BOOTSTRAP"
  printf '%s\n' '# REMNANODE_INCLUDE_PROBE_SITES' >"$sites_probe"
  printf '%s\n' '# REMNANODE_INCLUDE_PROBE_CONFD' >"$confd_probe"
  if ! dump="$(nginx -T 2>&1)"; then
    rm -f "$sites_probe" "$confd_probe"
    die "Существующая Nginx configuration повреждена вне installer; исправьте nginx -T перед xHTTP setup."
  fi
  rm -f "$sites_probe" "$confd_probe"

  if grep -Fq '# REMNANODE_INCLUDE_PROBE_SITES' <<<"$dump"; then
    NGINX_SITE_ENABLED="$NGINX_SITES_ENABLED_SITE"
    NGINX_BOOTSTRAP_ENABLED="$NGINX_SITES_ENABLED_BOOTSTRAP"
  elif grep -Fq '# REMNANODE_INCLUDE_PROBE_CONFD' <<<"$dump"; then
    NGINX_SITE_ENABLED="$NGINX_CONF_D_SITE"
    NGINX_BOOTSTRAP_ENABLED="$NGINX_CONF_D_BOOTSTRAP"
  else
    die "Nginx не загружает ни sites-enabled, ни conf.d; безопасно подключить xHTTP vhost невозможно."
  fi

  conflicts="$(awk -v domain="$XHTTP_DOMAIN" '
    $1 == "server_name" {
      for (i = 2; i <= NF; i++) {
        name = $i
        gsub(/;/, "", name)
        if (name == domain) count++
      }
    }
    END { print count + 0 }
  ' <<<"$dump")"
  (( conflicts == 0 )) || \
    die "Другой Nginx vhost уже использует server_name $XHTTP_DOMAIN; удалите конфликт перед установкой xHTTP."
}

write_nginx_bootstrap_site() {
  local ipv6_http=""
  if [[ -r /proc/sys/net/ipv6/conf/all/disable_ipv6 ]] && \
     [[ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)" == "0" ]]; then
    ipv6_http="    listen [::]:80;"
  fi
  install -d -m 0755 /etc/nginx/sites-available /etc/nginx/sites-enabled "$NGINX_ACME_ROOT"
  cat >"$NGINX_BOOTSTRAP_AVAILABLE" <<EOF
server {
    listen 80;
$ipv6_http
    server_name $XHTTP_DOMAIN;

    location ^~ /.well-known/acme-challenge/ {
        root $NGINX_ACME_ROOT;
        default_type text/plain;
    }

    location / {
        return 404;
    }
}
EOF
  # A broken/expired final TLS site would make nginx -t fail before Certbot
  # can repair it. Temporarily expose only the HTTP ACME bootstrap site.
  rm -f "$NGINX_SITES_ENABLED_SITE" "$NGINX_CONF_D_SITE"
  ln -sfn "$NGINX_BOOTSTRAP_AVAILABLE" "$NGINX_BOOTSTRAP_ENABLED"
  nginx -t
  systemctl enable --now nginx
  systemctl reload nginx
}

tls_pair_usable_for_domain() {
  local cert="$1"
  local key="$2"
  local domain="${3:-}"
  local cert_public=""
  local key_public=""

  [[ -r "$cert" && -r "$key" ]] || return 1
  openssl x509 -in "$cert" -checkend "$TLS_MIN_VALID_SECONDS" -noout >/dev/null 2>&1 || return 1
  openssl pkey -in "$key" -noout >/dev/null 2>&1 || return 1
  cert_public="$(openssl x509 -in "$cert" -pubkey -noout 2>/dev/null | \
    openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | awk '{print $1}')" || return 1
  key_public="$(openssl pkey -in "$key" -pubout -outform DER 2>/dev/null | \
    sha256sum | awk '{print $1}')" || return 1
  [[ -n "$cert_public" && "$cert_public" == "$key_public" ]] || return 1
  [[ -z "$domain" ]] || openssl x509 -in "$cert" -noout -checkhost "$domain" >/dev/null 2>&1
}

find_usable_certbot_lineage() {
  local domain="$1"
  local candidate=""
  local candidate_expiry=0
  local best=""
  local best_expiry=0
  local enddate=""
  local -a candidates=()

  [[ -n "$domain" ]] || return 1
  shopt -s nullglob
  candidates=(/etc/letsencrypt/live/*)
  shopt -u nullglob
  for candidate in "${candidates[@]}"; do
    [[ -d "$candidate" ]] || continue
    [[ -r "/etc/letsencrypt/renewal/$(basename "$candidate").conf" ]] || continue
    tls_pair_usable_for_domain "$candidate/fullchain.pem" "$candidate/privkey.pem" "$domain" || continue
    enddate="$(openssl x509 -in "$candidate/fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2-)"
    candidate_expiry="$(date -d "$enddate" +%s 2>/dev/null || printf '0')"
    [[ "$candidate_expiry" =~ ^[0-9]+$ ]] || candidate_expiry=0
    if (( candidate_expiry > best_expiry )); then
      best="$candidate"
      best_expiry="$candidate_expiry"
    fi
  done
  [[ -n "$best" ]] || return 1
  printf '%s' "$best"
}

acquire_nginx_lock() {
  [[ -z "$NGINX_LOCK_FD" ]] || return 0
  install -d -m 0755 "$(dirname "$NGINX_LOCK_FILE")"
  exec {NGINX_LOCK_FD}>"$NGINX_LOCK_FILE"
  flock -w 120 "$NGINX_LOCK_FD" || die "Не удалось получить lock для безопасного изменения Nginx."
}

release_nginx_lock() {
  [[ -n "$NGINX_LOCK_FD" ]] || return 0
  flock -u "$NGINX_LOCK_FD" >/dev/null 2>&1 || true
  exec {NGINX_LOCK_FD}>&-
  NGINX_LOCK_FD=""
}

warn_external_tls_lifecycle() {
  local cert="$1"
  local expiry="unknown"
  expiry="$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2- || true)"
  warn "TLS certificate не управляется Certbot этого installer (expires: $expiry). Настройте внешнее продление и повторный запуск installer до истечения certificate."
}

copy_tls_pair() {
  local cert="$1"
  local key="$2"
  local cert_public=""
  local key_public=""
  [[ -r "$cert" && -r "$key" ]] || die "Не найдена TLS-пара: $cert / $key"
  openssl x509 -in "$cert" -noout >/dev/null 2>&1 || die "Некорректный TLS certificate: $cert"
  openssl x509 -in "$cert" -checkend "$TLS_MIN_VALID_SECONDS" -noout >/dev/null 2>&1 || die "TLS certificate истёк или истекает менее чем через 7 суток: $cert"
  openssl pkey -in "$key" -noout >/dev/null 2>&1 || die "Некорректный TLS private key: $key"
  cert_public="$(openssl x509 -in "$cert" -pubkey -noout | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
  key_public="$(openssl pkey -in "$key" -pubout -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
  [[ -n "$cert_public" && "$cert_public" == "$key_public" ]] || die "TLS certificate и private key не образуют пару."
  if [[ -n "$XHTTP_DOMAIN" ]]; then
    openssl x509 -in "$cert" -noout -checkhost "$XHTTP_DOMAIN" >/dev/null 2>&1 || \
      die "TLS certificate не подходит домену $XHTTP_DOMAIN."
  fi

  if [[ ! -r "$TLS_DIR/fullchain.pem" || ! -r "$TLS_DIR/privkey.pem" ]] || \
     ! cmp -s "$cert" "$TLS_DIR/fullchain.pem" || ! cmp -s "$key" "$TLS_DIR/privkey.pem"; then
    install -m 0644 "$cert" "$TLS_DIR/fullchain.pem.new"
    install -m 0600 "$key" "$TLS_DIR/privkey.pem.new"
    mv -f "$TLS_DIR/fullchain.pem.new" "$TLS_DIR/fullchain.pem"
    mv -f "$TLS_DIR/privkey.pem.new" "$TLS_DIR/privkey.pem"
    TLS_CHANGED=1
  fi
  chmod 0644 "$TLS_DIR/fullchain.pem"
  chmod 0600 "$TLS_DIR/privkey.pem"
  # Keep compatibility with existing profile variants without exposing the
  # host Let's Encrypt tree inside the container.
  if [[ "$(readlink "$TLS_DIR/cert.pem" 2>/dev/null || true)" != "fullchain.pem" || \
        "$(readlink "$TLS_DIR/cert.key" 2>/dev/null || true)" != "privkey.pem" ]]; then
    TLS_CHANGED=1
  fi
  ln -sfnT fullchain.pem "$TLS_DIR/cert.pem"
  ln -sfnT privkey.pem "$TLS_DIR/cert.key"
}

obtain_or_copy_certificate() {
  local le_dir=""
  local -a email_args=()
  local -a renewal_args=(--keep-until-expiring)

  if [[ -n "$TLS_CERT_FILE" || -n "$TLS_KEY_FILE" ]]; then
    [[ -n "$TLS_CERT_FILE" && -n "$TLS_KEY_FILE" ]] || die "Нужно задать и TLS_CERT_FILE, и TLS_KEY_FILE."
    copy_tls_pair "$TLS_CERT_FILE" "$TLS_KEY_FILE"
    CERTBOT_MANAGED=0
    CERTBOT_LINEAGE_DIR=""
    warn_external_tls_lifecycle "$TLS_DIR/fullchain.pem"
    return 0
  fi

  le_dir="$(find_usable_certbot_lineage "$XHTTP_DOMAIN" || true)"
  if [[ -n "$le_dir" ]]; then
    copy_tls_pair "$le_dir/fullchain.pem" "$le_dir/privkey.pem"
    CERTBOT_MANAGED=1
    CERTBOT_LINEAGE_DIR="$le_dir"
    return 0
  fi

  if tls_pair_usable_for_domain "$TLS_DIR/fullchain.pem" "$TLS_DIR/privkey.pem" "$XHTTP_DOMAIN"; then
    warn "Найдена рабочая TLS-пара без Certbot lineage; выпускаю управляемый certificate, чтобы нода не отвалилась после её истечения."
  fi

  if [[ -n "$LETSENCRYPT_EMAIL" ]]; then
    email_args=(--email "$LETSENCRYPT_EMAIL")
  else
    email_args=(--register-unsafely-without-email)
  fi

  if [[ -d "/etc/letsencrypt/live/$XHTTP_DOMAIN" ]]; then
    renewal_args=(--force-renewal)
  fi
  log "Получаю Let's Encrypt certificate для $XHTTP_DOMAIN"
  certbot certonly --webroot -w "$NGINX_ACME_ROOT" -d "$XHTTP_DOMAIN" \
    --cert-name "$XHTTP_DOMAIN" --non-interactive --agree-tos \
    "${renewal_args[@]}" "${email_args[@]}"
  le_dir="/etc/letsencrypt/live/$XHTTP_DOMAIN"
  tls_pair_usable_for_domain "$le_dir/fullchain.pem" "$le_dir/privkey.pem" "$XHTTP_DOMAIN" || \
    die "Certbot завершился, но не создал пригодный certificate для $XHTTP_DOMAIN."
  copy_tls_pair "$le_dir/fullchain.pem" "$le_dir/privkey.pem"
  CERTBOT_MANAGED=1
  CERTBOT_LINEAGE_DIR="$le_dir"
}

write_cert_deploy_hook() {
  [[ "$CERTBOT_LINEAGE_DIR" == /etc/letsencrypt/live/* ]] || \
    die "Не определён безопасный Certbot lineage для deploy hook."
  install -d -m 0755 "$(dirname "$CERT_DEPLOY_HOOK")"
  cat >"$CERT_DEPLOY_HOOK" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
DOMAIN="$XHTTP_DOMAIN"
SRC="$CERTBOT_LINEAGE_DIR"
DST="$TLS_DIR"
LOCK_FILE="$NGINX_LOCK_FILE"
replaced=0
tmp_cert="\$DST/.fullchain.pem.new.\$\$"
tmp_key="\$DST/.privkey.pem.new.\$\$"
old_cert="\$DST/.fullchain.pem.old.\$\$"
old_key="\$DST/.privkey.pem.old.\$\$"
cleanup() { rm -f "\$tmp_cert" "\$tmp_key" "\$old_cert" "\$old_key"; }
trap cleanup EXIT

exec 9>"\$LOCK_FILE"
flock -w 120 9

if [[ -n "\${RENEWED_DOMAINS:-}" && " \${RENEWED_DOMAINS} " != *" \$DOMAIN "* ]]; then
  exit 0
fi
if [[ -n "\${RENEWED_LINEAGE:-}" ]]; then
  SRC="\$RENEWED_LINEAGE"
fi
[[ "\$SRC" == /etc/letsencrypt/live/* ]]

openssl x509 -in "\$SRC/fullchain.pem" -checkend $TLS_MIN_VALID_SECONDS -noout >/dev/null
openssl x509 -in "\$SRC/fullchain.pem" -checkhost "\$DOMAIN" -noout >/dev/null
openssl pkey -in "\$SRC/privkey.pem" -noout >/dev/null
cert_public="\$(openssl x509 -in "\$SRC/fullchain.pem" -pubkey -noout | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | awk '{print \$1}')"
key_public="\$(openssl pkey -in "\$SRC/privkey.pem" -pubout -outform DER 2>/dev/null | sha256sum | awk '{print \$1}')"
[[ -n "\$cert_public" && "\$cert_public" == "\$key_public" ]]

if ! cmp -s "\$SRC/fullchain.pem" "\$DST/fullchain.pem" || ! cmp -s "\$SRC/privkey.pem" "\$DST/privkey.pem"; then
  install -m 0644 "\$SRC/fullchain.pem" "\$tmp_cert"
  install -m 0600 "\$SRC/privkey.pem" "\$tmp_key"
  if [[ -r "\$DST/fullchain.pem" && -r "\$DST/privkey.pem" ]]; then
    install -m 0644 "\$DST/fullchain.pem" "\$old_cert"
    install -m 0600 "\$DST/privkey.pem" "\$old_key"
  fi
  mv -f "\$tmp_cert" "\$DST/fullchain.pem"
  mv -f "\$tmp_key" "\$DST/privkey.pem"
  replaced=1
fi
ln -sfnT fullchain.pem "\$DST/cert.pem"
ln -sfnT privkey.pem "\$DST/cert.key"

if command -v nginx >/dev/null 2>&1; then
  if ! nginx -t; then
    if [[ "\$replaced" == "1" ]]; then
      if [[ -r "\$old_cert" && -r "\$old_key" ]]; then
        mv -f "\$old_cert" "\$DST/fullchain.pem"
        mv -f "\$old_key" "\$DST/privkey.pem"
      else
        rm -f "\$DST/fullchain.pem" "\$DST/privkey.pem"
      fi
    fi
    exit 1
  fi
  systemctl reload nginx
fi

# Reload a currently running Node so Hysteria receives the renewed certificate.
# Never start a deliberately stopped container; retry only transient failures.
if docker inspect -f '{{.State.Running}}' remnanode 2>/dev/null | grep -qx true; then
  restart_ok=0
  for attempt in 1 2 3; do
    if docker restart --time 45 remnanode >/dev/null; then
      restart_ok=1
      break
    fi
    sleep "\$((attempt * 3))"
  done
  [[ "\$restart_ok" == "1" ]]
fi
EOF
  chmod 0700 "$CERT_DEPLOY_HOOK"
}

ensure_certbot_renewal() {
  (( CERTBOT_MANAGED == 1 )) || return 0
  if systemctl list-unit-files certbot.timer --no-legend 2>/dev/null | grep -q .; then
    systemctl enable --now certbot.timer >/dev/null || \
      die "Не удалось включить certbot.timer; автоматическое продление TLS не гарантировано."
    return 0
  fi
  if [[ -r /etc/cron.d/certbot ]]; then
    log "Автопродление TLS обслуживается /etc/cron.d/certbot."
    return 0
  fi
  die "Certbot установлен без timer/cron для автоматического продления TLS."
}

write_nginx_xhttp_site() {
  local ipv6_http=""
  local ipv6_https=""
  local grpc_socket_keepalive=""
  local nginx_version=""
  local tmp_site=""
  local changed=0
  local had_bootstrap=0
  local edge_status=""
  local loaded_dump=""
  if [[ -r /proc/sys/net/ipv6/conf/all/disable_ipv6 ]] && [[ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)" == "0" ]]; then
    ipv6_http="    listen [::]:80;"
    ipv6_https="    listen [::]:443 ssl http2;"
  fi
  nginx_version="$(nginx -v 2>&1 | sed -n 's#^nginx version: nginx/##p' | awk '{print $1}')"
  if [[ -n "$nginx_version" ]] && version_ge "$nginx_version" "1.15.6"; then
    grpc_socket_keepalive="        grpc_socket_keepalive on;"
  else
    warn "Nginx ${nginx_version:-unknown} не поддерживает grpc_socket_keepalive; xHTTP останется совместимым без этой необязательной директивы."
  fi

  tmp_site="$(mktemp)"
  cat >"$tmp_site" <<EOF
# remnanode-installer-managed-xhttp
server {
    listen 80;
$ipv6_http
    server_name $XHTTP_DOMAIN;

    location ^~ /.well-known/acme-challenge/ {
        root $NGINX_ACME_ROOT;
        default_type text/plain;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
$ipv6_https
    server_name $XHTTP_DOMAIN;
    server_tokens off;
    access_log off;

    ssl_certificate $TLS_DIR/fullchain.pem;
    ssl_certificate_key $TLS_DIR/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:REMNANODE_TLS:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    client_header_timeout 5m;
    keepalive_timeout 5m;
    keepalive_requests 10000;
    reset_timedout_connection on;

    location = / {
        return 204;
    }

    location ^~ $XHTTP_PATH {
        client_max_body_size 0;
        client_body_timeout 5m;
        grpc_read_timeout 315s;
        grpc_send_timeout 5m;
$grpc_socket_keepalive
        grpc_set_header Host \$host;
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_set_header X-Forwarded-Proto https;
        grpc_pass unix:$XHTTP_SOCKET;
    }

    location / {
        return 404;
    }
}
EOF
  if [[ ! -r "$NGINX_SITE_AVAILABLE" ]] || ! cmp -s "$tmp_site" "$NGINX_SITE_AVAILABLE"; then
    install -m 0644 "$tmp_site" "$NGINX_SITE_AVAILABLE"
    changed=1
  fi
  rm -f "$tmp_site"
  ln -sfn "$NGINX_SITE_AVAILABLE" "$NGINX_SITE_ENABLED"
  rm -f /etc/nginx/sites-enabled/remnanode-xhttp-http.conf \
    /etc/nginx/sites-available/remnanode-xhttp-http.conf \
    /etc/nginx/sites-enabled/remnanode-xhttp-h3-8443.conf \
    /etc/nginx/sites-available/remnanode-xhttp-h3-8443.conf \
    /etc/nginx/conf.d/00-tokervpn-xhttp-tuning.conf
  if [[ -e "$NGINX_SITES_ENABLED_BOOTSTRAP" || -e "$NGINX_CONF_D_BOOTSTRAP" || \
        -e "$NGINX_BOOTSTRAP_AVAILABLE" ]]; then
    had_bootstrap=1
  fi
  rm -f "$NGINX_SITES_ENABLED_BOOTSTRAP" "$NGINX_CONF_D_BOOTSTRAP" "$NGINX_BOOTSTRAP_AVAILABLE"
  nginx -t
  loaded_dump="$(nginx -T 2>&1)"
  grep -Fq '# remnanode-installer-managed-xhttp' <<<"$loaded_dump" || \
    die "Nginx принял файл, но не загрузил managed xHTTP vhost."
  systemctl enable nginx >/dev/null
  if ! systemctl is-active --quiet nginx.service; then
    systemctl start nginx
  elif (( NGINX_RESTART_REQUIRED == 1 )); then
    systemctl restart nginx
  elif (( changed == 1 || had_bootstrap == 1 || TLS_CHANGED == 1 )); then
    systemctl reload nginx
  fi
  edge_status="$(curl -ksS --http1.1 --noproxy '*' --connect-timeout 3 --max-time 8 \
    --resolve "$XHTTP_DOMAIN:443:127.0.0.1" -o /dev/null -w '%{http_code}' \
    "https://$XHTTP_DOMAIN/" 2>/dev/null || true)"
  [[ "$edge_status" == "204" ]] || die "Локальный TLS/SNI probe не попал в managed xHTTP vhost (HTTP ${edge_status:-none})."
  (( changed == 0 )) || log "xHTTP Nginx site обновлён."
}

disable_xhttp_module() {
  command -v nginx >/dev/null 2>&1 && acquire_nginx_lock
  rm -f "$NGINX_SITES_ENABLED_SITE" "$NGINX_CONF_D_SITE" "$NGINX_SITE_AVAILABLE" "$CERT_DEPLOY_HOOK" \
    "$NGINX_CAPACITY_DROPIN" "$NGINX_SITES_ENABLED_BOOTSTRAP" "$NGINX_CONF_D_BOOTSTRAP" "$NGINX_BOOTSTRAP_AVAILABLE" \
    /etc/nginx/sites-enabled/remnanode-xhttp-http.conf \
    /etc/nginx/sites-available/remnanode-xhttp-http.conf \
    /etc/nginx/sites-enabled/remnanode-xhttp-h3-8443.conf \
    /etc/nginx/sites-available/remnanode-xhttp-h3-8443.conf \
    /etc/nginx/conf.d/00-tokervpn-xhttp-tuning.conf
  if command -v nginx >/dev/null 2>&1; then
    nginx -t || die "После отключения xHTTP оставшаяся Nginx configuration невалидна."
    if systemctl is-active --quiet nginx.service; then
      systemctl reload nginx || die "Nginx не применил отключение xHTTP."
    fi
  fi
  systemctl daemon-reload >/dev/null 2>&1 || true
  release_nginx_lock
}

configure_xhttp_module() {
  local need_bootstrap=0
  local existing_le=""
  check_hysteria_port_conflicts
  if ! bool_true "$ENABLE_XHTTP"; then
    disable_xhttp_module
    if [[ -n "$TLS_CERT_FILE" || -n "$TLS_KEY_FILE" ]]; then
      [[ -n "$TLS_CERT_FILE" && -n "$TLS_KEY_FILE" ]] || die "Нужно задать и TLS_CERT_FILE, и TLS_KEY_FILE."
      copy_tls_pair "$TLS_CERT_FILE" "$TLS_KEY_FILE"
      warn_external_tls_lifecycle "$TLS_DIR/fullchain.pem"
    elif [[ -r "$TLS_DIR/fullchain.pem" && -r "$TLS_DIR/privkey.pem" ]]; then
      copy_tls_pair "$TLS_DIR/fullchain.pem" "$TLS_DIR/privkey.pem"
      warn "Использую существующий TLS для Hysteria; при отключённом xHTTP его продление остаётся внешней ответственностью."
    elif bool_true "$EXPECT_HYSTERIA"; then
      die "TLS-файлы Hysteria отсутствуют в $TLS_DIR. Задайте xHTTP domain либо TLS_CERT_FILE/TLS_KEY_FILE."
    fi
    return 0
  fi

  log "Настраиваю optional xHTTP module без HTTP/3 и без подмен RemnaNode"
  check_xhttp_port_conflicts
  apt_retry install -y --no-install-recommends nginx certbot
  acquire_nginx_lock
  select_nginx_include_target
  tune_nginx_capacity
  existing_le="$(find_usable_certbot_lineage "$XHTTP_DOMAIN" || true)"

  if [[ -n "$TLS_CERT_FILE" && -n "$TLS_KEY_FILE" ]]; then
    need_bootstrap=0
  elif [[ -n "$existing_le" ]]; then
    need_bootstrap=0
  else
    need_bootstrap=1
  fi

  if (( need_bootstrap == 1 )); then
    write_nginx_bootstrap_site
    release_nginx_lock
  fi
  obtain_or_copy_certificate
  acquire_nginx_lock
  if (( CERTBOT_MANAGED == 1 )); then
    write_cert_deploy_hook
    ensure_certbot_renewal
  else
    rm -f "$CERT_DEPLOY_HOOK"
  fi
  write_nginx_xhttp_site
  release_nginx_lock
}

configure_xhttp_socket_guard() {
  local guard_rc=0
  local tmp_script=""
  local tmp_service=""
  local tmp_timer=""

  systemctl disable --now remnanode-xhttp-socket-guard.timer >/dev/null 2>&1 || true
  systemctl stop remnanode-xhttp-socket-guard.service >/dev/null 2>&1 || true
  if ! bool_true "$ENABLE_XHTTP"; then
    rm -f "$XHTTP_GUARD_SCRIPT" "$XHTTP_GUARD_SERVICE" "$XHTTP_GUARD_TIMER" "$XHTTP_GUARD_MARKER"
    systemctl daemon-reload
    return 0
  fi

  tmp_script="$(mktemp)"
  tmp_service="$(mktemp)"
  tmp_timer="$(mktemp)"
  cat >"$tmp_script" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SOCKET_PATH='$XHTTP_SOCKET'
LOCK_PATH="\${SOCKET_PATH}.lock"
INSTALLER_LOCK_PATH='$LOCK_FILE'
RESTART_MARKER='$XHTTP_GUARD_MARKER'
RESTART_COOLDOWN_SECONDS=300

# The timer must never race an install/update/rollback. The installer invokes
# this root-only helper directly for its one pre-activation check.
if [[ "\${REMNANODE_GUARD_INSTALLER_CONTEXT:-0}" != "1" ]]; then
  exec 8>>"\$INSTALLER_LOCK_PATH"
  flock -n 8 || exit 0
fi

[[ -e "\$SOCKET_PATH" || -L "\$SOCKET_PATH" ]] || exit 0

# Healthy fast path: avoid starting Python on every timer tick. This check can
# only skip deletion, never authorize it; the locked Python check below is the
# authoritative path for anything that may be stale.
if [[ -r /proc/net/unix ]] && \
   awk -v wanted="\$SOCKET_PATH" 'NR > 1 && \$NF == wanted { found=1 } END { exit(found ? 0 : 1) }' /proc/net/unix; then
  exit 0
fi

# Xray serializes Unix bind attempts with <socket>.lock. Python opens that
# exact file with O_NOFOLLOW, takes the same nonblocking flock, validates the
# live kernel socket table and unlinks only an inactive Unix socket.
guard_result=""
if ! guard_result="\$(python3 - "\$SOCKET_PATH" "\$LOCK_PATH" "\$RESTART_MARKER" "\$RESTART_COOLDOWN_SECONDS" "\${REMNANODE_GUARD_INSTALLER_CONTEXT:-0}" <<'PY'
import fcntl
import os
import stat
import subprocess
import sys
import time

socket_path, lock_path, restart_marker = sys.argv[1:4]
restart_cooldown = int(sys.argv[4])
installer_context = sys.argv[5] == "1"
flags = os.O_CREAT | os.O_RDWR
if hasattr(os, "O_CLOEXEC"):
    flags |= os.O_CLOEXEC
if hasattr(os, "O_NOFOLLOW"):
    flags |= os.O_NOFOLLOW

try:
    fd = os.open(lock_path, flags, 0o600)
except OSError as exc:
    print(f"cannot safely open Xray lock {lock_path}: {exc}", file=sys.stderr)
    raise SystemExit(2)

try:
    opened = os.fstat(fd)
    if not stat.S_ISREG(opened.st_mode):
        print(f"Xray lock is not a regular file: {lock_path}", file=sys.stderr)
        raise SystemExit(2)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise SystemExit(0)
    os.fchown(fd, 0, 0)
    os.fchmod(fd, 0o600)
    try:
        linked = os.lstat(lock_path)
    except FileNotFoundError:
        raise SystemExit(0)
    if (opened.st_dev, opened.st_ino) != (linked.st_dev, linked.st_ino):
        print(f"replaced Xray lock path: {lock_path}", file=sys.stderr)
        raise SystemExit(2)
    if linked.st_uid != 0 or linked.st_nlink != 1:
        print(f"unsafe Xray lock owner/link count: {lock_path}", file=sys.stderr)
        raise SystemExit(2)

    try:
        socket_stat = os.lstat(socket_path)
    except FileNotFoundError:
        raise SystemExit(0)
    if not stat.S_ISSOCK(socket_stat.st_mode):
        print(f"refusing to remove non-socket path: {socket_path}", file=sys.stderr)
        raise SystemExit(2)
    if socket_stat.st_uid != 0 or socket_stat.st_nlink != 1:
        print(f"refusing unsafe socket owner/link count: {socket_path}", file=sys.stderr)
        raise SystemExit(2)

    try:
        with open("/proc/net/unix", "r", encoding="utf-8") as proc_unix:
            for line in proc_unix:
                fields = line.split()
                if len(fields) >= 8 and fields[7] == socket_path:
                    raise SystemExit(0)
    except OSError as exc:
        print(f"cannot verify /proc/net/unix: {exc}", file=sys.stderr)
        raise SystemExit(2)

    try:
        current_socket = os.lstat(socket_path)
    except FileNotFoundError:
        raise SystemExit(0)
    if (
        (current_socket.st_dev, current_socket.st_ino) != (socket_stat.st_dev, socket_stat.st_ino)
        or not stat.S_ISSOCK(current_socket.st_mode)
        or current_socket.st_uid != 0
        or current_socket.st_nlink != 1
    ):
        raise SystemExit(0)
    os.unlink(socket_path)

    if installer_context:
        print("cleaned-installer")
        raise SystemExit(0)

    # Prefer native s6 recovery from the image. A newly supervised rw-core may
    # be waiting on our flock; after we release it, that process can bind the now
    # clean path without interrupting healthy Hysteria sessions. Restart the
    # container only when s6 repeatedly and explicitly reports Xray down.
    try:
        inspected = subprocess.run(
            ["docker", "inspect", "-f", "{{.State.Running}}", "remnanode"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=10,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        print("cleaned-status-unknown")
        raise SystemExit(0)

    if inspected.returncode != 0 or inspected.stdout.strip() != "true":
        print("cleaned-no-container")
        raise SystemExit(0)

    status_valid = True
    xray_up = False
    for attempt in range(3):
        try:
            xray_status = subprocess.run(
                ["docker", "exec", "remnanode", "/command/s6-svstat", "-o", "up", "/run/service/xray"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=10,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            status_valid = False
            break
        answer = xray_status.stdout.strip().lower()
        if xray_status.returncode != 0 or answer not in {"true", "false"}:
            status_valid = False
            break
        if answer == "true":
            xray_up = True
            break
        if attempt < 2:
            time.sleep(1)

    if xray_up:
        print("cleaned-supervisor")
        raise SystemExit(0)
    if not status_valid:
        print("cleaned-status-unknown")
        raise SystemExit(0)

    try:
        cooldown_active = False
        try:
            marker_stat = os.lstat(restart_marker)
            if not stat.S_ISREG(marker_stat.st_mode) or marker_stat.st_uid != 0 or marker_stat.st_nlink != 1:
                print(f"unsafe restart marker: {restart_marker}", file=sys.stderr)
                raise SystemExit(2)
            elapsed = time.time() - marker_stat.st_mtime
            cooldown_active = elapsed < 0 or elapsed < restart_cooldown
        except FileNotFoundError:
            pass
        if cooldown_active:
            print("cleaned-cooldown")
            raise SystemExit(0)

        marker_flags = os.O_CREAT | os.O_WRONLY | os.O_TRUNC
        if hasattr(os, "O_CLOEXEC"):
            marker_flags |= os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            marker_flags |= os.O_NOFOLLOW
        marker_fd = os.open(restart_marker, marker_flags, 0o600)
        try:
            os.fchown(marker_fd, 0, 0)
            os.fchmod(marker_fd, 0o600)
            os.write(marker_fd, f"{int(time.time())}\n".encode("ascii"))
        finally:
            os.close(marker_fd)
        restarted = subprocess.run(
            ["docker", "restart", "--time", "45", "remnanode"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=90,
            check=False,
        )
        if restarted.returncode != 0:
            print("stale socket removed, but remnanode restart failed", file=sys.stderr)
            raise SystemExit(2)
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f"stale socket removed, but controlled restart failed: {exc}", file=sys.stderr)
        raise SystemExit(2)
    print("cleaned")
finally:
    os.close(fd)
PY
)"; then
  logger -p daemon.err -t remnanode-xhttp-guard -- "safe stale-socket check failed"
  exit 1
fi
case "\$guard_result" in
  cleaned)
    logger -p daemon.warning -t remnanode-xhttp-guard -- "removed stale xHTTP socket and performed one controlled restart: \$SOCKET_PATH"
    ;;
  cleaned-cooldown)
    logger -p daemon.warning -t remnanode-xhttp-guard -- "removed stale xHTTP socket; restart suppressed by 300s cooldown: \$SOCKET_PATH"
    ;;
  cleaned-supervisor)
    logger -p daemon.warning -t remnanode-xhttp-guard -- "removed stale xHTTP socket; native rw-core supervisor is recovering without container restart: \$SOCKET_PATH"
    ;;
  cleaned-status-unknown)
    logger -p daemon.warning -t remnanode-xhttp-guard -- "removed stale xHTTP socket; rw-core status was not provable, so container restart was skipped: \$SOCKET_PATH"
    ;;
  cleaned-no-container)
    logger -p daemon.warning -t remnanode-xhttp-guard -- "removed stale xHTTP socket; container was not running and was left stopped: \$SOCKET_PATH"
    ;;
  cleaned-installer)
    logger -p daemon.warning -t remnanode-xhttp-guard -- "removed stale xHTTP socket; installer will perform one transactional recreate: \$SOCKET_PATH"
    exit 10
    ;;
  *)
    exit 0
    ;;
esac
EOF

  cat >"$tmp_service" <<EOF
[Unit]
Description=Safe stale xHTTP Unix socket recovery for RemnaNode
After=docker.service

[Service]
Type=oneshot
ExecStart=$XHTTP_GUARD_SCRIPT
TimeoutStartSec=180
Nice=10
IOSchedulingClass=idle
NoNewPrivileges=yes
ProtectSystem=full
ProtectHome=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
LockPersonality=yes
RestrictAddressFamilies=AF_UNIX
ReadWritePaths=/dev/shm
EOF

  cat >"$tmp_timer" <<'EOF'
[Unit]
Description=Periodic stale xHTTP Unix socket recovery for RemnaNode

[Timer]
OnBootSec=30s
OnUnitInactiveSec=60s
AccuracySec=5s
Persistent=false
Unit=remnanode-xhttp-socket-guard.service

[Install]
WantedBy=timers.target
EOF

  install -m 0700 "$tmp_script" "$XHTTP_GUARD_SCRIPT"
  install -m 0644 "$tmp_service" "$XHTTP_GUARD_SERVICE"
  install -m 0644 "$tmp_timer" "$XHTTP_GUARD_TIMER"
  rm -f "$tmp_script" "$tmp_service" "$tmp_timer"
  systemctl daemon-reload
  systemctl enable remnanode-xhttp-socket-guard.timer >/dev/null

  # Clean a socket left by a previous hard crash before Compose activation.
  # The direct call is safe here because this installer owns LOCK_FILE.
  if REMNANODE_GUARD_INSTALLER_CONTEXT=1 "$XHTTP_GUARD_SCRIPT"; then
    guard_rc=0
  else
    guard_rc=$?
  fi
  case "$guard_rc" in
    0) ;;
    10) INSTALL_CHANGED=1 ;;
    *) die "Безопасная проверка stale xHTTP socket завершилась ошибкой." ;;
  esac
}

start_xhttp_socket_guard() {
  bool_true "$ENABLE_XHTTP" || return 0
  systemctl start remnanode-xhttp-socket-guard.timer
  systemctl is-active --quiet remnanode-xhttp-socket-guard.timer || \
    die "Таймер безопасного восстановления xHTTP socket не запустился."
}

select_and_pull_image() {
  local -a candidates=()
  local image=""
  local attempt=0
  local source_label=""

  if [[ -n "$NODE_IMAGE_INPUT" ]]; then
    candidates=("$NODE_IMAGE_INPUT")
  else
    candidates=(
      "ghcr.io/remnawave/node:$NODE_VERSION"
      "remnawave/node:$NODE_VERSION"
    )
  fi

  for image in "${candidates[@]}"; do
    for attempt in 1 2 3; do
      log "Pull $image (attempt $attempt/3)"
      if docker pull "$image"; then
        source_label="$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.source"}}' "$image" 2>/dev/null || true)"
        if ! bool_true "$ALLOW_CUSTOM_IMAGE" && [[ "$source_label" != "https://github.com/remnawave/node" ]]; then
          warn "Image $image не прошёл проверку OCI source label."
          break
        fi
        SELECTED_IMAGE="$image"
        return 0
      fi
      sleep $((attempt * 4))
    done
  done
  die "Не удалось получить официальный RemnaNode $NODE_VERSION из GHCR или Docker Hub."
}

render_node_files() {
  local shm_mount=""

  STAGE_DIR="$(mktemp -d /tmp/remnanode-stage.XXXXXX)"
  chmod 0700 "$STAGE_DIR"

  {
    printf 'NODE_PORT=%s\n' "$NODE_PORT"
    printf 'SECRET_KEY=%s\n' "$SECRET_VALUE"
  } >"$STAGE_DIR/.env"
  chmod 0600 "$STAGE_DIR/.env"

  if bool_true "$ENABLE_XHTTP"; then
    shm_mount="      - /dev/shm:/dev/shm:rw"
  fi

  cat >"$STAGE_DIR/docker-compose.yml" <<EOF
services:
  remnanode:
    image: $SELECTED_IMAGE
    container_name: remnanode
    hostname: remnanode
    network_mode: host
    restart: always
    stop_grace_period: 45s
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    env_file:
      - .env
    healthcheck:
      test: ["CMD", "node", "-e", "const net=require('net');const s=net.connect($NODE_PORT,'127.0.0.1',()=>{s.end();process.exit(0)});s.setTimeout(3000,()=>process.exit(1));s.on('error',()=>process.exit(1));"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
    volumes:
      - $TLS_DIR:$TLS_DIR:ro
      - $TLS_DIR:/var/lib/remnawave/configs/xray/ssl:ro
      - $LOG_DIR:/var/log/xray
      - $LOG_DIR:/var/log/remnanode
$shm_mount
    logging:
      driver: json-file
      options:
        max-size: "20m"
        max-file: "5"
EOF

  docker compose --project-directory "$STAGE_DIR" -f "$STAGE_DIR/docker-compose.yml" config >/dev/null
}

node_files_changed() {
  [[ -r "$COMPOSE_FILE" ]] || return 0
  [[ -r "$ENV_FILE" ]] || return 0
  cmp -s "$STAGE_DIR/docker-compose.yml" "$COMPOSE_FILE" || return 0
  cmp -s "$STAGE_DIR/.env" "$ENV_FILE" || return 0
  return 1
}

install_rendered_files() {
  if node_files_changed; then
    INSTALL_CHANGED=1
    install -m 0640 "$STAGE_DIR/docker-compose.yml" "$COMPOSE_FILE"
    install -m 0600 "$STAGE_DIR/.env" "$ENV_FILE"
  fi
  [[ ! -e "$NODE_ROOT/docker-compose.override.yml" && ! -L "$NODE_ROOT/docker-compose.override.yml" ]] || \
    die "Compose override остался после безопасной миграции: $NODE_ROOT/docker-compose.override.yml"
  [[ ! -e "$NODE_ROOT/docker-compose.override.yaml" && ! -L "$NODE_ROOT/docker-compose.override.yaml" ]] || \
    die "Compose override остался после безопасной миграции: $NODE_ROOT/docker-compose.override.yaml"
}

container_needs_recreate() {
  local running_id=""
  local desired_id=""
  [[ "$INSTALL_CHANGED" == "1" ]] && return 0
  [[ "$TLS_CHANGED" == "1" ]] && return 0
  docker inspect remnanode >/dev/null 2>&1 || return 0
  [[ "$(docker inspect --format '{{.State.Running}}' remnanode 2>/dev/null)" == "true" ]] || return 0
  running_id="$(docker inspect --format '{{.Image}}' remnanode)"
  desired_id="$(docker image inspect --format '{{.Id}}' "$SELECTED_IMAGE")"
  [[ "$running_id" != "$desired_id" ]]
}

activate_node() {
  if container_needs_recreate; then
    log "Применяю RemnaNode $NODE_VERSION"
    docker compose --project-directory "$NODE_ROOT" -f "$COMPOSE_FILE" up -d --force-recreate --remove-orphans
    INSTALL_CHANGED=1
  else
    log "Конфигурация и image уже актуальны; контейнер не перезапускаю."
  fi
}

port_listening() {
  ss -H -ltn "sport = :$NODE_PORT" 2>/dev/null | grep -q .
}

udp_port_listening() {
  local port="$1"
  ss -H -lun "sport = :$port" 2>/dev/null | grep -q .
}

verify_native_plugins() {
  local deadline=$((SECONDS + 45))
  local logs=""
  local started_at=""
  local plugin=""
  local available=0
  local nft4=0
  local nft6=0
  local -a plugins=("Ingress Filter" "Egress Filter" "Torrent Blocker" "Connection Drop")

  started_at="$(docker inspect --format '{{.State.StartedAt}}' remnanode 2>/dev/null || true)"
  while (( SECONDS < deadline )); do
    nft list table ip remnanode >/dev/null 2>&1 && nft4=1 || nft4=0
    nft list table ip6 remnanode6 >/dev/null 2>&1 && nft6=1 || nft6=0
    if (( nft4 == 1 && nft6 == 1 )) && [[ "$INSTALL_CHANGED" == "0" ]]; then
      log "Native Node Plugins: runtime capability и nftables tables подтверждены (idempotent check)."
      return 0
    fi
    logs="$(docker logs --since "$started_at" --tail 1200 remnanode 2>&1 || docker logs --tail 1200 remnanode 2>&1 || true)"
    available=0
    for plugin in "${plugins[@]}"; do
      grep -Fq "[PLUGIN] $plugin: available" <<<"$logs" && ((available += 1))
    done
    (( available == 4 && nft4 == 1 && nft6 == 1 )) && break
    sleep 2
  done

  if (( available == 4 && nft4 == 1 && nft6 == 1 )); then
    log "Native Node Plugins доступны: ingress, egress, torrent blocker, connection drop; enabled-policy задаёт панель."
    return 0
  fi

  if bool_true "$REQUIRE_NODE_PLUGINS" && ! bool_true "$ALLOW_OLD_KERNEL" && ! bool_true "$ALLOW_NO_NET_ADMIN"; then
    if grep -Fq '[PLUGIN] NftManager initialization failed.' <<<"$logs" || \
       grep -Fq ': not available' <<<"$logs"; then
      die "RemnaNode не смог инициализировать native nftables plugins."
    fi
    die "Не подтверждена готовность native Node Plugins (available=$available/4, nft4=$nft4, nft6=$nft6)."
  fi
  warn "Native Node Plugins не подтверждены (available=$available/4, nft4=$nft4, nft6=$nft6)."
}

profile_not_ready() {
  local message="$1"
  if bool_true "$REQUIRE_PROFILE_READY"; then
    die "$message"
  fi
  warn "$message"
}

verify_local_xhttp_h2_edge() {
  local attempt=0
  local headers=""
  for attempt in 1 2 3 4 5; do
    headers="$(curl -ksS --http2 --noproxy '*' --connect-timeout 3 --max-time 8 \
      --resolve "$XHTTP_DOMAIN:443:127.0.0.1" -o /dev/null -D - \
      "https://$XHTTP_DOMAIN$XHTTP_PATH" 2>/dev/null || true)"
    if grep -qE '^HTTP/[^ ]+ 400([[:space:]]|$)' <<<"$headers"; then
      return 0
    fi
    sleep 2
  done
  return 1
}

verify_profile_transports() {
  local deadline=$((SECONDS + PROFILE_WAIT_SECONDS))
  local xhttp_ready=1
  local hysteria_ready=1
  local alpn_output=""
  local listener_line=""

  bool_true "$VERIFY_PROFILE_TRANSPORTS" || return 0
  log "Проверяю runtime-пути профиля STABLE-IN-443 и Hysteria"

  while (( SECONDS <= deadline )); do
    xhttp_ready=1
    hysteria_ready=1
    if bool_true "$ENABLE_XHTTP"; then
      [[ -S "$XHTTP_SOCKET" ]] || xhttp_ready=0
      ss -H -ltn 'sport = :443' 2>/dev/null | grep -q . || xhttp_ready=0
    fi
    if bool_true "$EXPECT_HYSTERIA"; then
      udp_port_listening "$HYSTERIA_PORT" || hysteria_ready=0
    fi
    (( xhttp_ready == 1 && hysteria_ready == 1 )) && break
    (( SECONDS >= deadline )) && break
    sleep 2
  done

  if bool_true "$ENABLE_XHTTP"; then
    systemctl is-active --quiet nginx.service || die "Nginx для xHTTP не активен."
    nginx -t >/dev/null 2>&1 || die "Nginx xHTTP configuration не проходит nginx -t."
    if [[ ! -S "$XHTTP_SOCKET" ]]; then
      profile_not_ready "Нет $XHTTP_SOCKET: назначьте ноде профиль STABLE-IN-443 с listen=$XHTTP_SOCKET и path=$XHTTP_PATH."
    else
      if id www-data >/dev/null 2>&1 && \
         ! runuser -u www-data -- test -w "$XHTTP_SOCKET"; then
        profile_not_ready "Nginx worker www-data не имеет доступа к xHTTP socket $XHTTP_SOCKET."
      fi
      verify_local_xhttp_h2_edge || \
        profile_not_ready "Локальный Nginx→xHTTP socket self-test не получил ожидаемый HTTP 400 на $XHTTP_PATH."
    fi
    alpn_output="$(timeout 8 openssl s_client -connect 127.0.0.1:443 -servername "$XHTTP_DOMAIN" -alpn h2 </dev/null 2>&1 || true)"
    grep -Fq 'ALPN protocol: h2' <<<"$alpn_output" || die "Локальная TLS-проверка xHTTP не согласовала HTTP/2 ALPN."
  fi

  if bool_true "$EXPECT_HYSTERIA"; then
    [[ -r "$TLS_DIR/fullchain.pem" && -r "$TLS_DIR/privkey.pem" ]] || \
      profile_not_ready "Для Hysteria нет TLS-файлов $TLS_DIR/fullchain.pem и privkey.pem."
    udp_port_listening "$HYSTERIA_PORT" || \
      profile_not_ready "Hysteria не слушает UDP/$HYSTERIA_PORT: проверьте BBR-IN-443 в назначенном профиле."
    listener_line="$(hysteria_listener_line)"
    if [[ "$listener_line" == *users:* ]] && ! hysteria_listener_is_expected "$listener_line"; then
      profile_not_ready "UDP/$HYSTERIA_PORT слушает посторонний процесс вместо RemnaNode/Xray: $listener_line"
    fi
  fi
}

verify_node() {
  local deadline=$((SECONDS + 120))
  local logs=""
  local xray_version=""
  local restarts_before=""
  local started_before=""
  local cap_eff=""
  local running_id=""
  local desired_id=""

  log "Проверяю Node API, NET_ADMIN и встроенный Xray"
  while (( SECONDS < deadline )); do
    if [[ "$(docker inspect --format '{{.State.Running}}' remnanode 2>/dev/null || true)" == "true" ]] && port_listening; then
      break
    fi
    sleep 2
  done

  [[ "$(docker inspect --format '{{.State.Running}}' remnanode 2>/dev/null || true)" == "true" ]] || \
    die "Контейнер remnanode не запущен."
  port_listening || die "Node control-port $NODE_PORT не слушает."

  logs="$(docker logs --tail 300 remnanode 2>&1 || true)"
  if grep -Eqi 'Invalid SECRET_KEY|SECRET_KEY is not set|invalid node payload|FATAL|UnhandledPromiseRejection' <<<"$logs"; then
    die "RemnaNode сообщил об ошибке SECRET_KEY или критическом старте."
  fi
  running_id="$(docker inspect --format '{{.Image}}' remnanode)"
  desired_id="$(docker image inspect --format '{{.Id}}' "$SELECTED_IMAGE")"
  [[ "$running_id" == "$desired_id" ]] || die "Контейнер запущен не из выбранного image $SELECTED_IMAGE."

  cap_eff="$(docker exec remnanode awk '/^CapEff:/ {print $2}' /proc/1/status 2>/dev/null || true)"
  if ! python3 - "$cap_eff" <<'PY'
import sys
try:
    value = int(sys.argv[1], 16)
except Exception:
    raise SystemExit(1)
raise SystemExit(0 if value & (1 << 12) else 1)
PY
  then
    if bool_true "$ALLOW_NO_NET_ADMIN"; then
      warn "CAP_NET_ADMIN не подтверждён: online count и Node Plugins могут не работать."
    else
      die "CAP_NET_ADMIN недоступен. Без него нативный online count Node 2.8.0 неполный."
    fi
  fi

  xray_version="$(docker exec remnanode rw-core version 2>/dev/null | head -n1 || true)"
  [[ "$xray_version" =~ Xray[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+) ]] || die "Не удалось определить встроенный Xray."
  version_ge "${BASH_REMATCH[1]}" "26.6.27" || die "Xray ${BASH_REMATCH[1]} старее 26.6.27."

  verify_native_plugins

  restarts_before="$(docker inspect --format '{{.RestartCount}}' remnanode)"
  started_before="$(docker inspect --format '{{.State.StartedAt}}' remnanode)"
  sleep "$STABILITY_SECONDS"
  [[ "$(docker inspect --format '{{.State.Running}}' remnanode 2>/dev/null || true)" == "true" ]] || \
    die "Контейнер остановился во время stability-window."
  [[ "$(docker inspect --format '{{.RestartCount}}' remnanode)" == "$restarts_before" ]] || \
    die "Контейнер перезапустился во время stability-window."
  [[ "$(docker inspect --format '{{.State.StartedAt}}' remnanode)" == "$started_before" ]] || \
    die "StartedAt изменился во время stability-window."
  [[ "$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' remnanode)" != "unhealthy" ]] || \
    die "Docker healthcheck Node API получил статус unhealthy."

  verify_profile_transports

  log "Node verification OK: $xray_version; restart_count=$restarts_before"
}

write_state() {
  local tmp=""
  tmp="$(mktemp)"
  {
    printf 'SAVED_NODE_VERSION=%q\n' "$NODE_VERSION"
    printf 'SAVED_NODE_IMAGE=%q\n' "$SELECTED_IMAGE"
    printf 'SAVED_NODE_PORT=%q\n' "$NODE_PORT"
    printf 'SAVED_PANEL_IPS=%q\n' "$PANEL_IPS"
    printf 'SAVED_ENABLE_XHTTP=%q\n' "$ENABLE_XHTTP"
    printf 'SAVED_XHTTP_DOMAIN=%q\n' "$XHTTP_DOMAIN"
    printf 'SAVED_XHTTP_PATH=%q\n' "$XHTTP_PATH"
    printf 'SAVED_XHTTP_SOCKET=%q\n' "$XHTTP_SOCKET"
    printf 'SAVED_MANAGE_FIREWALL=%q\n' "$MANAGE_FIREWALL"
    printf 'SAVED_PUBLIC_TCP_PORTS=%q\n' "$PUBLIC_TCP_PORTS"
    printf 'SAVED_PUBLIC_UDP_PORTS=%q\n' "$PUBLIC_UDP_PORTS"
    printf 'SAVED_BLOCK_SMTP_EGRESS=%q\n' "$BLOCK_SMTP_EGRESS"
    printf 'SAVED_BLOCK_SMTP_FORWARD=%q\n' "$BLOCK_SMTP_FORWARD"
    printf 'SAVED_SMTP_EGRESS_PORTS=%q\n' "$SMTP_EGRESS_PORTS"
    printf 'SAVED_ENABLE_BBR=%q\n' "$ENABLE_BBR"
    printf 'SAVED_AUTO_SWAP=%q\n' "$AUTO_SWAP"
    printf 'SAVED_ENABLE_MAINTENANCE=%q\n' "$ENABLE_MAINTENANCE"
    printf 'SAVED_BACKUP_RETENTION=%q\n' "$BACKUP_RETENTION"
    printf 'SAVED_JOURNAL_MAX_USE=%q\n' "$JOURNAL_MAX_USE"
    printf 'SAVED_JOURNAL_RETENTION=%q\n' "$JOURNAL_RETENTION"
    printf 'SAVED_EXPECT_HYSTERIA=%q\n' "$EXPECT_HYSTERIA"
    printf 'SAVED_HYSTERIA_PORT=%q\n' "$HYSTERIA_PORT"
    printf 'SAVED_UPDATED_AT=%q\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >"$tmp"
  install -m 0600 "$tmp" "$STATE_FILE"
  install -m 0600 "$tmp" "$INSTALLER_CONFIG"
  rm -f "$tmp"

  install -d -m 0750 /etc/cake_panel
  local -a panel_items=()
  read -r -a panel_items <<<"$PANEL_IPS"
  printf '%s\n' "${panel_items[@]}" >"$PANEL_IPS_FILE"
  chmod 0640 "$PANEL_IPS_FILE"
}

restore_security_timers_if_legacy() {
  local unit=""
  local unit_state=""
  [[ "$LEGACY_DETECTED" == "1" ]] || return 0
  for unit in apt-daily.service apt-daily-upgrade.service unattended-upgrades.service \
    apt-daily.timer apt-daily-upgrade.timer; do
    systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q . || continue
    systemctl unmask "$unit" >/dev/null 2>&1 || true
  done
  for unit in apt-daily.timer apt-daily-upgrade.timer; do
    systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q . || continue
    systemctl enable --now "$unit" >/dev/null 2>&1 || \
      warn "Не удалось вернуть системный security timer $unit."
  done
  if systemctl list-unit-files unattended-upgrades.service --no-legend 2>/dev/null | grep -q .; then
    unit_state="$(systemctl is-enabled unattended-upgrades.service 2>/dev/null || true)"
    if [[ "$unit_state" == "disabled" ]]; then
      systemctl enable unattended-upgrades.service >/dev/null 2>&1 || \
        warn "Не удалось вернуть unattended-upgrades.service в enabled state."
    fi
  fi
}

record_legacy_reboot_requirement() {
  local current_boot=""
  local marked_boot=""
  current_boot="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
  [[ -n "$current_boot" ]] || return 0

  if [[ "$LEGACY_RUNTIME_TUNING_DETECTED" == "1" ]]; then
    printf '%s\n' "$current_boot" >"$LEGACY_REBOOT_MARKER"
    chmod 0600 "$LEGACY_REBOOT_MARKER"
  elif [[ -r "$LEGACY_REBOOT_MARKER" ]]; then
    marked_boot="$(tr -d '\n' <"$LEGACY_REBOOT_MARKER")"
    [[ "$marked_boot" == "$current_boot" ]] || rm -f "$LEGACY_REBOOT_MARKER"
  fi
}

legacy_reboot_required() {
  local current_boot=""
  local marked_boot=""
  [[ -r "$LEGACY_REBOOT_MARKER" ]] || return 1
  current_boot="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
  marked_boot="$(tr -d '\n' <"$LEGACY_REBOOT_MARKER")"
  [[ -n "$current_boot" && "$current_boot" == "$marked_boot" ]]
}

print_profile_contract() {
  printf '\nПрофиль мастер-панели должен совпадать с runtime-контрактом:\n'
  if bool_true "$ENABLE_XHTTP"; then
    printf '  STABLE-IN-443: VLESS/xHTTP, listen=%s,0666, path=%s\n' "$XHTTP_SOCKET" "$XHTTP_PATH"
    printf '  xHTTP edge:    TCP/443 TLS + HTTP/2 через Nginx; HTTP/3 на Nginx отключён\n'
  fi
  if bool_true "$EXPECT_HYSTERIA"; then
    printf '  BBR-IN-443:    Hysteria 2 на UDP/%s, TLS из %s\n' "$HYSTERIA_PORT" "$TLS_DIR"
    printf '  Hysteria BBR:  finalmask.quicParams.congestion=bbr задаётся именно в JSON профиля\n'
    printf '  Hysteria LTE:  finalmask.quicParams.disablePathMTUDiscovery=true рекомендуется для проблемных мобильных сетей\n'
  fi
  printf '  Node Plugins:    включаются и применяются мастер-панелью (по умолчанию они выключены)\n'
  printf '  Torrent Blocker: нужен sniffing.enabled=true и destOverride в inbound-профиле\n'
}

show_status() {
  local state="missing"
  local image="-"
  local restarts="-"
  local started="-"
  local xray="-"
  local cap="unknown"
  local health="-"
  local cap_eff=""
  local plugin_state="capability not confirmed"
  local firewall="inactive"
  local maintenance="inactive"
  local xhttp_guard="inactive"
  local bbr=""
  bbr="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || printf '-')"

  if command -v docker >/dev/null 2>&1 && docker inspect remnanode >/dev/null 2>&1; then
    state="$(docker inspect --format '{{.State.Status}}' remnanode)"
    image="$(docker inspect --format '{{.Config.Image}}' remnanode)"
    restarts="$(docker inspect --format '{{.RestartCount}}' remnanode)"
    started="$(docker inspect --format '{{.State.StartedAt}}' remnanode)"
    health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' remnanode)"
    xray="$(docker exec remnanode rw-core version 2>/dev/null | head -n1 || true)"
    cap_eff="$(docker exec remnanode awk '/^CapEff:/ {print $2}' /proc/1/status 2>/dev/null || true)"
    if python3 - "$cap_eff" >/dev/null 2>&1 <<'PY'
import sys
try:
    value = int(sys.argv[1], 16)
except Exception:
    raise SystemExit(1)
raise SystemExit(0 if value & (1 << 12) else 1)
PY
    then
      cap="available"
    else
      cap="missing"
    fi
  fi
  if nft list table ip remnanode >/dev/null 2>&1 && nft list table ip6 remnanode6 >/dev/null 2>&1; then
    plugin_state="runtime tables present; policy is panel-managed"
  fi
  nft list table inet remnanode_installer >/dev/null 2>&1 && firewall="active"
  systemctl is-active --quiet remnanode-maintenance.timer 2>/dev/null && maintenance="active"
  systemctl is-active --quiet remnanode-xhttp-socket-guard.timer 2>/dev/null && xhttp_guard="active"

  printf 'Installer:       %s\n' "$INSTALLER_VERSION"
  printf 'Container:       %s\n' "$state"
  printf 'Image:           %s\n' "$image"
  printf 'Restarts:        %s\n' "$restarts"
  printf 'StartedAt:       %s\n' "$started"
  printf 'Health:          %s\n' "$health"
  printf 'Xray:            %s\n' "$xray"
  printf 'CAP_NET_ADMIN:   %s\n' "$cap"
  printf 'Node Plugins:    %s\n' "$plugin_state"
  printf 'BBR/TCP CC:      %s\n' "$bbr"
  printf 'Firewall:        %s\n' "$firewall"
  printf 'Maintenance:     %s\n' "$maintenance"
  printf 'xHTTP recovery:  %s\n' "$xhttp_guard"
  if legacy_reboot_required; then
    printf 'Legacy reboot:   required (one planned reboot)\n'
  else
    printf 'Legacy reboot:   not required\n'
  fi
  if command -v ss >/dev/null 2>&1; then
    printf 'Control port:    %s\n' "$(ss -H -ltn "sport = :${NODE_PORT:-2222}" 2>/dev/null | grep -q . && echo listening || echo not-listening)"
  fi
  if [[ -n "${XHTTP_SOCKET:-}" ]]; then
    printf 'xHTTP socket:    %s\n' "$([[ -S "$XHTTP_SOCKET" ]] && echo present || echo absent)"
  fi
  if command -v ss >/dev/null 2>&1; then
    printf 'Hysteria UDP:    %s\n' "$(udp_port_listening "${HYSTERIA_PORT:-443}" && echo listening || echo not-listening)"
  fi
  if [[ -r "$TLS_DIR/fullchain.pem" ]]; then
    printf 'TLS expires:     %s\n' "$(openssl x509 -in "$TLS_DIR/fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2-)"
  fi
}

select_rollback_backup() {
  local selected="$BACKUP_REQUEST"
  local candidate=""
  local backup_root_real=""
  if [[ -z "$selected" ]]; then
    while IFS= read -r candidate; do
      [[ -r "$candidate/manifest.env" ]] || continue
      grep -qx 'BACKUP_FORMAT=2' "$candidate/manifest.env" || continue
      selected="$candidate"
      break
    done < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d \
      -regextype posix-extended -regex '.*/[0-9]{8}T[0-9]{6}Z' -print 2>/dev/null | sort -r)
  fi
  [[ -n "$selected" ]] || die "Не найден полный backup format 2 в $BACKUP_ROOT."
  backup_root_real="$(realpath -e "$BACKUP_ROOT" 2>/dev/null || true)"
  selected="$(realpath -e "$selected" 2>/dev/null || true)"
  [[ -n "$backup_root_real" && -n "$selected" && "$selected" == "$backup_root_real"/* ]] || \
    die "Backup должен находиться в $BACKUP_ROOT."
  [[ "$(basename "$selected")" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || die "Некорректное имя backup: $selected"
  [[ -r "$selected/manifest.env" ]] || die "Не найден manifest backup: $selected"
  grep -qx 'BACKUP_FORMAT=2' "$selected/manifest.env" || die "Backup не завершён или имеет неподдерживаемый format."
  printf '%s' "$selected"
}

run_install() {
  collect_inputs
  if command -v python3 >/dev/null 2>&1 && command -v openssl >/dev/null 2>&1; then
    validate_panel_ips_strict
    validate_secret_payload
  elif bool_true "$DRY_RUN"; then
    warn "Python 3/OpenSSL отсутствует: dry-run выполнил базовую проверку; строгая JSON/IP/PKI-проверка будет после установки зависимостей."
  fi
  preflight_host
  print_plan

  if bool_true "$DRY_RUN"; then
    log "Dry-run завершён: изменений не внесено."
    return 0
  fi

  create_backup
  stop_legacy_units
  install_base_packages
  ensure_docker
  validate_panel_ips_strict
  validate_secret_payload
  prepare_directories
  cleanup_legacy_files
  configure_small_swap
  configure_minimal_sysctl
  write_logrotate
  configure_log_hygiene_and_maintenance
  write_firewall
  configure_xhttp_module
  select_and_pull_image
  render_node_files
  install_rendered_files
  configure_xhttp_socket_guard
  activate_node
  start_xhttp_socket_guard
  verify_node
  write_state
  restore_security_timers_if_legacy
  record_legacy_reboot_requirement

  MUTATION_STARTED=0
  log "Установка завершена успешно"
  show_status
  print_profile_contract
  if legacy_reboot_required; then
    warn "Старые MTU/RPS/offload/qdisc/DNS/SSH runtime-настройки могли остаться в памяти ядра. Выполните один плановый reboot после проверки доступности ноды."
  fi
  printf '\nBackup для ручного rollback: %s\n' "$BACKUP_DIR"
  printf 'Rollback: sudo bash setup-remnanode.sh rollback --backup %q\n' "$BACKUP_DIR"
}

main() {
  parse_args "$@"
  require_root
  acquire_lock

  case "$MODE" in
    status)
      load_saved_state
      show_status
      ;;
    rollback)
      rollback_from_backup "$(select_rollback_backup)"
      show_status
      ;;
    install|update|repair)
      run_install
      ;;
    *)
      die "Неизвестный mode: $MODE"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
  main "$@"
fi
