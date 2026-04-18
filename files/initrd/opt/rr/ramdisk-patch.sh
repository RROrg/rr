#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# shellcheck disable=SC2034

[ -z "${WORK_PATH}" ] || [ ! -d "${WORK_PATH}/include" ] && WORK_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. "${WORK_PATH}/include/functions.sh"

set -o pipefail # Get exit code from process piped

# get user data
PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
SMALLNUM="$(readConfigKey "smallnum" "${USER_CONFIG_FILE}")"
KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"
RD_COMPRESSED="$(readConfigKey "rd-compressed" "${USER_CONFIG_FILE}")"
LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"
LAYOUT="$(readConfigKey "layout" "${USER_CONFIG_FILE}")"
KEYMAP="$(readConfigKey "keymap" "${USER_CONFIG_FILE}")"
PATURL="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
PATSUM="$(readConfigKey "patsum" "${USER_CONFIG_FILE}")"
ODP="$(readConfigKey "odp" "${USER_CONFIG_FILE}")" # official drivers priorities

DT="$(readConfigKey "dt" "${USER_CONFIG_FILE}")"
KVER="$(readConfigKey "kver" "${USER_CONFIG_FILE}")"
KPRE="$(readConfigKey "kpre" "${USER_CONFIG_FILE}")"

# Sanity check
if [ -z "${PLATFORM}" ] || [ -z "${KPRE:+${KPRE}-}${KVER}" ]; then
  echo "ERROR: Configuration for model ${MODEL} and productversion ${PRODUCTVER} not found." >"${LOG_FILE}"
  exit 1
fi

[ "${PATURL:0:1}" = "#" ] && PATURL=""
[ "${PATSUM:0:1}" = "#" ] && PATSUM=""

# Sanity check
if [ ! -f "${ORI_RDGZ_FILE}" ]; then
  echo "ERROR: ${ORI_RDGZ_FILE} not found!" >"${LOG_FILE}"
  exit 1
fi

echo -n "Patching Ramdisk"

# Unzipping ramdisk
rm -rf "${RAMDISK_PATH}" # Force clean
mkdir -p "${RAMDISK_PATH}"
(cd "${RAMDISK_PATH}" && xz -dc <"${ORI_RDGZ_FILE}" | cpio -idm) >/dev/null 2>&1

# Check if DSM buildnumber changed
. "${RAMDISK_PATH}/etc/VERSION"

BUILDNUM=${buildnumber:-0}
SMALLNUM=${smallfixnumber:-0}
writeConfigKey "buildnum" "${BUILDNUM}" "${USER_CONFIG_FILE}"
writeConfigKey "smallnum" "${SMALLNUM}" "${USER_CONFIG_FILE}"

declare -A ADDONS
declare -A MODULES
declare -A SYNOINFO

# Read addons, modules and synoinfo from user config
while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && ADDONS["${KEY}"]="${VALUE}"
done <<<"$(readConfigMap "addons" "${USER_CONFIG_FILE}")"

# Read modules from user config
while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && MODULES["${KEY}"]="${VALUE}"
done <<<"$(readConfigMap "modules" "${USER_CONFIG_FILE}")"

# SYNOINFO["SN"]="${SN}"
while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && SYNOINFO["${KEY}"]="${VALUE}"
done <<<"$(readConfigMap "synoinfo" "${USER_CONFIG_FILE}")"

# Patches (diff -Naru OLDFILE NEWFILE > xxx.patch)
echo -n "."
PATCHS=(
  "ramdisk-etc-rc-*.patch"
  "ramdisk-init-script-*.patch"
  "ramdisk-post-init-script-*.patch"
)
for PE in "${PATCHS[@]}"; do
  RET=1
  echo "Patching with ${PE}" >"${LOG_FILE}"
  # ${PE} contains *, so double quotes cannot be added
  for PF in ${WORK_PATH}/patch/${PE}; do
    [ ! -e "${PF}" ] && continue
    echo "Patching with ${PF}" >>"${LOG_FILE}"
    # busybox patch and gun patch have different processing methods and parameters.
    (cd "${RAMDISK_PATH}" && busybox patch -p1 -i "${PF}") >>"${LOG_FILE}" 2>&1
    RET=$?
    [ ${RET} -eq 0 ] && break
  done
  [ ${RET} -ne 0 ] && exit 1
done
# for DSM 7.3
sed -i 's#/usr/syno/sbin/broadcom_update.sh#/usr/syno/sbin/broadcom_update.sh.rr#g' "${RAMDISK_PATH}/linuxrc.syno.impl"
# LKM
gzip -dc "${LKMS_PATH}/rp-${PLATFORM}-${KPRE:+${KPRE}-}${KVER}-${LKM}.ko.gz" >"${RAMDISK_PATH}/usr/lib/modules/rp.ko" 2>"${LOG_FILE}" || exit 1
if [ "$(echo "${KVER:-4}" | cut -d'.' -f1)" -lt 5 ]; then
  # Copying fake modprobe
  cp -f "${WORK_PATH}/patch/iosched-trampoline.sh" "${RAMDISK_PATH}/usr/sbin/modprobe"
else
  # for issues/313
  sed -i 's#/dev/console#/var/log/lrc#g' "${RAMDISK_PATH}/usr/bin/busybox"
  sed -i '/^echo "START/a \\nmknod -m 0666 /dev/console c 1 3' "${RAMDISK_PATH}/linuxrc.syno"
fi

if [ "${PLATFORM}" = "broadwellntbap" ]; then
  sed -i 's/IsUCOrXA="yes"/XIsUCOrXA="yes"/g; s/IsUCOrXA=yes/XIsUCOrXA=yes/g' "${RAMDISK_PATH}/usr/syno/share/environments.sh"
fi

# Addons
echo -n "."
mkdir -p "${RAMDISK_PATH}/addons"
echo "Create addons.sh" >"${LOG_FILE}"
{
  echo "#!/bin/sh"
  echo 'echo "addons.sh called with params ${@}"'
  echo 'export LOADERLABEL="RR"'
  echo "export LOADERRELEASE=\"${RR_RELEASE}\""
  echo "export LOADERVERSION=\"${RR_VERSION}\""
  echo "export PLATFORM=\"${PLATFORM}\""
  echo "export MODEL=\"${MODEL}\""
  echo "export PRODUCTVERL=\"${PRODUCTVERL}\""
  echo "export MLINK=\"${PATURL}\""
  echo "export MCHECKSUM=\"${PATSUM}\""
  echo "export LAYOUT=\"${LAYOUT}\""
  echo "export KEYMAP=\"${KEYMAP}\""
} >"${RAMDISK_PATH}/addons/addons.sh"
chmod +x "${RAMDISK_PATH}/addons/addons.sh"

# This order cannot be changed.  # ( "netfix" )
for ADDON in "redpill" "revert" "misc" "eudev" "disks" "localrss" "notify" "wol"; do
  PARAMS=""
  if [ "${ADDON}" = "disks" ]; then
    [ -f "${USER_UP_PATH}/model.dts" ] && cp -f "${USER_UP_PATH}/model.dts" "${RAMDISK_PATH}/addons/model.dts"
    [ -f "${USER_UP_PATH}/${MODEL}.dts" ] && cp -f "${USER_UP_PATH}/${MODEL}.dts" "${RAMDISK_PATH}/addons/model.dts"
  fi
  installAddon "${ADDON}" "${PLATFORM}" "${KPRE:+${KPRE}-}${KVER}" || exit 1
  echo "/addons/${ADDON}.sh \${1} ${PARAMS}" >>"${RAMDISK_PATH}/addons/addons.sh" 2>>"${LOG_FILE}" || exit 1
done

# User addons
for ADDON in "${!ADDONS[@]}"; do
  PARAMS=${ADDONS[${ADDON}]}
  installAddon "${ADDON}" "${PLATFORM}" "${KPRE:+${KPRE}-}${KVER}" || exit 1
  echo "/addons/${ADDON}.sh \${1} ${PARAMS}" >>"${RAMDISK_PATH}/addons/addons.sh" 2>>"${LOG_FILE}" || exit 1
done

# Modules
echo -n "."
installModules "${PLATFORM}" "${KPRE:+${KPRE}-}${KVER}" "${!MODULES[@]}" || exit 1
# Build modules dependencies
# ${WORK_PATH}/depmod -a -b ${RAMDISK_PATH} 2>/dev/null  # addon eudev will do this
# Copying modulelist
if [ -f "${USER_UP_PATH}/modulelist" ]; then
  cp -f "${USER_UP_PATH}/modulelist" "${RAMDISK_PATH}/addons/modulelist"
else
  cp -f "${WORK_PATH}/patch/modulelist" "${RAMDISK_PATH}/addons/modulelist"
fi

# Patch synoinfo.conf
echo -n "."
echo -n "" >"${RAMDISK_PATH}/addons/synoinfo.conf"
for KEY in "${!SYNOINFO[@]}"; do
  echo "Set synoinfo ${KEY}" >>"${LOG_FILE}"
  echo "${KEY}=\"${SYNOINFO[${KEY}]}\"" >>"${RAMDISK_PATH}/addons/synoinfo.conf"
  _set_conf_kv "${RAMDISK_PATH}/etc/synoinfo.conf" "${KEY}" "${SYNOINFO[${KEY}]}" || exit 1
  _set_conf_kv "${RAMDISK_PATH}/etc.defaults/synoinfo.conf" "${KEY}" "${SYNOINFO[${KEY}]}" || exit 1
done
if [ ! -x "${RAMDISK_PATH}/usr/bin/get_key_value" ]; then
  printf '#!/bin/sh\n%s\n_get_conf_kv "$@"' "$(declare -f _get_conf_kv)" >"${RAMDISK_PATH}/usr/bin/get_key_value"
  chmod a+x "${RAMDISK_PATH}/usr/bin/get_key_value"
fi
if [ ! -x "${RAMDISK_PATH}/usr/bin/set_key_value" ]; then
  printf '#!/bin/sh\n%s\n_set_conf_kv "$@"' "$(declare -f _set_conf_kv)" >"${RAMDISK_PATH}/usr/bin/set_key_value"
  chmod a+x "${RAMDISK_PATH}/usr/bin/set_key_value"
fi

echo -n "."
echo "Modify files" >"${LOG_FILE}"
# Remove function from scripts
[ "${BUILDNUM}" -le 25556 ] && find "${RAMDISK_PATH}/addons/" -type f -name "*.sh" -exec sed -i 's/function //g' {} \;

# backup current loader configs
mkdir -p "${RAMDISK_PATH}/usr/rr"
{
  echo 'LOADERLABEL="RR"'
  echo "LOADERRELEASE=\"${RR_RELEASE}\""
  echo "LOADERVERSION=\"${RR_VERSION}\""
} >"${RAMDISK_PATH}/usr/rr/VERSION"
BACKUP_PATH="${RAMDISK_PATH}/usr/rr/backup"
rm -rf "${BACKUP_PATH}"
for F in "${USER_GRUB_CONFIG}" "${USER_CONFIG_FILE}" "${USER_LOCALE_FILE}" "${USER_UP_PATH}" "${SCRIPTS_PATH}" "/mnt/p2/machine.key" "/mnt/p2/Sone.9.bak"; do
  if [ -f "${F}" ]; then
    FD="$(dirname "${F}")"
    mkdir -p "${FD/\/mnt/${BACKUP_PATH}}"
    cp -f "${F}" "${FD/\/mnt/${BACKUP_PATH}}"
  elif [ -d "${F}" ]; then
    SIZE="$(du -sm "${F}" 2>/dev/null | awk '{print $1}')"
    if [ ${SIZE:-0} -gt 4 ]; then
      echo "Backup of ${F} skipped, size is ${SIZE}MB" >>"${LOG_FILE}"
      continue
    fi
    FD="$(dirname "${F}")"
    mkdir -p "${FD/\/mnt/${BACKUP_PATH}}"
    cp -rf "${F}" "${FD/\/mnt/${BACKUP_PATH}}"
  fi
done

# Network card configuration file
for N in $(seq 0 7); do
  echo -e "DEVICE=eth${N}\nBOOTPROTO=dhcp\nONBOOT=yes\nIPV6INIT=auto_dhcp\nIPV6_ACCEPT_RA=1" >"${RAMDISK_PATH}/etc/sysconfig/network-scripts/ifcfg-eth${N}"
done

# Call user patch scripts
echo -n "."
for F in $(LC_ALL=C printf '%s\n' ${SCRIPTS_PATH}/*.sh | sort -V); do
  [ ! -e "${F}" ] && continue
  echo "Calling ${F}" >"${LOG_FILE}"
  # shellcheck source=/dev/null
  . "${F}" >>"${LOG_FILE}" 2>&1 || exit 1
done

# Reassembly ramdisk
rm -f "${MOD_RDGZ_FILE}"
if [ "${RD_COMPRESSED}" = "true" ]; then
  (cd "${RAMDISK_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root | xz -9 --format=lzma >"${MOD_RDGZ_FILE}") >"${LOG_FILE}" 2>&1 || exit 1
else
  (cd "${RAMDISK_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root >"${MOD_RDGZ_FILE}") >"${LOG_FILE}" 2>&1 || exit 1
fi

sync

# Clean
rm -rf "${RAMDISK_PATH}"

# Update SHA256 hash
RAMDISK_HASH_CUR="$(sha256sum "${ORI_RDGZ_FILE}" 2>/dev/null | awk '{print $1}')"
writeConfigKey "ramdisk-hash" "${RAMDISK_HASH_CUR}" "${USER_CONFIG_FILE}"

MACHINE_KEY_HASH="$(sha256sum "/mnt/p2/machine.key" 2>/dev/null | awk '{print $1}')"
writeConfigKey "machine_key-hash" "${MACHINE_KEY_HASH}" "${USER_CONFIG_FILE}"
SONE_9_BAK_HASH="$(sha256sum "/mnt/p2/Sone.9.bak" 2>/dev/null | awk '{print $1}')"
writeConfigKey "sone_9_bak-hash" "${SONE_9_BAK_HASH}" "${USER_CONFIG_FILE}"

echo -n "."
echo
