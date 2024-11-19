###############################################################################
# Unpack modules from a tgz file
# 1 - Platform
# 2 - Kernel Version
function unpackModules() {
  local PLATFORM=${1}
  local KVER=${2}
  local KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"

  rm -rf "${TMP_PATH}/modules"
  mkdir -p "${TMP_PATH}/modules"
  if [ "${KERNEL}" = "custom" ]; then
    tar -zxf "${CKS_PATH}/modules-${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules"
  else
    tar -zxf "${MODULES_PATH}/${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules"
  fi
}

###############################################################################
# Packag modules to a tgz file
# 1 - Platform
# 2 - Kernel Version
function packagModules() {
  local PLATFORM=${1}
  local KVER=${2}
  local KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"

  if [ "${KERNEL}" = "custom" ]; then
    tar -zcf "${CKS_PATH}/modules-${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules" .
  else
    tar -zcf "${MODULES_PATH}/${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules" .
  fi
}

###############################################################################
# Return list of all modules available
# 1 - Platform
# 2 - Kernel Version
function getAllModules() {
  local PLATFORM=${1}
  local KVER=${2}

  if [ -z "${PLATFORM}" ] || [ -z "${KVER}" ]; then
    return 1
  fi

  unpackModules "${PLATFORM}" "${KVER}"

  for F in $(ls ${TMP_PATH}/modules/*.ko 2>/dev/null); do
    local X=$(basename "${F}")
    local M=${X:0:-3}
    local DESC=$(modinfo "${F}" 2>/dev/null | awk -F':' '/description:/{ print $2}' | awk '{sub(/^[ ]+/,""); print}')
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
  local KVER=${2}
  shift 2
  local MLIST="${@}"

  if [ -z "${PLATFORM}" ] || [ -z "${KVER}" ]; then
    echo "ERROR: installModules: Platform or Kernel Version not defined" >"${LOG_FILE}"
    return 1
  fi

  unpackModules "${PLATFORM}" "${KVER}"

  local ODP="$(readConfigKey "odp" "${USER_CONFIG_FILE}")"
  for F in $(ls "${TMP_PATH}/modules/"*.ko 2>/dev/null); do
    local M=$(basename "${F}")
    [ "${ODP}" == "true" ] && [  -f "${RAMDISK_PATH}/usr/lib/modules/${M}" ] && continue
    if echo "${MLIST}" | grep -wq "${M:0:-3}"; then
      cp -f "${F}" "${RAMDISK_PATH}/usr/lib/modules/${M}" 2>"${LOG_FILE}"
    else
      rm -f "${RAMDISK_PATH}/usr/lib/modules/${M}" 2>"${LOG_FILE}"
    fi
  done

  mkdir -p "${RAMDISK_PATH}/usr/lib/firmware"
  local KERNEL=$(readConfigKey "kernel" "${USER_CONFIG_FILE}")
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
  local KVER=${2}
  local KOFILE=${3}

  if [ -z "${PLATFORM}" ] || [ -z "${KVER}" ] || [ -z "${KOFILE}" ]; then
    echo ""
    return 1
  fi

  unpackModules "${PLATFORM}" "${KVER}"

  cp -f "${KOFILE}" "${TMP_PATH}/modules"

  packagModules "${PLATFORM}" "${KVER}"
}

###############################################################################
# del a ko of modules.tgz
# 1 - Platform
# 2 - Kernel Version
# 3 - ko name
function delToModules() {
  local PLATFORM=${1}
  local KVER=${2}
  local KONAME=${3}

  if [ -z "${PLATFORM}" ] || [ -z "${KVER}" ] || [ -z "${KONAME}" ]; then
    echo ""
    return 1
  fi

  unpackModules "${PLATFORM}" "${KVER}"

  rm -f "${TMP_PATH}/modules/${KONAME}"

  packagModules "${PLATFORM}" "${KVER}"
}

###############################################################################
# get depends of ko
# 1 - Platform
# 2 - Kernel Version
# 3 - ko name
function getdepends() {
  function _getdepends() {
    if [ -f "${TMP_PATH}/modules/${1}.ko" ]; then
      local depends=($(modinfo "${TMP_PATH}/modules/${1}.ko" 2>/dev/null | grep depends: | awk -F: '{print $2}' | awk '$1=$1' | sed 's/,/ /g'))
      if [ ${#depends[@]} -gt 0 ]; then
        for k in "${depends[@]}"; do
          echo "${k}"
          _getdepends "${k}"
        done
      fi
    fi
  }

  local PLATFORM=${1}
  local KVER=${2}
  local KONAME=${3}

  if [ -z "${PLATFORM}" ] || [ -z "${KVER}" ] || [ -z "${KONAME}" ]; then
    echo ""
    return 1
  fi

  unpackModules "${PLATFORM}" "${KVER}"

  local DPS=($(_getdepends "${KONAME}" | tr ' ' '\n' | sort -u))
  echo "${DPS[@]}"
  rm -rf "${TMP_PATH}/modules"
}
