#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

INSTALLER_REPO="${INSTALLER_REPO:-MALYSHVIP/node-installer}"
INSTALLER_REF="${INSTALLER_REF:-main}"
INSTALLER_FILE="${INSTALLER_FILE:-setup-remnanode.sh}"
TMP_FILE=""
LOCAL_INSTALLER_USED=0

log() {
  printf '[install] %s\n' "$*"
}

die() {
  printf '[install] %s\n' "$*" >&2
  exit 1
}

need_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    die "run as root"
  fi
}

cleanup() {
  if [[ -n "$TMP_FILE" && -f "$TMP_FILE" ]]; then
    rm -f "$TMP_FILE"
  fi
}

run_installer_script() {
  local installer="$1"
  local rc=0
  shift

  # /dev/tty can exist yet be unopenable in cron, cloud-init or a detached
  # shell. Probe the open itself and otherwise preserve inherited stdin.
  if { exec 7</dev/tty; } 2>/dev/null; then
    bash "$installer" "$@" <&7 7<&- || rc=$?
    exec 7<&-
  else
    bash "$installer" "$@" || rc=$?
  fi
  return "$rc"
}

run_local_installer() {
  local rc=0
  local script_dir=""
  local local_installer=""
  local source_path="${BASH_SOURCE[0]:-}"

  # When invoked as `curl ... | bash`, Bash has no source filename. In that
  # mode skip local discovery and download the pinned installer as intended.
  [[ -n "$source_path" ]] || return 0

  script_dir="$(cd "$(dirname "$source_path")" && pwd)"
  local_installer="${script_dir}/${INSTALLER_FILE}"

  if [[ -f "$local_installer" && "$source_path" != "$local_installer" ]]; then
    LOCAL_INSTALLER_USED=1
    log "source=local installer=${local_installer}"
    run_installer_script "$local_installer" "$@" || rc=$?
    return "$rc"
  fi

  return 0
}

download_installer() {
  local url=""

  url="https://raw.githubusercontent.com/${INSTALLER_REPO}/${INSTALLER_REF}/${INSTALLER_FILE}"
  log "source=github repo=${INSTALLER_REPO} ref=${INSTALLER_REF} file=${INSTALLER_FILE}"

  if command -v curl >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -fsSL \
      --connect-timeout 15 --retry 4 --retry-delay 2 \
      "$url" -o "$TMP_FILE"
    return 0
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -qO "$TMP_FILE" "$url"
    return 0
  fi

  die "curl or wget is required"
}

main() {
  local local_rc=0
  need_root
  trap cleanup EXIT

  run_local_installer "$@" || local_rc=$?
  if [[ "$LOCAL_INSTALLER_USED" == "1" ]]; then
    exit "$local_rc"
  fi

  TMP_FILE="$(mktemp /tmp/node-installer.XXXXXX.sh)"
  download_installer
  [[ -s "$TMP_FILE" ]] || die "downloaded installer is empty"
  bash -n "$TMP_FILE" || die "downloaded installer has invalid shell syntax"
  chmod 700 "$TMP_FILE"
  run_installer_script "$TMP_FILE" "$@"
}

main "$@"
