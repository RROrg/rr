#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# sudo apt update
# sudo apt install -y locales busybox dialog gettext sed gawk jq curl 
# sudo apt install -y python-is-python3 python3-pip libelf-dev qemu-utils cpio xz-utils lz4 lzma bzip2 gzip zstd
# # sudo snap install yq
# if ! command -v yq &>/dev/null || ! yq --version 2>/dev/null | grep -q "v4."; then
#   sudo curl -kL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/bin/yq && sudo chmod a+x /usr/bin/yq
# fi
# 
# # Backup the original python3 executable.
# sudo mv -f "$(realpath $(which python3))/EXTERNALLY-MANAGED" "$(realpath $(which python3))/EXTERNALLY-MANAGED.bak" 2>/dev/null || true
# sudo pip3 install -U click requests requests-toolbelt qrcode[pil] beautifulsoup4
# 
# sudo locale-gen ar_SA.UTF-8 de_DE.UTF-8 en_US.UTF-8 es_ES.UTF-8 fr_FR.UTF-8 ja_JP.UTF-8 ko_KR.UTF-8 ru_RU.UTF-8 th_TH.UTF-8 tr_TR.UTF-8 uk_UA.UTF-8 vi_VN.UTF-8 zh_CN.UTF-8 zh_HK.UTF-8 zh_TW.UTF-8
#
# export TOKEN="${1}"
#

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

. scripts/func.sh "${TOKEN}"

echo "Get extractor"
getCKs "files/mnt/p3/cks" "true"
getLKMs "files/mnt/p3/lkms" "true"
getAddons "files/mnt/p3/addons" "true"
getModules "files/mnt/p3/modules" "true"
getBuildroot "files/mnt/p3" "true"
getExtractor "files/mnt/p3/extractor"

echo "Repack initrd"
convertpo2mo "files/initrd/opt/rr/lang"
repackInitrd "files/mnt/p3/initrd-rr" "files/initrd"

if [ -n "${1}" ]; then
  export LOADER_DISK="LOCALBUILD"
  export CHROOT_PATH="$(realpath files)"
  (
    cd "${CHROOT_PATH}/initrd/opt/rr"
    ./init.sh
    ./menu.sh modelMenu "${1}"
    ./menu.sh productversMenu "${2:-7.2}"
    ./menu.sh make -1
    ./menu.sh cleanCache -1
  )
fi

IMAGE_FILE="rr.img"
gzip -dc "files/initrd/opt/rr/grub.img.gz" >"${IMAGE_FILE}"
fdisk -l "${IMAGE_FILE}"

LOOPX=$(sudo losetup -f)
sudo losetup -P "${LOOPX}" "${IMAGE_FILE}"

for i in {1..3}; do
  [ ! -d "files/mnt/p${i}" ] && continue
  
  rm -rf "/tmp/mnt/p${i}"
  mkdir -p "/tmp/mnt/p${i}"

  echo "Mounting ${LOOPX}p${i}"
  sudo mount "${LOOPX}p${i}" "/tmp/mnt/p${i}" || {
    echo "Can't mount ${LOOPX}p${i}."
    break
  }
  echo "Copying files to ${LOOPX}p${i}"
  [ ${i} -eq 1 ] && sudo cp -af "files/mnt/p${i}/"{.locale,.timezone} "/tmp/mnt/p${i}/" 2>/dev/null || true
  sudo cp -rf "files/mnt/p${i}/"* "/tmp/mnt/p${i}" || true

  sudo sync

  echo "Unmounting ${LOOPX}p${i}"
  sudo umount "/tmp/mnt/p${i}" || {
    echo "Can't umount ${LOOPX}p${i}."
    break
  }
  rm -rf "/tmp/mnt/p${i}"
done

sudo losetup --detach "${LOOPX}"

resizeImg "${IMAGE_FILE}" "+2560M"

# convertova "${IMAGE_FILE}" "${IMAGE_FILE/.img/.ova}"

# update.zip
sha256sum update-list.yml update-check.sh >sha256sum
zip -9j "update.zip" update-list.yml update-check.sh
while read -r F; do
  if [ -d "${F}" ]; then
    FTGZ="$(basename "${F}").tgz"
    tar -zcf "${FTGZ}" -C "${F}" .
    sha256sum "${FTGZ}" >>sha256sum
    zip -9j "update.zip" "${FTGZ}"
    rm -f "${FTGZ}"
  else
    (cd $(dirname "${F}") && sha256sum $(basename "${F}")) >>sha256sum
    zip -9j "update.zip" "${F}"
  fi
done <<<$(yq '.replace | explode(.) | to_entries | map([.key])[] | .[]' update-list.yml)
zip -9j "update.zip" sha256sum
