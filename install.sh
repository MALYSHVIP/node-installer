#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

BOOTSTRAP_VERSION="1.2.0"
INSTALLER_REPO="${INSTALLER_REPO:-MALYSHVIP/node-installer}"
INSTALLER_REF="${INSTALLER_REF:-main}"
export INSTALLER_REPO INSTALLER_REF
INSTALLER_FILE="${INSTALLER_FILE:-setup-remnanode.sh}"
MIN_MAIN_INSTALLER_VERSION="4.1.0"
DOWNLOAD_ATTEMPTS=3
TMP_FILE=""
LOCAL_INSTALLER_USED=0
DOWNLOADED_VERSION=""
DOWNLOADED_SHA256=""

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

current_bash() {
  local candidate="${BASH:-}"
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    printf '%s' "$candidate"
  else
    printf '/bin/bash'
  fi
}

run_installer_script() {
  local installer="$1"
  local bash_bin=""
  shift
  bash_bin="$(current_bash)"

  # Replace the bootstrap, do not spawn a grandchild of sudo. With sudo-rs
  # use_pty and piped stdin, a grandchild reading /dev/tty can stop on SIGTTIN
  # without sudo receiving its status. Only the directly monitored child can
  # reliably trigger sudo's foreground handover and be resumed.
  # The installer owns cleanup of this one bootstrap-created temporary file
  # after exec. Local source files must never be marked for deletion.
  unset NODE_INSTALLER_BOOTSTRAP_TMP_FILE
  if [[ -n "$TMP_FILE" && "$installer" == "$TMP_FILE" ]]; then
    export NODE_INSTALLER_BOOTSTRAP_TMP_FILE="$TMP_FILE"
  fi

  # /dev/tty may exist but be unopenable in a detached/non-interactive shell.
  if { exec 7</dev/tty; } 2>/dev/null; then
    exec "$bash_bin" "$installer" "$@" <&7 7<&-
  else
    exec "$bash_bin" "$installer" "$@"
  fi
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

version_ge() {
  local have="$1"
  local need="$2"
  local have_major=0 have_minor=0 have_patch=0
  local need_major=0 need_minor=0 need_patch=0

  [[ "$have" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  [[ "$need" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  IFS=. read -r have_major have_minor have_patch <<<"$have"
  IFS=. read -r need_major need_minor need_patch <<<"$need"

  (( have_major > need_major )) && return 0
  (( have_major < need_major )) && return 1
  (( have_minor > need_minor )) && return 0
  (( have_minor < need_minor )) && return 1
  (( have_patch >= need_patch ))
}

expected_main_installer() {
  [[ "$INSTALLER_REPO" == "MALYSHVIP/node-installer" && \
     "$INSTALLER_REF" == "main" && \
     "$INSTALLER_FILE" == "setup-remnanode.sh" ]]
}

installer_version() {
  sed -n 's/^INSTALLER_VERSION="\([^"]*\)"$/\1/p' "$TMP_FILE" | head -n1
}

installer_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$TMP_FILE" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$TMP_FILE" | awk '{print $1}'
  fi
}

download_url() {
  local url="$1"

  if command -v curl >/dev/null 2>&1; then
    curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL \
      --connect-timeout 15 --max-time 120 --retry 2 --retry-delay 2 --retry-max-time 240 \
      -H 'Cache-Control: no-cache, no-store' -H 'Pragma: no-cache' \
      "$url" -o "$TMP_FILE"
    return $?
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -q --https-only --timeout=30 --tries=3 --no-cache \
      --header='Cache-Control: no-cache, no-store' --header='Pragma: no-cache' \
      -O "$TMP_FILE" "$url"
    return $?
  fi

  die "curl or wget is required"
}

download_installer() {
  local base_url=""
  local url=""
  local nonce=""
  local attempt=1

  base_url="https://raw.githubusercontent.com/${INSTALLER_REPO}/${INSTALLER_REF}/${INSTALLER_FILE}"
  log "source=github repo=${INSTALLER_REPO} ref=${INSTALLER_REF} file=${INSTALLER_FILE}"

  while (( attempt <= DOWNLOAD_ATTEMPTS )); do
    nonce="$(date -u +%s 2>/dev/null || date +%s)-$$-${attempt}"
    url="${base_url}?bootstrap=${nonce}"
    : >"$TMP_FILE"
    if download_url "$url"; then
      if [[ "$(head -n1 "$TMP_FILE")" != '#!/usr/bin/env bash' ]] || \
         grep -Eq '^[[:space:]]*```' "$TMP_FILE"; then
        log "downloaded file contains text/Markdown instead of a clean Bash script; retry=${attempt}/${DOWNLOAD_ATTEMPTS}"
        ((attempt++))
        continue
      fi
      DOWNLOADED_VERSION="$(installer_version)"
      if expected_main_installer && \
         ! version_ge "$DOWNLOADED_VERSION" "$MIN_MAIN_INSTALLER_VERSION"; then
        log "stale installer version=${DOWNLOADED_VERSION:-unknown}; expected >=${MIN_MAIN_INSTALLER_VERSION}; retry=${attempt}/${DOWNLOAD_ATTEMPTS}"
        ((attempt++))
        continue
      fi
      DOWNLOADED_SHA256="$(installer_sha256)"
      log "downloaded version=${DOWNLOADED_VERSION:-unknown} sha256=${DOWNLOADED_SHA256:-unavailable} bytes=$(wc -c <"$TMP_FILE" | tr -d ' ')"
      return 0
    fi
    log "download failed; retry=${attempt}/${DOWNLOAD_ATTEMPTS}"
    ((attempt++))
  done

  die "failed to download a current installer after ${DOWNLOAD_ATTEMPTS} attempts"
}

main() {
  local local_rc=0
  local bash_bin=""
  need_root
  trap cleanup EXIT
  log "bootstrap version=${BOOTSTRAP_VERSION}"

  run_local_installer "$@" || local_rc=$?
  if [[ "$LOCAL_INSTALLER_USED" == "1" ]]; then
    exit "$local_rc"
  fi

  TMP_FILE="$(mktemp /tmp/node-installer.sh.XXXXXX)"
  download_installer
  [[ -s "$TMP_FILE" ]] || die "downloaded installer is empty"
  bash_bin="$(current_bash)"
  "$bash_bin" -n "$TMP_FILE" || die "downloaded installer has invalid shell syntax"
  chmod 700 "$TMP_FILE"
  run_installer_script "$TMP_FILE" "$@"
}

if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
