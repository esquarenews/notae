#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "" || "${2:-}" == "" ]]; then
  echo "Usage: $0 /path/to/backup_dir /path/to/restored/storage [relative/path/to/expected/file]"
  exit 1
fi

BACKUP_DIR="$1"
RESTORED_STORAGE_ROOT="$2"
EXPECTED_RELATIVE_PATH="${3:-}"
STORAGE_ARCHIVE="${BACKUP_DIR}/storage.tar.gz"

if [[ ! -d "${BACKUP_DIR}" ]]; then
  echo "Backup directory does not exist: ${BACKUP_DIR}"
  exit 1
fi

if [[ ! -f "${STORAGE_ARCHIVE}" ]]; then
  echo "Storage archive not found: ${STORAGE_ARCHIVE}"
  exit 1
fi

if [[ ! -d "${RESTORED_STORAGE_ROOT}" ]]; then
  echo "Restored storage directory does not exist: ${RESTORED_STORAGE_ROOT}"
  exit 1
fi

normalize_expected_path() {
  local value="$1"
  value="${value#storage/}"
  value="${value#/}"
  printf '%s\n' "${value}"
}

normalize_archive_path() {
  local value="$1"
  value="${value#*/}"
  printf '%s\n' "${value}"
}

ARCHIVE_MANIFEST="$(mktemp)"
RESTORED_MANIFEST="$(mktemp)"
MISSING_MANIFEST="$(mktemp)"
EXTRA_MANIFEST="$(mktemp)"
trap 'rm -f "${ARCHIVE_MANIFEST}" "${RESTORED_MANIFEST}" "${MISSING_MANIFEST}" "${EXTRA_MANIFEST}"' EXIT

tar -tzf "${STORAGE_ARCHIVE}" \
  | awk '!/\/$/ { print }' \
  | while IFS= read -r path; do
      normalize_archive_path "${path}"
    done \
  | LC_ALL=C sort -u > "${ARCHIVE_MANIFEST}"

find "${RESTORED_STORAGE_ROOT}" -type f -print \
  | while IFS= read -r path; do
      path="${path#${RESTORED_STORAGE_ROOT}/}"
      printf '%s\n' "${path}"
    done \
  | LC_ALL=C sort -u > "${RESTORED_MANIFEST}"

comm -23 "${ARCHIVE_MANIFEST}" "${RESTORED_MANIFEST}" > "${MISSING_MANIFEST}" || true
comm -13 "${ARCHIVE_MANIFEST}" "${RESTORED_MANIFEST}" > "${EXTRA_MANIFEST}" || true

ARCHIVE_FILE_COUNT="$(wc -l < "${ARCHIVE_MANIFEST}" | tr -d ' ')"
RESTORED_FILE_COUNT="$(wc -l < "${RESTORED_MANIFEST}" | tr -d ' ')"
MISSING_FILE_COUNT="$(wc -l < "${MISSING_MANIFEST}" | tr -d ' ')"
EXTRA_FILE_COUNT="$(wc -l < "${EXTRA_MANIFEST}" | tr -d ' ')"

echo "Archive file count: ${ARCHIVE_FILE_COUNT}"
echo "Restored file count: ${RESTORED_FILE_COUNT}"
echo "Missing restored files: ${MISSING_FILE_COUNT}"
echo "Extra restored files: ${EXTRA_FILE_COUNT}"

if [[ -n "${EXPECTED_RELATIVE_PATH}" ]]; then
  NORMALIZED_EXPECTED_PATH="$(normalize_expected_path "${EXPECTED_RELATIVE_PATH}")"

  if ! grep -Fxq "${NORMALIZED_EXPECTED_PATH}" "${ARCHIVE_MANIFEST}"; then
    echo "Expected file is not present in the backup archive: ${NORMALIZED_EXPECTED_PATH}"
    exit 1
  fi

  if [[ ! -f "${RESTORED_STORAGE_ROOT}/${NORMALIZED_EXPECTED_PATH}" ]]; then
    echo "Expected file is missing from restored storage: ${NORMALIZED_EXPECTED_PATH}"
    exit 1
  fi

  echo "Verified expected file: ${NORMALIZED_EXPECTED_PATH}"
fi

if [[ "${MISSING_FILE_COUNT}" != "0" ]]; then
  echo
  echo "Missing files from restored storage:"
  sed -n '1,20p' "${MISSING_MANIFEST}"
  exit 1
fi

if [[ "${EXTRA_FILE_COUNT}" != "0" ]]; then
  echo
  echo "Extra files present in restored storage (showing up to 20):"
  sed -n '1,20p' "${EXTRA_MANIFEST}"
fi

echo
echo "Storage recovery verification passed."
