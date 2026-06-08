#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

INSTALLER_REPO="${INSTALLER_REPO:-MALYSHVIP/node-installer}"
INSTALLER_REF="${INSTALLER_REF:-main}"
INSTALLER_FILE="${INSTALLER_FILE:-setup-remnanode.sh}"
TMP_FILE=""

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

run_local_installer() {
  local script_dir=""
  local local_installer=""

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local_installer="${script_dir}/${INSTALLER_FILE}"

  if [[ -f "$local_installer" && "${BASH_SOURCE[0]}" != "$local_installer" ]]; then
    log "source=local installer=${local_installer}"
    bash "$local_installer" "$@"
    return 0
  fi

  return 1
}

download_installer() {
  local url=""

  url="https://raw.githubusercontent.com/${INSTALLER_REPO}/${INSTALLER_REF}/${INSTALLER_FILE}"
  log "source=github repo=${INSTALLER_REPO} ref=${INSTALLER_REF} file=${INSTALLER_FILE}"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$TMP_FILE"
    return 0
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -qO "$TMP_FILE" "$url"
    return 0
  fi

  die "curl or wget is required"
}

main() {
  need_root
  trap cleanup EXIT

  if run_local_installer "$@"; then
    exit 0
  fi

  TMP_FILE="$(mktemp /tmp/node-installer.XXXXXX.sh)"
  download_installer
  chmod 700 "$TMP_FILE"
  bash "$TMP_FILE" "$@"
}

main "$@"
