#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

[ -z "${WORK_PATH}" ] || [ ! -d "${WORK_PATH}/include" ] && WORK_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. "${WORK_PATH}/include/functions.sh"

set -o pipefail # Get exit code from process piped

# Sanity check
if [ ! -f "${ORI_ZIMAGE_FILE}" ]; then
  echo "ERROR: ${ORI_ZIMAGE_FILE} not found!" >"${LOG_FILE}"
  exit 1
fi

echo -n "Patching zImage"
rm -f "${MOD_ZIMAGE_FILE}"

KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"

if [ "${KERNEL}" = "custom" ]; then
  echo -n "."
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  KVER="$(readConfigKey "kver" "${USER_CONFIG_FILE}")"
  KPRE="$(readConfigKey "kpre" "${USER_CONFIG_FILE}")"
  # Extract bzImage
  gzip -dc "${CKS_PATH}/bzImage-${PLATFORM}-${KPRE:+${KPRE}-}${KVER}.gz" >"${MOD_ZIMAGE_FILE}"
  echo -n "..."
else
  echo -n "."
  # Extract vmlinux
  "${WORK_PATH}/bzImage-to-vmlinux.sh" "${ORI_ZIMAGE_FILE}" "${TMP_PATH}/vmlinux" >"${LOG_FILE}" 2>&1 || exit 1
  echo -n "."
  # Patch boot params and ramdisk check
  "${WORK_PATH}/kpatch" "${TMP_PATH}/vmlinux" "${TMP_PATH}/vmlinux-mod" >"${LOG_FILE}" 2>&1 || exit 1
  echo -n "."
  # Rebuild zImage
  "${WORK_PATH}/vmlinux-to-bzImage.sh" "${TMP_PATH}/vmlinux-mod" "${MOD_ZIMAGE_FILE}" >"${LOG_FILE}" 2>&1 || exit 1
  echo -n "."
fi

sync

echo -n "."
# Update HASH of new DSM zImage
HASH="$(sha256sum "${ORI_ZIMAGE_FILE}" 2>/dev/null | awk '{print $1}')"
writeConfigKey "zimage-hash" "${HASH}" "${USER_CONFIG_FILE}"

echo -n "."
echo
