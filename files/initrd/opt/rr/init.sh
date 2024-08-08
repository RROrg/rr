#!/usr/bin/env bash

set -e
[ -z "${WORK_PATH}" -o ! -d "${WORK_PATH}/include" ] && WORK_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. ${WORK_PATH}/include/functions.sh
. ${WORK_PATH}/include/addons.sh

[ -z "${LOADER_DISK}" ] && die "$(TEXT "Loader is not init!")"
checkBootLoader || die "$(TEXT "The loader is corrupted, please rewrite it!")"

# Shows title
clear
[ -z "${COLUMNS}" ] && COLUMNS=50
TITLE="$(printf "$(TEXT "Welcome to %s")" "$([ -z "${RR_RELEASE}" ] && echo "${RR_TITLE}" || echo "${RR_TITLE}(${RR_RELEASE})")")"
printf "\033[1;44m%*s\n" ${COLUMNS} ""
printf "\033[1;44m%*s\033[A\n" ${COLUMNS} ""
printf "\033[1;32m%*s\033[0m\n" $(((${#TITLE} + ${COLUMNS}) / 2)) "${TITLE}"
printf "\033[1;44m%*s\033[0m\n" ${COLUMNS} ""

# Get first MAC address
ETHX=$(ls /sys/class/net/ 2>/dev/null | grep -v lo) || true
# No network devices
[ $(echo ${ETHX} | wc -w) -le 0 ] && die "$(TEXT "Network devices not found! Please re execute init.sh after connecting to the network!")"

# If user config file not exists, initialize it
if [ ! -f "${USER_CONFIG_FILE}" ]; then
  touch "${USER_CONFIG_FILE}"
fi

initConfigKey "kernel" "official" "${USER_CONFIG_FILE}"
initConfigKey "rd-compressed" "false" "${USER_CONFIG_FILE}"
initConfigKey "satadom" "2" "${USER_CONFIG_FILE}"
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
initConfigKey "emmcboot" "false" "${USER_CONFIG_FILE}"
initConfigKey "platform" "" "${USER_CONFIG_FILE}"
initConfigKey "model" "" "${USER_CONFIG_FILE}"
initConfigKey "modelid" "" "${USER_CONFIG_FILE}"
initConfigKey "productver" "" "${USER_CONFIG_FILE}"
initConfigKey "buildnum" "" "${USER_CONFIG_FILE}"
initConfigKey "smallnum" "" "${USER_CONFIG_FILE}"
initConfigKey "paturl" "" "${USER_CONFIG_FILE}"
initConfigKey "patsum" "" "${USER_CONFIG_FILE}"
initConfigKey "sn" "" "${USER_CONFIG_FILE}"
initConfigKey "mac1" "" "${USER_CONFIG_FILE}"
initConfigKey "mac2" "" "${USER_CONFIG_FILE}"
initConfigKey "layout" "qwerty" "${USER_CONFIG_FILE}"
initConfigKey "keymap" "" "${USER_CONFIG_FILE}"
initConfigKey "zimage-hash" "" "${USER_CONFIG_FILE}"
initConfigKey "ramdisk-hash" "" "${USER_CONFIG_FILE}"
initConfigKey "cmdline" "{}" "${USER_CONFIG_FILE}"
initConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
initConfigKey "addons" "{}" "${USER_CONFIG_FILE}"
initConfigKey "addons.acpid" "" "${USER_CONFIG_FILE}"
initConfigKey "addons.mountloader" "" "${USER_CONFIG_FILE}"
initConfigKey "addons.powersched" "" "${USER_CONFIG_FILE}"
initConfigKey "addons.reboottoloader" "" "${USER_CONFIG_FILE}"
initConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
initConfigKey "modblacklist" "evbug,cdc_ether" "${USER_CONFIG_FILE}"

# for update
if [ -f "${PART2_PATH}/GRUB_VER" ]; then
  PLATFORMTMP="$(_get_conf_kv "PLATFORM" "${PART2_PATH}/GRUB_VER")"
  MODELTMP="$(_get_conf_kv "MODEL" "${PART2_PATH}/GRUB_VER")"
  [ -z "$(readConfigKey "platform" "${USER_CONFIG_FILE}")" ] &&
    writeConfigKey "platform" "${PLATFORMTMP,,}" "${USER_CONFIG_FILE}"
  [ -z "$(readConfigKey "model" "${USER_CONFIG_FILE}")" ] &&
    writeConfigKey "model" "$(echo ${MODELTMP} | sed 's/d$/D/; s/rp$/RP/; s/rp+/RP+/')" "${USER_CONFIG_FILE}"
  [ -z "$(readConfigKey "modelid" "${USER_CONFIG_FILE}")" ] &&
    writeConfigKey "modelid" "${MODELTMP}" "${USER_CONFIG_FILE}"
fi

if [ ! "LOCALBUILD" = "${LOADER_DISK}" ]; then
  if arrayExistItem "sortnetif:" $(readConfigMap "addons" "${USER_CONFIG_FILE}"); then
    _sort_netif "$(readConfigKey "addons.sortnetif" "${USER_CONFIG_FILE}")"
  fi
  for ETH in ${ETHX}; do
    [ "${ETH::4}" = "wlan" ] && connectwlanif "${ETH}" && sleep 1
    MACR="$(cat /sys/class/net/${ETH}/address 2>/dev/null | sed 's/://g')"
    IPR="$(readConfigKey "network.${MACR}" "${USER_CONFIG_FILE}")"
    if [ -n "${IPR}" ]; then
      IFS='/' read -r -a IPRA <<<"$IPR"
      ip addr flush dev $ETH
      ip addr add ${IPRA[0]}/${IPRA[1]:-"255.255.255.0"} dev $ETH
      if [ -n "${IPRA[2]}" ]; then
        ip route add default via ${IPRA[2]} dev $ETH
      fi
      if [ -n "${IPRA[3]:-${IPRA[2]}}" ]; then
        sed -i "/nameserver ${IPRA[3]:-${IPRA[2]}}/d" /etc/resolv.conf
        echo "nameserver ${IPRA[3]:-${IPRA[2]}}" >>/etc/resolv.conf
      fi
      sleep 1
    fi
    [ "${ETH::3}" = "eth" ] && ethtool -s ${ETH} wol g 2>/dev/null || true
    [ "${ETH::3}" = "eth" ] && ethtool -K ${ETH} rxhash off 2>/dev/null || true
  done
fi

# Get the VID/PID if we are in USB
VID="0x46f4"
PID="0x0001"
TYPE="DoM"
BUS=$(getBus "${LOADER_DISK}")

BUSLIST="usb sata sas scsi nvme mmc ide virtio vmbus xen"
if [ "${BUS}" = "usb" ]; then
  VID="0x$(udevadm info --query property --name ${LOADER_DISK} 2>/dev/null | grep ID_VENDOR_ID | cut -d= -f2)"
  PID="0x$(udevadm info --query property --name ${LOADER_DISK} 2>/dev/null | grep ID_MODEL_ID | cut -d= -f2)"
  TYPE="flashdisk"
elif ! echo "${BUSLIST}" | grep -wq "${BUS}"; then
  if [ "LOCALBUILD" = "${LOADER_DISK}" ]; then
    echo "LOCALBUILD MODE"
    TYPE="PC"
  else
    die "$(printf "$(TEXT "The boot disk does not support the current %s, only %s DoM is supported.")" "${BUS}" "${BUSLIST// /\/}")"
  fi
fi

# Save variables to user config file
writeConfigKey "vid" ${VID} "${USER_CONFIG_FILE}"
writeConfigKey "pid" ${PID} "${USER_CONFIG_FILE}"

# Inform user
echo -e "$(TEXT "Loader disk:") \033[1;32m${LOADER_DISK}\033[0m (\033[1;32m${BUS^^} ${TYPE}\033[0m)"

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
  ${WORK_PATH}/boot.sh && exit 0
fi

# Wait for an IP
echo "$(printf "$(TEXT "Detected %s network cards.")" "$(echo ${ETHX} | wc -w)")"
echo -en "$(TEXT "Checking Connect.")"
COUNT=0
while [ ${COUNT} -lt 30 ]; do
  MSG=""
  for N in ${ETHX}; do
    if ethtool ${N} 2>/dev/null | grep 'Link detected' | grep -q 'yes'; then
      MSG+="${N} "
    fi
  done
  if [ -n "${MSG}" ]; then
    echo -en "\r${MSG}$(TEXT "connected.")                  \n"
    break
  fi
  COUNT=$((${COUNT} + 1))
  echo -n "."
  sleep 1
done

[ ! -f /var/run/dhcpcd/pid ] && /etc/init.d/S41dhcpcd restart >/dev/null 2>&1 || true

echo "$(TEXT "Waiting IP.")"
for N in ${ETHX}; do
  COUNT=0
  DRIVER=$(ls -ld /sys/class/net/${N}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
  echo -en "${N}(${DRIVER}): "
  while true; do
    if ! ip link show ${N} 2>/dev/null | grep -q 'UP'; then
      echo -en "\r${N}(${DRIVER}): $(TEXT "DOWN")\n"
      break
    fi
    if ethtool ${N} 2>/dev/null | grep 'Link detected' | grep -q 'no'; then
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
      if [[ "${IP}" =~ ^169\.254\..* ]]; then
        echo -en "\r${N}(${DRIVER}): $(TEXT "LINK LOCAL (No DHCP server detected.)")\n"
      else
        echo -en "\r${N}(${DRIVER}): $(printf "$(TEXT "Access \033[1;34mhttp://%s:7681\033[0m to configure the loader via web terminal.")" "${IP}")\n"
      fi
      break
    fi
    echo -n "."
    sleep 1
  done
done

# Inform user
echo
echo -e "$(TEXT "Call \033[1;32minit.sh\033[0m to re get init info")"
echo -e "$(TEXT "Call \033[1;32mmenu.sh\033[0m to configure loader")"
echo
echo -e "$(TEXT "User config is on") \033[1;32m${USER_CONFIG_FILE}\033[0m"
echo -e "$(TEXT "TTYD: \033[1;34mhttp://rr:7681/\033[0m")"
echo -e "$(TEXT "DUFS: \033[1;34mhttp://rr:7304/\033[0m")"
echo -e "$(TEXT "TTYD&DUFS: \033[1;34mhttp://rr:80/\033[0m")"
echo
echo -e "$(TEXT "Default SSH \033[1;31mroot\033[0m password is") \033[1;31mrr\033[0m"
echo

DSMLOGO="$(readConfigKey "dsmlogo" "${USER_CONFIG_FILE}")"
if [ "${DSMLOGO}" = "true" -a -c "/dev/fb0" -a ! "LOCALBUILD" = "${LOADER_DISK}" ]; then
  IP="$(getIP)"
  [[ "${IP}" =~ ^169\.254\..* ]] && IP=""
  [ -n "${IP}" ] && URL="http://${IP}:7681" || URL="http://rr:7681/"
  python ${WORK_PATH}/include/functions.py makeqr -d "${URL}" -l "0" -o "${TMP_PATH}/qrcode_init.png"
  [ -f "${TMP_PATH}/qrcode_init.png" ] && echo | fbv -acufi "${TMP_PATH}/qrcode_init.png" >/dev/null 2>/dev/null || true

  python ${WORK_PATH}/include/functions.py makeqr -f "${WORK_PATH}/include/qhxg.png" -l "7" -o "${TMP_PATH}/qrcode_qhxg.png"
  [ -f "${TMP_PATH}/qrcode_qhxg.png" ] && echo | fbv -acufi "${TMP_PATH}/qrcode_qhxg.png" >/dev/null 2>/dev/null || true
fi

# Check memory
RAM=$(awk '/MemTotal:/ {printf "%.0f", $2 / 1024}' /proc/meminfo 2>/dev/null)
if [ ${RAM:-0} -le 3500 ]; then
  echo -e "\033[1;33m$(TEXT "You have less than 4GB of RAM, if errors occur in loader creation, please increase the amount of memory.")\033[0m\n"
fi

mkdir -p "${CKS_PATH}"
mkdir -p "${LKMS_PATH}"
mkdir -p "${ADDONS_PATH}"
mkdir -p "${MODULES_PATH}"

exit 0
