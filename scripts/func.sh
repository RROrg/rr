#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# sudo apt install -y locales busybox dialog gettext sed gawk jq curl
# sudo apt install -y python-is-python3 python3-pip libelf-dev qemu-utils cpio xz-utils lz4 lzma bzip2 gzip zstd

[ -n "${1}" ] && export TOKEN="${1}"

REPO="https://api.github.com/repos/RROrg"

# Convert po2mo
# $1 path
function convertpo2mo() {
  echo "Convert po2mo begin"
  local DEST_PATH="${1:-lang}"
  while read -r P; do
    # Use msgfmt command to compile the .po file into a binary .mo file
    echo "msgfmt ${P} to ${P/.po/.mo}"
    msgfmt "${P}" -o "${P/.po/.mo}"
  done <<<$(find "${DEST_PATH}" -type f -name 'rr.po')
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
  if [ $? -ne 0 ] || [ "${STATUS:-0}" -ne 200 ]; then
    echo "[E] DSM_DS3622xs%2B_42218.pat download error!"
    rm -rf "${CACHE_DIR}"
    exit 1
  fi

  mkdir -p "${CACHE_DIR}/ramdisk"
  tar -C "${CACHE_DIR}/ramdisk/" -xf "${CACHE_DIR}/${PAT_FILE}" "rd.gz" 2>&1
  if [ $? -ne 0 ]; then
    echo "[E] extractor rd.gz error!"
    rm -rf "${CACHE_DIR}"
    exit 1
  fi
  (cd "${CACHE_DIR}/ramdisk" && xz -dc <"rd.gz" | cpio -idm) >/dev/null 2>&1 || true

  rm -rf "${DEST_PATH}"
  mkdir -p "${DEST_PATH}"

  # Copy only necessary files
  for f in libcurl.so.4 libmbedcrypto.so.5 libmbedtls.so.13 libmbedx509.so.1 libmsgpackc.so.2 libsodium.so libsynocodesign-ng-virtual-junior-wins.so.7; do
    cp -f "${CACHE_DIR}/ramdisk/usr/lib/${f}" "${DEST_PATH}"
  done
  cp -f "${CACHE_DIR}/ramdisk/usr/syno/bin/scemd" "${DEST_PATH}/syno_extract_system_patch"

  # Clean up
  rm -rf "${CACHE_DIR}"
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
  local TAG
  if [ "${2}" = "true" ]; then
    TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "${REPO}/rr-buildroot/releases" | jq -r ".[].tag_name" | sort -rV | head -1)
  else
    TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "${REPO}/rr-buildroot/releases/latest" | jq -r ".tag_name")
  fi
  while read -r ID NAME; do
    if [ "${NAME}" = "buildroot-${TAG}.zip" ]; then
      STATUS=$(curl -kL -w "%{http_code}" -H "Authorization: token ${TOKEN}" -H "Accept: application/octet-stream" "${REPO}/rr-buildroot/releases/assets/${ID}" -o "${CACHE_FILE}")
      echo "TAG=${TAG}; Status=${STATUS}"
      [ ${STATUS:-0} -ne 200 ] && exit 1
    fi
  done <<<$(curl -skL -H "Authorization: Bearer ${TOKEN}" "${REPO}/rr-buildroot/releases/tags/${TAG}" | jq -r '.assets[] | "\(.id) \(.name)"')
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
  local TAG
  if [ "${2}" = "true" ]; then
    TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "${REPO}/rr-cks/releases" | jq -r ".[].tag_name" | sort -rV | head -1)
  else
    TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "${REPO}/rr-cks/releases/latest" | jq -r ".tag_name")
  fi
  while read -r ID NAME; do
    if [ "${NAME}" = "rr-cks-${TAG}.zip" ]; then
      STATUS=$(curl -kL -w "%{http_code}" -H "Authorization: token ${TOKEN}" -H "Accept: application/octet-stream" "${REPO}/rr-cks/releases/assets/${ID}" -o "${CACHE_FILE}")
      echo "TAG=${TAG}; Status=${STATUS}"
      [ ${STATUS:-0} -ne 200 ] && exit 1
    fi
  done <<<$(curl -skL -H "Authorization: Bearer ${TOKEN}" "${REPO}/rr-cks/releases/tags/${TAG}" | jq -r '.assets[] | "\(.id) \(.name)"')
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
  local TAG
  if [ "${2}" = "true" ]; then
    TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "${REPO}/rr-lkms/releases" | jq -r ".[].tag_name" | sort -rV | head -1)
  else
    TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "${REPO}/rr-lkms/releases/latest" | jq -r ".tag_name")
  fi
  while read -r ID NAME; do
    if [ "${NAME}" = "rp-lkms-${TAG}.zip" ]; then
      STATUS=$(curl -kL -w "%{http_code}" -H "Authorization: token ${TOKEN}" -H "Accept: application/octet-stream" "${REPO}/rr-lkms/releases/assets/${ID}" -o "${CACHE_FILE}")
      echo "TAG=${TAG}; Status=${STATUS}"
      [ ${STATUS:-0} -ne 200 ] && exit 1
    fi
  done <<<$(curl -skL -H "Authorization: Bearer ${TOKEN}" "${REPO}/rr-lkms/releases/tags/${TAG}" | jq -r '.assets[] | "\(.id) \(.name)"')
  [ ! -f "${CACHE_FILE}" ] && exit 1
  # Unzip LKMs
  rm -rf "${DEST_PATH}"
  mkdir -p "${DEST_PATH}"
  unzip "${CACHE_FILE}" -d "${DEST_PATH}"
  rm -f "${CACHE_FILE}"
  echo "Getting LKMs end"
}

# Get latest addons and install them
# $1 path
# $2 (true|false[d]) include prerelease
function getAddons() {
  echo "Getting Addons begin"
  local DEST_PATH="${1:-addons}"
  local CACHE_DIR="/tmp/addons"
  local CACHE_FILE="/tmp/addons.zip"
  local TAG
  if [ "${2}" = "true" ]; then
    TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "${REPO}/rr-addons/releases" | jq -r ".[].tag_name" | sort -rV | head -1)
  else
    TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "${REPO}/rr-addons/releases/latest" | jq -r ".tag_name")
  fi
  while read -r ID NAME; do
    if [ "${NAME}" = "addons-${TAG}.zip" ]; then
      STATUS=$(curl -kL -w "%{http_code}" -H "Authorization: token ${TOKEN}" -H "Accept: application/octet-stream" "${REPO}/rr-addons/releases/assets/${ID}" -o "${CACHE_FILE}")
      echo "TAG=${TAG}; Status=${STATUS}"
      [ ${STATUS:-0} -ne 200 ] && exit 1
    fi
  done <<<$(curl -skL -H "Authorization: Bearer ${TOKEN}" "${REPO}/rr-addons/releases/tags/${TAG}" | jq -r '.assets[] | "\(.id) \(.name)"')
  [ ! -f "${CACHE_FILE}" ] && exit 1
  rm -rf "${DEST_PATH}"
  mkdir -p "${DEST_PATH}"
  # Install Addons
  rm -rf "${CACHE_DIR}"
  mkdir -p "${CACHE_DIR}"
  unzip "${CACHE_FILE}" -d "${CACHE_DIR}"
  echo "Installing addons to ${DEST_PATH}"
  [ -f "/tmp/addons/VERSION" ] && cp -f "/tmp/addons/VERSION" "${DEST_PATH}/"
  for PKG in "${CACHE_DIR}"/*.addon; do
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
  local TAG
  if [ "${2}" = "true" ]; then
    TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "${REPO}/rr-modules/releases" | jq -r ".[].tag_name" | sort -rV | head -1)
  else
    TAG=$(curl -skL -H "Authorization: token ${TOKEN}" "${REPO}/rr-modules/releases/latest" | jq -r ".tag_name")
  fi
  while read -r ID NAME; do
    if [ "${NAME}" = "modules-${TAG}.zip" ]; then
      STATUS=$(curl -kL -w "%{http_code}" -H "Authorization: token ${TOKEN}" -H "Accept: application/octet-stream" "${REPO}/rr-modules/releases/assets/${ID}" -o "${CACHE_FILE}")
      echo "TAG=${TAG}; Status=${STATUS}"
      [ ${STATUS:-0} -ne 200 ] && exit 1
    fi
  done <<<$(curl -skL -H "Authorization: Bearer ${TOKEN}" "${REPO}/rr-modules/releases/tags/${TAG}" | jq -r '.assets[] | "\(.id) \(.name)"')
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
  local INITRD_FILE="${1}"
  local PLUGIN_PATH="${2}"
  local OUTPUT_PATH="${3:-${INITRD_FILE}}"

  [ -z "${INITRD_FILE}" ] || [ ! -f "${INITRD_FILE}" ] && exit 1
  [ -z "${PLUGIN_PATH}" ] || [ ! -d "${PLUGIN_PATH}" ] && exit 1

  INITRD_FILE="$(realpath "${INITRD_FILE}")"
  PLUGIN_PATH="$(realpath "${PLUGIN_PATH}")"
  OUTPUT_PATH="$(realpath "${OUTPUT_PATH}")"

  local RDXZ_PATH="rdxz_tmp"
  mkdir -p "${RDXZ_PATH}"
  local INITRD_FORMAT=$(file -b --mime-type "${INITRD_FILE}")

  case "${INITRD_FORMAT}" in
  *'x-cpio'*) (cd "${RDXZ_PATH}" && sudo cpio -idm <"${INITRD_FILE}") >/dev/null 2>&1 ;;
  *'x-xz'*) (cd "${RDXZ_PATH}" && xz -dc "${INITRD_FILE}" | sudo cpio -idm) >/dev/null 2>&1 ;;
  *'x-lz4'*) (cd "${RDXZ_PATH}" && lz4 -dc "${INITRD_FILE}" | sudo cpio -idm) >/dev/null 2>&1 ;;
  *'x-lzma'*) (cd "${RDXZ_PATH}" && lzma -dc "${INITRD_FILE}" | sudo cpio -idm) >/dev/null 2>&1 ;;
  *'x-bzip2'*) (cd "${RDXZ_PATH}" && bzip2 -dc "${INITRD_FILE}" | sudo cpio -idm) >/dev/null 2>&1 ;;
  *'gzip'*) (cd "${RDXZ_PATH}" && gzip -dc "${INITRD_FILE}" | sudo cpio -idm) >/dev/null 2>&1 ;;
  *'zstd'*) (cd "${RDXZ_PATH}" && zstd -dc "${INITRD_FILE}" | sudo cpio -idm) >/dev/null 2>&1 ;;
  *) ;;
  esac

  sudo cp -rf "${PLUGIN_PATH}/"* "${RDXZ_PATH}/"
  [ -f "${OUTPUT_PATH}" ] && rm -rf "${OUTPUT_PATH}"

  case "${INITRD_FORMAT}" in
  *'x-cpio'*) (cd "${RDXZ_PATH}" && sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root >"${OUTPUT_PATH}") >/dev/null 2>&1 ;;
  *'x-xz'*) (cd "${RDXZ_PATH}" && sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root | xz -9 -C crc32 -c - >"${OUTPUT_PATH}") >/dev/null 2>&1 ;;
  *'x-lz4'*) (cd "${RDXZ_PATH}" && sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root | lz4 -9 -l -c - >"${OUTPUT_PATH}") >/dev/null 2>&1 ;;
  *'x-lzma'*) (cd "${RDXZ_PATH}" && sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root | lzma -9 -c - >"${OUTPUT_PATH}") >/dev/null 2>&1 ;;
  *'x-bzip2'*) (cd "${RDXZ_PATH}" && sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root | bzip2 -9 -c - >"${OUTPUT_PATH}") >/dev/null 2>&1 ;;
  *'gzip'*) (cd "${RDXZ_PATH}" && sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root | gzip -9 -c - >"${OUTPUT_PATH}") >/dev/null 2>&1 ;;
  *'zstd'*) (cd "${RDXZ_PATH}" && sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root | zstd -19 -T0 -f -c - >"${OUTPUT_PATH}") >/dev/null 2>&1 ;;
  *) ;;
  esac
  sudo rm -rf "${RDXZ_PATH}"
}

# resizeimg
# $1 input file
# $2 changsize MB eg: +50M -50M
# $3 output file
function resizeImg() {
  local INPUT_FILE="${1}"
  local CHANGE_SIZE="${2}"
  local OUTPUT_FILE="${3:-${INPUT_FILE}}"

  [ -z "${INPUT_FILE}" ] || [ ! -f "${INPUT_FILE}" ] && exit 1
  [ -z "${CHANGE_SIZE}" ] && exit 1

  INPUT_FILE="$(realpath "${INPUT_FILE}")"
  OUTPUT_FILE="$(realpath "${OUTPUT_FILE}")"

  local SIZE=$(($(du -sm "${INPUT_FILE}" 2>/dev/null | awk '{print $1}')$(echo "${CHANGE_SIZE}" | sed 's/M//g; s/b//g')))
  [ "${SIZE:-0}" -lt 0 ] && exit 1

  if [ ! "${INPUT_FILE}" = "${OUTPUT_FILE}" ]; then
    sudo cp -f "${INPUT_FILE}" "${OUTPUT_FILE}"
  fi

  sudo truncate -s ${SIZE}M "${OUTPUT_FILE}"
  echo -e "d\n\nn\n\n\n\n\nn\nw" | sudo fdisk "${OUTPUT_FILE}" >/dev/null 2>&1
  local LOOPX=$(sudo losetup -f)
  sudo losetup -P ${LOOPX} "${OUTPUT_FILE}"
  sudo e2fsck -fp $(ls ${LOOPX}* 2>/dev/null | sort -n | tail -1)
  sudo resize2fs $(ls ${LOOPX}* 2>/dev/null | sort -n | tail -1)
  sudo losetup -d ${LOOPX}
}

# createvmx
# $1 bootloader file
# $2 vmx name
function createvmx() {
  BLIMAGE=${1}
  VMNAME=${2}

  if ! command -v qemu-img &>/dev/null; then
    sudo apt install -y qemu-utils
  fi

  # Convert raw image to VMDK
  rm -rf "VMX_${VMNAME}"
  mkdir -p "VMX_${VMNAME}"
  qemu-img convert -O vmdk -o 'adapter_type=lsilogic,subformat=streamOptimized,compat6' "${BLIMAGE}" "VMX_${VMNAME}/${VMNAME}-disk1.vmdk"
  qemu-img create -f vmdk "VMX_${VMNAME}/${VMNAME}-disk2.vmdk" "32G"

  # Create VM configuration
  cat <<_EOF_ >"VMX_${VMNAME}/${VMNAME}.vmx"
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "17"
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
serial0.fileType = "file"
serial0.fileName = "serial0.log"
serial0.present = "TRUE"
sata0.present = "TRUE"
sata0:0.fileName = "${VMNAME}-disk1.vmdk"
sata0:0.present = "TRUE"
sata0:1.fileName = "${VMNAME}-disk2.vmdk"
sata0:1.present = "TRUE"
_EOF_

}

# convertvmx
# $1 bootloader file
# $2 vmx file
function convertvmx() {
  local BLIMAGE=${1}
  local VMXPATH=${2}

  BLIMAGE="$(realpath "${BLIMAGE}")"
  VMXPATH="$(realpath "${VMXPATH}")"
  local VMNAME="$(basename "${VMXPATH}" .vmx)"

  createvmx "${BLIMAGE}" "${VMNAME}"

  rm -rf "${VMXPATH}"
  mv -f "VMX_${VMNAME}" "${VMXPATH}"
}

# convertova
# $1 bootloader file
# $2 ova file
function convertova() {
  local BLIMAGE=${1}
  local OVAPATH=${2}

  BLIMAGE="$(realpath "${BLIMAGE}")"
  OVAPATH="$(realpath "${OVAPATH}")"
  local VMNAME="$(basename "${OVAPATH}" .ova)"

  createvmx "${BLIMAGE}" "${VMNAME}"

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

  rm -f "${OVAPATH}"
  ovftool/ovftool "VMX_${VMNAME}/${VMNAME}.vmx" "${OVAPATH}"
  rm -rf "VMX_${VMNAME}"
}

# createvmc
# $1 vhd file
# $2 vmc file
function createvmc() {
  local BLIMAGE=${1:-rr.vhd}
  local VMCPATH=${2:-rr.vmc}

  BLIMAGE="$(basename "${BLIMAGE}")"
  VMCPATH="$(realpath "${VMCPATH}")"

  cat <<_EOF_ >"${VMCPATH}"
<?xml version="1.0" encoding="UTF-8"?>
<preferences>
    <version type="string">2.0</version>
    <hardware>
        <memory>
          <ram_size type="integer">4096</ram_size>
        </memory>
        <pci_bus>
            <ide_adapter>
                <ide_controller id="0">
                    <location id="0">
                        <drive_type type="integer">1</drive_type>
                        <pathname>
                            <relative type="string">${BLIMAGE}</relative>
                        </pathname>
                    </location>
                </ide_controller>
            </ide_adapter>
        </pci_bus>
    </hardware>
</preferences>
_EOF_
}
