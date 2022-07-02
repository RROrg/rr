#!/usr/bin/env bash

set -e

BR_VER="buildroot-2022.02.2"
if [ ! -d "${BR_VER}" ]; then
  echo "Downloading buildroot"
  curl -LO "https://buildroot.org/downloads/${BR_VER}.tar.gz"
  echo "Extracting buildroot"
  tar xf "${BR_VER}.tar.gz"
  rm "${BR_VER}.tar.gz"
fi
# Remove old files
rm -rf "${BR_VER}/output/target/opt/arpl"
rm -rf "${BR_VER}/board/arpl/overlayfs"
rm -rf "${BR_VER}/board/arpl/p1"
rm -rf "${BR_VER}/board/arpl/p3"

# Get latest LKMs
echo "Getting latest LKMs"
TAG=`curl -s https://api.github.com/repos/fbelavenuto/redpill-lkm/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`
curl -L "https://github.com/fbelavenuto/redpill-lkm/releases/download/${TAG}/rp-lkms.zip" -o /tmp/rp-lkms.zip
rm -rf files/board/arpl/p3/lkms/*
unzip /tmp/rp-lkms.zip -d files/board/arpl/p3/lkms

# Get latest addons and install its
echo "Getting latest Addons"
TAG=`curl -s https://api.github.com/repos/fbelavenuto/arpl-addons/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`
curl -L "https://github.com/fbelavenuto/arpl-addons/releases/download/${TAG}/addons.zip" -o /tmp/addons.zip
rm -rf /tmp/addons
mkdir -p /tmp/addons
unzip /tmp/addons.zip -d /tmp/addons
DEST_PATH="files/board/arpl/p3/addons"
echo "Installing addons to ${DEST_PATH}"
for PKG in `ls /tmp/addons/*.addon`; do
  ADDON=`basename ${PKG} | sed 's|.addon||'`
  mkdir -p "${DEST_PATH}/${ADDON}"
  echo "Extracting ${PKG} to ${DEST_PATH}/${ADDON}"
  tar xaf "${PKG}" -C "${DEST_PATH}/${ADDON}"
done

# Copy files
echo "Copying files"
cp -Ru files/* "${BR_VER}/"
VERSION=`cat VERSION`
sed 's/^ARPL_VERSION=.*/ARPL_VERSION="'${VERSION}'"/' -i files/board/arpl/overlayfs/opt/arpl/include/consts.sh

cd "${BR_VER}"
echo "Generating default config"
make arpl_defconfig
echo "Version: ${VERSION}"
echo "Building... Drink a coffee and wait!"
make
cd -
rm -f *.zip
zip -9 "arpl-${VERSION}.img.zip" arpl.img
