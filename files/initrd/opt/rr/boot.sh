#!/usr/bin/env bash

set -e
[ -z "${WORK_PATH}" -o ! -d "${WORK_PATH}/include" ] && WORK_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. ${WORK_PATH}/include/functions.sh

[ -z "${LOADER_DISK}" ] && die "$(TEXT "Loader is not init!")"
# Sanity check
loaderIsConfigured || die "$(TEXT "Loader is not configured!")"

# Clear logs for dbgutils addons
rm -rf "${PART1_PATH}/logs" >/dev/null 2>&1 || true
rm -rf /sys/fs/pstore/* >/dev/null 2>&1 || true

# Check if machine has EFI
[ -d /sys/firmware/efi ] && EFI=1 || EFI=0

BUS=$(getBus "${LOADER_DISK}")

# Print text centralized
clear
[ -z "${COLUMNS}" ] && COLUMNS=50
TITLE="$(printf "$(TEXT "Welcome to %s")" "$([ -z "${RR_RELEASE}" ] && echo "${RR_TITLE}" || echo "${RR_TITLE}(${RR_RELEASE})")")"
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
if [ -f ${PART1_PATH}/.build -o "$(sha256sum "${ORI_ZIMAGE_FILE}" | awk '{print $1}')" != "${ZIMAGE_HASH}" ]; then
  echo -e "\033[1;43m$(TEXT "DSM zImage changed")\033[0m"
  ${WORK_PATH}/zimage-patch.sh
  if [ $? -ne 0 ]; then
    echo -e "\033[1;43m$(TEXT "zImage not patched,\nPlease upgrade the bootloader version and try again.\nPatch error:\n")$(cat "${LOG_FILE}")\033[0m"
    exit 1
  fi
fi

# Check if DSM ramdisk changed, patch it if necessary
RAMDISK_HASH="$(readConfigKey "ramdisk-hash" "${USER_CONFIG_FILE}")"
if [ -f ${PART1_PATH}/.build -o "$(sha256sum "${ORI_RDGZ_FILE}" | awk '{print $1}')" != "${RAMDISK_HASH}" ]; then
  echo -e "\033[1;43m$(TEXT "DSM Ramdisk changed")\033[0m"
  ${WORK_PATH}/ramdisk-patch.sh
  if [ $? -ne 0 ]; then
    echo -e "\033[1;43m$(TEXT "Ramdisk not patched,\nPlease upgrade the bootloader version and try again.\nPatch error:\n")$(cat "${LOG_FILE}")\033[0m"
    exit 1
  fi
fi
[ -f ${PART1_PATH}/.build ] && rm -f ${PART1_PATH}/.build

# Load necessary variables
PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
MODELID="$(readConfigKey "modelid" "${USER_CONFIG_FILE}")"
PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
SMALLNUM="$(readConfigKey "smallnum" "${USER_CONFIG_FILE}")"
KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"
LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"

DMI="$(dmesg 2>/dev/null | grep -i "DMI:" | sed 's/\[.*\] DMI: //i')"
CPU="$(echo $(cat /proc/cpuinfo 2>/dev/null | grep 'model name' | uniq | awk -F':' '{print $2}'))"
MEM="$(awk '/MemTotal:/ {printf "%.0f", $2 / 1024}' /proc/meminfo 2>/dev/null) MB"

echo -e "$(TEXT "Model:   ") \033[1;36m${MODEL}(${PLATFORM})\033[0m"
echo -e "$(TEXT "Version: ") \033[1;36m${PRODUCTVER}(${BUILDNUM}$([ ${SMALLNUM:-0} -ne 0 ] && echo "u${SMALLNUM}"))\033[0m"
echo -e "$(TEXT "Kernel:  ") \033[1;36m${KERNEL}\033[0m"
echo -e "$(TEXT "LKM:     ") \033[1;36m${LKM}\033[0m"
echo -e "$(TEXT "DMI:     ") \033[1;36m${DMI}\033[0m"
echo -e "$(TEXT "CPU:     ") \033[1;36m${CPU}\033[0m"
echo -e "$(TEXT "MEM:     ") \033[1;36m${MEM}\033[0m"

if ! readConfigMap "addons" "${USER_CONFIG_FILE}" | grep -q nvmesystem; then
  HASATA=0
  for D in $(lsblk -dpno NAME); do
    [ "${D}" = "${LOADER_DISK}" ] && continue
    if echo "sata sas scsi" | grep -qw "$(getBus "${D}")"; then
      HASATA=1
      break
    fi
  done
  [ ${HASATA} = "0" ] && echo -e "\033[1;33m*** $(TEXT "Please insert at least one sata/scsi disk for system installation, except for the bootloader disk.") ***\033[0m"
fi

VID="$(readConfigKey "vid" "${USER_CONFIG_FILE}")"
PID="$(readConfigKey "pid" "${USER_CONFIG_FILE}")"
SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"
MAC1="$(readConfigKey "mac1" "${USER_CONFIG_FILE}")"
MAC2="$(readConfigKey "mac2" "${USER_CONFIG_FILE}")"
KERNELPANIC="$(readConfigKey "kernelpanic" "${USER_CONFIG_FILE}")"
EMMCBOOT="$(readConfigKey "emmcboot" "${USER_CONFIG_FILE}")"
MODBLACKLIST="$(readConfigKey "modblacklist" "${USER_CONFIG_FILE}")"

declare -A CMDLINE

# Automatic values
CMDLINE['syno_hw_version']="${MODELID:-${MODEL}}"
CMDLINE['vid']="${VID:-"0x46f4"}" # Sanity check
CMDLINE['pid']="${PID:-"0x0001"}" # Sanity check
CMDLINE['sn']="${SN}"

CMDLINE['netif_num']="0"
[ -z "${MAC1}" -a -n "${MAC2}" ] && MAC1=${MAC2} && MAC2="" # Sanity check
[ -n "${MAC1}" ] && CMDLINE['mac1']="${MAC1}" && CMDLINE['netif_num']="1"
[ -n "${MAC2}" ] && CMDLINE['mac2']="${MAC2}" && CMDLINE['netif_num']="2"

# set fixed cmdline
if grep -q "force_junior" /proc/cmdline; then
  CMDLINE['force_junior']=""
fi
if grep -q "recovery" /proc/cmdline; then
  CMDLINE['force_junior']=""
  CMDLINE['recovery']=""
fi
if [ ${EFI} -eq 1 ]; then
  CMDLINE['withefi']=""
else
  CMDLINE['noefi']=""
fi
DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${WORK_PATH}/platforms.yml")"
KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${WORK_PATH}/platforms.yml")"
KPRE="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kpre" "${WORK_PATH}/platforms.yml")"
if [ $(echo "${KVER:-4}" | cut -d'.' -f1) -lt 5 ]; then
  if [ ! "${BUS}" = "usb" ]; then
    SZ=$(blockdev --getsz ${LOADER_DISK} 2>/dev/null) # SZ=$(cat /sys/block/${LOADER_DISK/\/dev\//}/size)
    SS=$(blockdev --getss ${LOADER_DISK} 2>/dev/null) # SS=$(cat /sys/block/${LOADER_DISK/\/dev\//}/queue/hw_sector_size)
    SIZE=$((${SZ:-0} * ${SS:-0} / 1024 / 1024 + 10))
    # Read SATADoM type
    SATADOM="$(readConfigKey "satadom" "${USER_CONFIG_FILE}")"
    CMDLINE['synoboot_satadom']="${SATADOM:-2}"
    CMDLINE['dom_szmax']="${SIZE}"
  fi
  CMDLINE["elevator"]="elevator"
fi
if [ "${DT}" = "true" ]; then
  CMDLINE["syno_ttyS0"]="serial,0x3f8"
  CMDLINE["syno_ttyS1"]="serial,0x2f8"
else
  CMDLINE["SMBusHddDynamicPower"]="1"
  CMDLINE["syno_hdd_detect"]="0"
  CMDLINE["syno_hdd_powerup_seq"]="0"
fi
CMDLINE["HddHotplug"]="1"
CMDLINE["vender_format_version"]="2"
CMDLINE['skip_vender_mac_interfaces']="0,1,2,3,4,5,6,7"

CMDLINE['earlyprintk']=""
CMDLINE['earlycon']="uart8250,io,0x3f8,115200n8"
CMDLINE['console']="ttyS0,115200n8"
CMDLINE['consoleblank']="600"
# CMDLINE['no_console_suspend']="1"
CMDLINE['root']="/dev/md0"
CMDLINE['rootwait']=""
CMDLINE['loglevel']="15"
CMDLINE['log_buf_len']="32M"
CMDLINE['panic']="${KERNELPANIC:-0}"
CMDLINE['pcie_aspm']="off"
CMDLINE['modprobe.blacklist']="${MODBLACKLIST}"

# if [ -n "$(ls /dev/mmcblk* 2>/dev/null)" ] && [ ! "${BUS}" = "mmc" ] && [ ! "${EMMCBOOT}" = "true" ]; then
#   if ! echo "${CMDLINE['modprobe.blacklist']}" | grep -q "sdhci"; then
#     [ ! "${CMDLINE['modprobe.blacklist']}" = "" ] && CMDLINE['modprobe.blacklist']+=","
#     CMDLINE['modprobe.blacklist']+="sdhci,sdhci_pci,sdhci_acpi"
#   fi
# fi
if [ "${DT}" = "true" ] && ! echo "epyc7002 purley broadwellnkv2" | grep -wq "${PLATFORM}"; then
  if ! echo "${CMDLINE['modprobe.blacklist']}" | grep -q "mpt3sas"; then
    [ ! "${CMDLINE['modprobe.blacklist']}" = "" ] && CMDLINE['modprobe.blacklist']+=","
    CMDLINE['modprobe.blacklist']+="mpt3sas"
  fi
fi

# CMDLINE['kvm.ignore_msrs']="1"
# CMDLINE['kvm.report_ignored_msrs']="0"

if echo "apollolake geminilake" | grep -wq "${PLATFORM}"; then
  CMDLINE["intel_iommu"]="igfx_off"
fi
if echo "purley broadwellnkv2" | grep -wq "${PLATFORM}"; then
  CMDLINE["SASmodel"]="1"
fi

while IFS=': ' read KEY VALUE; do
  [ -n "${KEY}" ] && CMDLINE["network.${KEY}"]="${VALUE}"
done <<<$(readConfigMap "network" "${USER_CONFIG_FILE}")

while IFS=': ' read KEY VALUE; do
  [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
done <<<$(readConfigMap "cmdline" "${USER_CONFIG_FILE}")

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
  grub-editenv ${USER_GRUBENVFILE} set dsm_cmdline="${CMDLINE_DIRECT}"
  grub-editenv ${USER_GRUBENVFILE} set next_entry="direct"
  echo -e "\033[1;33m$(TEXT "Reboot to boot directly in DSM")\033[0m"
  reboot
  exit 0
else
  grub-editenv ${USER_GRUBENVFILE} unset dsm_cmdline
  grub-editenv ${USER_GRUBENVFILE} unset next_entry
  ETHX=$(ls /sys/class/net/ 2>/dev/null | grep -v lo) || true
  echo "$(printf "$(TEXT "Detected %s network cards.")" "$(echo ${ETHX} | wc -w)")"
  echo -en "$(TEXT "Checking Connect.")"
  COUNT=0
  BOOTIPWAIT="$(readConfigKey "bootipwait" "${USER_CONFIG_FILE}")"
  [ -z "${BOOTIPWAIT}" ] && BOOTIPWAIT=10
  while [ ${COUNT} -lt $((${BOOTIPWAIT} + 32)) ]; do
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
      if [ ${COUNT} -eq ${BOOTIPWAIT} ]; then # Under normal circumstances, no errors should occur here.
        echo -en "\r${N}(${DRIVER}): $(TEXT "TIMEOUT (Please check the IP on the router.)")\n"
        break
      fi
      COUNT=$((${COUNT} + 1))
      IP="$(getIP ${N})"
      if [ -n "${IP}" ]; then
        if [[ "${IP}" =~ ^169\.254\..* ]]; then
          echo -en "\r${N}(${DRIVER}): $(TEXT "LINK LOCAL (No DHCP server detected.)")\n"
        else
          echo -en "\r${N}(${DRIVER}): $(printf "$(TEXT "Access \033[1;34mhttp://%s:5000\033[0m to connect the DSM via web.")" "${IP}")\n"
        fi
        break
      fi
      echo -n "."
      sleep 1
    done
  done
  BOOTWAIT="$(readConfigKey "bootwait" "${USER_CONFIG_FILE}")"
  [ -z "${BOOTWAIT}" ] && BOOTWAIT=10
  busybox w 2>/dev/null | awk '{print $1" "$2" "$4" "$5" "$6}' >WB
  MSG=""
  while test ${BOOTWAIT} -ge 0; do
    MSG="$(printf "\033[1;33m$(TEXT "%2ds (Changing access(ssh/web) status will interrupt boot)")\033[0m" "${BOOTWAIT}")"
    echo -en "\r${MSG}"
    busybox w 2>/dev/null | awk '{print $1" "$2" "$4" "$5" "$6}' >WC
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

  echo -e "\033[1;37m$(TEXT "Loading DSM kernel ...")\033[0m"

  DSMLOGO="$(readConfigKey "dsmlogo" "${USER_CONFIG_FILE}")"
  if [ "${DSMLOGO}" = "true" -a -c "/dev/fb0" ]; then
    IP="$(getIP)"
    [[ "${IP}" =~ ^169\.254\..* ]] && IP=""
    [ -n "${IP}" ] && URL="http://${IP}:5000" || URL="http://find.synology.com/"
    python ${WORK_PATH}/include/functions.py makeqr -d "${URL}" -l "6" -o "${TMP_PATH}/qrcode_boot.png"
    [ -f "${TMP_PATH}/qrcode_boot.png" ] && echo | fbv -acufi "${TMP_PATH}/qrcode_boot.png" >/dev/null 2>/dev/null || true

    python ${WORK_PATH}/include/functions.py makeqr -f "${WORK_PATH}/include/qhxg.png" -l "7" -o "${TMP_PATH}/qrcode_qhxg.png"
    [ -f "${TMP_PATH}/qrcode_qhxg.png" ] && echo | fbv -acufi "${TMP_PATH}/qrcode_qhxg.png" >/dev/null 2>/dev/null || true
  fi

  # Executes DSM kernel via KEXEC
  KEXECARGS="-a"
  if [ $(echo "${KVER:-4}" | cut -d'.' -f1) -lt 4 ] && [ ${EFI} -eq 1 ]; then
    echo -e "\033[1;33m$(TEXT "Warning, running kexec with --noefi param, strange things will happen!!")\033[0m"
    KEXECARGS+=" --noefi"
  fi
  kexec ${KEXECARGS} -l "${MOD_ZIMAGE_FILE}" --initrd "${MOD_RDGZ_FILE}" --command-line="${CMDLINE_LINE}" >"${LOG_FILE}" 2>&1 || dieLog

  echo -e "\033[1;37m$(TEXT "Booting ...")\033[0m"
  # show warning message
  for T in $(busybox w 2>/dev/null | grep -v 'TTY' | awk '{print $2}'); do
    [ -w "/dev/${T}" ] && echo -e "\n\033[1;43m$(TEXT "[This interface will not be operational. Please wait a few minutes.\nFind DSM via http://find.synology.com/ or Synology Assistant and connect.]")\033[0m\n" >"/dev/${T}" 2>/dev/null || true
  done

  # # Unload all network interfaces
  # for D in $(readlink /sys/class/net/*/device/driver); do rmmod -f "$(basename ${D})" 2>/dev/null || true; done

  # Reboot
  KERNELWAY="$(readConfigKey "kernelway" "${USER_CONFIG_FILE}")"
  [ "${KERNELWAY}" = "kexec" ] && kexec -e || poweroff
  exit 0
fi
