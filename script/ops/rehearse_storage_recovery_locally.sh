#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/notae-storage-recovery-drill.XXXXXX")"

cleanup() {
  if [[ "${NOTAE_STORAGE_DRILL_KEEP_TMP:-0}" == "1" ]]; then
    echo "Keeping drill workspace: ${TMP_ROOT}"
  else
    rm -rf "${TMP_ROOT}"
  fi
}
trap cleanup EXIT

BACKUP_DIR="${TMP_ROOT}/backup"
SOURCE_STORAGE="${TMP_ROOT}/storage"
RESTORED_STORAGE="${TMP_ROOT}/restored_storage"
EXPECTED_FILE="active_storage/blobs/demo/blob.txt"

mkdir -p "${BACKUP_DIR}" "$(dirname "${SOURCE_STORAGE}/${EXPECTED_FILE}")" "$(dirname "${SOURCE_STORAGE}/covers/demo-cover.txt")"
printf 'notae storage recovery drill\n' > "${SOURCE_STORAGE}/${EXPECTED_FILE}"
printf 'cover image placeholder\n' > "${SOURCE_STORAGE}/covers/demo-cover.txt"

tar -C "${TMP_ROOT}" -czf "${BACKUP_DIR}/storage.tar.gz" "$(basename "${SOURCE_STORAGE}")"
cp -R "${SOURCE_STORAGE}" "${RESTORED_STORAGE}"

"${REPO_ROOT}/script/ops/verify_notae_storage_recovery.sh" \
  "${BACKUP_DIR}" \
  "${RESTORED_STORAGE}" \
  "${EXPECTED_FILE}"

echo
echo "Local storage recovery rehearsal passed."
