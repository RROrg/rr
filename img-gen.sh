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
if [ `ls ../redpill-lkm/output | wc -l` -eq 0 ]; then
  echo "  Downloading from github"
  TAG=`curl -s https://api.github.com/repos/fbelavenuto/redpill-lkm/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`
  curl -L "https://github.com/fbelavenuto/redpill-lkm/releases/download/${TAG}/rp-lkms.zip" -o /tmp/rp-lkms.zip
  rm -rf files/board/arpl/p3/lkms/*
  unzip /tmp/rp-lkms.zip -d files/board/arpl/p3/lkms
else
  echo "  Copying from ../redpill-lkm/output"
  rm -rf files/board/arpl/p3/lkms/*
  cp -f ../redpill-lkm/output/* files/board/arpl/p3/lkms
fi

# Get latest addons and install its
echo "Getting latest Addons"
rm -Rf /tmp/addons
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

# Get latest modules
echo "Getting latest modules"
MODULES_DIR="${PWD}/files/board/arpl/p3/modules"
if [ -d ../arpl-modules ]; then
  cd ../arpl-modules
  for D in `ls -d *-*`; do
    echo "${D}"
    (cd ${D} && tar caf "${MODULES_DIR}/${D}.tgz" *.ko)
  done
  (cd firmware && tar caf "${MODULES_DIR}/firmware.tgz" *)
  cd -
else
  TAG=`curl -s https://api.github.com/repos/fbelavenuto/arpl-modules/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`
  while read PLATFORM KVER; do
    FILE="${PLATFORM}-${KVER}"
    curl -L "https://github.com/fbelavenuto/arpl-modules/releases/download/${TAG}/${FILE}.tgz" -o "${MODULES_DIR}/${FILE}.tgz"
  done < PLATFORMS
  curl -L "https://github.com/fbelavenuto/arpl-modules/releases/download/${TAG}/firmware.tgz" -o "${MODULES_DIR}/firmware.tgz"
fi

# Copy files
echo "Copying files"
VERSION=`cat VERSION`
sed 's/^ARPL_VERSION=.*/ARPL_VERSION="'${VERSION}'"/' -i files/board/arpl/overlayfs/opt/arpl/include/consts.sh
echo "${VERSION}" > files/board/arpl/p1/ARPL-VERSION
cp -Ru files/* .buildroot/

cd .buildroot
echo "Generating default config"
make BR2_EXTERNAL=../external -j`nproc` arpl_defconfig
echo "Version: ${VERSION}"
echo "Building... Drink a coffee and wait!"
make BR2_EXTERNAL=../external -j`nproc`
cd -
qemu-img convert -O vmdk arpl.img arpl-dyn.vmdk
qemu-img convert -O vmdk -o adapter_type=lsilogic arpl.img -o subformat=monolithicFlat arpl.vmdk
[ -x test.sh ] && ./test.sh
rm -f *.zip
zip -9 "arpl-${VERSION}.img.zip" arpl.img
zip -9 "arpl-${VERSION}.vmdk-dyn.zip" arpl-dyn.vmdk
zip -9 "arpl-${VERSION}.vmdk-flat.zip" arpl.vmdk arpl-flat.vmdk
sha256sum update-list.yml > sha256sum
yq '.replace | explode(.) | to_entries | map([.key])[] | .[]' update-list.yml | while read F; do
  (cd `dirname ${F}` && sha256sum `basename ${F}`) >> sha256sum
done
yq '.replace | explode(.) | to_entries | map([.key])[] | .[]' update-list.yml | xargs zip -9j "update.zip" sha256sum update-list.yml
rm -f sha256sum
