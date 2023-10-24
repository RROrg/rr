#!/usr/bin/env bash

set -e

. scripts/func.sh

# Convert po2mo, Get extractor, LKM, addons and Modules
convertpo2mo "files/initrd/opt/rr/lang"
getExtractor "files/p3/extractor"
getLKMs "files/p3/lkms" true
getAddons "files/p3/addons" true
getModules "files/p3/modules" true


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
cp -f "br/bzImage-rr" "files/p3/bzImage-rr"
repackInitrd "br/initrd-rr" "files/initrd" "files/p3/initrd-rr"

echo "Copying files"
sudo cp -Rf "files/p1/"* "/tmp/p1"
sudo cp -Rf "files/p3/"* "/tmp/p3"
sync

echo "Unmount image file"
sudo umount "/tmp/p1"
sudo umount "/tmp/p3"
rmdir "/tmp/p1"
rmdir "/tmp/p3"

sudo losetup --detach ${LOOPX}

