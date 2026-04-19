#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="${APP_ROOT:-/home/esquarenews/apps/notae}"
ENV_FILE="${ENV_FILE:-/etc/notae/notae.env}"
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/notae}"
TIMESTAMP="${TIMESTAMP:-$(date +%Y%m%d_%H%M%S)}"
ARCHIVE_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
STORAGE_ROOT="${STORAGE_ROOT:-${APP_ROOT}/storage}"

DB_USER="${DB_USER:-notae}"
DB_HOST="${DB_HOST:-${PGHOST:-}}"
DB_PORT="${DB_PORT:-${PGPORT:-}}"

PRIMARY_DB="${PRIMARY_DB:-notae_production}"
CACHE_DB="${CACHE_DB:-notae_production_cache}"
QUEUE_DB="${QUEUE_DB:-notae_production_queue}"
CABLE_DB="${CABLE_DB:-notae_production_cable}"

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

mkdir -p "${ARCHIVE_DIR}"

pg_dump_database() {
  local database_name="$1"
  local output_name="$2"
  local -a command

  command=(pg_dump --format=custom --no-owner --no-privileges -U "${DB_USER}")
  [[ -n "${DB_HOST}" ]] && command+=(-h "${DB_HOST}")
  [[ -n "${DB_PORT}" ]] && command+=(-p "${DB_PORT}")
  command+=(-d "${database_name}" -f "${ARCHIVE_DIR}/${output_name}.dump")

  echo "Dumping ${database_name} -> ${output_name}.dump"
  PGPASSWORD="${NOTAE_DATABASE_PASSWORD}" "${command[@]}"
}

pg_dump_database "${PRIMARY_DB}" "primary"
pg_dump_database "${CACHE_DB}" "cache"
pg_dump_database "${QUEUE_DB}" "queue"
pg_dump_database "${CABLE_DB}" "cable"

if [[ -d "${STORAGE_ROOT}" ]]; then
  echo "Archiving storage from ${STORAGE_ROOT}"
  tar -C "$(dirname "${STORAGE_ROOT}")" -czf "${ARCHIVE_DIR}/storage.tar.gz" "$(basename "${STORAGE_ROOT}")"
else
  echo "Storage path ${STORAGE_ROOT} does not exist. Skipping storage archive."
fi

{
  echo "BACKUP_CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "APP_ROOT=${APP_ROOT}"
  echo "STORAGE_ROOT=${STORAGE_ROOT}"
  echo "PRIMARY_DB=${PRIMARY_DB}"
  echo "CACHE_DB=${CACHE_DB}"
  echo "QUEUE_DB=${QUEUE_DB}"
  echo "CABLE_DB=${CABLE_DB}"
  if command -v git >/dev/null 2>&1; then
    echo "GIT_REVISION=$(git -C "${APP_ROOT}" rev-parse HEAD 2>/dev/null || true)"
  fi
} > "${ARCHIVE_DIR}/metadata.env"

(
  cd "${ARCHIVE_DIR}"
  shasum -a 256 ./* > SHA256SUMS
)

echo
echo "Backup complete: ${ARCHIVE_DIR}"
echo "Artifacts:"
ls -1 "${ARCHIVE_DIR}"
