
###############################################################################
# Return list of available addons
# 1 - Platform
# 2 - Kernel Version
function availableAddons() {
  while read D; do
    [ ! -f "${D}/manifest.yml" ] && continue
    ADDON=`basename ${D}`
    checkAddonExist "${ADDON}" "${1}" "${2}" || continue
    SYSTEM=`readConfigKey "system" "${D}/manifest.yml"`
    [ "${SYSTEM}" = "true" ] && continue
    DESC="`readConfigKey "description" "${D}/manifest.yml"`"
    echo -e "${ADDON}\t${DESC}"
  done < <(find "${ADDONS_PATH}" -maxdepth 1 -type d | sort)
}

###############################################################################
# Check if addon exist
# 1 - Addon id
# 2 - Platform
# 3 - Kernel Version
# Return ERROR if not exists
function checkAddonExist() {
  # First check generic files
  if [ -f "${ADDONS_PATH}/${1}/all.tgz" ]; then
    return 0 # OK
  fi
  # Now check specific platform file
  if [ -f "${ADDONS_PATH}/${1}/${2}-${3}.tgz" ]; then
    return 0 # OK
  fi
  return 1 # ERROR
}

###############################################################################
# Install Addon into ramdisk image
# 1 - Addon id
function installAddon() {
  ADDON="${1}"
  mkdir -p "${TMP_PATH}/${ADDON}"
  HAS_FILES=0
  # First check generic files
  if [ -f "${ADDONS_PATH}/${ADDON}/all.tgz" ]; then
    tar -zxf "${ADDONS_PATH}/${ADDON}/all.tgz" -C "${TMP_PATH}/${ADDON}"
    HAS_FILES=1
  fi
  # Now check specific platform files
  if [ -f "${ADDONS_PATH}/${ADDON}/${PLATFORM}-${KVER}.tgz" ]; then
    tar -zxf "${ADDONS_PATH}/${ADDON}/${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/${ADDON}"
    HAS_FILES=1
  fi
  # If has files to copy, copy it, else return error
  [ ${HAS_FILES} -ne 1 ] && return 1
  cp "${TMP_PATH}/${ADDON}/install.sh" "${RAMDISK_PATH}/addons/${ADDON}.sh" 2>"${LOG_FILE}" || dieLog
  chmod +x "${RAMDISK_PATH}/addons/${ADDON}.sh"
  [ -d ${TMP_PATH}/${ADDON}/root ] && (cp -R "${TMP_PATH}/${ADDON}/root/"* "${RAMDISK_PATH}/" 2>"${LOG_FILE}" || dieLog)
  rm -rf "${TMP_PATH}/${ADDON}"
  return 0
}

###############################################################################
# Untar an addon to correct path
# 1 - Addon file path
# Return name of addon on sucess or empty on error
function untarAddon() {
  rm -rf "${TMP_PATH}/addon"
  mkdir -p "${TMP_PATH}/addon"
  tar -xaf "${1}" -C "${TMP_PATH}/addon" || return
  ADDON=`readConfigKey "name" "${TMP_PATH}/addon/manifest.yml"`
  [ -z "${ADDON}" ] && return
  rm -rf "${ADDONS_PATH}/${ADDON}"
  mv "${TMP_PATH}/addon" "${ADDONS_PATH}/${ADDON}"
  echo "${ADDON}"
}
