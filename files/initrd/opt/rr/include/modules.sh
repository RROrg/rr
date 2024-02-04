###############################################################################
# Return list of all modules available
# 1 - Platform
# 2 - Kernel Version
function getAllModules() {
  local PLATFORM=${1}
  local KVER=${2}

  if [ -z "${PLATFORM}" -o -z "${KVER}" ]; then
    echo ""
    return 1
  fi
  # Unzip modules for temporary folder
  rm -rf "${TMP_PATH}/modules"
  mkdir -p "${TMP_PATH}/modules"
  local KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"
  if [ "${KERNEL}" = "custom" ]; then
    tar -zxf "${CKS_PATH}/modules-${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules"
  else
    tar -zxf "${MODULES_PATH}/${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules"
  fi
  # Get list of all modules
  for F in $(ls ${TMP_PATH}/modules/*.ko 2>/dev/null); do
    local X=$(basename ${F})
    local M=${X:0:-3}
    local DESC=$(modinfo ${F} | awk -F':' '/description:/{ print $2}' | awk '{sub(/^[ ]+/,""); print}')
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
  local MLIST=${3}

  if [ -z "${PLATFORM}" -o -z "${KVER}" ]; then
    echo ""
    return 1
  fi
  # Unzip modules for temporary folder
  rm -rf "${TMP_PATH}/modules"
  mkdir -p "${TMP_PATH}/modules"
  local KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"
  if [ "${KERNEL}" = "custom" ]; then
    tar -zxf "${CKS_PATH}/modules-${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules"
  else
    tar -zxf "${MODULES_PATH}/${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules"
  fi
  local ODP="$(readConfigKey "odp" "${USER_CONFIG_FILE}")"
  for F in $(ls "${TMP_PATH}/modules/"*.ko 2>/dev/null); do
    local M=$(basename ${F})
    [ "${ODP}" = "true" -a -f "${RAMDISK_PATH}/usr/lib/modules/${M}" ] && continue
    if echo "${MLIST}" | grep -wq "${M:0:-3}"; then
      cp -f "${F}" "${RAMDISK_PATH}/usr/lib/modules/${M}"
    else
      rm -f "${RAMDISK_PATH}/usr/lib/modules/${M}"
    fi
  done
  mkdir -p "${RAMDISK_PATH}/usr/lib/firmware"
  tar -zxf "${MODULES_PATH}/firmware.tgz" -C "${RAMDISK_PATH}/usr/lib/firmware"
  # Clean
  rm -rf "${TMP_PATH}/modules"
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

  if [ -z "${PLATFORM}" -o -z "${KVER}" -o -z "${KOFILE}" ]; then
    echo ""
    return 1
  fi
  # Unzip modules for temporary folder
  rm -rf "${TMP_PATH}/modules"
  mkdir -p "${TMP_PATH}/modules"
  local KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"
  if [ "${KERNEL}" = "custom" ]; then
    tar -zxf "${CKS_PATH}/modules-${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules"
  else
    tar -zxf "${MODULES_PATH}/${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules"
  fi
  cp -f ${KOFILE} ${TMP_PATH}/modules
  if [ "${KERNEL}" = "custom" ]; then
    tar -zcf "${CKS_PATH}/modules-${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules" .
  else
    tar -zcf "${MODULES_PATH}/${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules" .
  fi
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

  if [ -z "${PLATFORM}" -o -z "${KVER}" -o -z "${KONAME}" ]; then
    echo ""
    return 1
  fi
  # Unzip modules for temporary folder
  rm -rf "${TMP_PATH}/modules"
  mkdir -p "${TMP_PATH}/modules"
  local KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"
  if [ "${KERNEL}" = "custom" ]; then
    tar -zxf "${CKS_PATH}/modules-${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules"
  else
    tar -zxf "${MODULES_PATH}/${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules"
  fi
  rm -f ${TMP_PATH}/modules/${KONAME}
  if [ "${KERNEL}" = "true" ]; then
    tar -zcf "${CKS_PATH}/modules-${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules" .
  else
    tar -zcf "${MODULES_PATH}/${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules" .
  fi
}

###############################################################################
# get depends of ko
# 1 - Platform
# 2 - Kernel Version
# 3 - ko name
function getdepends() {
  function _getdepends() {
    if [ -f "${TMP_PATH}/modules/${1}.ko" ]; then
      depends=($(modinfo "${TMP_PATH}/modules/${1}.ko" | grep depends: | awk -F: '{print $2}' | awk '$1=$1' | sed 's/,/ /g'))
      if [ ${#depends[@]} -gt 0 ]; then
        for k in ${depends[@]}; do
          echo "${k}"
          _getdepends "${k}"
        done
      fi
    fi
  }
  local PLATFORM=${1}
  local KVER=${2}
  local KONAME=${3}

  if [ -z "${PLATFORM}" -o -z "${KVER}" -o -z "${KONAME}" ]; then
    echo ""
    return 1
  fi
  # Unzip modules for temporary folder
  rm -rf "${TMP_PATH}/modules"
  mkdir -p "${TMP_PATH}/modules"
  local KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"
  if [ "${KERNEL}" = "custom" ]; then
    tar -zxf "${CKS_PATH}/modules-${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules"
  else
    tar -zxf "${MODULES_PATH}/${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules"
  fi
  local DPS=($(_getdepends ${KONAME} | tr ' ' '\n' | sort -u))
  echo ${DPS[@]}
  rm -rf "${TMP_PATH}/modules"
}
