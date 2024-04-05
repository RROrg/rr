#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# sudo apt update
# sudo apt install -y locales busybox dialog curl xz-utils cpio sed
# sudo locale-gen de_DE.UTF-8 en_US.UTF-8 es_ES.UTF-8 fr_FR.UTF-8 ja_JP.UTF-8 ko_KR.UTF-8 ru_RU.UTF-8 uk_UA.UTF-8 vi_VN.UTF-8 zh_CN.UTF-8 zh_HK.UTF-8 zh_TW.UTF-8
#
# export TOKEN="${1}"
#

set -e

PROMPT=$(sudo -nv 2>&1)
if [ $? -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

PRE="true"

. scripts/func.sh

echo "Get extractor"
getCKs "files/p3/cks" "${PRE}"
getLKMs "files/p3/lkms" "${PRE}"
getAddons "files/p3/addons" "${PRE}"
getModules "files/p3/modules" "${PRE}"
getBuildroot "files/p3" "${PRE}"
getExtractor "files/p3/extractor"

echo "Repack initrd"
convertpo2mo "files/initrd/opt/rr/lang"
repackInitrd "files/p3/initrd-rr" "files/initrd"

if [ -n "${1}" ]; then
  if echo "$(
    cd "files/initrd/opt/rr/model-configs" 2>/dev/null
    ls *.yml 2>/dev/null | cut -d'.' -f1
  )" | grep -q "${1}"; then
    echo "Model found: ${1}"
    export LOADER_DISK="LOCALBUILD"
    export CHROOT_PATH="$(realpath files)"
    (
      cd "${CHROOT_PATH}/initrd/opt/rr"
      # sed -i 's/rd-compressed:.*$/rd-compressed: true/g' "model-configs/${1}.yml"
      ./init.sh
      ./menu.sh modelMenu "${1}"
      ./menu.sh productversMenu "7.2"
      ./menu.sh make -1
      ./menu.sh cleanCache -1
    )
  else
    echo "Model not found: ${1}"
    exit 1
  fi
fi

IMAGE_FILE="rr.img"
gzip -dc "files/grub.img.gz" >"${IMAGE_FILE}"
fdisk -l "${IMAGE_FILE}"

LOOPX=$(sudo losetup -f)
sudo losetup -P "${LOOPX}" "${IMAGE_FILE}"

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
  echo -e "Can't mount ${LOOPX}p1."
  exit 1
)
sudo mount ${LOOPX}p3 "/tmp/mnt/p3" || (
  echo -e "Can't mount ${LOOPX}p1."
  exit 1
)

echo "Copying files"
sudo cp -af "files/mnt/p1/.locale" "/tmp/mnt/p1" 2>/dev/null
sudo cp -rf "files/mnt/p1/"* "/tmp/mnt/p1" || (
  echo -e "Can't cp ${LOOPX}p1."
  exit 1
)
cp -rf "files/mnt/p2/"* "/tmp/mnt/p2" || (
  echo -e "Can't cp ${LOOPX}p1."
  exit 1
)
cp -rf "files/mnt/p3/"* "/tmp/mnt/p3" || (
  echo -e "Can't cp ${LOOPX}p1."
  exit 1
)

sudo sync

# update.zip
sha256sum update-list.yml update-check.sh >sha256sum
zip -9j update.zip update-list.yml update-check.sh
while read F; do
  if [ -d "/tmp/${F}" ]; then
    FTGZ="$(basename "/tmp/${F}").tgz"
    tar -czf "${FTGZ}" -C "/tmp/${F}" .
    sha256sum "${FTGZ}" >>sha256sum
    zip -9j update.zip "${FTGZ}"
    sudo rm -f "${FTGZ}"
  else
    (cd $(dirname "/tmp/${F}") && sha256sum $(basename "/tmp/${F}")) >>sha256sum
    zip -9j update.zip "/tmp/${F}"
  fi
done <<<$(yq '.replace | explode(.) | to_entries | map([.key])[] | .[]' update-list.yml)
zip -9j update.zip sha256sum

echo "Unmount image file"
sudo umount "/tmp/files/p1"
sudo umount "/tmp/files/p2"
sudo umount "/tmp/files/p3"

sudo losetup --detach ${LOOPX}

if [ -n "${1}" ]; then
  echo "Packing image file"
  sudo mv "${IMAGE_FILE}" "rr-${1}.img"
fi
