#!/usr/bin/env bash

set -e
[ -z "${WORK_PATH}" -o ! -d "${WORK_PATH}/include" ] && WORK_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. ${WORK_PATH}/include/functions.sh

[ -z "${LOADER_DISK}" ] && die "$(TEXT "Loader is not init!")"
# Sanity check
loaderIsConfigured || die "$(TEXT "Loader is not configured!")"

# Check if machine has EFI
[ -d /sys/firmware/efi ] && EFI=1 || EFI=0

BUS=$(getBus "${LOADER_DISK}")

# Print text centralized
clear
[ -z "${COLUMNS}" ] && COLUMNS=50
TITLE="$(printf "$(TEXT "Welcome to %s")" "${RR_TITLE}")"
printf "\033[1;44m%*s\n" ${COLUMNS} ""
printf "\033[1;44m%*s\033[A\n" ${COLUMNS} ""
printf "\033[1;32m%*s\033[0m\n" $(((${#TITLE} + ${COLUMNS}) / 2)) "${TITLE}"
printf "\033[1;44m%*s\033[0m\n" ${COLUMNS} ""
TITLE="BOOTING:"
[ ${EFI} -eq 1 ] && TITLE+=" [UEFI]" || TITLE+=" [BIOS]"
[ "${BUS}" = "usb" ] && TITLE+=" [${BUS^^} flashdisk]" || TITLE+=" [${BUS^^} DoM]"
printf "\033[1;33m%*s\033[0m\n" $(((${#TITLE} + ${COLUMNS}) / 2)) "${TITLE}"

# Check if DSM zImage changed, patch it if necessary
ZIMAGE_HASH="$(readConfigKey "zimage-hash" "${USER_CONFIG_FILE}")"
if [ -f ${PART1_PATH}/.build -o "$(sha256sum "${ORI_ZIMAGE_FILE}" | awk '{print$1}')" != "${ZIMAGE_HASH}" ]; then
  echo -e "\033[1;43m$(TEXT "DSM zImage changed")\033[0m"
  ${WORK_PATH}/zimage-patch.sh
  if [ $? -ne 0 ]; then
    echo -e "\033[1;43m$(TEXT "zImage not patched,\nPlease upgrade the bootloader version and try again.\nPatch error:\n")$(<"${LOG_FILE}")\033[0m"
    exit 1
  fi
fi

# Check if DSM ramdisk changed, patch it if necessary
RAMDISK_HASH="$(readConfigKey "ramdisk-hash" "${USER_CONFIG_FILE}")"
RAMDISK_HASH_CUR="$(sha256sum "${ORI_RDGZ_FILE}" | awk '{print $1}')"
if [ -f ${PART1_PATH}/.build -o "${RAMDISK_HASH_CUR}" != "${RAMDISK_HASH}" ]; then
  echo -e "\033[1;43m$(TEXT "DSM Ramdisk changed")\033[0m"
  ${WORK_PATH}/ramdisk-patch.sh
  if [ $? -ne 0 ]; then
    echo -e "\033[1;43m$(TEXT "Ramdisk not patched,\nPlease upgrade the bootloader version and try again.\nPatch error:\n")$(<"${LOG_FILE}")\033[0m"
    exit 1
  fi
  # Update SHA256 hash
  writeConfigKey "ramdisk-hash" "${RAMDISK_HASH_CUR}" "${USER_CONFIG_FILE}"
fi
[ -f ${PART1_PATH}/.build ] && rm -f ${PART1_PATH}/.build

# Load necessary variables
MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
SMALLNUM="$(readConfigKey "smallnum" "${USER_CONFIG_FILE}")"
LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"

DMI="$(dmesg | grep -i "DMI:" | sed 's/\[.*\] DMI: //i')"
CPU="$(echo $(cat /proc/cpuinfo | grep 'model name' | uniq | awk -F':' '{print $2}'))"
MEM="$(free -m | grep -i mem | awk '{print$2}') MB"

echo -e "$(TEXT "Model:") \033[1;36m${MODEL}\033[0m"
echo -e "$(TEXT "Build:") \033[1;36m${PRODUCTVER}(${BUILDNUM}$([ ${SMALLNUM:-0} -ne 0 ] && echo "u${SMALLNUM}"))\033[0m"
echo -e "$(TEXT "LKM:  ") \033[1;36m${LKM}\033[0m"
echo -e "$(TEXT "DMI:  ") \033[1;36m${DMI}\033[0m"
echo -e "$(TEXT "CPU:  ") \033[1;36m${CPU}\033[0m"
echo -e "$(TEXT "MEM:  ") \033[1;36m${MEM}\033[0m"

if [ ! -f "${WORK_PATH}/model-configs/${MODEL}.yml" ] || [ -z "$(readModelKey ${MODEL} "productvers.[${PRODUCTVER}]")" ]; then
  echo -e "\033[1;33m*** $(printf "$(TEXT "The current version of bootloader does not support booting %s-%s, please upgrade and rebuild.")" "${MODEL}" "${PRODUCTVER}") ***\033[0m"
  exit 1
fi

HASATA=0
for D in $(lsblk -dpno NAME); do
  [ "${D}" = "${LOADER_DISK}" ] && continue
  if [ "$(getBus "${D}")" = "sata" -o "$(getBus "${D}")" = "scsi" ]; then
    HASATA=1
    break
  fi
done
[ ${HASATA} = "0" ] && echo -e "\033[1;33m*** $(TEXT "Please insert at least one sata/scsi disk for system installation, except for the bootloader disk.") ***\033[0m"

VID="$(readConfigKey "vid" "${USER_CONFIG_FILE}")"
PID="$(readConfigKey "pid" "${USER_CONFIG_FILE}")"
SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"
MAC1="$(readConfigKey "mac1" "${USER_CONFIG_FILE}")"
MAC2="$(readConfigKey "mac2" "${USER_CONFIG_FILE}")"
KERNELPANIC="$(readConfigKey "kernelpanic" "${USER_CONFIG_FILE}")"

declare -A CMDLINE

# Automatic values
CMDLINE['syno_hw_version']="${MODEL}"
[ -z "${VID}" ] && VID="0x46f4" # Sanity check
[ -z "${PID}" ] && PID="0x0001" # Sanity check
CMDLINE['vid']="${VID}"
CMDLINE['pid']="${PID}"
CMDLINE['sn']="${SN}"

CMDLINE['netif_num']="0"
[ -z "${MAC1}" -a -n "${MAC2}" ] && MAC1=${MAC2} && MAC2="" # Sanity check
[ -n "${MAC1}" ] && CMDLINE['mac1']="${MAC1}" && CMDLINE['netif_num']="1"
[ -n "${MAC2}" ] && CMDLINE['mac2']="${MAC2}" && CMDLINE['netif_num']="2"

# set fixed cmdline
if grep -q "force_junior" /proc/cmdline; then
  CMDLINE['force_junior']=""
fi
if [ ${EFI} -eq 1 ]; then
  CMDLINE['withefi']=""
else
  CMDLINE['noefi']=""
fi
if [ ! "${BUS}" = "usb" ]; then
  SIZE=$(($(cat /sys/block/${LOADER_DISK/\/dev\//}/size) / 2048 + 10))
  # Read SATADoM type
  DOM="$(readModelKey "${MODEL}" "dom")"
  CMDLINE['synoboot_satadom']="${DOM}"
  CMDLINE['dom_szmax']="${SIZE}"
fi
CMDLINE['panic']="${KERNELPANIC:-0}"
CMDLINE['console']="ttyS0,115200n8"
CMDLINE['earlyprintk']=""
CMDLINE['earlycon']="uart8250,io,0x3f8,115200n8"
CMDLINE['root']="/dev/md0"
CMDLINE['skip_vender_mac_interfaces']="0,1,2,3,4,5,6,7"
CMDLINE['loglevel']="15"
CMDLINE['log_buf_len']="32M"

# Read cmdline
while IFS=': ' read KEY VALUE; do
  [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
done < <(readModelMap "${MODEL}" "productvers.[${PRODUCTVER}].cmdline")
while IFS=': ' read KEY VALUE; do
  [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
done < <(readConfigMap "cmdline" "${USER_CONFIG_FILE}")

# Prepare command line
CMDLINE_LINE=""
for KEY in ${!CMDLINE[@]}; do
  VALUE="${CMDLINE[${KEY}]}"
  CMDLINE_LINE+=" ${KEY}"
  [ -n "${VALUE}" ] && CMDLINE_LINE+="=${VALUE}"
done
CMDLINE_LINE=$(echo "${CMDLINE_LINE}" | sed 's/^ //') # Remove leading space
echo -e "$(TEXT "Cmdline:\n")\033[1;36m${CMDLINE_LINE}\033[0m"

DIRECT="$(readConfigKey "directboot" "${USER_CONFIG_FILE}")"
if [ "${DIRECT}" = "true" ]; then
  CMDLINE_DIRECT=$(echo ${CMDLINE_LINE} | sed 's/>/\\\\>/g') # Escape special chars
  grub-editenv ${GRUB_PATH}/grubenv set dsm_cmdline="${CMDLINE_DIRECT}"
  echo -e "\033[1;33m$(TEXT "Reboot to boot directly in DSM")\033[0m"
  grub-editenv ${GRUB_PATH}/grubenv set next_entry="direct"
  reboot
  exit 0
else
  ETHX=$(ls /sys/class/net/ | grep -v lo) || true
  echo "$(printf "$(TEXT "Detected %s network cards.")" "$(echo ${ETHX} | wc -w)")"
  echo "$(TEXT "Checking Connect.")"
  COUNT=0
  BOOTIPWAIT="$(readConfigKey "bootipwait" "${USER_CONFIG_FILE}")"
  [ -z "${BOOTIPWAIT}" ] && BOOTIPWAIT=10
  while [ ${COUNT} -lt $((${BOOTIPWAIT} + 32)) ]; do
    hasConnect="false"
    for N in ${ETHX}; do
      if ethtool ${N} | grep 'Link detected' | grep -q 'yes'; then
        echo -en "${N} "
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
      if [ ${COUNT} -eq ${BOOTIPWAIT} ]; then # Under normal circumstances, no errors should occur here.
        echo -en "\r${N}(${DRIVER}): $(TEXT "TIMEOUT (Please check the IP on the router.)")\n"
        break
      fi
      COUNT=$((${COUNT} + 1))
      IP="$(getIP ${N})"
      if [ -n "${IP}" ]; then
        echo -en "\r${N}(${DRIVER}): $(printf "$(TEXT "Access \033[1;34mhttp://%s:5000\033[0m to connect the DSM via web.")" "${IP}")\n"
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
    MSG="$(printf "\033[1;33m$(TEXT "%2ds (Changing access(ssh/web) status will interrupt boot)")\033[0m" "${BOOTWAIT}")"
    echo -en "\r${MSG}"
    w | awk '{print $1" "$2" "$4" "$5" "$6}' >WC
    if ! diff WB WC >/dev/null 2>&1; then
      echo -en "\r\033[1;33m$(TEXT "access(ssh/web) status has changed and booting is interrupted.")\033[0m\n"
      rm -f WB WC
      exit 0
    fi
    sleep 1
    BOOTWAIT=$((BOOTWAIT - 1))
  done
  rm -f WB WC
  echo -en "\r$(printf "%$((${#MSG} * 2))s" " ")\n"

  echo -e "\033[1;37m$(TEXT "Loading DSM kernel...")\033[0m"

  DSMLOGO="$(readConfigKey "dsmlogo" "${USER_CONFIG_FILE}")"
  if [ "${DSMLOGO}" = "true" -a -c "/dev/fb0" ]; then
    IP="$(getIP)"
    [ -n "${IP}" ] && URL="http://${IP}:5000" || URL="http://find.synology.com/"
    python ${WORK_PATH}/include/functions.py makeqr -d "${URL}" -l "br" -o "${TMP_PATH}/qrcode.png"
    [ -f "${TMP_PATH}/qrcode.png" ] && echo | fbv -acufi "${TMP_PATH}/qrcode.png" >/dev/null 2>/dev/null || true
  fi

  # Executes DSM kernel via KEXEC
  KVER=$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")
  if [ "${KVER:0:1}" = "3" -a ${EFI} -eq 1 ]; then
    echo -e "\033[1;33m$(TEXT "Warning, running kexec with --noefi param, strange things will happen!!")\033[0m"
    kexec --noefi -l "${MOD_ZIMAGE_FILE}" --initrd "${MOD_RDGZ_FILE}" --command-line="${CMDLINE_LINE}" >"${LOG_FILE}" 2>&1 || dieLog
  else
    kexec -l "${MOD_ZIMAGE_FILE}" --initrd "${MOD_RDGZ_FILE}" --command-line="${CMDLINE_LINE}" >"${LOG_FILE}" 2>&1 || dieLog
  fi
  echo -e "\033[1;37m$(TEXT "Booting...")\033[0m"
  for T in $(w | grep -v "TTY" | awk -F' ' '{print $2}'); do
    echo -e "\n\033[1;43m$(TEXT "[This interface will not be operational. Please wait a few minutes.\nFind DSM via http://find.synology.com/ or Synology Assistant and connect.]")\033[0m\n" >"/dev/${T}" 2>/dev/null || true
  done
  KERNELWAY="$(readConfigKey "kernelway" "${USER_CONFIG_FILE}")"
  [ "${KERNELWAY}" = "kexec" ] && kexec -f -e || poweroff
  exit 0
fi
