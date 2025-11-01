#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

###############################################################################
# Unpack modules from a tgz file
# 1 - Platform
# 2 - Kernel Version
# 3 - dummy path
function unpackModules() {
  local PLATFORM=${1}
  local PKVER=${2}
  local UNPATH=${3:-"${TMP_PATH}/modules"}
  local KERNEL
  KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"

  rm -rf "${UNPATH}"
  mkdir -p "${UNPATH}"
  if [ "${KERNEL}" = "custom" ]; then
    tar -zxf "${CKS_PATH}/modules-${PLATFORM}-${PKVER}.tgz" -C "${UNPATH}"
  else
    tar -zxf "${MODULES_PATH}/${PLATFORM}-${PKVER}.tgz" -C "${UNPATH}"
  fi
}

###############################################################################
# Packag modules to a tgz file
# 1 - Platform
# 2 - Kernel Version
# 3 - dummy path
function packagModules() {
  local PLATFORM=${1}
  local PKVER=${2}
  local UNPATH=${3:-"${TMP_PATH}/modules"}
  local KERNEL
  KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"

  if [ "${KERNEL}" = "custom" ]; then
    tar -zcf "${CKS_PATH}/modules-${PLATFORM}-${PKVER}.tgz" -C "${UNPATH}" .
  else
    tar -zcf "${MODULES_PATH}/${PLATFORM}-${PKVER}.tgz" -C "${UNPATH}" .
  fi
}

###############################################################################
# Return list of all modules available
# 1 - Platform
# 2 - Kernel Version
function getAllModules() {
  local PLATFORM=${1}
  local PKVER=${2}

  if [ -z "${PLATFORM}" ] || [ -z "${PKVER}" ]; then
    return 1
  fi

  UNPATH="${TMP_PATH}/modules"
  unpackModules "${PLATFORM}" "${PKVER}" "${UNPATH}"

  for D in "" "update"; do
    for F in ${UNPATH}/${D:+${D}/}*.ko; do
      [ ! -e "${F}" ] && continue
      local N DESC
      N="$(basename "${F}" .ko)"
      DESC="$(modinfo -F description "${F}" 2>/dev/null)"
      DESC="$(echo "${DESC}" | tr -d '\n\r\t\\' | sed "s/\"/'/g")"
      echo "${D:+${D}/}${N} \"${DESC:-${D:+${D}/}${N}}\""
    done
  done
  rm -rf "${UNPATH}"
}

function getLoadedModules() {
  local PLATFORM=${1}
  local PKVER=${2}

  if [ -z "${PLATFORM}" ] || [ -z "${PKVER}" ]; then
    return 1
  fi

  UNPATH="${TMP_PATH}/lib/modules/$(uname -r)"
  unpackModules "${PLATFORM}" "${PKVER}" "${UNPATH}"
  depmod -a -b "${TMP_PATH}" >/dev/null 2>&1

  ALL_KO=$(
    find /sys/devices -name modalias -exec cat {} \; | while read -r modalias; do
      modprobe -d "${TMP_PATH}" --resolve-alias "${modalias}" 2>/dev/null
    done | sort -u
  )
  rm -rf "${UNPATH}"

  ALL_DEPS=""
  for M in ${ALL_KO}; do
    ALL_DEPS="${ALL_DEPS} $(getdepends "${PLATFORM}" "${PKVER}" "${M}")"
  done

  echo "${ALL_DEPS}" | tr ' ' '\n' | grep -v '^$' | sort -u
  return 0
}

###############################################################################
# Return list of all modules available
# 1 - Platform
# 2 - Kernel Version
# 3 - Module list
function installModules() {
  local PLATFORM=${1}
  local PKVER=${2}

  if [ -z "${PLATFORM}" ] || [ -z "${PKVER}" ]; then
    echo "ERROR: installModules: Platform or Kernel Version not defined" >"${LOG_FILE}"
    return 1
  fi
  local MLIST ODP KERNEL
  shift 2
  MLIST="${*}"

  UNPATH="${TMP_PATH}/modules"
  unpackModules "${PLATFORM}" "${PKVER}" "${UNPATH}"

  ODP="$(readConfigKey "odp" "${USER_CONFIG_FILE}")"
  for D in "" "update"; do
    for F in ${UNPATH}/${D:+${D}/}*.ko; do
      [ ! -e "${F}" ] && continue
      M=$(basename "${F}")
      [ "${ODP}" = "true" ] && [ -f "${RAMDISK_PATH}/usr/lib/modules/${D:+${D}/}${M}" ] && continue # TODO: check if module is already loaded
      if echo "${MLIST}" | grep -wq "${D:+${D}/}$(basename "${M}" .ko)"; then
        mkdir -p "${RAMDISK_PATH}/usr/lib/modules/${D:+${D}/}"
        cp -f "${F}" "${RAMDISK_PATH}/usr/lib/modules/${D:+${D}/}${M}" 2>"${LOG_FILE}"
      else
        rm -f "${RAMDISK_PATH}/usr/lib/modules/${D:+${D}/}${M}" 2>"${LOG_FILE}"
      fi
    done
  done
  rm -rf "${UNPATH}"

  mkdir -p "${RAMDISK_PATH}/usr/lib/firmware"
  KERNEL=$(readConfigKey "kernel" "${USER_CONFIG_FILE}")
  if [ "${KERNEL}" = "custom" ]; then
    tar -zxf "${CKS_PATH}/firmware.tgz" -C "${RAMDISK_PATH}/usr/lib/firmware" 2>"${LOG_FILE}"
  else
    tar -zxf "${MODULES_PATH}/firmware.tgz" -C "${RAMDISK_PATH}/usr/lib/firmware" 2>"${LOG_FILE}"
  fi
  if [ $? -ne 0 ]; then
    return 1
  fi
  return 0
}

###############################################################################
# add a ko of modules.tgz
# 1 - Platform
# 2 - Kernel Version
# 3 - ko file
function addToModules() {
  local PLATFORM=${1}
  local PKVER=${2}
  local KOFILE=${3}

  if [ -z "${PLATFORM}" ] || [ -z "${PKVER}" ] || [ -z "${KOFILE}" ]; then
    echo ""
    return 1
  fi

  UNPATH="${TMP_PATH}/modules"
  unpackModules "${PLATFORM}" "${PKVER}" "${UNPATH}"

  cp -f "${KOFILE}" "${UNPATH}"

  packagModules "${PLATFORM}" "${PKVER}" "${UNPATH}"
}

###############################################################################
# del a ko of modules.tgz
# 1 - Platform
# 2 - Kernel Version
# 3 - ko name
function delToModules() {
  local PLATFORM=${1}
  local PKVER=${2}
  local KONAME=${3}

  if [ -z "${PLATFORM}" ] || [ -z "${PKVER}" ] || [ -z "${KONAME}" ]; then
    echo ""
    return 1
  fi

  UNPATH="${TMP_PATH}/modules"
  unpackModules "${PLATFORM}" "${PKVER}" "${UNPATH}"

  rm -f "${UNPATH}/${KONAME}"

  packagModules "${PLATFORM}" "${PKVER}" "${UNPATH}"
}

###############################################################################
# get depends of ko
# 1 - Platform
# 2 - Kernel Version
# 3 - ko name
function getdepends() {
  function _getdepends() {
    if [ -f "${UNPATH}/${1}.ko" ]; then
      local depends
      depends="$(modinfo -F depends "${UNPATH}/${1}.ko" 2>/dev/null | sed 's/,/\n/g')"
      if [ "$(echo "${depends}" | wc -w)" -gt 0 ]; then
        for k in ${depends}; do
          echo "${k}"
          _getdepends "${k}"
        done
      fi
    fi
  }

  local PLATFORM=${1}
  local PKVER=${2}
  local KONAME=${3}

  if [ -z "${PLATFORM}" ] || [ -z "${PKVER}" ] || [ -z "${KONAME}" ]; then
    echo ""
    return 1
  fi

  UNPATH="${TMP_PATH}/modules"
  unpackModules "${PLATFORM}" "${PKVER}" "${UNPATH}"

  _getdepends "${KONAME}" | sort -u
  echo "${KONAME}"
  rm -rf "${UNPATH}"
}
