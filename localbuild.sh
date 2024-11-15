#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

PROMPT=$(sudo -nv 2>&1)
if [ $? -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

function help() {
  echo "Usage: $0 <command> [args]"
  echo "Commands:"
  echo "  create [workspace] [rr.img] - Create the workspace"
  echo "  init - Initialize the environment"
  echo "  config [model] [version] - Config the DSM system"
  echo "  build - Build the DSM system"
  echo "  pack [rr.img] - Pack to rr.img"
  echo "  help - Show this help"
  exit 1
}

function create() {
  WORKSPACE="$(realpath ${1:-"workspace"})"
  RRIMGPATH="$(realpath ${2:-"rr.img"})"

  if [ ! -f "${RRIMGPATH}" ]; then
    echo "File not found: ${RRIMGPATH}"
    exit 1
  fi

  sudo apt update
  sudo apt install -y locales busybox dialog curl xz-utils cpio sed qemu-utils
  sudo pip install bs4
  sudo locale-gen ar_SA.UTF-8 de_DE.UTF-8 en_US.UTF-8 es_ES.UTF-8 fr_FR.UTF-8 ja_JP.UTF-8 ko_KR.UTF-8 ru_RU.UTF-8 th_TH.UTF-8 tr_TR.UTF-8 uk_UA.UTF-8 vi_VN.UTF-8 zh_CN.UTF-8 zh_HK.UTF-8 zh_TW.UTF-8

  YQ=$(command -v yq)
  if [ -z "${YQ}" ] || ! ${YQ} --version 2>/dev/null | grep -q "v4."; then
    wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O "${YQ:-"/usr/bin/yq"}" && chmod +x "${YQ:-"/usr/bin/yq"}"
  fi

  LOOPX=$(sudo losetup -f)
  sudo losetup -P "${LOOPX}" "${RRIMGPATH}"

  echo "Mounting image file"
  rm -rf "/tmp/mnt/p1"
  rm -rf "/tmp/mnt/p2"
  rm -rf "/tmp/mnt/p3"
  mkdir -p "/tmp/mnt/p1"
  mkdir -p "/tmp/mnt/p2"
  mkdir -p "/tmp/mnt/p3"
  sudo mount ${LOOPX}p1 "/tmp/mnt/p1" || (
    echo -e "Can't mount ${LOOPX}p1."
    exit 1
  )

  sudo mount ${LOOPX}p2 "/tmp/mnt/p2" || (
    echo -e "Can't mount ${LOOPX}p2."
    exit 1
  )
  sudo mount ${LOOPX}p3 "/tmp/mnt/p3" || (
    echo -e "Can't mount ${LOOPX}p3."
    exit 1
  )

  echo "Create WORKSPACE"
  rm -rf "${WORKSPACE}"
  mkdir -p "${WORKSPACE}/mnt"
  mkdir -p "${WORKSPACE}/tmp"
  mkdir -p "${WORKSPACE}/initrd"
  cp -rf "/tmp/mnt/p1" "${WORKSPACE}/mnt/p1"
  cp -rf "/tmp/mnt/p2" "${WORKSPACE}/mnt/p2"
  cp -rf "/tmp/mnt/p3" "${WORKSPACE}/mnt/p3"

  INITRD_FILE="${WORKSPACE}/mnt/p3/initrd-rr"
  INITRD_FORMAT=$(file -b --mime-type "${INITRD_FILE}")
  (
    cd "${WORKSPACE}/initrd"
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
  ) 2>/dev/null
  sudo sync
  sudo umount "/tmp/mnt/p1"
  sudo umount "/tmp/mnt/p2"
  sudo umount "/tmp/mnt/p3"
  rm -rf "/tmp/mnt/p1"
  rm -rf "/tmp/mnt/p2"
  rm -rf "/tmp/mnt/p3"
  sudo losetup --detach ${LOOPX}

  if [ ! -f "${WORKSPACE}/initrd/opt/rr/init.sh" ] || ! [ -f "${WORKSPACE}/initrd/opt/rr/menu.sh" ]; then
    echo "initrd decompression failed."
    exit 1
  fi

  rm -f $(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/rr.env
  echo "export LOADER_DISK=\"LOCALBUILD\"" >>$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/rr.env
  echo "export CHROOT_PATH=\"${WORKSPACE}\"" >>$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/rr.env
  echo "OK."
}

function init() {
  if [ ! -f $(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/rr.env ]; then
    echo "Please run init first"
    exit 1
  fi
  . $(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/rr.env
  pushd "${CHROOT_PATH}/initrd/opt/rr"
  echo "init"
  ./init.sh
  RET=$?
  popd
  [ ${RET} -ne 0 ] && echo "Failed." || echo "Success."
  return ${RET}
}

function config() {
  if [ ! -f $(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/rr.env ]; then
    echo "Please run init first"
    exit 1
  fi
  . $(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/rr.env
  RET=1
  pushd "${CHROOT_PATH}/initrd/opt/rr"
  while true; do
    if [ -z "${1}" ]; then
      echo "menu"
      ./menu.sh || break
      RET=0
    else
      echo "model"
      ./menu.sh modelMenu "${1:-"SA6400"}" || break
      echo "version"
      ./menu.sh productversMenu "${2:-"7.2"}" || break
      RET=0
    fi
    break
  done
  popd
  [ ${RET} -ne 0 ] && echo "Failed." || echo "Success."
  return ${RET}
}

function build() {
  if [ ! -f $(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/rr.env ]; then
    echo "Please run init first"
    exit 1
  fi
  . $(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/rr.env
  RET=1
  pushd "${CHROOT_PATH}/initrd/opt/rr"
  while true; do
    echo "build"
    ./menu.sh make -1 || break
    echo "clean"
    ./menu.sh cleanCache -1 || break
    RET=0
    break
  done
  popd
  [ ${RET} -ne 0 ] && echo "Failed." || echo "Success."
  return ${RET}
}

function pack() {
  if [ ! -f $(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/rr.env ]; then
    echo "Please run init first"
    exit 1
  fi
  . $(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/rr.env

  RRIMGPATH="$(realpath ${1:-"rr.img"})"
  if [ ! -f "${RRIMGPATH}" ]; then
    gzip -dc "${CHROOT_PATH}/initrd/opt/rr/grub.img.gz" >"${RRIMGPATH}"
  fi
  fdisk -l "${RRIMGPATH}"

  LOOPX=$(sudo losetup -f)
  sudo losetup -P "${LOOPX}" "${RRIMGPATH}"

  echo "Mounting image file"
  rm -rf "/tmp/mnt/p1"
  rm -rf "/tmp/mnt/p2"
  rm -rf "/tmp/mnt/p3"
  mkdir -p "/tmp/mnt/p1"
  mkdir -p "/tmp/mnt/p2"
  mkdir -p "/tmp/mnt/p3"
  sudo mount ${LOOPX}p1 "/tmp/mnt/p1" || (
    echo -e "Can't mount ${LOOPX}p1."
    exit 1
  )
  sudo mount ${LOOPX}p2 "/tmp/mnt/p2" || (
    echo -e "Can't mount ${LOOPX}p2."
    exit 1
  )
  sudo mount ${LOOPX}p3 "/tmp/mnt/p3" || (
    echo -e "Can't mount ${LOOPX}p3."
    exit 1
  )

  echo "Pack image file"
  sudo cp -af "${CHROOT_PATH}/mnt/p1/.locale" "/tmp/mnt/p1" 2>/dev/null
  sudo cp -rf "${CHROOT_PATH}/mnt/p1/"* "/tmp/mnt/p1" || (
    echo -e "Can't cp ${LOOPX}p1."
    exit 1
  )
  sudo cp -rf "${CHROOT_PATH}/mnt/p2/"* "/tmp/mnt/p2" || (
    echo -e "Can't cp ${LOOPX}p2."
    exit 1
  )
  sudo cp -rf "${CHROOT_PATH}/mnt/p3/"* "/tmp/mnt/p3" || (
    echo -e "Can't cp ${LOOPX}p3."
    exit 1
  )
  sudo sync
  sudo umount "/tmp/mnt/p1"
  sudo umount "/tmp/mnt/p2"
  sudo umount "/tmp/mnt/p3"
  rm -rf "/tmp/mnt/p1"
  rm -rf "/tmp/mnt/p2"
  rm -rf "/tmp/mnt/p3"
  sudo losetup --detach ${LOOPX}
  echo "OK."
}

$@
