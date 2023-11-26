#!/usr/bin/env bash

set -e

. scripts/func.sh

# Convert po2mo
convertpo2mo "files/initrd/opt/rr/lang"

IMAGE_FILE="rr.img"
gzip -dc "files/grub.img.gz" >"${IMAGE_FILE}"
fdisk -l "${IMAGE_FILE}"

LOOPX=$(sudo losetup -f)
sudo losetup -P "${LOOPX}" "${IMAGE_FILE}"

echo "Mounting image file"
sudo rm -rf "/tmp/files/p1"
sudo rm -rf "/tmp/files/p3"
sudo mkdir -p "/tmp/files/p1"
sudo mkdir -p "/tmp/files/p3"
sudo mount ${LOOPX}p1 "/tmp/files/p1"
sudo mount ${LOOPX}p3 "/tmp/files/p3"

echo "Get Buildroot"
[ ! -f "br/bzImage-rr" -o ! -f "br/initrd-rr" ] && getBuildroot "2023.08.x" "br"
[ ! -f "br/bzImage-rr" -o ! -f "br/initrd-rr" ] && return 1

read -p "Press enter to continue"

echo "Repack initrd"
sudo cp -f "br/bzImage-rr" "/tmp/files/p3/bzImage-rr"
repackInitrd "br/initrd-rr" "files/initrd" "/tmp/files/p3/initrd-rr"

echo "Copying files"
sudo cp -Rf "files/p1/"* "/tmp/files/p1"
sudo cp -Rf "files/p3/"* "/tmp/files/p3"
# Get extractor, LKM, addons and Modules
getLKMs "/tmp/files/p3/lkms" true
getAddons "/tmp/files/p3/addons" true
getModules "/tmp/files/p3/modules" true
getExtractor "/tmp/files/p3/extractor"

sync

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
done < <(yq '.replace | explode(.) | to_entries | map([.key])[] | .[]' update-list.yml)
zip -9j update.zip sha256sum


echo "Unmount image file"
sudo umount "/tmp/files/p1"
sudo umount "/tmp/files/p3"

sudo losetup --detach ${LOOPX}
