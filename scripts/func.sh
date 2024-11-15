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
    TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/RROrg/rr-buildroot/releases" | jq -r ".[].tag_name" | sort -rV | head -1)
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
    TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/RROrg/rr-cks/releases" | jq -r ".[].tag_name" | sort -rV | head -1)
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
    TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/RROrg/rr-lkms/releases" | jq -r ".[].tag_name" | sort -rV | head -1)
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
    TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/RROrg/rr-addons/releases" | jq -r ".[].tag_name" | sort -rV | head -1)
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
    TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/RROrg/rr-modules/releases" | jq -r ".[].tag_name" | sort -rV | head -1)
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
  INITRD_FORMAT=$(file -b --mime-type "${INITRD_FILE}")
  (
    cd "${RDXZ_PATH}"
    case "${INITRD_FORMAT}" in
    *'x-cpio'*) sudo cpio -idm <"${INITRD_FILE}" ;;
    *'x-xz'*) xz -dc "${INITRD_FILE}" | sudo cpio -idm ;;
    *'x-lz4'*) lz4 -dc "${INITRD_FILE}" | sudo cpio -idm ;;
    *'x-lzma'*) lzma -dc "${INITRD_FILE}" | sudo cpio -idm ;;
    *'x-bzip2'*) bzip2 -dc "${INITRD_FILE}" | sudo cpio -idm ;;
    *'gzip'*) gzip -dc "${INITRD_FILE}" | sudo cpio -idm ;;
    *'zstd'*) zstd -dc "${INITRD_FILE}" | sudo cpio -idm ;;
    *) ;;
    esac
  ) || true
  sudo cp -rf "${PLUGIN_PATH}/"* "${RDXZ_PATH}/"
  [ -f "${OUTPUT_PATH}" ] && rm -rf "${OUTPUT_PATH}"
  (
    cd "${RDXZ_PATH}"
    case "${INITRD_FORMAT}" in
    *'x-cpio'*) sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root >"${OUTPUT_PATH}" ;;
    *'x-xz'*) sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root | xz -9 -C crc32 -c - >"${OUTPUT_PATH}" ;;
    *'x-lz4'*) sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root | lz4 -9 -l -c - >"${OUTPUT_PATH}" ;;
    *'x-lzma'*) sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root | lzma -9 -c - >"${OUTPUT_PATH}" ;;
    *'x-bzip2'*) sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root | bzip2 -9 -c - >"${OUTPUT_PATH}" ;;
    *'gzip'*) sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root | gzip -9 -c - >"${OUTPUT_PATH}" ;;
    *'zstd'*) sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root | zstd -19 -T0 -f -c - >"${OUTPUT_PATH}" ;;
    *) ;;
    esac
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

# convertova
# $1 bootloader file
# $2 ova file
function convertova() {
  BLIMAGE=${1}
  OVAPATH=${2}

  BLIMAGE="$(readlink -f "${BLIMAGE}")"
  OVAPATH="$(readlink -f "${OVAPATH}")"
  VMNAME="$(basename "${OVAPATH}" .ova)"

  # Download and install ovftool if it doesn't exist
  if [ ! -x ovftool/ovftool ]; then
    rm -rf ovftool ovftool.zip
    curl -skL https://github.com/rgl/ovftool-binaries/raw/main/archive/VMware-ovftool-4.6.0-21452615-lin.x86_64.zip -o ovftool.zip
    if [ $? -ne 0 ]; then
      echo "Failed to download ovftool"
      exit 1
    fi
    unzip ovftool.zip -d . >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      echo "Failed to extract ovftool"
      exit 1
    fi
    chmod +x ovftool/ovftool
  fi
  if ! command -v qemu-img &>/dev/null; then
    sudo apt install -y qemu-utils
  fi

  # Convert raw image to VMDK
  rm -rf "OVA_${VMNAME}"
  mkdir -p "OVA_${VMNAME}"
  qemu-img convert -O vmdk -o 'adapter_type=lsilogic,subformat=streamOptimized,compat6' "${BLIMAGE}" "OVA_${VMNAME}/${VMNAME}-disk1.vmdk"
  qemu-img create -f vmdk "OVA_${VMNAME}/${VMNAME}-disk2.vmdk" "32G"

  # Create VM configuration
  cat <<_EOF_ >"OVA_${VMNAME}/${VMNAME}.vmx"
.encoding = "GBK"
config.version = "8"
virtualHW.version = "21"
displayName = "${VMNAME}"
annotation = "https://github.com/RROrg/rr"
guestOS = "ubuntu-64"
firmware = "efi"
mks.enable3d = "TRUE"
pciBridge0.present = "TRUE"
pciBridge4.present = "TRUE"
pciBridge4.virtualDev = "pcieRootPort"
pciBridge4.functions = "8"
pciBridge5.present = "TRUE"
pciBridge5.virtualDev = "pcieRootPort"
pciBridge5.functions = "8"
pciBridge6.present = "TRUE"
pciBridge6.virtualDev = "pcieRootPort"
pciBridge6.functions = "8"
pciBridge7.present = "TRUE"
pciBridge7.virtualDev = "pcieRootPort"
pciBridge7.functions = "8"
vmci0.present = "TRUE"
hpet0.present = "TRUE"
nvram = "${VMNAME}.nvram"
virtualHW.productCompatibility = "hosted"
powerType.powerOff = "soft"
powerType.powerOn = "soft"
powerType.suspend = "soft"
powerType.reset = "soft"
tools.syncTime = "FALSE"
sound.autoDetect = "TRUE"
sound.fileName = "-1"
sound.present = "TRUE"
numvcpus = "2"
cpuid.coresPerSocket = "1"
vcpu.hotadd = "TRUE"
memsize = "4096"
mem.hotadd = "TRUE"
usb.present = "TRUE"
ehci.present = "TRUE"
usb_xhci.present = "TRUE"
svga.graphicsMemoryKB = "8388608"
usb.vbluetooth.startConnected = "TRUE"
extendedConfigFile = "${VMNAME}.vmxf"
floppy0.present = "FALSE"
ethernet0.addressType = "generated"
ethernet0.virtualDev = "vmxnet3"
ethernet0.connectionType = "nat"
ethernet0.allowguestconnectioncontrol = "true"
ethernet0.present = "TRUE"
sata0.present = "TRUE"
sata0:0.fileName = "${VMNAME}-disk1.vmdk"
sata0:0.present = "TRUE"
sata0:1.fileName = "${VMNAME}-disk2.vmdk"
sata0:1.present = "TRUE"
_EOF_

  rm -f "${OVAPATH}"
  ovftool/ovftool "OVA_${VMNAME}/${VMNAME}.vmx" "${OVAPATH}"
  rm -rf "OVA_${VMNAME}"
}
