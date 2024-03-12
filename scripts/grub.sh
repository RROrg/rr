#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# sudo apt update
# sudo apt install -y autoconf automake autopoint gettext build-essential bison flex libtool dosfstools e2fsprogs
#

GRUB=${1:-"grub-2.12"}
BIOS=${2:-"i386-pc i386-efi x86_64-efi"}
NAME=${3:-"RR"}


# Create image
rm -f grub.img
dd if=/dev/zero of=grub.img bs=1M seek=1024 count=0
echo -e "n\np\n1\n\n+50M\nn\np\n2\n\n+50M\nn\np\n3\n\n\na\n1\nw\nq\n" | fdisk grub.img
fdisk -l grub.img

LOOPX=$(sudo losetup -f)
sudo losetup -P ${LOOPX} grub.img
sudo mkdosfs -F32 -n ${NAME}1 ${LOOPX}p1
sudo mkfs.ext2 -F -L ${NAME}2 ${LOOPX}p2
sudo mkfs.ext4 -F -L ${NAME}3 ${LOOPX}p3

rm -rf ${NAME}1
mkdir -p ${NAME}1
sudo mount ${LOOPX}p1 ${NAME}1

sudo mkdir -p ${NAME}1/EFI
sudo mkdir -p ${NAME}1/boot/grub
cat >device.map <<EOF
(hd0)   ${LOOPX}
EOF
# mv: failed to preserve ownership for 'RR1/boot/grub/device.map': Operation not permitted
#
# This problem can actually be ignored. The file has been moved successfully.
#
# This error usually occurs when you try to move a file on a file system that does not support ownership, such as FAT32 or NTFS. 
# On these file systems, the owners and groups of all files are fixed and cannot be changed.
#
# If you need to move files on such a file system, 
# you can use the --no-preserve=ownership option to tell the mv command not to try to preserve ownership of the files.
# 
sudo mv device.map ${NAME}1/boot/grub/device.map


# Install grub
rm -rf grub
git clone --depth=1 -b ${GRUB} https://git.savannah.gnu.org/git/grub.git grub
pushd grub
./bootstrap
./autogen.sh 
popd

for B in ${BIOS}; do
  b=(${B//-/ })
  echo "Make ${B} ..."
  mkdir -p grub/${B}
  RET=0
  pushd grub/${B}
  ../configure --prefix=$PWD/usr -sbindir=$PWD/sbin --sysconfdir=$PWD/etc --disable-werror --target=${b[0]} --with-platform=${b[1]}
  make -j$(nproc) && make -j$(nproc) install
  RET=$?
  popd
  [ ${RET:-0} -ne 0 ] && break

  echo "Install ${B} ..."
  args=""
  args+=" ${LOOPX} --target=${B} --no-floppy --recheck --grub-mkdevicemap=${NAME}1/boot/grub/device.map --boot-directory=${NAME}1/boot"
  if [[ "${B}" == *"efi" ]]; then
    args+=" --efi-directory=${NAME}1 --removable --no-nvram"
  else
    args+=" --root-directory=${NAME}1"
  fi
  sudo grub/${B}/grub-install ${args}
done

if [ -d ${NAME}1/boot/grub/fonts -a -f /usr/share/grub/unicode.pf2 ]; then
  sudo cp /usr/share/grub/unicode.pf2 ${NAME}1/boot/grub/fonts
fi

sudo sync

sudo umount ${LOOPX}p1
sudo losetup -d ${LOOPX}
sudo rm -rf ${NAME}1

rm -f grub.img.gz
gzip grub.img
