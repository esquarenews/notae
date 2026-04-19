#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "" ]]; then
  echo "Usage: NOTAE_RESTORE_CONFIRM=restore $0 /path/to/backup_dir"
  exit 1
fi

if [[ "${NOTAE_RESTORE_CONFIRM:-}" != "restore" ]]; then
  echo "Refusing to run without NOTAE_RESTORE_CONFIRM=restore"
  exit 1
fi

BACKUP_DIR="$1"
APP_ROOT="${APP_ROOT:-/home/esquarenews/apps/notae}"
ENV_FILE="${ENV_FILE:-/etc/notae/notae.env}"
STORAGE_ROOT="${STORAGE_ROOT:-${APP_ROOT}/storage}"
SKIP_SERVICE_CONTROL="${SKIP_SERVICE_CONTROL:-0}"

DB_USER="${DB_USER:-notae}"
DB_HOST="${DB_HOST:-${PGHOST:-}}"
DB_PORT="${DB_PORT:-${PGPORT:-}}"

PRIMARY_DB="${PRIMARY_DB:-notae_production}"
CACHE_DB="${CACHE_DB:-notae_production_cache}"
QUEUE_DB="${QUEUE_DB:-notae_production_queue}"
CABLE_DB="${CABLE_DB:-notae_production_cable}"

SYSTEMD_SERVICES=(
  notae
  notae-sidekiq
  notae-meeting-bot-worker
)

if [[ ! -d "${BACKUP_DIR}" ]]; then
  echo "Backup directory does not exist: ${BACKUP_DIR}"
  exit 1
fi

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

if [[ -z "${NOTAE_DATABASE_PASSWORD:-}" ]]; then
  echo "NOTAE_DATABASE_PASSWORD is not set. Check ${ENV_FILE} or export it before running."
  exit 1
fi

if [[ -f "${BACKUP_DIR}/SHA256SUMS" ]]; then
  echo "Verifying backup checksums"
  (
    cd "${BACKUP_DIR}"
    shasum -a 256 -c SHA256SUMS
  )
fi

stop_services() {
  [[ "${SKIP_SERVICE_CONTROL}" == "1" ]] && return 0
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemctl not available and SKIP_SERVICE_CONTROL is not set."
    exit 1
  fi

  echo "Stopping application services"
  sudo systemctl stop "${SYSTEMD_SERVICES[@]}"
}

start_services() {
  [[ "${SKIP_SERVICE_CONTROL}" == "1" ]] && return 0

  echo "Starting application services"
  sudo systemctl start "${SYSTEMD_SERVICES[@]}"
  sudo systemctl start notae-epistularium-sync.timer || true
}

pg_admin_command() {
  local base_command="$1"
  shift
  local -a command

  command=("${base_command}" -U "${DB_USER}")
  [[ -n "${DB_HOST}" ]] && command+=(-h "${DB_HOST}")
  [[ -n "${DB_PORT}" ]] && command+=(-p "${DB_PORT}")
  command+=("$@")

  PGPASSWORD="${NOTAE_DATABASE_PASSWORD}" "${command[@]}"
}

restore_database() {
  local database_name="$1"
  local dump_name="$2"
  local dump_path="${BACKUP_DIR}/${dump_name}.dump"

  if [[ ! -f "${dump_path}" ]]; then
    echo "Missing dump file: ${dump_path}"
    exit 1
  fi

  echo "Restoring ${database_name} from ${dump_name}.dump"
  pg_admin_command dropdb --if-exists "${database_name}"
  pg_admin_command createdb "${database_name}"

  local -a restore_command
  restore_command=(pg_restore --no-owner --no-privileges --clean --if-exists -U "${DB_USER}")
  [[ -n "${DB_HOST}" ]] && restore_command+=(-h "${DB_HOST}")
  [[ -n "${DB_PORT}" ]] && restore_command+=(-p "${DB_PORT}")
  restore_command+=(-d "${database_name}" "${dump_path}")

  PGPASSWORD="${NOTAE_DATABASE_PASSWORD}" "${restore_command[@]}"
}

restore_storage() {
  local storage_archive="${BACKUP_DIR}/storage.tar.gz"
  local restore_stamp
  restore_stamp="$(date +%Y%m%d_%H%M%S)"

  if [[ ! -f "${storage_archive}" ]]; then
    echo "Storage archive not found: ${storage_archive}. Skipping storage restore."
    return 0
  fi

  if [[ -d "${STORAGE_ROOT}" ]]; then
    local backup_path="${STORAGE_ROOT}.pre_restore.${restore_stamp}"
    echo "Moving existing storage to ${backup_path}"
    mv "${STORAGE_ROOT}" "${backup_path}"
  fi

  mkdir -p "$(dirname "${STORAGE_ROOT}")"
  echo "Restoring storage archive"
  tar -C "$(dirname "${STORAGE_ROOT}")" -xzf "${storage_archive}"
}

stop_services

restore_database "${PRIMARY_DB}" "primary"
restore_database "${CACHE_DB}" "cache"
restore_database "${QUEUE_DB}" "queue"
restore_database "${CABLE_DB}" "cable"
restore_storage

start_services

echo
echo "Restore complete from ${BACKUP_DIR}"
echo "Next checks:"
echo "  sudo systemctl status notae notae-sidekiq notae-meeting-bot-worker --no-pager"
echo "  sudo systemctl status notae-epistularium-sync.timer --no-pager"
echo "  redis-cli ping"
