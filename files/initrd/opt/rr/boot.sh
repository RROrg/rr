#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# shellcheck disable=SC2034

set -e
[ -z "${WORK_PATH}" ] || [ ! -d "${WORK_PATH}/include" ] && WORK_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. "${WORK_PATH}/include/functions.sh"
[ -z "${LOADER_DISK}" ] && die "$(TEXT "Loader is not init!")"
# Sanity check
loaderIsConfigured || die "$(TEXT "Loader is not configured!")"

# Clear logs for dbgutils addons
rm -rf "${PART1_PATH}/logs" /sys/fs/pstore/* >/dev/null 2>&1 || true

# Check if machine has EFI
EFI=$([ -d /sys/firmware/efi ] && echo 1 || echo 0)
FBI=$(cat /sys/class/graphics/fb*/name 2>/dev/null | head -1)
BUS=$(getBus "${LOADER_DISK}")

# Print text centralized
clear
COLUMNS=$(ttysize 2>/dev/null | awk '{print $1}')
COLUMNS=${COLUMNS:-80}
WTITLE="$(printf "$(TEXT "Welcome to %s")" "${RR_TITLE}${RR_RELEASE:+(${RR_RELEASE})}")"
DATE="$(date)"
printf "\033[1;44m%*s\n" "${COLUMNS}" ""
printf "\033[1;44m%*s\033[A\n" "${COLUMNS}" ""
printf "\033[1;31m%*s\033[0m\n" "$(((${#WTITLE} + ${COLUMNS}) / 2))" "${WTITLE}"
printf "\033[1;44m%*s\033[A\n" "${COLUMNS}" ""
printf "\033[1;32m%*s\033[0m\n" "${COLUMNS}" "${DATE}"

BTITLE="Boot Type:"
BTITLE+="$([ ${EFI} -eq 1 ] && echo " [UEFI]" || echo " [BIOS]")"
BTITLE+="$([ "${BUS}" = "usb" ] && echo " [${BUS^^} flashdisk]" || echo " [${BUS^^} DoM]")"
printf "\033[1;33m%*s\033[0m\n" $(((${#BTITLE} + ${COLUMNS}) / 2)) "${BTITLE}"

if [ -f "${PART1_PATH}/.upgraded" ]; then
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
  if [ -n "${MODEL}" ] && [ -n "${PLATFORM}" ]; then
    printf "\033[1;43m%s\033[0m\n" "$(TEXT "Reconfigure after upgrade ...")"
    PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
    PATURL="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
    PATSUM="$(readConfigKey "patsum" "${USER_CONFIG_FILE}")"
    ./menu.sh reconfiguringM "${MODEL}" "${PLATFORM}" || {
      echo -e "$(TEXT "Reconfiguration failed!")"
      exit 1
    }
    if [ -n "${PRODUCTVER}" ] && [ -n "${PATURL}" ]; then
      ./menu.sh reconfiguringV "${PRODUCTVER}" "${PATURL}" "${PATSUM}" || {
        echo -e "$(TEXT "Reconfiguration failed!")"
        exit 1
      }
    fi
  fi
  rm -f "${PART1_PATH}/.upgraded"
fi
# Check if DSM zImage changed, patch it if necessary
ZIMAGE_HASH="$(readConfigKey "zimage-hash" "${USER_CONFIG_FILE}")"
if [ -f "${PART1_PATH}/.build" ] || [ "$(sha256sum "${ORI_ZIMAGE_FILE}" | awk '{print $1}')" != "${ZIMAGE_HASH}" ]; then
  printf "\033[1;43m%s\033[0m\n" "$(TEXT "DSM zImage changed")"
  ${WORK_PATH}/zimage-patch.sh || {
    printf "\033[1;43m%s\n%s\n%s:\n%s\033[0m\n" "$(TEXT "DSM zImage not patched")" "$(TEXT "Please upgrade the bootloader version and try again.")" "$(TEXT "Error")" "$(cat "${LOG_FILE}")"
    exit 1
  }
fi

# Check if DSM ramdisk changed, patch it if necessary
RAMDISK_HASH="$(readConfigKey "ramdisk-hash" "${USER_CONFIG_FILE}")"
if [ -f "${PART1_PATH}/.build" ] || [ "$(sha256sum "${ORI_RDGZ_FILE}" | awk '{print $1}')" != "${RAMDISK_HASH}" ]; then
  printf "\033[1;43m%s\033[0m\n" "$(TEXT "DSM ramdisk changed")"
  ${WORK_PATH}/ramdisk-patch.sh || {
    printf "\033[1;43m%s\n%s\n%s:\n%s\033[0m\n" "$(TEXT "DSM ramdisk not patched")" "$(TEXT "Please upgrade the bootloader version and try again.")" "$(TEXT "Error")" "$(cat "${LOG_FILE}")"
    exit 1
  }
fi
[ -f "${PART1_PATH}/.build" ] && rm -f "${PART1_PATH}/.build"

# Load necessary variables
PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
MODELID="$(readConfigKey "modelid" "${USER_CONFIG_FILE}")"
PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
SMALLNUM="$(readConfigKey "smallnum" "${USER_CONFIG_FILE}")"
DT="$(readConfigKey "dt" "${USER_CONFIG_FILE}")"
KVER="$(readConfigKey "kver" "${USER_CONFIG_FILE}")"
KPRE="$(readConfigKey "kpre" "${USER_CONFIG_FILE}")"
KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"
LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"

MEV="$(virt-what 2>/dev/null | head -1)"
DMI="$(dmesg 2>/dev/null | grep -i "DMI:" | head -1 | sed 's/\[.*\] DMI: //i')"
CPU="$(awk -F': ' '/model name/ {print $2}' /proc/cpuinfo | uniq)"
MEM="$(awk '/MemTotal:/ {printf "%.0f", $2 / 1024}' /proc/meminfo) MB"

printf "%s \033[1;36m%s(%s)\033[0m\n" "$(TEXT "Model:   ")" "${MODEL}" "${PLATFORM}"
printf "%s \033[1;36m%s(%s%s)\033[0m\n" "$(TEXT "Version: ")" "${PRODUCTVER}" "${BUILDNUM}" "$([ ${SMALLNUM:-0} -ne 0 ] && echo "u${SMALLNUM}")"
printf "%s \033[1;36m%s\033[0m\n" "$(TEXT "Kernel:  ")" "${KERNEL}"
printf "%s \033[1;36m%s\033[0m\n" "$(TEXT "LKM:     ")" "${LKM}"
printf "%s \033[1;36m%s\033[0m\n" "$(TEXT "MEV:     ")" "${MEV:-physical}"
printf "%s \033[1;36m%s\033[0m\n" "$(TEXT "DMI:     ")" "${DMI}"
printf "%s \033[1;36m%s\033[0m\n" "$(TEXT "CPU:     ")" "${CPU}"
printf "%s \033[1;36m%s\033[0m\n" "$(TEXT "MEM:     ")" "${MEM}"

if readConfigMap "addons" "${USER_CONFIG_FILE}" | grep -q nvmesystem; then
  [ -z "$(ls /dev/nvme* | grep -vE "${LOADER_DISK}[0-9]?$" 2>/dev/null)" ] && printf "\033[1;33m*** %s ***\033[0m\n" "$(TEXT "Notice: Please insert at least one m.2 disk for system installation.")"
else
	[ -z "$(ls /dev/sd* | grep -vE "${LOADER_DISK}[0-9]?$" 2>/dev/null)" ] && printf "\033[1;33m*** %s ***\033[0m\n" "$(TEXT "Notice: Please insert at least one sata disk for system installation.")"
fi

if checkBIOS_VT_d && [ "$(echo "${KVER:-4}" | cut -d'.' -f1)" -lt 5 ]; then
  printf "\033[1;33m*** %s ***\033[0m\n" "$(TEXT "Notice: Please disable Intel(VT-d)/AMD(AMD-Vi) in BIOS/UEFI settings if you encounter a boot failure.")"
fi

VID="$(readConfigKey "vid" "${USER_CONFIG_FILE}")"
PID="$(readConfigKey "pid" "${USER_CONFIG_FILE}")"
SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"
MAC1="$(readConfigKey "mac1" "${USER_CONFIG_FILE}")"
MAC2="$(readConfigKey "mac2" "${USER_CONFIG_FILE}")"
KERNELPANIC="$(readConfigKey "kernelpanic" "${USER_CONFIG_FILE}")"
HDDSORT="$(readConfigKey "hddsort" "${USER_CONFIG_FILE}")"
USBASINTERNAL="$(readConfigKey "usbasinternal" "${USER_CONFIG_FILE}")"
EMMCBOOT="$(readConfigKey "emmcboot" "${USER_CONFIG_FILE}")"
MODBLACKLIST="$(readConfigKey "modblacklist" "${USER_CONFIG_FILE}")"

declare -A CMDLINE

# Automatic values
CMDLINE['syno_hw_version']="${MODELID:-${MODEL}}"
CMDLINE['vid']="${VID:-"0x46f4"}" # Sanity check
CMDLINE['pid']="${PID:-"0x0001"}" # Sanity check

if [ -z "${SN}" ]; then
  SN="$(generateSerial "${MODEL}")"
  writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
fi
CMDLINE['sn']="${SN}"

if [ -z "${MAC1}" ]; then
  if [ -n "${MAC2}" ]; then
    MAC1=${MAC2}
    MAC2=""
    writeConfigKey "mac1" "${MAC1}" "${USER_CONFIG_FILE}"
    writeConfigKey "mac2" "${MAC2}" "${USER_CONFIG_FILE}"
  else
    NETIF_NUM=2
    MACS="$(generateMacAddress "${MODEL}" ${NETIF_NUM})"
    for I in $(seq 1 ${NETIF_NUM}); do
      eval MAC${I}="$(echo ${MACS} | cut -d' ' -f${I})"
      writeConfigKey "mac${I}" "$(echo ${MACS} | cut -d' ' -f${I})" "${USER_CONFIG_FILE}"
    done
  fi
fi
[ -n "${MAC1}" ] && CMDLINE['mac1']="${MAC1}" && CMDLINE['netif_num']="1"
[ -n "${MAC2}" ] && CMDLINE['mac2']="${MAC2}" && CMDLINE['netif_num']="2"

CMDLINE['skip_vender_mac_interfaces']="$(seq -s, 0 $((${CMDLINE['netif_num']:-1} - 1)))"

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
if [ "$(echo "${KVER:-4}" | cut -d'.' -f1)" -lt 5 ]; then
  if [ ! "${BUS}" = "usb" ]; then
    SZ=$(blockdev --getsz "${LOADER_DISK}" 2>/dev/null) # SZ=$(cat /sys/block/${LOADER_DISK/\/dev\//}/size)
    SS=$(blockdev --getss "${LOADER_DISK}" 2>/dev/null) # SS=$(cat /sys/block/${LOADER_DISK/\/dev\//}/queue/hw_sector_size)
    SIZE=$((${SZ:-0} * ${SS:-0} / 1024 / 1024 + 10))
    # Read SATADoM type
    SATADOM="$(readConfigKey "satadom" "${USER_CONFIG_FILE}")"
    CMDLINE['synoboot_satadom']="${SATADOM:-2}"
    CMDLINE['dom_szmax']="${SIZE}"
  fi
  CMDLINE["elevator"]="elevator"
else
  CMDLINE["split_lock_detect"]="off"
  # CMDLINE['module.sig_enforce']="0"
  # CMDLINE['loadpin.enforce']="0"
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
CMDLINE['earlyprintk']=""
CMDLINE['earlycon']="uart8250,io,0x3f8,115200n8"
CMDLINE['console']="ttyS0,115200n8"
CMDLINE['consoleblank']="600"
# CMDLINE['no_console_suspend']="1"
CMDLINE['root']="/dev/md0"
CMDLINE['loglevel']="15"
CMDLINE['log_buf_len']="32M"
CMDLINE['rootwait']=""
CMDLINE['panic']="${KERNELPANIC:-0}"
# CMDLINE['intremap']="off" # no need
# CMDLINE['amd_iommu_intr']="legacy" # no need
# CMDLINE['split_lock_detect']="off" # check KVER
CMDLINE['pcie_aspm']="off"
# CMDLINE['intel_pstate']="disable"
# CMDLINE['amd_pstate']="disable"
# CMDLINE['nox2apic']=""  # check platform
# CMDLINE['nomodeset']=""
CMDLINE['nowatchdog']=""

CMDLINE['modprobe.blacklist']="${MODBLACKLIST}"
CMDLINE['mev']="${MEV:-physical}"

if [ "${MEV:-physical}" = "vmware" ]; then
  CMDLINE['tsc']="reliable"
  CMDLINE['pmtmr']="0x0"
fi

if [ "${HDDSORT}" = "true" ]; then
  CMDLINE['hddsort']=""
fi
if [ "${USBASINTERNAL}" = "true" ]; then
  CMDLINE['usbasinternal']=""
fi

if echo "apollolake geminilake purley geminilakenk" | grep -wq "${PLATFORM}"; then
  CMDLINE["nox2apic"]=""
fi

# # Save command line to grubenv  RR_CMDLINE= ... nox2apic
# if echo "apollolake geminilake purley geminilakenk" | grep -wq "${PLATFORM}"; then
#   if grep -Eq "^flags.*x2apic.*" /proc/cpuinfo; then
#     checkCmdline "rr_cmdline" "nox2apic" || addCmdline "rr_cmdline" "nox2apic"
#   fi
# else
#   checkCmdline "rr_cmdline" "nox2apic" && delCmdline "rr_cmdline" "nox2apic"
# fi

# if [ -n "$(ls /dev/mmcblk* 2>/dev/null)" ] && [ ! "${BUS}" = "mmc" ] && [ ! "${EMMCBOOT}" = "true" ]; then
#   if ! echo "${CMDLINE['modprobe.blacklist']}" | grep -q "sdhci"; then
#     [ ! "${CMDLINE['modprobe.blacklist']}" = "" ] && CMDLINE['modprobe.blacklist']+=","
#     CMDLINE['modprobe.blacklist']+="sdhci,sdhci_pci,sdhci_acpi"
#   fi
# fi
if [ "${DT}" = "true" ] && ! echo "purley broadwellnkv2 epyc7002 geminilakenk r1000nk v1000nk" | grep -wq "${PLATFORM}"; then
  if ! echo "${CMDLINE['modprobe.blacklist']}" | grep -q "mpt3sas"; then
    [ ! "${CMDLINE['modprobe.blacklist']}" = "" ] && CMDLINE['modprobe.blacklist']+=","
    CMDLINE['modprobe.blacklist']+="mpt3sas"
  fi
#else
#  CMDLINE['scsi_mod.scan']="sync"  # TODO: redpill panic of vmware scsi? (add to cmdline)
fi

# CMDLINE['kvm.ignore_msrs']="1"
# CMDLINE['kvm.report_ignored_msrs']="0"

if echo "apollolake geminilake geminilakenk" | grep -wq "${PLATFORM}"; then
  CMDLINE["intel_iommu"]="igfx_off"
fi

if echo "purley broadwellnkv2" | grep -wq "${PLATFORM}"; then
  CMDLINE["SASmodel"]="1"
fi

SSID="$(cat "${PART1_PATH}/wpa_supplicant.conf" 2>/dev/null | grep 'ssid=' | cut -d'=' -f2 | sed 's/^"//; s/"$//' | xxd -p | tr -d '\n')"
PSK="$(cat "${PART1_PATH}/wpa_supplicant.conf" 2>/dev/null | grep 'psk=' | cut -d'=' -f2 | sed 's/^"//; s/"$//' | xxd -p | tr -d '\n')"

if [ -n "${SSID}" ] && [ -n "${PSK}" ]; then
  CMDLINE["wpa.ssid"]="${SSID}"
  CMDLINE["wpa.psk"]="${PSK}"
fi

while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && CMDLINE["network.${KEY}"]="${VALUE}"
done <<<"$(readConfigMap "network" "${USER_CONFIG_FILE}")"

while IFS=': ' read -r KEY VALUE; do
  [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
done <<<"$(readConfigMap "cmdline" "${USER_CONFIG_FILE}")"

# Prepare command line
CMDLINE_LINE=""
for KEY in "${!CMDLINE[@]}"; do
  VALUE="${CMDLINE[${KEY}]}"
  CMDLINE_LINE+=" ${KEY}"
  [ -n "${VALUE}" ] && CMDLINE_LINE+="=${VALUE}"
done
CMDLINE_LINE="$(echo "${CMDLINE_LINE}" | sed 's/^ //')" # Remove leading space
printf "%s:\n\033[1;36m%s\033[0m\n" "$(TEXT "Cmdline")" "${CMDLINE_LINE}"

# Check if user wants to modify at this stage
function _bootwait() {
  BOOTWAIT="$(readConfigKey "bootwait" "${USER_CONFIG_FILE}")"
  [ -z "${BOOTWAIT}" ] && BOOTWAIT=10
  busybox w 2>/dev/null | awk '{print $1" "$2" "$4" "$5" "$6}' >WB
  MSG=""
  while [ ${BOOTWAIT} -gt 0 ]; do
    sleep 1
    BOOTWAIT=$((BOOTWAIT - 1))
    MSG="$(printf "\033[1;33m$(TEXT "%2ds (Changing access(ssh/web) status will interrupt boot)")\033[0m" "${BOOTWAIT}")"
    printf "\r${MSG}"
    busybox w 2>/dev/null | awk '{print $1" "$2" "$4" "$5" "$6}' >WC
    if ! diff WB WC >/dev/null 2>&1; then
      printf "\r%$((${#MSG} * 2))s\n" " "
      printf "\r\033[1;33m%s\033[0m\n" "$(TEXT "Access(ssh/web) status has changed and booting is interrupted.")"
      rm -f WB WC
      return 1
    fi
    if ! ps -p "${PPID}" -o cmd | grep -q "menu.sh" && [ -f "${TMP_PATH}/menu.lock" ]; then
      printf "\r%$((${#MSG} * 2))s\n" " "
      printf "\r\033[1;33m%s\033[0m\n" "$(TEXT "Menu opened and booting is interrupted.")"
      rm -f WB WC
      return 1
    fi
  done
  rm -f WB WC
  printf "\r%$((${#MSG} * 2))s\n" " "
  return 0
}

DIRECT="$(readConfigKey "directboot" "${USER_CONFIG_FILE}")"
if [ "${DIRECT}" = "true" ] || echo "parallels xen" | grep -qw "${MEV:-physical}"; then
  # grubenv file limit is 1024 bytes.
  grub-editenv "${USER_RSYSENVFILE}" create
  grub-editenv "${USER_RSYSENVFILE}" set rr_version="${WTITLE}"
  grub-editenv "${USER_RSYSENVFILE}" set rr_booting="${BTITLE}"
  grub-editenv "${USER_RSYSENVFILE}" set dsm_model="${MODEL}(${PLATFORM})"
  grub-editenv "${USER_RSYSENVFILE}" set dsm_version="${PRODUCTVER}(${BUILDNUM}$([ ${SMALLNUM:-0} -ne 0 ] && echo "u${SMALLNUM}"))"
  grub-editenv "${USER_RSYSENVFILE}" set dsm_kernel="${KERNEL}"
  grub-editenv "${USER_RSYSENVFILE}" set dsm_lkm="${LKM}"
  grub-editenv "${USER_RSYSENVFILE}" set sys_mev="${MEV:-physical}"
  grub-editenv "${USER_RSYSENVFILE}" set sys_dmi="${DMI}"
  grub-editenv "${USER_RSYSENVFILE}" set sys_cpu="${CPU}"
  grub-editenv "${USER_RSYSENVFILE}" set sys_mem="${MEM}"

  CMDLINE_DIRECT=$(echo "${CMDLINE_LINE}" | sed 's/>/\\\\>/g') # Escape special chars
  grub-editenv "${USER_GRUBENVFILE}" set dsm_cmdline="${CMDLINE_DIRECT}"
  grub-editenv "${USER_GRUBENVFILE}" set next_entry="direct"

  _bootwait || exit 0

  printf "\033[1;33m%s\033[0m\n" "$(TEXT "Reboot to boot directly in DSM")"
  [ ! -f "/.dockerenv" ] && reboot
  exit 0
else
  rm -f "${USER_RSYSENVFILE}" 2>/dev/null || true
  grub-editenv "${USER_GRUBENVFILE}" unset dsm_cmdline
  grub-editenv "${USER_GRUBENVFILE}" unset next_entry
  ETHX="$(find /sys/class/net/ -mindepth 1 -maxdepth 1 ! -name lo -exec basename {} \; | sort)"
  printf "$(TEXT "Detected %s network cards.\n")" "$(echo "${ETHX}" | wc -w)"
  printf "$(TEXT "Checking Connect.")"
  COUNT=0
  BOOTIPWAIT="$(readConfigKey "bootipwait" "${USER_CONFIG_FILE}")"
  BOOTIPWAIT=${BOOTIPWAIT:-10}
  while [ ${COUNT} -lt $((${BOOTIPWAIT} + 32)) ]; do
    MSG=""
    for N in ${ETHX}; do
      if [ "1" = "$(cat "/sys/class/net/${N}/carrier" 2>/dev/null)" ]; then
        MSG+="${N} "
      fi
    done
    if [ -n "${MSG}" ]; then
      printf "\r%s%s                  \n" "${MSG}" "$(TEXT "connected.")"
      break
    fi
    COUNT=$((COUNT + 1))
    printf "."
    sleep 1
  done
  if [ ! -f "/.dockerenv" ]; then
    [ ! -f /var/run/dhcpcd/pid ] && /etc/init.d/S41dhcpcd restart >/dev/null 2>&1 || true
  fi
  printf "$(TEXT "Waiting IP.\n")"
  for N in ${ETHX}; do
    COUNT=0
    DRIVER="$(basename "$(realpath "/sys/class/net/${N}/device/driver" 2>/dev/null)" 2>/dev/null)"
    MAC="$(cat "/sys/class/net/${N}/address" 2>/dev/null)" || MAC="00:00:00:00:00:00"
    printf "%s(%s): " "${N}" "${MAC}@${DRIVER}"
    while true; do
      if false && [ ! "${N::3}" = "eth" ]; then
        printf "\r%s(%s): %s\n" "${N}" "${MAC}@${DRIVER}" "$(TEXT "IGNORE (Does not support non-wired network card.)")"
        break
      fi
      if [ -z "$(cat "/sys/class/net/${N}/carrier" 2>/dev/null)" ]; then
        printf "\r%s(%s): %s\n" "${N}" "${MAC}@${DRIVER}" "$(TEXT "DOWN")"
        break
      fi
      if [ "0" = "$(cat "/sys/class/net/${N}/carrier" 2>/dev/null)" ]; then
        printf "\r%s(%s): %s\n" "${N}" "${MAC}@${DRIVER}" "$(TEXT "NOT CONNECTED")"
        break
      fi
      if [ ${COUNT} -eq ${BOOTIPWAIT} ]; then # Under normal circumstances, no errors should occur here.
        printf "\r%s(%s): %s\n" "${N}" "${MAC}@${DRIVER}" "$(TEXT "TIMEOUT (Please check the IP on the router.)")"
        break
      fi
      COUNT=$((COUNT + 1))
      IP="$(getIP "${N}")"
      if [ -n "${IP}" ]; then
        if echo "${IP}" | grep -q "^169\.254\."; then
          printf "\r%s(%s): %s\n" "${N}" "${MAC}@${DRIVER}" "$(TEXT "LINK LOCAL (No DHCP server detected.)")"
        else
          printf "\r%s(%s): %s\n" "${N}" "${MAC}@${DRIVER}" "$(printf "$(TEXT "Access \033[1;34mhttp://%s:5000\033[0m to connect the DSM via web.")" "${IP}")"
        fi
        break
      fi
      printf "."
      sleep 1
    done
  done

  _bootwait || exit 0

  [ -n "$(cat "${ADD_TIPS_FILE}" 2>/dev/null)" ] && printf "$(TEXT "%s\n")" "$(cat "${ADD_TIPS_FILE}" 2>/dev/null)"
  printf "\033[1;37m%s\033[0m\n" "$(TEXT "Loading DSM kernel ...")"

  DSMLOGO="$(readConfigKey "dsmlogo" "${USER_CONFIG_FILE}")"
  if [ "${DSMLOGO}" = "true" ] && [ -c "/dev/fb0" ]; then
    IP="$(getIP)"
    echo "${IP}" | grep -q "^169\.254\." && IP=""
    [ -n "${IP}" ] && URL="http://${IP}:5000" || URL="http://find.synology.com/"
    python3 "${WORK_PATH}/include/functions.py" "makeqr" -d "${URL}" -l "7" -o "${TMP_PATH}/qrcode_boot.png"
    [ -f "${TMP_PATH}/qrcode_boot.png" ] && echo | fbv -acufi "${TMP_PATH}/qrcode_boot.png" >/dev/null 2>&1 || true
  fi

  # Executes DSM kernel via KEXEC
  KEXECARGS="-a"
  if [ "$(echo "${KVER:-4}" | cut -d'.' -f1)" -lt 4 ] && [ ${EFI} -eq 1 ]; then
    printf "\033[1;33m%s\033[0m\n" "$(TEXT "Warning, running kexec with --noefi param, strange things will happen!!")"
    KEXECARGS+=" --noefi"
  fi
  kexec ${KEXECARGS} -l "${MOD_ZIMAGE_FILE}" --initrd "${MOD_RDGZ_FILE}" --command-line="${CMDLINE_LINE} kexecboot" >"${LOG_FILE}" 2>&1 || dieLog

  printf "\033[1;37m%s\033[0m\n" "$(TEXT "Booting ...")"
  # show warning message
  for T in $(busybox w 2>/dev/null | grep -v 'TTY' | awk '{print $2}'); do
    if [ -w "/dev/${T}" ]; then
      echo -e "\n\033[1;43m$(TEXT "Interface not operational. Wait a few minutes.\nFind DSM via http://find.synology.com/ or Synology Assistant.")\033[0m\n" >"/dev/${T}" 2>/dev/null || true
    fi
  done

  if [ ! -f "/.dockerenv" ]; then
    # Disconnect wireless
    lsmod | grep -q iwlwifi && for F in /sys/class/net/wlan*; do
      [ ! -e "${F}" ] && continue
      connectwlanif "$(basename "${F}")" 0 2>/dev/null
    done
    # Unload all network drivers
    # for F in $(realpath /sys/class/net/*/device/driver); do [ ! -e "${F}" ] && continue; rmmod -f "$(basename ${F})" 2>/dev/null || true; done

    # Unload all graphics drivers
    # for D in $(lsmod | grep -E '^(nouveau|amdgpu|radeon|i915)' | awk '{print $1}'); do rmmod -f "${D}" 2>/dev/null || true; done
    # for I in $(find /sys/devices -name uevent -exec bash -c 'cat {} 2>/dev/null | grep -Eq "PCI_CLASS=0?30[0|1|2]00" && dirname {}' \;); do
    #   [ -e ${I}/reset ] && cat "${I}/vendor" >/dev/null | grep -iq 0x10de && echo 1 >${I}/reset || true # Proc open nvidia driver when booting
    # done

    # Reboot
    KERNELWAY="$(readConfigKey "kernelway" "${USER_CONFIG_FILE}")"
    [ "${KERNELWAY}" = "kexec" ] && kexec -e || poweroff
  fi
  exit 0
fi
