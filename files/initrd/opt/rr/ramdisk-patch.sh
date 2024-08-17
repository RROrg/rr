#!/usr/bin/env bash

[ -z "${WORK_PATH}" -o ! -d "${WORK_PATH}/include" ] && WORK_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. ${WORK_PATH}/include/functions.sh
. ${WORK_PATH}/include/addons.sh
. ${WORK_PATH}/include/modules.sh

set -o pipefail # Get exit code from process piped

# Sanity check
if [ ! -f "${ORI_RDGZ_FILE}" ]; then
  echo "ERROR: ${ORI_RDGZ_FILE} not found!" >"${LOG_FILE}"
  exit 1
fi

echo -n "Patching Ramdisk"

# Remove old rd.gz patched
rm -f "${MOD_RDGZ_FILE}"

# Unzipping ramdisk
echo -n "."
rm -rf "${RAMDISK_PATH}" # Force clean
mkdir -p "${RAMDISK_PATH}"
(
  cd "${RAMDISK_PATH}"
  xz -dc <"${ORI_RDGZ_FILE}" | cpio -idm
) >/dev/null 2>&1

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
HDDSORT="$(readConfigKey "hddsort" "${USER_CONFIG_FILE}")"

[ "${PATURL:0:1}" = "#" ] && PATURL=""
[ "${PATSUM:0:1}" = "#" ] && PATSUM=""

# Check if DSM buildnumber changed
. "${RAMDISK_PATH}/etc/VERSION"

if [ -n "${PRODUCTVER}" -a -n "${BUILDNUM}" -a -n "${SMALLNUM}" ] &&
  ([ ! "${PRODUCTVER}" = "${majorversion}.${minorversion}" ] || [ ! "${BUILDNUM}" = "${buildnumber}" ] || [ ! "${SMALLNUM}" = "${smallfixnumber}" ]); then
  OLDVER="${PRODUCTVER}(${BUILDNUM}$([ ${SMALLNUM:-0} -ne 0 ] && echo "u${SMALLNUM}"))"
  NEWVER="${majorversion}.${minorversion}(${buildnumber}$([ ${smallfixnumber:-0} -ne 0 ] && echo "u${smallfixnumber}"))"
  echo -e "\033[A\n\033[1;32mBuild number changed from \033[1;31m${OLDVER}\033[1;32m to \033[1;31m${NEWVER}\033[0m"
  echo -n "Patching Ramdisk."
  PATURL=""
  PATSUM=""
  # Clean old pat file
  rm -f "${PART3_PATH}/dl/${MODEL}-${PRODUCTVER}.pat" 2>/dev/null || true
fi
# Update new buildnumber
PRODUCTVER=${majorversion}.${minorversion}
BUILDNUM=${buildnumber}
SMALLNUM=${smallfixnumber}
writeConfigKey "productver" "${PRODUCTVER}" "${USER_CONFIG_FILE}"
writeConfigKey "buildnum" "${BUILDNUM}" "${USER_CONFIG_FILE}"
writeConfigKey "smallnum" "${SMALLNUM}" "${USER_CONFIG_FILE}"

echo -n "."
# Read model data
KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${WORK_PATH}/platforms.yml")"
KPRE="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kpre" "${WORK_PATH}/platforms.yml")"

# Sanity check
if [ -z "${PLATFORM}" -o -z "${KVER}" ]; then
  echo "ERROR: Configuration for model ${MODEL} and productversion ${PRODUCTVER} not found." >"${LOG_FILE}"
  exit 1
fi

declare -A SYNOINFO
declare -A ADDONS
declare -A MODULES

# Read synoinfo and addons from config
while IFS=': ' read KEY VALUE; do
  [ -n "${KEY}" ] && SYNOINFO["${KEY}"]="${VALUE}"
done <<<$(readConfigMap "synoinfo" "${USER_CONFIG_FILE}")
while IFS=': ' read KEY VALUE; do
  [ -n "${KEY}" ] && ADDONS["${KEY}"]="${VALUE}"
done <<<$(readConfigMap "addons" "${USER_CONFIG_FILE}")

# Read modules from user config
while IFS=': ' read KEY VALUE; do
  [ -n "${KEY}" ] && MODULES["${KEY}"]="${VALUE}"
done <<<$(readConfigMap "modules" "${USER_CONFIG_FILE}")

# Patches (diff -Naru OLDFILE NEWFILE > xxx.patch)
PATCHS=()
PATCHS+=("ramdisk-etc-rc-*.patch")
PATCHS+=("ramdisk-init-script-*.patch")
PATCHS+=("ramdisk-post-init-script-*.patch")
PATCHS+=("ramdisk-disable-root-pwd-*.patch")
PATCHS+=("ramdisk-disable-disabled-ports-*.patch")
for PE in ${PATCHS[@]}; do
  RET=1
  echo "Patching with ${PE}" >"${LOG_FILE}"
  for PF in $(ls ${WORK_PATH}/patch/${PE} 2>/dev/null); do
    echo -n "."
    echo "Patching with ${PF}" >>"${LOG_FILE}"
    (
      cd "${RAMDISK_PATH}"
      busybox patch -p1 -i "${PF}" >>"${LOG_FILE}" 2>&1 # busybox patch and gun patch have different processing methods and parameters.
    )
    RET=$?
    [ ${RET} -eq 0 ] && break
  done
  [ ${RET} -ne 0 ] && exit 1
done

# Patch /etc/synoinfo.conf /etc.defaults/synoinfo.conf
echo -n "."
# Add serial number to synoinfo.conf, to help to recovery a installed DSM
echo "Set synoinfo SN" >"${LOG_FILE}"
_set_conf_kv "SN" "${SN}" "${RAMDISK_PATH}/etc/synoinfo.conf" >>"${LOG_FILE}" 2>&1 || exit 1
_set_conf_kv "SN" "${SN}" "${RAMDISK_PATH}/etc.defaults/synoinfo.conf" >>"${LOG_FILE}" 2>&1 || exit 1
for KEY in ${!SYNOINFO[@]}; do
  echo "Set synoinfo ${KEY}" >>"${LOG_FILE}"
  _set_conf_kv "${KEY}" "${SYNOINFO[${KEY}]}" "${RAMDISK_PATH}/etc/synoinfo.conf" >>"${LOG_FILE}" 2>&1 || exit 1
  _set_conf_kv "${KEY}" "${SYNOINFO[${KEY}]}" "${RAMDISK_PATH}/etc.defaults/synoinfo.conf" >>"${LOG_FILE}" 2>&1 || exit 1
done

# Patch /sbin/init.post
echo -n "."
grep -v -e '^[\t ]*#' -e '^$' "${WORK_PATH}/patch/config-manipulators.sh" >"${TMP_PATH}/rp.txt"
sed -e "/@@@CONFIG-MANIPULATORS-TOOLS@@@/ {" -e "r ${TMP_PATH}/rp.txt" -e 'd' -e '}' -i "${RAMDISK_PATH}/sbin/init.post"
rm -f "${TMP_PATH}/rp.txt"
touch "${TMP_PATH}/rp.txt"
echo "_set_conf_kv 'SN' '${SN}' '/tmpRoot/etc/synoinfo.conf'" >>"${TMP_PATH}/rp.txt"
echo "_set_conf_kv 'SN' '${SN}' '/tmpRoot/etc.defaults/synoinfo.conf'" >>"${TMP_PATH}/rp.txt"
for KEY in ${!SYNOINFO[@]}; do
  echo "_set_conf_kv '${KEY}' '${SYNOINFO[${KEY}]}' '/tmpRoot/etc/synoinfo.conf'" >>"${TMP_PATH}/rp.txt"
  echo "_set_conf_kv '${KEY}' '${SYNOINFO[${KEY}]}' '/tmpRoot/etc.defaults/synoinfo.conf'" >>"${TMP_PATH}/rp.txt"
done
sed -e "/@@@CONFIG-GENERATED@@@/ {" -e "r ${TMP_PATH}/rp.txt" -e 'd' -e '}' -i "${RAMDISK_PATH}/sbin/init.post"
rm -f "${TMP_PATH}/rp.txt"

# Extract ck modules to ramdisk
echo -n "."
installModules "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}" "${!MODULES[@]}" || exit 1

echo -n "."
# Copying fake modprobe
[ $(echo "${KVER:-4}" | cut -d'.' -f1) -lt 5 ] && cp -f "${WORK_PATH}/patch/iosched-trampoline.sh" "${RAMDISK_PATH}/usr/sbin/modprobe"
# Copying LKM to /usr/lib/modules
gzip -dc "${LKMS_PATH}/rp-${PLATFORM}-$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}-${LKM}.ko.gz" >"${RAMDISK_PATH}/usr/lib/modules/rp.ko" 2>"${LOG_FILE}" || exit 1

# Addons
echo -n "."
echo "Create addons.sh" >"${LOG_FILE}"
mkdir -p "${RAMDISK_PATH}/addons"
echo "#!/bin/sh" >"${RAMDISK_PATH}/addons/addons.sh"
echo 'echo "addons.sh called with params ${@}"' >>"${RAMDISK_PATH}/addons/addons.sh"
echo "export LOADERLABEL=\"RR\"" >>"${RAMDISK_PATH}/addons/addons.sh"
echo "export LOADERRELEASE=\"${RR_RELEASE}\"" >>"${RAMDISK_PATH}/addons/addons.sh"
echo "export LOADERVERSION=\"${RR_VERSION}\"" >>"${RAMDISK_PATH}/addons/addons.sh"
echo "export PLATFORM=\"${PLATFORM}\"" >>"${RAMDISK_PATH}/addons/addons.sh"
echo "export MODEL=\"${MODEL}\"" >>"${RAMDISK_PATH}/addons/addons.sh"
echo "export PRODUCTVERL=\"${PRODUCTVERL}\"" >>"${RAMDISK_PATH}/addons/addons.sh"
echo "export MLINK=\"${PATURL}\"" >>"${RAMDISK_PATH}/addons/addons.sh"
echo "export MCHECKSUM=\"${PATSUM}\"" >>"${RAMDISK_PATH}/addons/addons.sh"
echo "export LAYOUT=\"${LAYOUT}\"" >>"${RAMDISK_PATH}/addons/addons.sh"
echo "export KEYMAP=\"${KEYMAP}\"" >>"${RAMDISK_PATH}/addons/addons.sh"
chmod +x "${RAMDISK_PATH}/addons/addons.sh"

# This order cannot be changed.
for ADDON in "redpill" "revert" "misc" "eudev" "disks" "localrss" "notify" "wol" "rndis"; do
  PARAMS=""
  if [ "${ADDON}" = "disks" ]; then
    PARAMS=${HDDSORT}
    [ -f "${USER_UP_PATH}/${MODEL}.dts" ] && cp -f "${USER_UP_PATH}/${MODEL}.dts" "${RAMDISK_PATH}/addons/model.dts"
  fi
  installAddon "${ADDON}" "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}" || exit 1
  echo "/addons/${ADDON}.sh \${1} ${PARAMS}" >>"${RAMDISK_PATH}/addons/addons.sh" 2>>"${LOG_FILE}" || exit 1
done

# User addons
for ADDON in ${!ADDONS[@]}; do
  PARAMS=${ADDONS[${ADDON}]}
  installAddon "${ADDON}" "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}" || exit 1
  echo "/addons/${ADDON}.sh \${1} ${PARAMS}" >>"${RAMDISK_PATH}/addons/addons.sh" 2>>"${LOG_FILE}" || exit 1
done

# Enable Telnet
echo "inetd" >>"${RAMDISK_PATH}/addons/addons.sh"

echo -n "."
echo "Modify files" >"${LOG_FILE}"
# Remove function from scripts
[ "2" = "${BUILDNUM:0:1}" ] && sed -i 's/function //g' $(find "${RAMDISK_PATH}/addons/" -type f -name "*.sh")

# Build modules dependencies
# ${WORK_PATH}/depmod -a -b ${RAMDISK_PATH} 2>/dev/null  # addon eudev will do this

# Copying modulelist
if [ -f "${USER_UP_PATH}/modulelist" ]; then
  cp -f "${USER_UP_PATH}/modulelist" "${RAMDISK_PATH}/addons/modulelist"
else
  cp -f "${WORK_PATH}/patch/modulelist" "${RAMDISK_PATH}/addons/modulelist"
fi

# backup current loader configs
BACKUP_PATH="${RAMDISK_PATH}/usr/rr/backup"
rm -rf "${BACKUP_PATH}"
for F in "${USER_GRUB_CONFIG}" "${USER_CONFIG_FILE}" "${USER_LOCALE_FILE}" "${USER_UP_PATH}" "${SCRIPTS_PATH}"; do
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
  echo -e "DEVICE=eth${N}\nBOOTPROTO=dhcp\nONBOOT=yes\nIPV6INIT=dhcp\nIPV6_ACCEPT_RA=1" >"${RAMDISK_PATH}/etc/sysconfig/network-scripts/ifcfg-eth${N}"
done

# issues/313
if [ ${PLATFORM} = "epyc7002" ]; then
  sed -i 's#/dev/console#/var/log/lrc#g' ${RAMDISK_PATH}/usr/bin/busybox
  sed -i '/^echo "START/a \\nmknod -m 0666 /dev/console c 1 3' ${RAMDISK_PATH}/linuxrc.syno
fi

if [ "${PLATFORM}" = "broadwellntbap" ]; then
  sed -i 's/IsUCOrXA="yes"/XIsUCOrXA="yes"/g; s/IsUCOrXA=yes/XIsUCOrXA=yes/g' ${RAMDISK_PATH}/usr/syno/share/environments.sh
fi

# Call user patch scripts
echo -n "."
for F in $(ls -1 ${SCRIPTS_PATH}/*.sh 2>/dev/null); do
  echo "Calling ${F}" >"${LOG_FILE}"
  . "${F}" >>"${LOG_FILE}" 2>&1 || exit 1
done

# Reassembly ramdisk
echo -n "."
if [ "${RD_COMPRESSED}" == "true" ]; then
  (cd "${RAMDISK_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root | xz -9 --format=lzma >"${MOD_RDGZ_FILE}") >"${LOG_FILE}" 2>&1 || exit 1
else
  (cd "${RAMDISK_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root >"${MOD_RDGZ_FILE}") >"${LOG_FILE}" 2>&1 || exit 1
fi

sync

# Clean
rm -rf "${RAMDISK_PATH}"

# Update SHA256 hash
echo -n "."
RAMDISK_HASH_CUR="$(sha256sum "${ORI_RDGZ_FILE}" | awk '{print $1}')"
writeConfigKey "ramdisk-hash" "${RAMDISK_HASH_CUR}" "${USER_CONFIG_FILE}"

echo
