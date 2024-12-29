#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

function help() {
  cat <<EOF
Usage: $0 <command> [args]
Commands:
  create [workspace] [rr.img] - Create the workspace
  init - Initialize the environment
  config [model] [version] - Config the DSM system
  build - Build the DSM system
  pack [rr.img] - Pack to rr.img
  help - Show this help
EOF
  exit 1
}

function create() {
  local WORKSPACE RRIMGPATH LOOPX INITRD_FILE INITRD_FORMAT
  WORKSPACE="$(realpath "${1:-workspace}")"
  RRIMGPATH="$(realpath "${2:-rr.img}")"

  if [ ! -f "${RRIMGPATH}" ]; then
    echo "File not found: ${RRIMGPATH}"
    exit 1
  fi

  sudo apt update
  sudo apt install -y locales busybox dialog gettext sed gawk jq curl
  sudo apt install -y python-is-python3 python3-pip libelf-dev qemu-utils cpio xz-utils lz4 lzma bzip2 gzip zstd
  # sudo snap install yq
  if ! command -v yq &>/dev/null || ! yq --version 2>/dev/null | grep -q "v4."; then
    sudo curl -kL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/bin/yq && sudo chmod a+x /usr/bin/yq
  fi

  # Backup the original python3 executable.
  sudo mv -f "$(realpath $(which python3))/EXTERNALLY-MANAGED" "$(realpath $(which python3))/EXTERNALLY-MANAGED.bak" 2>/dev/null || true
  sudo pip3 install -U click requests requests-toolbelt qrcode[pil] beautifulsoup4

  sudo locale-gen ar_SA.UTF-8 de_DE.UTF-8 en_US.UTF-8 es_ES.UTF-8 fr_FR.UTF-8 ja_JP.UTF-8 ko_KR.UTF-8 ru_RU.UTF-8 th_TH.UTF-8 tr_TR.UTF-8 uk_UA.UTF-8 vi_VN.UTF-8 zh_CN.UTF-8 zh_HK.UTF-8 zh_TW.UTF-8

  LOOPX=$(sudo losetup -f)
  sudo losetup -P "${LOOPX}" "${RRIMGPATH}"

  echo "Mounting image file"
  for i in {1..3}; do
    rm -rf "/tmp/mnt/p${i}"
    mkdir -p "/tmp/mnt/p${i}"
    sudo mount "${LOOPX}p${i}" "/tmp/mnt/p${i}" || {
      echo "Can't mount ${LOOPX}p${i}."
      exit 1
    }
  done

  echo "Create WORKSPACE"
  rm -rf "${WORKSPACE}"
  mkdir -p "${WORKSPACE}/mnt" "${WORKSPACE}/tmp" "${WORKSPACE}/initrd"
  cp -rpf /tmp/mnt/p{1,2,3} "${WORKSPACE}/mnt/"

  INITRD_FILE="${WORKSPACE}/mnt/p3/initrd-rr"
  INITRD_FORMAT=$(file -b --mime-type "${INITRD_FILE}")

  case "${INITRD_FORMAT}" in
  *'x-cpio'*) (cd "${WORKSPACE}/initrd" && sudo cpio -idm <"${INITRD_FILE}") >/dev/null 2>&1 ;;
  *'x-xz'*) (cd "${WORKSPACE}/initrd" && xz -dc "${INITRD_FILE}" | sudo cpio -idm) >/dev/null 2>&1 ;;
  *'x-lz4'*) (cd "${WORKSPACE}/initrd" && lz4 -dc "${INITRD_FILE}" | sudo cpio -idm) >/dev/null 2>&1 ;;
  *'x-lzma'*) (cd "${WORKSPACE}/initrd" && lzma -dc "${INITRD_FILE}" | sudo cpio -idm) >/dev/null 2>&1 ;;
  *'x-bzip2'*) (cd "${WORKSPACE}/initrd" && bzip2 -dc "${INITRD_FILE}" | sudo cpio -idm) >/dev/null 2>&1 ;;
  *'gzip'*) (cd "${WORKSPACE}/initrd" && gzip -dc "${INITRD_FILE}" | sudo cpio -idm) >/dev/null 2>&1 ;;
  *'zstd'*) (cd "${WORKSPACE}/initrd" && zstd -dc "${INITRD_FILE}" | sudo cpio -idm) >/dev/null 2>&1 ;;
  *) ;;
  esac

  sudo sync
  for i in {1..3}; do
    sudo umount "/tmp/mnt/p${i}"
    rm -rf "/tmp/mnt/p${i}"
  done
  sudo losetup --detach "${LOOPX}"

  if [ ! -f "${WORKSPACE}/initrd/opt/rr/init.sh" ] || [ ! -f "${WORKSPACE}/initrd/opt/rr/menu.sh" ]; then
    echo "initrd decompression failed."
    exit 1
  fi

  rm -f "$(dirname "${BASH_SOURCE[0]}")/rr.env"
  cat <<EOF >"$(dirname "${BASH_SOURCE[0]}")/rr.env"
export LOADER_DISK="LOCALBUILD"
export CHROOT_PATH="${WORKSPACE}"
EOF
  echo "OK."
}

function init() {
  if [ ! -f "$(dirname "${BASH_SOURCE[0]}")/rr.env" ]; then
    echo "Please run init first"
    exit 1
  fi
  . "$(dirname "${BASH_SOURCE[0]}")/rr.env"
  pushd "${CHROOT_PATH}/initrd/opt/rr" >/dev/null
  echo "init"
  ./init.sh
  local RET=$?
  popd >/dev/null
  [ ${RET} -ne 0 ] && echo "Failed." || echo "Success."
  exit ${RET}
}

function config() {
  if [ ! -f "$(dirname "${BASH_SOURCE[0]}")/rr.env" ]; then
    echo "Please run init first"
    exit 1
  fi
  . "$(dirname "${BASH_SOURCE[0]}")/rr.env"
  local RET=1
  pushd "${CHROOT_PATH}/initrd/opt/rr" >/dev/null
  while true; do
    if [ -z "${1}" ]; then
      echo "menu"
      ./menu.sh || break
      RET=0
    else
      echo "model"
      ./menu.sh modelMenu "${1:-SA6400}" || break
      echo "version"
      ./menu.sh productversMenu "${2:-7.2}" || break
      RET=0
    fi
    break
  done
  popd >/dev/null
  [ ${RET} -ne 0 ] && echo "Failed." || echo "Success."
  exit ${RET}
}

function build() {
  if [ ! -f "$(dirname "${BASH_SOURCE[0]}")/rr.env" ]; then
    echo "Please run init first"
    exit 1
  fi
  . "$(dirname "${BASH_SOURCE[0]}")/rr.env"
  local RET=1
  pushd "${CHROOT_PATH}/initrd/opt/rr" >/dev/null
  while true; do
    echo "build"
    ./menu.sh make -1 || break
    echo "clean"
    ./menu.sh cleanCache -1 || break
    RET=0
    break
  done
  popd >/dev/null
  [ ${RET} -ne 0 ] && echo "Failed." || echo "Success."
  exit ${RET}
}

function pack() {
  if [ ! -f "$(dirname "${BASH_SOURCE[0]}")/rr.env" ]; then
    echo "Please run init first"
    exit 1
  fi
  . "$(dirname "${BASH_SOURCE[0]}")/rr.env"

  local RRIMGPATH LOOPX
  RRIMGPATH="$(realpath "${1:-rr.img}")"
  if [ ! -f "${RRIMGPATH}" ]; then
    gzip -dc "${CHROOT_PATH}/initrd/opt/rr/grub.img.gz" >"${RRIMGPATH}"
  fi
  fdisk -l "${RRIMGPATH}"

  LOOPX=$(sudo losetup -f)
  sudo losetup -P "${LOOPX}" "${RRIMGPATH}"

  echo "Mounting image file"
  for i in {1..3}; do
    rm -rf "/tmp/mnt/p${i}"
    mkdir -p "/tmp/mnt/p${i}"
    sudo mount "${LOOPX}p${i}" "/tmp/mnt/p${i}" || {
      echo "Can't mount ${LOOPX}p${i}."
      exit 1
    }
  done

  echo "Pack image file"
  for i in {1..3}; do
    [ ${i} -eq 1 ] && sudo cp -af "${CHROOT_PATH}/mnt/p${i}/"{.locale,.timezone} "/tmp/mnt/p${i}/" 2>/dev/null
    sudo cp -rf "${CHROOT_PATH}/mnt/p${i}/"* "/tmp/mnt/p${i}" || {
      echo "Can't cp ${LOOPX}p${i}."
      exit 1
    }
  done

  sudo sync
  for i in {1..3}; do
    sudo umount "/tmp/mnt/p${i}"
    rm -rf "/tmp/mnt/p${i}"
  done
  sudo losetup --detach "${LOOPX}"
  echo "OK."
  exit 0
}

$@
