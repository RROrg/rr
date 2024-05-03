#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

[ -n "${1}" ] && export TOKEN="${1}"

# Convert po2mo
# $1 path
function convertpo2mo() {
  echo "Convert po2mo begin"
  local DEST_PATH="${1:-lang}"
  for P in $(ls ${DEST_PATH}/*/LC_MESSAGES/rr.po 2>/dev/null); do
    # Use msgfmt command to compile the .po file into a binary .mo file
    echo "msgfmt ${P} to ${P/.po/.mo}"
    msgfmt ${P} -o ${P/.po/.mo}
  done
  echo "Convert po2mo end"
}

# Get extractor
# $1 path
function getExtractor() {
  echo "Getting syno extractor begin"
  local DEST_PATH="${1:-extractor}"
  local CACHE_DIR="/tmp/pat"
  rm -rf "${CACHE_DIR}"
  mkdir -p "${CACHE_DIR}"
  # Download pat file
  # global.synologydownload.com, global.download.synology.com, cndl.synology.cn
  local PAT_URL="https://global.synologydownload.com/download/DSM/release/7.0.1/42218/DSM_DS3622xs%2B_42218.pat"
  local PAT_FILE="DSM_DS3622xs+_42218.pat"
  local STATUS=$(curl -#L -w "%{http_code}" "${PAT_URL}" -o "${CACHE_DIR}/${PAT_FILE}")
  if [ $? -ne 0 -o ${STATUS:-0} -ne 200 ]; then
    echo "[E] DSM_DS3622xs%2B_42218.pat download error!"
    rm -rf ${CACHE_DIR}
    exit 1
  fi

  mkdir -p "${CACHE_DIR}/ramdisk"
  tar -C "${CACHE_DIR}/ramdisk/" -xf "${CACHE_DIR}/${PAT_FILE}" rd.gz 2>&1
  if [ $? -ne 0 ]; then
    echo "[E] extractor rd.gz error!"
    rm -rf ${CACHE_DIR}
    exit 1
  fi
  (
    cd "${CACHE_DIR}/ramdisk"
    xz -dc <rd.gz | cpio -idm
  ) >/dev/null 2>&1 || true

  rm -rf "${DEST_PATH}"
  mkdir -p "${DEST_PATH}"

  # Copy only necessary files
  for f in libcurl.so.4 libmbedcrypto.so.5 libmbedtls.so.13 libmbedx509.so.1 libmsgpackc.so.2 libsodium.so libsynocodesign-ng-virtual-junior-wins.so.7; do
    cp -f "${CACHE_DIR}/ramdisk/usr/lib/${f}" "${DEST_PATH}"
  done
  cp -f "${CACHE_DIR}/ramdisk/usr/syno/bin/scemd" "${DEST_PATH}/syno_extract_system_patch"

  # Clean up
  rm -rf ${CACHE_DIR}
  echo "Getting syno extractor end"
}

# Get latest Buildroot
# $1 path
# $2 (true|false[d]) include prerelease
function getBuildroot() {
  echo "Getting Buildroot begin"
  local DEST_PATH="${1:-buildroot}"
  local CACHE_DIR="/tmp/buildroot"
  local CACHE_FILE="/tmp/buildroot.zip"
  rm -f "${CACHE_FILE}"
  if [ "${2}" = "true" ]; then
    TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/RROrg/rr-buildroot/releases" | jq -r ".[0].tag_name")
  else
    TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/RROrg/rr-buildroot/releases/latest" | jq -r ".tag_name")
  fi
  while read ID NAME; do
    if [ "${NAME}" = "buildroot-${TAG}.zip" ]; then
      STATUS=$(curl -kL -w "%{http_code}" -H "Authorization: token ${TOKEN}" -H "Accept: application/octet-stream" "https://api.github.com/repos/RROrg/rr-buildroot/releases/assets/${ID}" -o "${CACHE_FILE}")
      echo "TAG=${TAG}; Status=${STATUS}"
      [ ${STATUS:-0} -ne 200 ] && exit 1
    fi
  done <<<$(curl -skL -H "Authorization: Bearer ${TOKEN}" "https://api.github.com/repos/RROrg/rr-buildroot/releases/tags/${TAG}" | jq -r '.assets[] | "\(.id) \(.name)"')
  # Unzip Buildroot
  rm -rf "${CACHE_DIR}"
  mkdir -p "${CACHE_DIR}"
  unzip "${CACHE_FILE}" -d "${CACHE_DIR}"
  mkdir -p "${DEST_PATH}"
  mv -f "${CACHE_DIR}/bzImage-rr" "${DEST_PATH}"
  mv -f "${CACHE_DIR}/initrd-rr" "${DEST_PATH}"
  rm -rf "${CACHE_DIR}"
  rm -f "${CACHE_FILE}"
  echo "Getting Buildroot end"
}

# Get latest CKs
# $1 path
# $2 (true|false[d]) include prerelease
function getCKs() {
  echo "Getting CKs begin"
  local DEST_PATH="${1:-cks}"
  local CACHE_FILE="/tmp/rr-cks.zip"
  rm -f "${CACHE_FILE}"
  if [ "${2}" = "true" ]; then
    TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/RROrg/rr-cks/releases" | jq -r ".[0].tag_name")
  else
    TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/RROrg/rr-cks/releases/latest" | jq -r ".tag_name")
  fi
  while read ID NAME; do
    if [ "${NAME}" = "rr-cks-${TAG}.zip" ]; then
      STATUS=$(curl -kL -w "%{http_code}" -H "Authorization: token ${TOKEN}" -H "Accept: application/octet-stream" "https://api.github.com/repos/RROrg/rr-cks/releases/assets/${ID}" -o "${CACHE_FILE}")
      echo "TAG=${TAG}; Status=${STATUS}"
      [ ${STATUS:-0} -ne 200 ] && exit 1
    fi
  done <<<$(curl -skL -H "Authorization: Bearer ${TOKEN}" "https://api.github.com/repos/RROrg/rr-cks/releases/tags/${TAG}" | jq -r '.assets[] | "\(.id) \(.name)"')
  [ ! -f "${CACHE_FILE}" ] && exit 1
  # Unzip CKs
  rm -rf "${DEST_PATH}"
  mkdir -p "${DEST_PATH}"
  unzip "${CACHE_FILE}" -d "${DEST_PATH}"
  rm -f "${CACHE_FILE}"
  echo "Getting CKs end"
}

# Get latest LKMs
# $1 path
# $2 (true|false[d]) include prerelease
function getLKMs() {
  echo "Getting LKMs begin"
  local DEST_PATH="${1:-lkms}"
  local CACHE_FILE="/tmp/rp-lkms.zip"
  rm -f "${CACHE_FILE}"
  if [ "${2}" = "true" ]; then
    TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/RROrg/rr-lkms/releases" | jq -r ".[0].tag_name")
  else
    TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/RROrg/rr-lkms/releases/latest" | jq -r ".tag_name")
  fi
  while read ID NAME; do
    if [ "${NAME}" = "rp-lkms-${TAG}.zip" ]; then
      STATUS=$(curl -kL -w "%{http_code}" -H "Authorization: token ${TOKEN}" -H "Accept: application/octet-stream" "https://api.github.com/repos/RROrg/rr-lkms/releases/assets/${ID}" -o "${CACHE_FILE}")
      echo "TAG=${TAG}; Status=${STATUS}"
      [ ${STATUS:-0} -ne 200 ] && exit 1
    fi
  done <<<$(curl -skL -H "Authorization: Bearer ${TOKEN}" "https://api.github.com/repos/RROrg/rr-lkms/releases/tags/${TAG}" | jq -r '.assets[] | "\(.id) \(.name)"')
  [ ! -f "${CACHE_FILE}" ] && exit 1
  # Unzip LKMs
  rm -rf "${DEST_PATH}"
  mkdir -p "${DEST_PATH}"
  unzip "${CACHE_FILE}" -d "${DEST_PATH}"
  rm -f "${CACHE_FILE}"
  echo "Getting LKMs end"
}

# Get latest addons and install its
# $1 path
# $2 (true|false[d]) include prerelease
function getAddons() {
  echo "Getting Addons begin"
  local DEST_PATH="${1:-addons}"
  local CACHE_DIR="/tmp/addons"
  local CACHE_FILE="/tmp/addons.zip"
  if [ "${2}" = "true" ]; then
    TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/RROrg/rr-addons/releases" | jq -r ".[0].tag_name")
  else
    TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/RROrg/rr-addons/releases/latest" | jq -r ".tag_name")
  fi
  while read ID NAME; do
    if [ "${NAME}" = "addons-${TAG}.zip" ]; then
      STATUS=$(curl -kL -w "%{http_code}" -H "Authorization: token ${TOKEN}" -H "Accept: application/octet-stream" "https://api.github.com/repos/RROrg/rr-addons/releases/assets/${ID}" -o "${CACHE_FILE}")
      echo "TAG=${TAG}; Status=${STATUS}"
      [ ${STATUS:-0} -ne 200 ] && exit 1
    fi
  done <<<$(curl -skL -H "Authorization: Bearer ${TOKEN}" "https://api.github.com/repos/RROrg/rr-addons/releases/tags/${TAG}" | jq -r '.assets[] | "\(.id) \(.name)"')
  [ ! -f "${CACHE_FILE}" ] && exit 1
  rm -rf "${DEST_PATH}"
  mkdir -p "${DEST_PATH}"
  # Install Addons
  rm -rf "${CACHE_DIR}"
  mkdir -p "${CACHE_DIR}"
  unzip "${CACHE_FILE}" -d "${CACHE_DIR}"
  echo "Installing addons to ${DEST_PATH}"
  [ -f /tmp/addons/VERSION ] && cp -f /tmp/addons/VERSION ${DEST_PATH}/
  for PKG in $(ls ${CACHE_DIR}/*.addon 2>/dev/null); do
    ADDON=$(basename "${PKG}" .addon)
    mkdir -p "${DEST_PATH}/${ADDON}"
    echo "Extracting ${PKG} to ${DEST_PATH}/${ADDON}"
    tar -xaf "${PKG}" -C "${DEST_PATH}/${ADDON}"
  done
  rm -rf "${CACHE_DIR}"
  rm -f "${CACHE_FILE}"
  echo "Getting Addons end"
}

# Get latest modules
# $1 path
# $2 (true|false[d]) include prerelease
function getModules() {
  echo "Getting Modules begin"
  local DEST_PATH="${1:-addons}"
  local CACHE_FILE="/tmp/modules.zip"
  rm -f "${CACHE_FILE}"
  if [ "${2}" = "true" ]; then
    TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/RROrg/rr-modules/releases" | jq -r ".[0].tag_name")
  else
    TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/RROrg/rr-modules/releases/latest" | jq -r ".tag_name")
  fi
  while read ID NAME; do
    if [ "${NAME}" = "modules-${TAG}.zip" ]; then
      STATUS=$(curl -kL -w "%{http_code}" -H "Authorization: token ${TOKEN}" -H "Accept: application/octet-stream" "https://api.github.com/repos/RROrg/rr-modules/releases/assets/${ID}" -o "${CACHE_FILE}")
      echo "TAG=${TAG}; Status=${STATUS}"
      [ ${STATUS:-0} -ne 200 ] && exit 1
    fi
  done <<<$(curl -skL -H "Authorization: Bearer ${TOKEN}" "https://api.github.com/repos/RROrg/rr-modules/releases/tags/${TAG}" | jq -r '.assets[] | "\(.id) \(.name)"')
  [ ! -f "${CACHE_FILE}" ] && exit 1
  # Unzip Modules
  rm -rf "${DEST_PATH}"
  mkdir -p "${DEST_PATH}"
  unzip "${CACHE_FILE}" -d "${DEST_PATH}"
  rm -f "${CACHE_FILE}"
  echo "Getting Modules end"
}

# repack initrd
# $1 initrd file
# $2 plugin path
# $3 output file
function repackInitrd() {
  INITRD_FILE="${1}"
  PLUGIN_PATH="${2}"
  OUTPUT_PATH="${3:-${INITRD_FILE}}"

  [ -z "${INITRD_FILE}" -o ! -f "${INITRD_FILE}" ] && exit 1
  [ -z "${PLUGIN_PATH}" -o ! -d "${PLUGIN_PATH}" ] && exit 1

  INITRD_FILE="$(readlink -f "${INITRD_FILE}")"
  PLUGIN_PATH="$(readlink -f "${PLUGIN_PATH}")"
  OUTPUT_PATH="$(readlink -f "${OUTPUT_PATH}")"

  RDXZ_PATH="rdxz_tmp"
  mkdir -p "${RDXZ_PATH}"
  (
    cd "${RDXZ_PATH}"
    sudo xz -dc <"${INITRD_FILE}" | sudo cpio -idm
  ) || true
  sudo cp -Rf "${PLUGIN_PATH}/"* "${RDXZ_PATH}/"
  [ -f "${OUTPUT_PATH}" ] && rm -rf "${OUTPUT_PATH}"
  (
    cd "${RDXZ_PATH}"
    sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root | xz -9 --check=crc32 >"${OUTPUT_PATH}"
  ) || true
  sudo rm -rf "${RDXZ_PATH}"
}

# resizeimg
# $1 input file
# $2 changsize MB eg: +50M -50M
# $3 output file
function resizeImg() {
  INPUT_FILE="${1}"
  CHANGE_SIZE="${2}"
  OUTPUT_FILE="${3:-${INPUT_FILE}}"

  [ -z "${INPUT_FILE}" -o ! -f "${INPUT_FILE}" ] && exit 1
  [ -z "${CHANGE_SIZE}" ] && exit 1

  INPUT_FILE="$(readlink -f "${INPUT_FILE}")"
  OUTPUT_FILE="$(readlink -f "${OUTPUT_FILE}")"

  SIZE=$(($(du -sm "${INPUT_FILE}" 2>/dev/null | awk '{print $1}')$(echo "${CHANGE_SIZE}" | sed 's/M//g; s/b//g')))
  [ "${SIZE:-0}" -lt 0 ] && exit 1

  if [ ! "${INPUT_FILE}" = "${OUTPUT_FILE}" ]; then
    sudo cp -f "${INPUT_FILE}" "${OUTPUT_FILE}"
  fi

  sudo truncate -s ${SIZE}M "${OUTPUT_FILE}"
  echo -e "d\n\nn\n\n\n\n\nn\nw" | sudo fdisk "${OUTPUT_FILE}"
  LOOPX=$(sudo losetup -f)
  sudo losetup -P ${LOOPX} "${OUTPUT_FILE}"
  sudo e2fsck -fp $(ls ${LOOPX}* 2>/dev/null | sort -n | tail -1)
  sudo resize2fs $(ls ${LOOPX}* 2>/dev/null | sort -n | tail -1)
  sudo losetup -d ${LOOPX}
}
