#!/usr/bin/env bash

set -e
[ -z "${WORK_PATH}" -o ! -d "${WORK_PATH}/include" ] && WORK_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. ${WORK_PATH}/include/functions.sh
. ${WORK_PATH}/include/addons.sh

[ -z "${LOADER_DISK}" ] && die "$(TEXT "Loader is not init!")"

# Shows title
clear
[ -z "${COLUMNS}" ] && COLUMNS=50
TITLE="$(printf "$(TEXT "Welcome to %s")" "${RR_TITLE}")"
printf "\033[1;44m%*s\n" ${COLUMNS} ""
printf "\033[1;44m%*s\033[A\n" ${COLUMNS} ""
printf "\033[1;32m%*s\033[0m\n" $(((${#TITLE} + ${COLUMNS}) / 2)) "${TITLE}"
printf "\033[1;44m%*s\033[0m\n" ${COLUMNS} ""

# Get first MAC address
ETHX=$(ls /sys/class/net/ | grep -v lo) || true
# No network devices
[ $(echo ${ETHX} | wc -w) -le 0 ] && die "$(TEXT "Network devices not found!")"

# If user config file not exists, initialize it
if [ ! -f "${USER_CONFIG_FILE}" ]; then
  touch "${USER_CONFIG_FILE}"
fi
initConfigKey "lkm" "prod" "${USER_CONFIG_FILE}"
initConfigKey "dsmlogo" "true" "${USER_CONFIG_FILE}"
initConfigKey "directboot" "false" "${USER_CONFIG_FILE}"
initConfigKey "prerelease" "false" "${USER_CONFIG_FILE}"
initConfigKey "bootwait" "10" "${USER_CONFIG_FILE}"
initConfigKey "bootipwait" "10" "${USER_CONFIG_FILE}"
initConfigKey "kernelway" "power" "${USER_CONFIG_FILE}"
initConfigKey "kernelpanic" "5" "${USER_CONFIG_FILE}"
initConfigKey "odp" "false" "${USER_CONFIG_FILE}"
initConfigKey "hddsort" "false" "${USER_CONFIG_FILE}"
initConfigKey "model" "" "${USER_CONFIG_FILE}"
initConfigKey "productver" "" "${USER_CONFIG_FILE}"
initConfigKey "buildnum" "" "${USER_CONFIG_FILE}"
initConfigKey "smallnum" "" "${USER_CONFIG_FILE}"
initConfigKey "paturl" "" "${USER_CONFIG_FILE}"
initConfigKey "patsum" "" "${USER_CONFIG_FILE}"
initConfigKey "sn" "" "${USER_CONFIG_FILE}"
initConfigKey "mac1" "" "${USER_CONFIG_FILE}"
initConfigKey "mac2" "" "${USER_CONFIG_FILE}"
# initConfigKey "maxdisks" "" "${USER_CONFIG_FILE}"
initConfigKey "layout" "qwerty" "${USER_CONFIG_FILE}"
initConfigKey "keymap" "" "${USER_CONFIG_FILE}"
initConfigKey "zimage-hash" "" "${USER_CONFIG_FILE}"
initConfigKey "ramdisk-hash" "" "${USER_CONFIG_FILE}"
initConfigKey "cmdline" "{}" "${USER_CONFIG_FILE}"
initConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
initConfigKey "addons" "{}" "${USER_CONFIG_FILE}"
initConfigKey "addons.misc" "" "${USER_CONFIG_FILE}"
initConfigKey "addons.acpid" "" "${USER_CONFIG_FILE}"
initConfigKey "addons.reboottoloader" "" "${USER_CONFIG_FILE}"
initConfigKey "modules" "{}" "${USER_CONFIG_FILE}"

# _sort_netif "$(readConfigKey "addons.sortnetif" "${USER_CONFIG_FILE}")"

for ETH in ${ETHX}; do
  [ "${ETH::4}" = "wlan" ] && connectwlanif "${ETH}" && sleep 1
  MACR="$(cat /sys/class/net/${ETH}/address | sed 's/://g')"
  IPR="$(readConfigKey "network.${MACR}" "${USER_CONFIG_FILE}")"
  if [ -n "${IPR}" ]; then
    ip addr add ${IPC}/24 dev ${ETH}
    sleep 1
  fi
  [ "${ETH::3}" = "eth" ] && ethtool -s ${ETH} wol g 2>/dev/null
done

# Get the VID/PID if we are in USB
VID="0x46f4"
PID="0x0001"
BUS=$(getBus "${LOADER_DISK}")

if [ "${BUS}" = "usb" ]; then
  VID="0x$(udevadm info --query property --name ${LOADER_DISK} | grep ID_VENDOR_ID | cut -d= -f2)"
  PID="0x$(udevadm info --query property --name ${LOADER_DISK} | grep ID_MODEL_ID | cut -d= -f2)"
elif [ "${BUS}" != "sata" -a "${BUS}" != "scsi" -a "${BUS}" != "nvme" -a "${BUS}" != "mmc" ]; then
  die "$(TEXT "Loader disk neither USB or SATA/SCSI/NVME/MMC DoM")"
fi

# Save variables to user config file
writeConfigKey "vid" ${VID} "${USER_CONFIG_FILE}"
writeConfigKey "pid" ${PID} "${USER_CONFIG_FILE}"

# Inform user
echo -e "$(TEXT "Loader disk:") \033[1;32m${LOADER_DISK}\033[0m (\033[1;32m${BUS^^} flashdisk\033[0m)"

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
echo "$(printf "$(TEXT "Detected %s network cards.")" "$(echo ${ETHX} | wc -w)")"
echo "$(TEXT "Checking Connect.")"
COUNT=0
while [ ${COUNT} -lt 30 ]; do
  hasConnect="false"
  for N in ${ETHX}; do
    if ethtool ${N} | grep 'Link detected' | grep -q 'yes'; then
      echo -en "${N} "
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
for N in ${ETHX}; do
  COUNT=0
  DRIVER=$(ls -ld /sys/class/net/${N}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
  echo -en "${N}(${DRIVER}): "
  while true; do
    if ! ip link show ${N} | grep -q 'UP'; then
      echo -en "\r${N}(${DRIVER}): $(TEXT "DOWN")\n"
      break
    fi
    if ethtool ${N} | grep 'Link detected' | grep -q 'no'; then
      echo -en "\r${N}(${DRIVER}): $(TEXT "NOT CONNECTED")\n"
      break
    fi
    if [ ${COUNT} -eq 15 ]; then
      echo -en "\r${N}(${DRIVER}): $(TEXT "TIMEOUT (Please check the IP on the router.)")\n"
      break
    fi
    COUNT=$((${COUNT} + 1))
    IP="$(getIP ${N})"
    if [ -n "${IP}" ]; then
      echo -en "\r${N}(${DRIVER}): $(printf "$(TEXT "Access \033[1;34mhttp://%s:7681\033[0m to configure the loader via web terminal.")" "${IP}")\n"
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
echo -e "$(TEXT "Default SSH Root password is") \033[1;31mrr\033[0m"
echo

DSMLOGO="$(readConfigKey "dsmlogo" "${USER_CONFIG_FILE}")"
if [ "${DSMLOGO}" = "true" -a -c "/dev/fb0" ]; then
  IP="$(getIP)"
  [ -n "${IP}" ] && URL="http://${IP}:7681" || URL="http://arpl:7681/"
  python ${WORK_PATH}/include/functions.py makeqr -d "${URL}" -l "bl" -o "${TMP_PATH}/qrcode.png"
  [ -f "${TMP_PATH}/qrcode.png" ] && echo | fbv -acufi "${TMP_PATH}/qrcode.png" >/dev/null 2>/dev/null || true
fi

# Check memory
RAM=$(free -m | awk '/Mem:/{print$2}')
if [ ${RAM} -le 3500 ]; then
  echo -e "\033[1;33m$(TEXT "You have less than 4GB of RAM, if errors occur in loader creation, please increase the amount of memory.")\033[0m\n"
fi

mkdir -p "${ADDONS_PATH}"
mkdir -p "${LKM_PATH}"
mkdir -p "${MODULES_PATH}"

updateAddons
