#!/usr/bin/env bash

set -e

. scripts/func.sh


if [ ! -d .buildroot ]; then
  echo "Downloading buildroot"
  git clone --single-branch -b 2022.02 https://github.com/buildroot/buildroot.git .buildroot
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
zip -9 "arpl-i18n-${VERSION}.img.zip" arpl.img
zip -9 "arpl-i18n-${VERSION}.vmdk-dyn.zip" arpl-dyn.vmdk
zip -9 "arpl-i18n-${VERSION}.vmdk-flat.zip" arpl.vmdk arpl-flat.vmdk
sha256sum update-list.yml > sha256sum
zip -9j update.zip update-list.yml
while read F; do
  if [ -d "${F}" ]; then
    FTGZ="`basename "${F}"`.tgz"
    tar czf "${FTGZ}" -C "${F}" .
    sha256sum "${FTGZ}" >> sha256sum
    zip -9j update.zip "${FTGZ}"
    rm "${FTGZ}"
  else
    (cd `dirname ${F}` && sha256sum `basename ${F}`) >> sha256sum
    zip -9j update.zip "${F}"
  fi
done < <(yq '.replace | explode(.) | to_entries | map([.key])[] | .[]' update-list.yml)
zip -9j update.zip sha256sum 
rm -f sha256sum
