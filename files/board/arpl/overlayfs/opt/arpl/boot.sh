#!/usr/bin/env bash

set -e

. /opt/arpl/include/functions.sh

# Sanity check
loaderIsConfigured || die "$(TEXT "Loader is not configured!")"

# Check if machine has EFI
[ -d /sys/firmware/efi ] && EFI=1 || EFI=0

LOADER_DISK="$(blkid | grep 'LABEL="ARPL3"' | cut -d3 -f1)"
BUS=$(udevadm info --query property --name ${LOADER_DISK} | grep ID_BUS | cut -d= -f2)
[ "${BUS}" = "ata" ] && BUS="sata"

# Print text centralized
clear
[ -z "${COLUMNS}" ] && COLUMNS=50
TITLE="$(printf "$(TEXT "Welcome to %s")" "${ARPL_TITLE}")"
printf "\033[1;44m%*s\n" ${COLUMNS} ""
printf "\033[1;44m%*s\033[A\n" ${COLUMNS} ""
printf "\033[1;32m%*s\033[0m\n" $(((${#TITLE} + ${COLUMNS}) / 2)) "${TITLE}"
printf "\033[1;44m%*s\033[0m\n" ${COLUMNS} ""
TITLE="BOOTING:"
[ -d "/sys/firmware/efi" ] && TITLE+=" [UEFI]" || TITLE+=" [BIOS]"
[ "${BUS}" = "usb" ] && TITLE+=" [${BUS^^} flashdisk]" || TITLE+=" [${BUS^^} DoM]"
printf "\033[1;33m%*s\033[0m\n" $(((${#TITLE} + ${COLUMNS}) / 2)) "${TITLE}"

DSMLOGO="$(readConfigKey "dsmlogo" "${USER_CONFIG_FILE}")"
if [ "${DSMLOGO}" = "true" -a -c "/dev/fb0" -a -f "${CACHE_PATH}/logo.png" ]; then
  echo | fbv -acuf "${CACHE_PATH}/logo.png" >/dev/null 2>/dev/null
fi

# Check if DSM zImage changed, patch it if necessary
ZIMAGE_HASH="$(readConfigKey "zimage-hash" "${USER_CONFIG_FILE}")"
if [ "$(sha256sum "${ORI_ZIMAGE_FILE}" | awk '{print$1}')" != "${ZIMAGE_HASH}" ]; then
  echo -e "\033[1;43m$(TEXT "DSM zImage changed")\033[0m"
  /opt/arpl/zimage-patch.sh
  if [ $? -ne 0 ]; then
    dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Error")" \
      --msgbox "$(TEXT "zImage not patched:\n")$(<"${LOG_FILE}")" 12 70
    exit 1
  fi
fi

# Check if DSM ramdisk changed, patch it if necessary
RAMDISK_HASH="$(readConfigKey "ramdisk-hash" "${USER_CONFIG_FILE}")"
RAMDISK_HASH_CUR="$(sha256sum "${ORI_RDGZ_FILE}" | awk '{print $1}')"
if [ "${RAMDISK_HASH_CUR}" != "${RAMDISK_HASH}" ]; then
  echo -e "\033[1;43m$(TEXT "DSM Ramdisk changed")\033[0m"
  /opt/arpl/ramdisk-patch.sh
  if [ $? -ne 0 ]; then
    dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Error")" \
      --msgbox "$(TEXT "Ramdisk not patched:\n")$(<"${LOG_FILE}")" 12 70
    exit 1
  fi
  # Update SHA256 hash
  writeConfigKey "ramdisk-hash" "${RAMDISK_HASH_CUR}" "${USER_CONFIG_FILE}"
fi

# Load necessary variables
VID="$(readConfigKey "vid" "${USER_CONFIG_FILE}")"
PID="$(readConfigKey "pid" "${USER_CONFIG_FILE}")"
MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
SMALLNUM="$(readConfigKey "smallnum" "${USER_CONFIG_FILE}")"
LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"

CPU="$(echo $(cat /proc/cpuinfo | grep 'model name' | uniq | awk -F':' '{print $2}'))"
MEM="$(free -m | grep -i mem | awk '{print$2}') MB"

echo -e "$(TEXT "Model:") \033[1;36m${MODEL}\033[0m"
echo -e "$(TEXT "Build:") \033[1;36m${PRODUCTVER}(${BUILDNUM}$([ ${SMALLNUM:-0} -ne 0 ] && echo "u${SMALLNUM}"))\033[0m"
echo -e "$(TEXT "LKM:  ") \033[1;36m${LKM}\033[0m"
echo -e "$(TEXT "CPU:  ") \033[1;36m${CPU}\033[0m"
echo -e "$(TEXT "MEM:  ") \033[1;36m${MEM}\033[0m"

if [ ! -f "${MODEL_CONFIG_PATH}/${MODEL}.yml" ] || [ -z "$(readConfigKey "productvers.[${PRODUCTVER}]" "${MODEL_CONFIG_PATH}/${MODEL}.yml")" ]; then
  echo -e "\033[1;33m*** $(printf "$(TEXT "The current version of arpl does not support booting %s-%s, please rebuild.")" "${MODEL}" "${PRODUCTVER}") ***\033[0m"
  exit 1
fi

declare -A CMDLINE

# Fixed values
CMDLINE['netif_num']=0
# Automatic values
CMDLINE['syno_hw_version']="${MODEL}"
[ -z "${VID}" ] && VID="0x0000" # Sanity check
[ -z "${PID}" ] && PID="0x0000" # Sanity check
CMDLINE['vid']="${VID}"
CMDLINE['pid']="${PID}"
CMDLINE['sn']="${SN}"

# Read cmdline
while IFS=': ' read KEY VALUE; do
  [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
done < <(readModelMap "${MODEL}" "productvers.[${PRODUCTVER}].cmdline")
while IFS=': ' read KEY VALUE; do
  [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
done < <(readConfigMap "cmdline" "${USER_CONFIG_FILE}")

#
KVER=$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")

if [ ! "${BUS}" = "usb" ]; then
  LOADER_DEVICE_NAME=$(echo ${LOADER_DISK} | sed 's|/dev/||')
  SIZE=$(($(cat /sys/block/${LOADER_DEVICE_NAME}/size) / 2048 + 10))
  # Read SATADoM type
  DOM="$(readModelKey "${MODEL}" "dom")"
fi

NOTSETMACS="$(readConfigKey "notsetmacs" "${USER_CONFIG_FILE}")"
if [ "${NOTSETMACS}" = "true" ]; then
  # Currently, only up to 8 are supported.  (<==> menu.sh L396, <==> lkm: MAX_NET_IFACES)
  for N in $(seq 1 8); do
    [ -n "${CMDLINE["mac${N}"]}" ] && unset CMDLINE["mac${N}"]
  done
  unset CMDLINE['netif_num']
  echo -e "\033[1;33m*** $(printf "$(TEXT "'Not set MACs' is enabled.")") ***\033[0m"
else
  # Validate netif_num
  MACS=()
  # Currently, only up to 8 are supported.  (<==> menu.sh L396, <==> lkm: MAX_NET_IFACES)
  for N in $(seq 1 8); do
    [ -n "${CMDLINE["mac${N}"]}" ] && MACS+=(${CMDLINE["mac${N}"]})
  done
  NETIF_NUM=${#MACS[*]}
  # set netif_num to custom mac amount, netif_num must be equal to the MACX amount, otherwise the kernel will panic.
  CMDLINE["netif_num"]=${NETIF_NUM} # The current original CMDLINE['netif_num'] is no longer in use, Consider deleting.
  # real network cards amount
  NETRL_NUM=$(ls /sys/class/net/ | grep eth | wc -l)
  if [ ${NETIF_NUM} -le ${NETRL_NUM} ]; then
    echo -e "\033[1;33m*** $(printf "$(TEXT "Detected %s network cards, %s MACs were customized, the rest will use the original MACs.")" "${NETRL_NUM}" "${CMDLINE["netif_num"]}") ***\033[0m"
    ETHX=($(ls /sys/class/net/ | grep eth)) # real network cards list
    for N in $(seq $(expr ${NETIF_NUM} + 1) ${NETRL_NUM}); do
      MACR="$(cat /sys/class/net/${ETHX[$(expr ${N} - 1)]}/address | sed 's/://g')"
      # no duplicates
      while [[ "${MACS[*]}" =~ "$MACR" ]]; do # no duplicates
        MACR="${MACR:0:10}$(printf "%02x" $((0x${MACR:10:2} + 1)))"
      done
      CMDLINE["mac${N}"]="${MACR}"
    done
    CMDLINE["netif_num"]=${NETRL_NUM}
  fi
fi
# Prepare command line
CMDLINE_LINE=""
grep -q "force_junior" /proc/cmdline && CMDLINE_LINE+="force_junior "
[ ${EFI} -eq 1 ] && CMDLINE_LINE+="withefi " || CMDLINE_LINE+="noefi "
[ ! "${BUS}" = "usb" ] && CMDLINE_LINE+="synoboot_satadom=${DOM} dom_szmax=${SIZE} "
CMDLINE_LINE+="console=ttyS0,115200n8 earlyprintk earlycon=uart8250,io,0x3f8,115200n8 root=/dev/md0 loglevel=15 log_buf_len=32M"
CMDLINE_DIRECT="${CMDLINE_LINE}"
for KEY in ${!CMDLINE[@]}; do
  VALUE="${CMDLINE[${KEY}]}"
  CMDLINE_LINE+=" ${KEY}"
  CMDLINE_DIRECT+=" ${KEY}"
  [ -n "${VALUE}" ] && CMDLINE_LINE+="=${VALUE}"
  [ -n "${VALUE}" ] && CMDLINE_DIRECT+="=${VALUE}"
done
# Escape special chars
#CMDLINE_LINE=`echo ${CMDLINE_LINE} | sed 's/>/\\\\>/g'`
CMDLINE_DIRECT=$(echo ${CMDLINE_DIRECT} | sed 's/>/\\\\>/g')
echo -e "$(TEXT "Cmdline:\n")\033[1;36m${CMDLINE_LINE}\033[0m"

DIRECT="$(readConfigKey "directboot" "${USER_CONFIG_FILE}")"
if [ "${DIRECT}" = "true" ]; then
  grub-editenv ${GRUB_PATH}/grubenv set dsm_cmdline="${CMDLINE_DIRECT}"
  echo -e "\033[1;33m$(TEXT "Reboot to boot directly in DSM")\033[0m"
  grub-editenv ${GRUB_PATH}/grubenv set next_entry="direct"
  reboot
  exit 0
else
  ETHX=($(ls /sys/class/net/ | grep eth)) # real network cards list
  echo "$(printf "$(TEXT "Detected %s network cards.")" "${#ETHX[@]}")"
  echo "$(TEXT "Checking Connect.")"
  COUNT=0
  BOOTIPWAIT="$(readConfigKey "bootipwait" "${USER_CONFIG_FILE}")"
  [ -z "${BOOTIPWAIT}" ] && BOOTIPWAIT=10
  while [ ${COUNT} -lt $((${BOOTIPWAIT} + 32)) ]; do
    hasConnect="false"
    for N in $(seq 0 $(expr ${#ETHX[@]} - 1)); do
      if ethtool ${ETHX[${N}]} | grep 'Link detected' | grep -q 'yes'; then
        echo -en "${ETHX[${N}]} "
        hasConnect="true"
      fi
    done
    if [ ${hasConnect} = "true" ]; then
      echo -en "connected.\n"
      break
    fi
    COUNT=$((${COUNT} + 1))
    echo -n "."
    sleep 1
  done
  echo "$(TEXT "Waiting IP.(For reference only)")"
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
      if [ ${COUNT} -eq ${BOOTIPWAIT} ]; then # Under normal circumstances, no errors should occur here.
        echo -en "\r${ETHX[${N}]}(${DRIVER}): $(TEXT "TIMEOUT (Please check the IP on the router.)")\n"
        break
      fi
      COUNT=$((${COUNT} + 1))
      IP=$(ip route show dev ${ETHX[${N}]} 2>/dev/null | sed -n 's/.* via .* src \(.*\)  metric .*/\1/p')
      if [ -n "${IP}" ]; then
        echo -en "\r${ETHX[${N}]}(${DRIVER}): $(printf "$(TEXT "Access \033[1;34mhttp://%s:5000\033[0m to connect the DSM via web.")" "${IP}")\n"
        break
      fi
      echo -n "."
      sleep 1
    done
  done
  BOOTWAIT="$(readConfigKey "bootwait" "${USER_CONFIG_FILE}")"
  [ -z "${BOOTWAIT}" ] && BOOTWAIT=10
  w | awk '{print $1" "$2" "$4" "$5" "$6}' >WB
  MSG=""
  while test ${BOOTWAIT} -ge 0; do
    MSG="$(printf "\033[1;33m$(TEXT "%2ds (accessing arpl will interrupt boot)")\033[0m" "${BOOTWAIT}")"
    echo -en "\r${MSG}"
    w | awk '{print $1" "$2" "$4" "$5" "$6}' >WC
    if ! diff WB WC >/dev/null 2>&1; then
      echo -en "\r\033[1;33m$(TEXT "A new access is connected, the boot process is interrupted.")\033[0m\n"
      rm -f WB WC
      exit 0
    fi
    sleep 1
    BOOTWAIT=$((BOOTWAIT - 1))
  done
  rm -f WB WC
  echo -en "\r$(printf "%$((${#MSG} * 3))s" " ")\n"
fi

echo -e "\033[1;37m$(TEXT "Loading DSM kernel...")\033[0m"

# Executes DSM kernel via KEXEC
if [ "${KVER:0:1}" = "3" -a ${EFI} -eq 1 ]; then
  echo -e "\033[1;33m$(TEXT "Warning, running kexec with --noefi param, strange things will happen!!")\033[0m"
  kexec --noefi -l "${MOD_ZIMAGE_FILE}" --initrd "${MOD_RDGZ_FILE}" --command-line="${CMDLINE_LINE}" >"${LOG_FILE}" 2>&1 || dieLog
else
  kexec -l "${MOD_ZIMAGE_FILE}" --initrd "${MOD_RDGZ_FILE}" --command-line="${CMDLINE_LINE}" >"${LOG_FILE}" 2>&1 || dieLog
fi
echo -e "\033[1;37m$(TEXT "Booting...")\033[0m"
for T in $(w | grep -v "TTY" | awk -F' ' '{print $2}'); do
  echo -e "\n\033[1;43m$(TEXT "[This interface will not be operational.\nPlease wait for a few minutes before using the http://find.synology.com/ or Synology Assistant find DSM and connect.]")\033[0m\n" >"/dev/${T}" 2>/dev/null || true
done
KERNELWAY="$(readConfigKey "kernelway" "${USER_CONFIG_FILE}")"
[ "${KERNELWAY}" = "kexec" ] && kexec -f -e || poweroff
exit 0
