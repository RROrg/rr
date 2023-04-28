#!/usr/bin/env bash
# CONFIG_DIR = .
# $1 = Target path = ./output/target
# BR2_DL_DIR = ./dl
# BINARIES_DIR = ./output/images
# BUILD_DIR = ./output/build
# BASE_DIR = ./output

set -e

# Define some constants
MY_ROOT="${CONFIG_DIR}/.."
IMAGE_FILE="${MY_ROOT}/arpl.img"
BOARD_PATH="${CONFIG_DIR}/board/arpl"

echo "Creating image file"
# unzip base image
gzip -dc "${BOARD_PATH}/grub.img.gz" > "${IMAGE_FILE}"
# fdisk
fdisk -l "${IMAGE_FILE}"
# Find idle of loop device
LOOPX=`sudo losetup -f`
# Setup the ${LOOPX} loop device
sudo losetup -P "${LOOPX}" "${IMAGE_FILE}"

echo "Mounting image file"
mkdir -p "${BINARIES_DIR}/p1"
mkdir -p "${BINARIES_DIR}/p3"
sudo mount ${LOOPX}p1 "${BINARIES_DIR}/p1"
sudo mount ${LOOPX}p3 "${BINARIES_DIR}/p3"

echo "Copying files"
sudo cp "${BINARIES_DIR}/bzImage"            "${BINARIES_DIR}/p3/bzImage-arpl"
sudo cp "${BINARIES_DIR}/rootfs.cpio.xz"     "${BINARIES_DIR}/p3/initrd-arpl"
sudo cp -R "${BOARD_PATH}/p1/"*              "${BINARIES_DIR}/p1"
sudo cp -R "${BOARD_PATH}/p3/"*              "${BINARIES_DIR}/p3"
sync

echo "Unmount image file"
sudo umount "${BINARIES_DIR}/p1"
sudo umount "${BINARIES_DIR}/p3"
rmdir "${BINARIES_DIR}/p1"
rmdir "${BINARIES_DIR}/p3"

sudo losetup --detach ${LOOPX}
