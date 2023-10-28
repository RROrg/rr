#!/usr/bin/env bash

[ -z "${WORK_PATH}" -o ! -d "${WORK_PATH}/include" ] && WORK_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. ${WORK_PATH}/include/functions.sh

set -o pipefail # Get exit code from process piped

# Sanity check
[ -f "${ORI_ZIMAGE_FILE}" ] || (die "${ORI_ZIMAGE_FILE} not found!" | tee -a "${LOG_FILE}")

echo -n "Patching zImage"

rm -f "${MOD_ZIMAGE_FILE}"
echo -n "."
# Extract vmlinux
${WORK_PATH}/bzImage-to-vmlinux.sh "${ORI_ZIMAGE_FILE}" "${TMP_PATH}/vmlinux" >"${LOG_FILE}" 2>&1 || dieLog
echo -n "."
# Patch boot params and ramdisk check
${WORK_PATH}/kpatch "${TMP_PATH}/vmlinux" "${TMP_PATH}/vmlinux-mod" >"${LOG_FILE}" 2>&1 || dieLog
echo -n "."
# rebuild zImage
${WORK_PATH}/vmlinux-to-bzImage.sh "${TMP_PATH}/vmlinux-mod" "${MOD_ZIMAGE_FILE}" >"${LOG_FILE}" 2>&1 || dieLog
echo -n "."
# Update HASH of new DSM zImage
HASH="$(sha256sum ${ORI_ZIMAGE_FILE} | awk '{print$1}')"
writeConfigKey "zimage-hash" "${HASH}" "${USER_CONFIG_FILE}"
echo
