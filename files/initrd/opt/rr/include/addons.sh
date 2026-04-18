#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# shellcheck disable=SC2115,SC2155

###############################################################################
# Return list of available addons
# 1 - Platform
# 2 - Kernel Version
function availableAddons() {
  if [ -z "${1}" ] || [ -z "${2}" ]; then
    echo ""
    return 1
  fi
  while read -r D; do
    [ ! -f "${D}/manifest.yml" ] && continue
    local ADDON=$(basename "${D}")
    checkAddonExist "${ADDON}" "${1}" "${2}" || continue
    local SYSTEM=$(readConfigKey "system" "${D}/manifest.yml")
    [ "${SYSTEM}" = "true" ] && continue
    local LOCALE="${LC_ALL%%.*}"
    local DESC=""
    [ -z "${DESC}" ] && DESC="$(readConfigKey "description.${LOCALE:-"en_US"}" "${D}/manifest.yml")"
    [ -z "${DESC}" ] && DESC="$(readConfigKey "description.en_US" "${D}/manifest.yml")"
    [ -z "${DESC}" ] && DESC="$(readConfigKey "description" "${D}/manifest.yml")"

    DESC="$(echo "${DESC}" | tr -d '\n\r\t\\' | sed "s/\"/'/g")"
    echo "${ADDON} \"${DESC:-"unknown"}\""
  done <<<"$(find "${ADDONS_PATH}" -maxdepth 1 -type d 2>/dev/null | sort)"
}

###############################################################################
# Read Addon Key
# 1 - Addon
# 2 - key
function readAddonKey() {
  if [ -z "${1}" ] || [ -z "${2}" ]; then
    echo ""
    return 1
  fi
  if [ ! -f "${ADDONS_PATH}/${1}/manifest.yml" ]; then
    echo ""
    return 1
  fi
  readConfigKey "${2}" "${ADDONS_PATH}/${1}/manifest.yml"
}

###############################################################################
# Check if addon exist
# 1 - Addon id
# 2 - Platform
# 3 - Kernel Version
# Return ERROR if not exists
function checkAddonExist() {
  if [ -z "${1}" ] || [ -z "${2}" ] || [ -z "${3}" ]; then
    return 1 # ERROR
  fi
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
# 2 - Platform
# 3 - Kernel Version
# Return ERROR if not installed
function installAddon() {
  if [ -z "${1}" ]; then
    echo "ERROR: installAddon: Addon not defined"
    return 1
  fi
  local ADDON="${1}"
  mkdir -p "${TMP_PATH}/${ADDON}"
  local HAS_FILES=0
  # First check generic files
  if [ -f "${ADDONS_PATH}/${ADDON}/all.tgz" ]; then
    tar -zxf "${ADDONS_PATH}/${ADDON}/all.tgz" -C "${TMP_PATH}/${ADDON}" 2>"${LOG_FILE}"
    if [ $? -ne 0 ]; then
      return 1
    fi
    HAS_FILES=1
  fi
  # Now check specific platform files
  if [ -f "${ADDONS_PATH}/${ADDON}/${2}-${3}.tgz" ]; then
    tar -zxf "${ADDONS_PATH}/${ADDON}/${2}-${3}.tgz" -C "${TMP_PATH}/${ADDON}" 2>"${LOG_FILE}"
    if [ $? -ne 0 ]; then
      return 1
    fi
    HAS_FILES=1
  fi
  # If has files to copy, copy it, else return error
  if [ ${HAS_FILES} -ne 1 ]; then
    echo "ERROR: installAddon: ${ADDON} addon not found" >"${LOG_FILE}"
    return 1
  fi
  cp -f "${TMP_PATH}/${ADDON}/install.sh" "${RAMDISK_PATH}/addons/${ADDON}.sh" 2>"${LOG_FILE}"
  chmod +x "${RAMDISK_PATH}/addons/${ADDON}.sh"
  [ -d "${TMP_PATH}/${ADDON}/root" ] && cp -rnf "${TMP_PATH}/${ADDON}/root/"* "${RAMDISK_PATH}/" 2>"${LOG_FILE}"
  rm -rf "${TMP_PATH}/${ADDON}"
  return 0
}

###############################################################################
# Untar an addon to correct path
# 1 - Addon file path
# Return name of addon on success or empty on error
function untarAddon() {
  if [ -z "${1}" ]; then
    echo ""
    return 1
  fi
  rm -rf "${TMP_PATH}/addon"
  mkdir -p "${TMP_PATH}/addon"
  tar -xaf "${1}" -C "${TMP_PATH}/addon" || return 1
  local ADDON=$(readConfigKey "name" "${TMP_PATH}/addon/manifest.yml")
  [ -z "${ADDON}" ] && return 1
  rm -rf "${ADDONS_PATH}/${ADDON}"
  mv -f "${TMP_PATH}/addon" "${ADDONS_PATH}/${ADDON}"
  echo "${ADDON}"
  return 0
}
