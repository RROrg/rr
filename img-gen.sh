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
mkdir -p "/tmp/p1"
mkdir -p "/tmp/p3"
sudo mount ${LOOPX}p1 "/tmp/p1"
sudo mount ${LOOPX}p3 "/tmp/p3"

echo "Get Buildroot"
getBuildroot "2023.02.x" "br"
[ ! -f "br/bzImage-rr" -o ! -f "br/initrd-rr" ] && return 1

echo "Repack initrd"
cp -f "br/bzImage-rr" "/tmp/p3/bzImage-rr"
repackInitrd "br/initrd-rr" "files/initrd" "/tmp/p3/initrd-rr"

echo "Copying files"
sudo cp -Rf "files/p1/"* "/tmp/p1"
sudo cp -Rf "files/p3/"* "/tmp/p3"
# Get extractor, LKM, addons and Modules
getLKMs "/tmp/p3/lkms" true
getAddons "/tmp/p3/addons" true
getModules "/tmp/p3/modules" true
getExtractor "/tmp/p3/extractor"

read -p "Press enter to continue"

sync

echo "Unmount image file"
sudo umount "/tmp/p1"
sudo umount "/tmp/p3"
rmdir "/tmp/p1"
rmdir "/tmp/p3"

sudo losetup --detach ${LOOPX}

