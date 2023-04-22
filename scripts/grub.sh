#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
# 
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

ROOT=${1:-"grub"}
GRUB=${2:-"grub-2.06"}
BIOS=${3:-"i386-pc i386-efi x86_64-efi"}

curl -#kLO https://ftp.gnu.org/gnu/grub/${GRUB}.tar.gz
tar zxvf ${GRUB}.tar.gz 
pushd ${GRUB}

for B in ${BIOS}
do
  b=${B}
  b=(${b//-/ })
  echo "Make ${b[@]} ..."

  mkdir -p ${B}
  pushd ${B}
  ../configure --prefix=$PWD/usr -sbindir=$PWD/sbin --sysconfdir=$PWD/etc --disable-werror --target=${b[0]} --with-platform=${b[1]}
  make
  make install
  popd
done
popd


rm -f grub.img
dd if=/dev/zero of=grub.img bs=1M seek=50 count=0
echo -e "n\np\n\n\n\nw\n" | fdisk grub.img
fdisk -l grub.img

LOOPX=`sudo losetup -f`
sudo losetup -P ${LOOPX} grub.img
sudo mkdosfs -F32 -n ARPL1 ${LOOPX}p1

rm -rf ARPL1_MOUNT
mkdir -p ARPL1_MOUNT
sudo mount ${LOOPX}p1 ARPL1_MOUNT

for B in ${BIOS}
do
  args=""
  args+=" --target=${B} --recheck --boot-directory=ARPL1_MOUNT/boot"
  if [[ "${B}" == *"efi" ]]; then
      args+=" --efi-directory=ARPL1_MOUNT --removable --no-nvram"
  else
      args+=" --root-directory=ARPL1_MOUNT"
  fi
  args+=" -s --no-bootsector ${LOOPX}"

  sudo ${GRUB}/${B}/grub-install ${args}
done

if [ -d "ARPL1_MOUNT/boot/grub/fonts" -a -f /usr/share/grub/unicode.pf2 ]; then
  cp /usr/share/grub/unicode.pf2 "ARPL1_MOUNT/boot/grub/fonts"
fi

sync

ROOT="$(readlink -m ${ROOT})"
rm -rf ${ROOT}
mkdir -p ${ROOT}
cp -rf ARPL1_MOUNT/* ${ROOT}

#rm -rf grub.tgz
#tar zcvf grub.tgz -C ${ROOT} .

sudo umount ${LOOPX}p1
sudo losetup -d ${LOOPX}
rm -rf ARPL1_MOUNT grub.img
