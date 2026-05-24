#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="node-installer bootstrap"
REPO_SLUG_DEFAULT="MALYSHVIP/node-installer"
REPO_REF_DEFAULT="main"

REPO_SLUG="${NODE_INSTALLER_REPO:-${REPO_SLUG_DEFAULT}}"
REPO_REF="${NODE_INSTALLER_REF:-${REPO_REF_DEFAULT}}"
ARCHIVE_URL="${NODE_INSTALLER_ARCHIVE_URL:-https://codeload.github.com/${REPO_SLUG}/tar.gz/refs/heads/${REPO_REF}}"

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
  1. Скачивает весь репозиторий node-installer архивом
  2. Распаковывает его во временную папку
  3. Запускает setup-remnanode.sh уже локально, вместе с cake_soft_panel

Полезные переменные окружения:
  NODE_INSTALLER_REPO         По умолчанию MALYSHVIP/node-installer
  NODE_INSTALLER_REF          По умолчанию main
  NODE_INSTALLER_ARCHIVE_URL  Полный URL архива, если нужен кастомный источник
  PANEL_IP                    IPv4 мастер-панели, если не хотите вводить руками
  SECRET_KEY                  Не используется этим bootstrap напрямую
  NODE_IP                     Можно заранее передать IPv4 ноды

Любые аргументы после install.sh будут переданы в setup-remnanode.sh.
EOF
}

resolve_local_repo_root() {
  local script_path=""
  local script_dir=""

  script_path="${BASH_SOURCE[0]:-}"
  [[ -n "${script_path}" && -f "${script_path}" ]] || return 1

  script_dir="$(cd "$(dirname "${script_path}")" && pwd)"
  if [[ -f "${script_dir}/setup-remnanode.sh" && -d "${script_dir}/cake_soft_panel" ]]; then
    printf '%s\n' "${script_dir}"
    return 0
  fi

  return 1
}

run_local_repo() {
  local repo_root="$1"
  shift

  log "Использую локальную папку репозитория: ${repo_root}"
  exec bash "${repo_root}/setup-remnanode.sh" "$@"
}

run_downloaded_repo() {
  local tmpdir archive_file repo_root
  tmpdir="$(mktemp -d)"
  archive_file="${tmpdir}/node-installer.tar.gz"
  trap 'rm -rf "${tmpdir}"' EXIT

  log "Скачиваю репозиторий ${REPO_SLUG} (${REPO_REF})"
  curl -fsSL "${ARCHIVE_URL}" -o "${archive_file}" || die "Не удалось скачать архив репозитория"

  log "Распаковываю архив"
  tar -xzf "${archive_file}" -C "${tmpdir}" || die "Не удалось распаковать архив репозитория"

  repo_root="$(find "${tmpdir}" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  [[ -n "${repo_root}" ]] || die "Не удалось найти распакованную папку репозитория"
  [[ -f "${repo_root}/setup-remnanode.sh" ]] || die "В архиве нет setup-remnanode.sh"
  [[ -d "${repo_root}/cake_soft_panel" ]] || die "В архиве нет папки cake_soft_panel"

  exec bash "${repo_root}/setup-remnanode.sh" "$@"
}

main() {
  local local_repo_root=""

  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi

  if local_repo_root="$(resolve_local_repo_root)"; then
    run_local_repo "${local_repo_root}" "$@"
  fi

  run_downloaded_repo "$@"
}

main "$@"
