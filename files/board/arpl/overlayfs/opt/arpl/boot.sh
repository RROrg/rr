#!/usr/bin/env bash

set -e

. /opt/arpl/include/functions.sh

# Sanity check
loaderIsConfigured || die "Loader is not configured!"

# Print text centralized
clear
[ -z "${COLUMNS}" ] && COLUMNS=50
TITLE="Welcome to Automated Redpill Loader v${ARPL_VERSION}"
printf "\033[1;44m%*s\n" ${COLUMNS} ""
printf "\033[1;44m%*s\033[A\n" ${COLUMNS} ""
printf "\033[1;32m%*s\033[0m\n" $(((${#TITLE}+${COLUMNS})/2)) "${TITLE}"
printf "\033[1;44m%*s\033[0m\n" ${COLUMNS} ""
TITLE="BOOTING..."
printf "\033[1;33m%*s\033[0m\n" $(((${#TITLE}+${COLUMNS})/2)) "${TITLE}"

history -w
sync

# Check if DSM zImage changed, patch it if necessary
ZIMAGE_HASH="`readConfigKey "zimage-hash" "${USER_CONFIG_FILE}"`"
if [ "`sha256sum "${ORI_ZIMAGE_FILE}" | awk '{print$1}'`" != "${ZIMAGE_HASH}" ]; then
  echo -e "\033[1;43mDSM zImage changed\033[0m"
  /opt/arpl/zimage-patch.sh
  if [ $? -ne 0 ]; then
    dialog --backtitle "`backtitle`" --title "Error" \
      --msgbox "zImage not patched:\n`<"${LOG_FILE}"`" 12 70
    return 1
  fi
fi

# Check if DSM ramdisk changed, patch it if necessary
RAMDISK_HASH="`readConfigKey "ramdisk-hash" "${USER_CONFIG_FILE}"`"
if [ "`sha256sum "${ORI_RDGZ_FILE}" | awk '{print$1}'`" != "${RAMDISK_HASH}" ]; then
  echo -e "\033[1;43mDSM Ramdisk changed\033[0m"
  /opt/arpl/ramdisk-patch.sh
  if [ $? -ne 0 ]; then
    dialog --backtitle "`backtitle`" --title "Error" \
      --msgbox "Ramdisk not patched:\n`<"${LOG_FILE}"`" 12 70
    return 1
  fi
fi

# Load necessary variables
VID="`readConfigKey "vid" "${USER_CONFIG_FILE}"`"
PID="`readConfigKey "pid" "${USER_CONFIG_FILE}"`"
MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"
BUILD="`readConfigKey "build" "${USER_CONFIG_FILE}"`"
SN="`readConfigKey "sn" "${USER_CONFIG_FILE}"`"

echo -e "Model: \033[1;36m${MODEL}\033[0m"
echo -e "Build: \033[1;36m${BUILD}\033[0m"

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
while IFS="=" read KEY VALUE; do
  [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
done < <(readModelMap "${MODEL}" "builds.${BUILD}.cmdline")
while IFS="=" read KEY VALUE; do
  [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
done < <(readConfigMap "cmdline" "${USER_CONFIG_FILE}")

# Check if machine has EFI
[ -d /sys/firmware/efi ] && EFI=1 || EFI=0
# Read EFI bug value
EFI_BUG="`readModelKey "${MODEL}" "builds.${BUILD}.efi-bug"`"

LOADER_DISK="`blkid | grep 'LABEL="ARPL3"' | cut -d3 -f1`"
BUS=`udevadm info --query property --name ${LOADER_DISK} | grep ID_BUS | cut -d= -f2`
if [ "${BUS}" = "ata" ]; then
  LOADER_DEVICE_NAME=`echo ${LOADER_DISK} | sed 's|/dev/||'`
  SIZE=$((`cat /sys/block/${LOADER_DEVICE_NAME}/size`/2048+10))
  # Read SATADoM type
  DOM="`readModelKey "${MODEL}" "dom"`"
fi

# Validate netif_num
NETIF_NUM=${CMDLINE["netif_num"]}
MACS=0
for N in `seq 1 9`; do
  [ -n "${CMDLINE["mac${N}"]}" ] && MACS=$((${MACS}+1))
done
if [ ${NETIF_NUM} -ne ${MACS} ]; then
  echo -e "\033[1;33m*** netif_num is not equal to macX amount, set netif_num to ${MACS} ***\033[0m"
  CMDLINE["netif_num"]=${MACS}
fi

# Prepare command line
CMDLINE_LINE=""
grep -q "force_junior" /proc/cmdline && CMDLINE_LINE+="force_junior "
[ ${EFI} -eq 1 ] && CMDLINE_LINE+="withefi "
[ "${BUS}" = "ata" ] && CMDLINE_LINE+="synoboot_satadom=${DOM} dom_szmax=${SIZE} "
CMDLINE_DIRECT="${CMDLINE_LINE}"
CMDLINE_LINE+="console=ttyS0,115200n8 earlyprintk log_buf_len=32M earlycon=uart8250,io,0x3f8,115200n8 elevator=elevator root=/dev/md0 loglevel=15"
for KEY in ${!CMDLINE[@]}; do
  VALUE="${CMDLINE[${KEY}]}"
  CMDLINE_LINE+=" ${KEY}"
  CMDLINE_DIRECT+=" ${KEY}"
  [ -n "${VALUE}" ] && CMDLINE_LINE+="=${VALUE}"
  [ -n "${VALUE}" ] && CMDLINE_DIRECT+="=${VALUE}"
done
# Escape special chars
CMDLINE_LINE=`echo ${CMDLINE_LINE} | sed 's/>/\\\\>/g'`
CMDLINE_DIRECT=`echo ${CMDLINE_DIRECT} | sed 's/>/\\\\>/g'`
echo -e "Cmdline:\n\033[1;36m${CMDLINE_LINE}\033[0m"

# Wait for an IP
COUNT=0
echo -n "IP"
while true; do
  IP=`ip route get 1.1.1.1 2>/dev/null | awk '{print$7}'`
  if [ -n "${IP}" ]; then
    echo -e ": \033[1;32m${IP}\033[0m"
    break
  elif [ ${COUNT} -eq 30 ]; then
    echo -e ": \033[1;31mERROR\033[0m"
    break
  fi
  COUNT=$((${COUNT}+1))
  sleep 1
  echo -n "."
done

DIRECT="`readConfigKey "directboot" "${USER_CONFIG_FILE}"`"
if [ "${DIRECT}" = "true" ]; then
  grub-editenv ${GRUB_PATH}/grubenv set dsm_cmdline="${CMDLINE_DIRECT}"
  echo -e "\033[1;33mReboot to boot directly in DSM\033[0m"
  grub-editenv ${GRUB_PATH}/grubenv set next_entry="direct"
  reboot
  sleep 100
  exit
fi
echo -e "\033[1;37mLoading DSM kernel...\033[0m"

# Executes DSM kernel via KEXEC
if [ "${EFI_BUG}" = "yes" -a ${EFI} -eq 1 ]; then
  echo -e "\033[1;33mWarning, running kexec with --noefi param, strange things will happen!!\033[0m"
  kexec --args-linux --noefi -l "${MOD_ZIMAGE_FILE}" --initrd "${MOD_RDGZ_FILE}" --command-line="${CMDLINE_LINE}" >"${LOG_FILE}" 2>&1 || dieLog
else
  kexec --args-linux -l "${MOD_ZIMAGE_FILE}" --initrd "${MOD_RDGZ_FILE}" --command-line="${CMDLINE_LINE}" >"${LOG_FILE}" 2>&1 || dieLog
fi
/sbin/swapoff -a >/dev/null 2>&1 || true
/bin/umount -a -r >/dev/null 2>&1 || true
echo -e "\033[1;37mBooting...\033[0m"
kexec -e -a >"${LOG_FILE}" 2>&1 || dieLog
