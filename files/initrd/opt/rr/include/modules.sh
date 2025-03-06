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
function unpackModules() {
  local PLATFORM=${1}
  local PKVER=${2}
  local KERNEL
  KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"

  rm -rf "${TMP_PATH}/modules"
  mkdir -p "${TMP_PATH}/modules"
  if [ "${KERNEL}" = "custom" ]; then
    tar -zxf "${CKS_PATH}/modules-${PLATFORM}-${PKVER}.tgz" -C "${TMP_PATH}/modules"
  else
    tar -zxf "${MODULES_PATH}/${PLATFORM}-${PKVER}.tgz" -C "${TMP_PATH}/modules"
  fi
}

###############################################################################
# Packag modules to a tgz file
# 1 - Platform
# 2 - Kernel Version
function packagModules() {
  local PLATFORM=${1}
  local PKVER=${2}
  local KERNEL
  KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"

  if [ "${KERNEL}" = "custom" ]; then
    tar -zcf "${CKS_PATH}/modules-${PLATFORM}-${PKVER}.tgz" -C "${TMP_PATH}/modules" .
  else
    tar -zcf "${MODULES_PATH}/${PLATFORM}-${PKVER}.tgz" -C "${TMP_PATH}/modules" .
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

  unpackModules "${PLATFORM}" "${PKVER}"

  for F in ${TMP_PATH}/modules/*.ko; do
    [ ! -e "${F}" ] && continue
    local X M DESC
    X=$(basename "${F}")
    M=$(basename "${F}" .ko)
    DESC=$(modinfo "${F}" 2>/dev/null | awk -F':' '/description:/{ print $2}' | awk '{sub(/^[ ]+/,""); print}')
    [ -z "${DESC}" ] && DESC="${X}"
    echo "${M} \"${DESC}\""
  done

  rm -rf "${TMP_PATH}/modules"
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

  unpackModules "${PLATFORM}" "${PKVER}"

  ODP="$(readConfigKey "odp" "${USER_CONFIG_FILE}")"
  for F in ${TMP_PATH}/modules/*.ko; do
    [ ! -e "${F}" ] && continue
    M=$(basename "${F}")
    [ "${ODP}" = "true" ] && [ -f "${RAMDISK_PATH}/usr/lib/modules/${M}" ] && continue
    if echo "${MLIST}" | grep -wq "$(basename "${M}" .ko)"; then
      cp -f "${F}" "${RAMDISK_PATH}/usr/lib/modules/${M}" 2>"${LOG_FILE}"
    else
      rm -f "${RAMDISK_PATH}/usr/lib/modules/${M}" 2>"${LOG_FILE}"
    fi
  done

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

  rm -rf "${TMP_PATH}/modules"
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

  unpackModules "${PLATFORM}" "${PKVER}"

  cp -f "${KOFILE}" "${TMP_PATH}/modules"

  packagModules "${PLATFORM}" "${PKVER}"
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

  unpackModules "${PLATFORM}" "${PKVER}"

  rm -f "${TMP_PATH}/modules/${KONAME}"

  packagModules "${PLATFORM}" "${PKVER}"
}

###############################################################################
# get depends of ko
# 1 - Platform
# 2 - Kernel Version
# 3 - ko name
function getdepends() {
  function _getdepends() {
    if [ -f "${TMP_PATH}/modules/${1}.ko" ]; then
      local depends
      depends="$(modinfo "${TMP_PATH}/modules/${1}.ko" 2>/dev/null | grep depends: | awk -F: '{print $2}' | awk '$1=$1' | sed 's/,/\n/g')"
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

  unpackModules "${PLATFORM}" "${PKVER}"

  _getdepends "${KONAME}" | sort -u
  echo "${KONAME}"
  rm -rf "${TMP_PATH}/modules"
}
