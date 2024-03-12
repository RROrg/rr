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
  echo "Usage: $0 <command> [args]"
  echo "Commands:"
  echo "  init [workspace] [rr.img] - Initialize the workspace"
  echo "  config - Configure the workspace"
  echo "  pack [rr.img] - Pack the workspace"
  echo "  help - Show this help"
  exit 1
}

function init() {
  WORKSPACE="$(realpath ${1:-"workspace"})"
  RRIMGPATH="$(realpath ${2:-"rr.img"})"

  if [ ! -f "${RRIMGPATH}" ]; then
    echo "File not found: ${RRIMGPATH}"
    exit 1
  fi

  sudo apt update
  sudo apt install -y locales busybox dialog
  sudo locale-gen en_US.UTF-8 ko_KR.UTF-8 ru_RU.UTF-8 zh_CN.UTF-8 zh_HK.UTF-8 zh_TW.UTF-8

  YQ=$(command -v yq)
  if [ -z "${YQ}" ] || ! ${YQ} --version 2>/dev/null | grep -q "v4."; then
    wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O "${YQ:-"/usr/bin/yq"}" && chmod +x "${YQ:-"/usr/bin/yq"}"
  fi

  LOOPX=$(sudo losetup -f)
  sudo losetup -P "${LOOPX}" "${RRIMGPATH}"

  echo "Mounting image file"
  rm -rf "/tmp/p1"
  rm -rf "/tmp/p2"
  rm -rf "/tmp/p3"
  mkdir -p "/tmp/p1"
  mkdir -p "/tmp/p2"
  mkdir -p "/tmp/p3"
  sudo mount ${LOOPX}p1 "/tmp/p1"
  sudo mount ${LOOPX}p2 "/tmp/p2"
  sudo mount ${LOOPX}p3 "/tmp/p3"

  echo "Create WORKSPACE"
  rm -rf "${WORKSPACE}"
  mkdir -p "${WORKSPACE}/mnt"
  mkdir -p "${WORKSPACE}/tmp"
  mkdir -p "${WORKSPACE}/initrd"
  cp -rf "/tmp/p1" "${WORKSPACE}/mnt/p1"
  cp -rf "/tmp/p2" "${WORKSPACE}/mnt/p2"
  cp -rf "/tmp/p3" "${WORKSPACE}/mnt/p3"
  (
    cd "${WORKSPACE}/initrd"
    xz -dc <"${WORKSPACE}/mnt/p3/initrd-rr" | cpio -idm
  ) 2>/dev/null
  sudo sync
  sudo umount "/tmp/p1"
  sudo umount "/tmp/p2"
  sudo umount "/tmp/p3"
  rm -rf "/tmp/p1"
  rm -rf "/tmp/p2"
  rm -rf "/tmp/p3"
  sudo losetup --detach ${LOOPX}

  rm -f $(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/rr.env
  echo "export LOADER_DISK=\"LOCALBUILD\"" >>$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/rr.env
  echo "export CHROOT_PATH=\"${WORKSPACE}\"" >>$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/rr.env
  echo "OK."
}

function config() {
  if [ ! -f $(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/rr.env ]; then
    echo "Please run init first"
    exit 1
  fi
  . $(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/rr.env
  pushd "${CHROOT_PATH}/initrd/opt/rr"
  ./init.sh
  ./menu.sh
  popd
  echo "OK."
}

function pack() {
  if [ ! -f $(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/rr.env ]; then
    echo "Please run init first"
    exit 1
  fi
  . $(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/rr.env

  RRIMGPATH="$(realpath ${2:-"rr.img"})"
  if [ ! -f "${RRIMGPATH}" ]; then
    gzip -dc "${CHROOT_PATH}/initrd/opt/rr/grub.img.gz" >"${RRIMGPATH}"
  fi
  fdisk -l "${RRIMGPATH}"

  LOOPX=$(sudo losetup -f)
  sudo losetup -P "${LOOPX}" "${RRIMGPATH}"

  echo "Mounting image file"
  rm -rf "/tmp/p1"
  rm -rf "/tmp/p2"
  rm -rf "/tmp/p3"
  mkdir -p "/tmp/p1"
  mkdir -p "/tmp/p2"
  mkdir -p "/tmp/p3"
  sudo mount ${LOOPX}p1 "/tmp/p1"
  sudo mount ${LOOPX}p2 "/tmp/p2"
  sudo mount ${LOOPX}p3 "/tmp/p3"

  echo "Pack image file"
  cp -rf "${CHROOT_PATH}/mnt/p1/"* "/tmp/p1"
  cp -rf "${CHROOT_PATH}/mnt/p2/"* "/tmp/p2"
  cp -rf "${CHROOT_PATH}/mnt/p3/"* "/tmp/p3"
  sudo sync
  sudo umount "/tmp/p1"
  sudo umount "/tmp/p2"
  sudo umount "/tmp/p3"
  rm -rf "/tmp/p1"
  rm -rf "/tmp/p2"
  rm -rf "/tmp/p3"
  sudo losetup --detach ${LOOPX}
  echo "OK."
}

$@