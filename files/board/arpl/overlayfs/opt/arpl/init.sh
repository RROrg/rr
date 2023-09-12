#!/usr/bin/env bash

set -e

. /opt/arpl/include/functions.sh

# Wait kernel enumerate the disks
CNT=3
while true; do
  [ ${CNT} -eq 0 ] && break
  LOADER_DISK="$(blkid | grep 'LABEL="ARPL3"' | cut -d3 -f1)"
  [ -n "${LOADER_DISK}" ] && break
  CNT=$((${CNT} - 1))
  sleep 1
done

[ -z "${LOADER_DISK}" ] && die "$(TEXT "Loader disk not found!")"
NUM_PARTITIONS=$(blkid | grep "${LOADER_DISK}[0-9]\+" | cut -d: -f1 | wc -l)
[ ${NUM_PARTITIONS} -lt 3 ] && die "$(TEXT "Loader disk seems to be damaged!")"
[ ${NUM_PARTITIONS} -gt 3 ] && die "$(TEXT "There are multiple loader disks, please insert only one loader disk!")"

# Check partitions and ignore errors
fsck.vfat -aw ${LOADER_DISK}1 >/dev/null 2>&1 || true
fsck.ext2 -p ${LOADER_DISK}2 >/dev/null 2>&1 || true
fsck.ext4 -p ${LOADER_DISK}3 >/dev/null 2>&1 || true
# Make folders to mount partitions
mkdir -p ${BOOTLOADER_PATH}
mkdir -p ${SLPART_PATH}
mkdir -p ${CACHE_PATH}
mkdir -p ${DSMROOT_PATH}
# Mount the partitions
mount ${LOADER_DISK}1 ${BOOTLOADER_PATH} || die "$(printf "$(TEXT "Can't mount %s")" "${BOOTLOADER_PATH}")"
mount ${LOADER_DISK}2 ${SLPART_PATH} || die "$(printf "$(TEXT "Can't mount %s")" "${SLPART_PATH}")"
mount ${LOADER_DISK}3 ${CACHE_PATH} || die "$(printf "$(TEXT "Can't mount %s")" "${CACHE_PATH}")"

# Although i18n.sh is included in functions.sh, but i18n.sh dependent ${BOOTLOADER_PATH}/${LOADER_DISK}1, so need to call it again.
. /opt/arpl/include/i18n.sh

# Shows title
clear
TITLE="$(printf "$(TEXT "Welcome to %s")" "${ARPL_TITLE}")"
printf "\033[1;44m%*s\n" ${COLUMNS} ""
printf "\033[1;44m%*s\033[A\n" ${COLUMNS} ""
printf "\033[1;32m%*s\033[0m\n" $(((${#TITLE} + ${COLUMNS}) / 2)) "${TITLE}"
printf "\033[1;44m%*s\033[0m\n" ${COLUMNS} ""

# Move/link SSH machine keys to/from cache volume
[ ! -d "${CACHE_PATH}/ssh" ] && cp -R "/etc/ssh" "${CACHE_PATH}/ssh"
rm -rf "/etc/ssh"
ln -s "${CACHE_PATH}/ssh" "/etc/ssh"
# Link bash history to cache volume
rm -rf ~/.bash_history
ln -s ${CACHE_PATH}/.bash_history ~/.bash_history
touch ~/.bash_history
if ! grep -q "menu.sh" ~/.bash_history; then
  echo "menu.sh " >>~/.bash_history
fi
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
ETHX=($(ls /sys/class/net/ | grep eth)) # real network cards list
# No network devices
[ ${#ETHX[@]} -le 0 ] && die "$(TEXT "Network devices not found!")"

# If user config file not exists, initialize it
if [ ! -f "${USER_CONFIG_FILE}" ]; then
  touch "${USER_CONFIG_FILE}"
  writeConfigKey "lkm" "prod" "${USER_CONFIG_FILE}"
  writeConfigKey "dsmlogo" "true" "${USER_CONFIG_FILE}"
  writeConfigKey "directboot" "false" "${USER_CONFIG_FILE}"
  writeConfigKey "notsetmacs" "false" "${USER_CONFIG_FILE}"
  writeConfigKey "prerelease" "false" "${USER_CONFIG_FILE}"
  writeConfigKey "bootwait" "10" "${USER_CONFIG_FILE}"
  writeConfigKey "bootipwait" "10" "${USER_CONFIG_FILE}"
  writeConfigKey "kernelway" "power" "${USER_CONFIG_FILE}"
  writeConfigKey "odp" "false" "${USER_CONFIG_FILE}"
  writeConfigKey "model" "" "${USER_CONFIG_FILE}"
  writeConfigKey "productver" "" "${USER_CONFIG_FILE}"
  writeConfigKey "buildnum" "" "${USER_CONFIG_FILE}"
  writeConfigKey "smallnum" "" "${USER_CONFIG_FILE}"
  writeConfigKey "paturl" "" "${USER_CONFIG_FILE}"
  writeConfigKey "patsum" "" "${USER_CONFIG_FILE}"
  writeConfigKey "sn" "" "${USER_CONFIG_FILE}"
  # writeConfigKey "maxdisks" "" "${USER_CONFIG_FILE}"
  writeConfigKey "layout" "qwerty" "${USER_CONFIG_FILE}"
  writeConfigKey "keymap" "" "${USER_CONFIG_FILE}"
  writeConfigKey "zimage-hash" "" "${USER_CONFIG_FILE}"
  writeConfigKey "ramdisk-hash" "" "${USER_CONFIG_FILE}"
  writeConfigKey "cmdline" "{}" "${USER_CONFIG_FILE}"
  writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
  writeConfigKey "addons" "{}" "${USER_CONFIG_FILE}"
  writeConfigKey "addons.misc" "" "${USER_CONFIG_FILE}"
  writeConfigKey "addons.acpid" "" "${USER_CONFIG_FILE}"
  writeConfigKey "addons.reboottoarpl" "" "${USER_CONFIG_FILE}"
  writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
  # When the user has not customized, Use 1 to maintain normal startup parameters.
  # writeConfigKey "cmdline.netif_num" "1" "${USER_CONFIG_FILE}"
  # writeConfigKey "cmdline.mac1" "`cat /sys/class/net/${ETHX[0]}/address | sed 's/://g'`" "${USER_CONFIG_FILE}"
fi

for N in $(seq 1 ${#ETHX[@]}); do
  MACR="$(cat /sys/class/net/${ETHX[$(expr ${N} - 1)]}/address | sed 's/://g')"
  # Set custom MAC if defined
  MACF="$(readConfigKey "cmdline.mac${N}" "${USER_CONFIG_FILE}")"
  if [ -n "${MACF}" -a "${MACF}" != "${MACR}" ]; then
    MAC="${MACF:0:2}:${MACF:2:2}:${MACF:4:2}:${MACF:6:2}:${MACF:8:2}:${MACF:10:2}"
    echo "$(printf "$(TEXT "Setting %s MAC to %s")" "${ETHX[$(expr ${N} - 1)]}" "${MAC}")"
    ip link set dev ${ETHX[$(expr ${N} - 1)]} address ${MAC} >/dev/null 2>&1 &&
      (/etc/init.d/S41dhcpcd restart >/dev/null 2>&1 &) || true
  fi
  # Initialize with real MAC
  writeConfigKey "original-mac${N}" "${MACR}" "${USER_CONFIG_FILE}"
  # Enable Wake on Lan, ignore errors
  ethtool -s ${ETHX[$(expr ${N} - 1)]} wol g 2>/dev/null
done

# Get the VID/PID if we are in USB
VID="0x0000"
PID="0x0000"
BUS=$(udevadm info --query property --name ${LOADER_DISK} | grep ID_BUS | cut -d= -f2)
[ "${BUS}" = "ata" ] && BUS="sata"

if [ "${BUS}" = "usb" ]; then
  VID="0x$(udevadm info --query property --name ${LOADER_DISK} | grep ID_VENDOR_ID | cut -d= -f2)"
  PID="0x$(udevadm info --query property --name ${LOADER_DISK} | grep ID_MODEL_ID | cut -d= -f2)"
elif [ "${BUS}" != "sata" -a "${BUS}" != "scsi" ]; then
  die "$(TEXT "Loader disk neither USB or DoM")"
fi

# Save variables to user config file
writeConfigKey "vid" ${VID} "${USER_CONFIG_FILE}"
writeConfigKey "pid" ${PID} "${USER_CONFIG_FILE}"

# Inform user
echo -e "$(TEXT "Loader disk:") \033[1;32m${LOADER_DISK}\033[0m (\033[1;32m${BUS^^} flashdisk\033[0m)"

# Check if partition 3 occupies all free space, resize if needed
LOADER_DEVICE_NAME=$(echo ${LOADER_DISK} | sed 's|/dev/||')
SIZEOFDISK=$(cat /sys/block/${LOADER_DEVICE_NAME}/size)
ENDSECTOR=$(($(fdisk -l ${LOADER_DISK} | awk '/'${LOADER_DEVICE_NAME}3'/{print$3}') + 1))
if [ ${SIZEOFDISK} -ne ${ENDSECTOR} ]; then
  echo -e "\033[1;36m$(printf "$(TEXT "Resizing %s")" "${LOADER_DISK}3")\033[0m"
  echo -e "d\n\nn\n\n\n\n\nn\nw" | fdisk "${LOADER_DISK}" >"${LOG_FILE}" 2>&1 || dieLog
  resize2fs "${LOADER_DISK}3" >"${LOG_FILE}" 2>&1 || dieLog
fi

# Load keymap name
LAYOUT="$(readConfigKey "layout" "${USER_CONFIG_FILE}")"
KEYMAP="$(readConfigKey "keymap" "${USER_CONFIG_FILE}")"

# Loads a keymap if is valid
if [ -f "/usr/share/keymaps/i386/${LAYOUT}/${KEYMAP}.map.gz" ]; then
  echo -e "$(TEXT "Loading keymap") \033[1;32m${LAYOUT}/${KEYMAP}\033[0m"
  zcat "/usr/share/keymaps/i386/${LAYOUT}/${KEYMAP}.map.gz" | loadkeys
fi

# Decide if boot automatically
BOOT=1
if ! loaderIsConfigured; then
  echo -e "\033[1;33m$(TEXT "Loader is not configured!")\033[0m"
  BOOT=0
elif grep -q "IWANTTOCHANGETHECONFIG" /proc/cmdline; then
  echo -e "\033[1;33m$(TEXT "User requested edit settings.")\033[0m"
  BOOT=0
fi

# If is to boot automatically, do it
if [ ${BOOT} -eq 1 ]; then
  boot.sh && exit 0
fi

# Wait for an IP
echo "$(printf "$(TEXT "Detected %s network cards.")" "${#ETHX[@]}")"
echo "$(TEXT "Checking Connect.")"
COUNT=0
while [ ${COUNT} -lt 30 ]; do
  hasConnect="false"
  for N in $(seq 0 $(expr ${#ETHX[@]} - 1)); do
    if ethtool ${ETHX[${N}]} | grep 'Link detected' | grep -q 'yes'; then
      echo -en "${ETHX[${N}]} "
      hasConnect="true"
    fi
  done
  if [ "${hasConnect}" = "true" ]; then
    echo -en "connected.\n"
    break
  fi
  COUNT=$((${COUNT} + 1))
  echo -n "."
  sleep 1
done
echo "$(TEXT "Waiting IP.")"
for N in $(seq 0 $(expr ${#ETHX[@]} - 1)); do
  COUNT=0
  DRIVER=$(ls -ld /sys/class/net/${ETHX[${N}]}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
  echo -en "${ETHX[${N}]}(${DRIVER}): "
  while true; do
    if ! ip link show ${ETHX[${N}]} | grep -q 'UP'; then
      echo -en "\r${ETHX[${N}]}(${DRIVER}): $(TEXT "DOWN")\n"
      break
    fi
    if ethtool ${ETHX[${N}]} | grep 'Link detected' | grep -q 'no'; then
      echo -en "\r${ETHX[${N}]}(${DRIVER}): $(TEXT "NOT CONNECTED")\n"
      break
    fi
    if [ ${COUNT} -eq 15 ]; then
      echo -en "\r${ETHX[${N}]}(${DRIVER}): $(TEXT "TIMEOUT (Please check the IP on the router.)")\n"
      break
    fi
    COUNT=$((${COUNT} + 1))
    IP=$(ip route show dev ${ETHX[${N}]} 2>/dev/null | sed -n 's/.* via .* src \(.*\)  metric .*/\1/p')
    if [ -n "${IP}" ]; then
      echo -en "\r${ETHX[${N}]}(${DRIVER}): $(printf "$(TEXT "Access \033[1;34mhttp://%s:7681\033[0m to configure the loader via web terminal.")" "${IP}")\n"
      break
    fi
    echo -n "."
    sleep 1
  done
done

# Inform user
echo
echo -e "$(TEXT "Call \033[1;32mmenu.sh\033[0m to configure loader")"
echo
echo -e "$(TEXT "User config is on") \033[1;32m${USER_CONFIG_FILE}\033[0m"
echo -e "$(TEXT "Default SSH Root password is") \033[1;31marpl\033[0m"
echo

# Check memory
RAM=$(free -m | awk '/Mem:/{print$2}')
if [ ${RAM} -le 3500 ]; then
  echo -e "\033[1;33m$(TEXT "You have less than 4GB of RAM, if errors occur in loader creation, please increase the amount of memory.")\033[0m\n"
fi

mkdir -p "${ADDONS_PATH}"
mkdir -p "${LKM_PATH}"
mkdir -p "${MODULES_PATH}"

install-addons.sh
