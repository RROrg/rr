#!/usr/bin/env bash

set -e

if [ ! -d .buildroot ]; then
  echo "Downloading buildroot"
  git clone --single-branch -b 2022.02 https://github.com/buildroot/buildroot.git .buildroot
fi
# Remove old files
rm -rf ".buildroot/output/target/opt/arpl"
rm -rf ".buildroot/board/arpl/overlayfs"
rm -rf ".buildroot/board/arpl/p1"
rm -rf ".buildroot/board/arpl/p3"

# Get latest LKMs
echo "Getting latest LKMs"
TAG=`curl -s https://api.github.com/repos/fbelavenuto/redpill-lkm/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`
curl -L "https://github.com/fbelavenuto/redpill-lkm/releases/download/${TAG}/rp-lkms.zip" -o /tmp/rp-lkms.zip
rm -rf files/board/arpl/p3/lkms/*
unzip /tmp/rp-lkms.zip -d files/board/arpl/p3/lkms

# Get latest addons and install its
echo "Getting latest Addons"
mkdir -p /tmp/addons
if [ -d ../arpl-addons ]; then
  cp ../arpl-addons/*.addon /tmp/addons/
else
  TAG=`curl -s https://api.github.com/repos/fbelavenuto/arpl-addons/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`
  curl -L "https://github.com/fbelavenuto/arpl-addons/releases/download/${TAG}/addons.zip" -o /tmp/addons.zip
  rm -rf /tmp/addons
  unzip /tmp/addons.zip -d /tmp/addons
fi
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
VERSION=`cat VERSION`
sed 's/^ARPL_VERSION=.*/ARPL_VERSION="'${VERSION}'"/' -i files/board/arpl/overlayfs/opt/arpl/include/consts.sh
cp -Ru files/* .buildroot/

cd .buildroot
echo "Generating default config"
make arpl_defconfig
echo "Version: ${VERSION}"
echo "Building... Drink a coffee and wait!"
make
cd -
rm -f *.zip
zip -9 "arpl-${VERSION}.img.zip" arpl.img
