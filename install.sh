#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="node-installer bootstrap"
RAW_BASE_URL_DEFAULT="https://raw.githubusercontent.com/MALYSHVIP/node-installer/main"
RAW_BASE_URL="${NODE_INSTALLER_RAW_BASE_URL:-${RAW_BASE_URL_DEFAULT}}"

log() {
  printf '[%s] %s\n' "${APP_NAME}" "$1"
}

die() {
  printf '[%s] %s\n' "${APP_NAME}" "$1" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Использование:
  curl -fsSL https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh | sudo bash

Что делает bootstrap:
  1. Берет setup-remnanode.sh
  2. Запускает его локально
  3. Передает в него все ваши аргументы

Полезные переменные окружения:
  NODE_INSTALLER_RAW_BASE_URL  Базовый raw URL, по умолчанию MALYSHVIP/node-installer/main
  PANEL_IP                     IPv4 мастер-панели, если не хотите вводить руками
  NODE_IP                      Можно заранее передать IPv4 ноды
  SECRET_KEY                   Можно заранее передать секрет ноды и пропустить ручной prompt

Любые аргументы после install.sh будут переданы в setup-remnanode.sh.
EOF
}

resolve_local_setup_script() {
  local script_path=""
  local script_dir=""
  local candidate=""

  script_path="${BASH_SOURCE[0]:-}"
  [[ -n "${script_path}" && -f "${script_path}" ]] || return 1

  script_dir="$(cd "$(dirname "${script_path}")" && pwd)"
  candidate="${script_dir}/setup-remnanode.sh"
  if [[ -f "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  return 1
}

run_local_setup() {
  local setup_script="$1"
  shift

  log "Использую локальный setup-remnanode.sh: ${setup_script}"
  exec bash "${setup_script}" "$@"
}

run_downloaded_setup() {
  local tmpdir setup_script_url downloaded_script
  tmpdir="$(mktemp -d)"
  downloaded_script="${tmpdir}/setup-remnanode.sh"
  setup_script_url="${RAW_BASE_URL}/setup-remnanode.sh"
  trap 'rm -rf "${tmpdir}"' EXIT

  log "Скачиваю setup-remnanode.sh из ${setup_script_url}"
  curl -fsSL "${setup_script_url}" -o "${downloaded_script}" || die "Не удалось скачать setup-remnanode.sh"

  exec bash "${downloaded_script}" "$@"
}

main() {
  local local_setup=""

  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi

  if local_setup="$(resolve_local_setup_script)"; then
    run_local_setup "${local_setup}" "$@"
  fi

  run_downloaded_setup "$@"
}

main "$@"
