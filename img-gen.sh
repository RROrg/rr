#!/usr/bin/env bash

set -e

. scripts/func.sh

if [ ! -d .buildroot ]; then
  echo "Downloading buildroot"
  git clone --single-branch -b 2023.02.x https://github.com/buildroot/buildroot.git .buildroot
fi

# Convert po2mo, Get extractor, LKM, addons and Modules
convertpo2mo "files/board/arpl/overlayfs/opt/arpl/lang"
getExtractor "files/board/arpl/p3/extractor"
getLKMs "files/board/arpl/p3/lkms"
getAddons "files/board/arpl/p3/addons"
getModules "files/board/arpl/p3/modules"

# Remove old files
rm -rf ".buildroot/output/target/opt/arpl"
rm -rf ".buildroot/board/arpl/overlayfs"
rm -rf ".buildroot/board/arpl/p1"
rm -rf ".buildroot/board/arpl/p3"

# Copy files
echo "Copying files"
VERSION=$(cat VERSION)
sed 's/^ARPL_VERSION=.*/ARPL_VERSION="'${VERSION}'"/' -i files/board/arpl/overlayfs/opt/arpl/include/consts.sh
echo "${VERSION}" >files/board/arpl/p1/ARPL-VERSION
cp -Ru files/* .buildroot/

cd .buildroot
echo "Generating default config"
make BR2_EXTERNAL=../external -j$(nproc) arpl_defconfig
echo "Version: ${VERSION}"
echo "Building... Drink a coffee and wait!"
make BR2_EXTERNAL=../external -j$(nproc)
cd -
