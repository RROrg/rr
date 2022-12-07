#!/usr/bin/env bash

. /opt/arpl/include/functions.sh

set -e

# Wait kernel enumerate the disks
CNT=3
while true; do
  [ ${CNT} -eq 0 ] && break
  LOADER_DISK="`blkid | grep 'LABEL="ARPL3"' | cut -d3 -f1`"
  [ -n "${LOADER_DISK}" ] && break
  CNT=$((${CNT}-1))
  sleep 1
done
if [ -z "${LOADER_DISK}" ]; then
  die "Loader disk not found!"
fi
NUM_PARTITIONS=$(blkid | grep "${LOADER_DISK}" | cut -d: -f1 | wc -l)
if [ $NUM_PARTITIONS -ne 3 ]; then
  die "Loader disk not found!"
fi

# Shows title
clear
TITLE="Welcome to Automated Redpill Loader v${ARPL_VERSION}"
printf "\033[1;44m%*s\n" $COLUMNS ""
printf "\033[1;44m%*s\033[A\n" $COLUMNS ""
printf "\033[1;32m%*s\033[0m\n" $(((${#TITLE}+$COLUMNS)/2)) "${TITLE}"
printf "\033[1;44m%*s\033[0m\n" $COLUMNS ""

# Check partitions and ignore errors
fsck.vfat -aw ${LOADER_DISK}1 >/dev/null 2>&1 || true
fsck.ext2 -p ${LOADER_DISK}2 >/dev/null 2>&1 || true
fsck.ext2 -p ${LOADER_DISK}3 >/dev/null 2>&1 || true
# Make folders to mount partitions
mkdir -p ${BOOTLOADER_PATH}
mkdir -p ${SLPART_PATH}
mkdir -p ${CACHE_PATH}
mkdir -p ${DSMROOT_PATH}
# Mount the partitions
mount ${LOADER_DISK}1 ${BOOTLOADER_PATH} || die "Can't mount ${BOOTLOADER_PATH}"
mount ${LOADER_DISK}2 ${SLPART_PATH}     || die "Can't mount ${SLPART_PATH}"
mount ${LOADER_DISK}3 ${CACHE_PATH}      || die "Can't mount ${CACHE_PATH}"

# Move/link SSH machine keys to/from cache volume
[ ! -d "${CACHE_PATH}/ssh" ] && cp -R "/etc/ssh" "${CACHE_PATH}/ssh"
rm -rf "/etc/ssh"
ln -s "${CACHE_PATH}/ssh" "/etc/ssh"
# Link bash history to cache volume
rm -rf ~/.bash_history
ln -s ${CACHE_PATH}/.bash_history ~/.bash_history

# Check if exists directories into P3 partition, if yes remove and link it
if [ -d "${CACHE_PATH}/model-configs" ]; then
  rm -rf "${MODEL_CONFIG_PATH}"
  ln -s "${CACHE_PATH}/model-configs" "${MODEL_CONFIG_PATH}"
fi

if [ -d "${CACHE_PATH}/patch" ]; then
  rm -rf "${PATCH_PATH}"
  ln -s "${CACHE_PATH}/patch" "${PATCH_PATH}"
fi

# Get first MAC address
MAC=`ip link show eth0 | awk '/ether/{print$2}'`
MACF=`echo ${MAC} | sed 's/://g'`

# If user config file not exists, initialize it
if [ ! -f "${USER_CONFIG_FILE}" ]; then
  touch "${USER_CONFIG_FILE}"
  writeConfigKey "lkm" "dev" "${USER_CONFIG_FILE}"
  writeConfigKey "directboot" "false" "${USER_CONFIG_FILE}"
  writeConfigKey "model" "" "${USER_CONFIG_FILE}"
  writeConfigKey "build" "" "${USER_CONFIG_FILE}"
  writeConfigKey "sn" "" "${USER_CONFIG_FILE}"
  writeConfigKey "maxdisks" "" "${USER_CONFIG_FILE}"
  writeConfigKey "layout" "qwerty" "${USER_CONFIG_FILE}"
  writeConfigKey "keymap" "" "${USER_CONFIG_FILE}"
  writeConfigKey "zimage-hash" "" "${USER_CONFIG_FILE}"
  writeConfigKey "ramdisk-hash" "" "${USER_CONFIG_FILE}"
  writeConfigKey "cmdline" "{}" "${USER_CONFIG_FILE}"
  writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
  writeConfigKey "addons" "{}" "${USER_CONFIG_FILE}"
  writeConfigKey "addons.misc" "" "${USER_CONFIG_FILE}"
  writeConfigKey "addons.acpid" "" "${USER_CONFIG_FILE}"
  writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
  # Initialize with real MAC
  writeConfigKey "cmdline.netif_num" "1" "${USER_CONFIG_FILE}"
  writeConfigKey "cmdline.mac1" "${MACF}" "${USER_CONFIG_FILE}"
fi
writeConfigKey "original-mac" "${MACF}" "${USER_CONFIG_FILE}"

# Set custom MAC if defined
MAC1=`readConfigKey "cmdline.mac1" "${USER_CONFIG_FILE}"`
if [ -n "${MAC1}" -a "${MAC1}" != "${MACF}" ]; then
  MAC="${MAC1:0:2}:${MAC1:2:2}:${MAC1:4:2}:${MAC1:6:2}:${MAC1:8:2}:${MAC1:10:2}"
  echo "Setting MAC to ${MAC}"
  ip link set dev eth0 address ${MAC} >/dev/null 2>&1 && \
    (/etc/init.d/S41dhcpcd restart >/dev/null 2>&1 &) || true
fi

# Get the VID/PID if we are in USB
VID="0x0000"
PID="0x0000"
BUS=`udevadm info --query property --name ${LOADER_DISK} | grep BUS | cut -d= -f2`
if [ "${BUS}" = "usb" ]; then
  VID="0x`udevadm info --query property --name ${LOADER_DISK} | grep ID_VENDOR_ID | cut -d= -f2`"
  PID="0x`udevadm info --query property --name ${LOADER_DISK} | grep ID_MODEL_ID | cut -d= -f2`"
elif [ "${BUS}" != "ata" ]; then
  die "Loader disk neither USB or DoM"
fi

# Save variables to user config file
writeConfigKey "vid" ${VID} "${USER_CONFIG_FILE}"
writeConfigKey "pid" ${PID} "${USER_CONFIG_FILE}"

# Inform user
echo -en "Loader disk: \033[1;32m${LOADER_DISK}\033[0m ("
if [ "${BUS}" = "usb" ]; then
  echo -en "\033[1;32mUSB flashdisk\033[0m"
else
  echo -en "\033[1;32mSATA DoM\033[0m"
fi
echo ")"

# Check if partition 3 occupies all free space, resize if needed
LOADER_DEVICE_NAME=`echo ${LOADER_DISK} | sed 's|/dev/||'`
SIZEOFDISK=`cat /sys/block/${LOADER_DEVICE_NAME}/size`
ENDSECTOR=$((`fdisk -l ${LOADER_DISK} | awk '/'${LOADER_DEVICE_NAME}3'/{print$3}'`+1))
if [ ${SIZEOFDISK} -ne ${ENDSECTOR} ]; then
  echo -e "\033[1;36mResizing ${LOADER_DISK}3\033[0m"
  echo -e "d\n\nn\n\n\n\n\nn\nw" | fdisk "${LOADER_DISK}" >"${LOG_FILE}" 2>&1 || dieLog
  resize2fs ${LOADER_DISK}3 >"${LOG_FILE}" 2>&1 || dieLog
fi

# Load keymap name
LAYOUT="`readConfigKey "layout" "${USER_CONFIG_FILE}"`"
KEYMAP="`readConfigKey "keymap" "${USER_CONFIG_FILE}"`"

# Loads a keymap if is valid
if [ -f /usr/share/keymaps/i386/${LAYOUT}/${KEYMAP}.map.gz ]; then
  echo -e "Loading keymap \033[1;32m${LAYOUT}/${KEYMAP}\033[0m"
  zcat /usr/share/keymaps/i386/${LAYOUT}/${KEYMAP}.map.gz | loadkeys
fi

# Decide if boot automatically
BOOT=1
if ! loaderIsConfigured; then
  echo -e "\033[1;33mLoader is not configured!\033[0m"
  BOOT=0
elif grep -q "IWANTTOCHANGETHECONFIG" /proc/cmdline; then
  echo -e "\033[1;33mUser requested edit settings.\033[0m"
  BOOT=0
fi

# If is to boot automatically, do it
[ ${BOOT} -eq 1 ] && boot.sh

# Wait for an IP
COUNT=0
echo -n "Waiting IP."
while true; do
  if [ ${COUNT} -eq 30 ]; then
    echo "ERROR"
    break
  fi
  COUNT=$((${COUNT}+1))
  IP=`ip route get 1.1.1.1 2>/dev/null | awk '{print$7}'`
  if [ -n "${IP}" ]; then
    echo -en "OK\nAccess \033[1;34mhttp://${IP}:7681\033[0m to configure the loader via web terminal"
    break
  fi
  echo -n "."
  sleep 1
done

# Inform user
echo
echo -e "Call \033[1;32mmenu.sh\033[0m to configure loader"
echo
echo -e "User config is on \033[1;32m${USER_CONFIG_FILE}\033[0m"
echo -e "Default SSH Root password is \033[1;31mRedp1lL-1s-4weSomE\033[0m"
echo

# Check memory
RAM=`free -m | awk '/Mem:/{print$2}'`
if [ ${RAM} -le 3500 ]; then
  echo -e "\033[1;33mYou have less than 4GB of RAM, if errors occur in loader creation, please increase the amount of memory.\033[0m\n"
fi

mkdir -p "${ADDONS_PATH}"
mkdir -p "${LKM_PATH}"
mkdir -p "${MODULES_PATH}"

install-addons.sh
