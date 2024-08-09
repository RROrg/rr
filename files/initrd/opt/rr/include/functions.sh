[ -z "${WORK_PATH}" -o ! -d "${WORK_PATH}/include" ] && WORK_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../" >/dev/null 2>&1 && pwd)"

. ${WORK_PATH}/include/consts.sh
. ${WORK_PATH}/include/configFile.sh
. ${WORK_PATH}/include/i18n.sh

###############################################################################
# Check loader disk
function checkBootLoader() {
  while read KNAME RO; do
    [ -z "${KNAME}" ] && continue
    [ "${RO}" = "0" ] && continue
    hdparm -r0 "${KNAME}" >/dev/null 2>&1 || true
  done <<<$(lsblk -pno KNAME,RO 2>/dev/null)
  [ ! -w "${PART1_PATH}" ] && return 1
  [ ! -w "${PART2_PATH}" ] && return 1
  [ ! -w "${PART3_PATH}" ] && return 1
  command -v awk >/dev/null 2>&1 || return 1
  command -v cut >/dev/null 2>&1 || return 1
  command -v sed >/dev/null 2>&1 || return 1
  command -v tar >/dev/null 2>&1 || return 1
  return 0
}

###############################################################################
# Check if loader is fully configured
# Returns 1 if not
function loaderIsConfigured() {
  SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"
  [ -z "${SN}" ] && return 1
  [ ! -f "${MOD_ZIMAGE_FILE}" ] && return 1
  [ ! -f "${MOD_RDGZ_FILE}" ] && return 1
  return 0 # OK
}

###############################################################################
# Just show error message and dies
function die() {
  echo -e "\033[1;41m$@\033[0m"
  exit 1
}

###############################################################################
# Show error message with log content and dies
function dieLog() {
  echo -en "\n\033[1;41mUNRECOVERY ERROR: "
  cat "${LOG_FILE}"
  echo -e "\033[0m"
  sleep 3
  exit 1
}

###############################################################################
# Check if a item exists into array
# 1 - Item
# 2.. - Array
# Return 0 if exists
function arrayExistItem() {
  EXISTS=1
  ITEM="${1}"
  shift
  for i in "$@"; do
    [ "${i}" = "${ITEM}" ] || continue
    EXISTS=0
    break
  done
  return ${EXISTS}
}

###############################################################################
# Generate a number with 6 digits from 1 to 30000
function random() {
  printf "%06d" $((${RANDOM} % 30000 + 1))
}

###############################################################################
# Generate a hexa number from 0x00 to 0xFF
function randomhex() {
  printf "&02X" "$((${RANDOM} % 255 + 1))"
}

###############################################################################
# Generate a random letter
function genRandomLetter() {
  for i in A B C D E F G H J K L M N P Q R S T V W X Y Z; do
    echo ${i}
  done | sort -R | tail -1
}

###############################################################################
# Generate a random digit (0-9A-Z)
function genRandomValue() {
  for i in 0 1 2 3 4 5 6 7 8 9 A B C D E F G H J K L M N P Q R S T V W X Y Z; do
    echo ${i}
  done | sort -R | tail -1
}

###############################################################################
# Generate a random serial number for a model
# 1 - Model
# Returns serial number
function generateSerial() {
  PREFIX="$(readConfigArray "${1}.prefix" "${WORK_PATH}/serialnumber.yml" 2>/dev/null | sort -R | tail -1)"
  MIDDLE="$(readConfigArray "${1}.middle" "${WORK_PATH}/serialnumber.yml" 2>/dev/null | sort -R | tail -1)"
  SUFFIX="$(readConfigKey "${1}.suffix" "${WORK_PATH}/serialnumber.yml" 2>/dev/null)"

  local SERIAL="${PREFIX:-"0000"}${MIDDLE:-"XXX"}"
  case "${SUFFIX:-"alpha"}" in
  numeric)
    SERIAL+="$(random)"
    ;;
  alpha)
    SERIAL+="$(genRandomLetter)$(genRandomValue)$(genRandomValue)$(genRandomValue)$(genRandomValue)$(genRandomLetter)"
    ;;
  esac
  echo "${SERIAL}"
}

###############################################################################
# Generate a MAC address for a model
# 1 - Model
# 2 - number
# Returns serial number
function generateMacAddress() {
  MACPRE="$(readConfigArray "${1}.macpre" "${WORK_PATH}/serialnumber.yml" 2>/dev/null)"
  MACSUF="$(printf '%02x%02x%02x' $((${RANDOM} % 256)) $((${RANDOM} % 256)) $((${RANDOM} % 256)))"
  NUM=${2:-1}
  local MACS=""
  for I in $(seq 1 ${NUM}); do
    MACS+="$(printf '%06x%06x' $((0x${MACPRE:-"001132"})) $(($((0x${MACSUF})) + ${I})))"
    [ ${I} -lt ${NUM} ] && MACS+=" "
  done
  echo "${MACS}"
  return 0
}

###############################################################################
# Validate a serial number for a model
# 1 - Model
# 2 - Serial number to test
# Returns 1 if serial number is invalid
function validateSerial() {
  PREFIX="$(readConfigArray "${1}.prefix" "${WORK_PATH}/serialnumber.yml" 2>/dev/null)"
  MIDDLE="$(readConfigArray "${1}.middle" "${WORK_PATH}/serialnumber.yml" 2>/dev/null)"
  SUFFIX="$(readConfigKey "${1}.suffix" "${WORK_PATH}/serialnumber.yml" 2>/dev/null)"
  P=${2:0:4}
  M=${2:4:3}
  S=${2:7}
  L=${#2}
  if [ ${L} -ne 13 ]; then
    return 1
  fi
  if ! arrayExistItem ${P} ${PREFIX}; then
    return 1
  fi
  if ! arrayExistItem ${M} ${MIDDLE}; then
    return 1
  fi
  case "${SUFFIX:-"alpha"}" in
  numeric)
    if ! echo "${S}" | grep -q "^[0-9]\{6\}$"; then
      return 1
    fi
    ;;
  alpha)
    if ! echo "${S}" | grep -q "^[A-Z][0-9][0-9][0-9][0-9][A-Z]$"; then
      return 1
    fi
    ;;
  esac
  return 0
}

###############################################################################
# Get values in .conf K=V file
# 1 - key
# 2 - file
function _get_conf_kv() {
  grep "${1}" "${2}" 2>/dev/null | sed "s|^${1}=\"\(.*\)\"$|\1|g"
}

###############################################################################
# Replace/remove/add values in .conf K=V file
# 1 - name
# 2 - new_val
# 3 - path
function _set_conf_kv() {
  # Delete
  if [ -z "${2}" ]; then
    sed -i "${3}" -e "s/^${1}=.*$//" 2>/dev/null
    return $?
  fi

  # Replace
  if grep -q "^${1}=" "${3}"; then
    sed -i "${3}" -e "s\"^${1}=.*\"${1}=\\\"${2}\\\"\"" 2>/dev/null
    return $?
  fi

  # Add if doesn't exist
  echo "${1}=\"${2}\"" >>"${3}"
}

###############################################################################
# Get fastest url in list
# @ - url list
function _get_fastest() {
  local speedlist=""
  if ! command -v ping >/dev/null 2>&1; then
    for I in $@; do
      speed=$(ping -c 1 -W 5 ${I} 2>/dev/null | awk -F'[= ]' '/time=/ {for(i=1;i<=NF;i++) if ($i=="time") print $(i+1)}')
      speedlist+="${I} ${speed:-999}\n" # Assign default value 999 if speed is empty
    done
  else
    for I in $@; do
      speed=$(curl -o /dev/null -s -w '%{time_total}' ${I})
      speed=$(awk "BEGIN {print (${speed:-0.999} * 1000)}")
      speedlist+="${I} ${speed:-999}\n" # Assign default value 999 if speed is empty
    done
  fi
  local fastest="$(echo -e "${speedlist}" | tr -s '\n' | sort -k2n | head -1)"
  URL="$(echo "${fastest}" | awk '{print $1}')"
  SPD="$(echo "${fastest}" | awk '{print $2}')" # It is a float type
  echo "${URL}"
  [ $(printf "%.0f" ${SPD:-999}) -ge 999 ] && return 1 || return 0
}

###############################################################################
# sort netif name
# @1 -mac1,mac2,mac3...
function _sort_netif() {
  local ETHLIST=""
  local ETHX="$(ls /sys/class/net/ 2>/dev/null | grep eth)" # real network cards list
  for ETH in ${ETHX}; do
    local MAC="$(cat /sys/class/net/${ETH}/address 2>/dev/null | sed 's/://g' | tr '[:upper:]' '[:lower:]')"
    local BUS="$(ethtool -i ${ETH} 2>/dev/null | grep bus-info | cut -d' ' -f2)"
    ETHLIST="${ETHLIST}${BUS} ${MAC} ${ETH}\n"
  done
  local ETHLISTTMPM=""
  local ETHLISTTMPB="$(echo -e "${ETHLIST}" | sort)"
  if [ -n "${1}" ]; then
    local MACS="$(echo "${1}" | sed 's/://g' | tr '[:upper:]' '[:lower:]' | tr ',' ' ')"
    for MACX in ${MACS}; do
      ETHLISTTMPM="${ETHLISTTMPM}$(echo -e "${ETHLISTTMPB}" | grep "${MACX}")\n"
      ETHLISTTMPB="$(echo -e "${ETHLISTTMPB}" | grep -v "${MACX}")\n"
    done
  fi
  local ETHLIST="$(echo -e "${ETHLISTTMPM}${ETHLISTTMPB}" | grep -v '^$')"
  local ETHSEQ="$(echo -e "${ETHLIST}" | awk '{print $3}' | sed 's/eth//g')"
  local ETHNUM="$(echo -e "${ETHLIST}" | wc -l)"

  # echo "${ETHSEQ}"
  # sort
  if [ ! "${ETHSEQ}" = "$(seq 0 $((${ETHNUM:0} - 1)))" ]; then
    /etc/init.d/S41dhcpcd stop >/dev/null 2>&1
    /etc/init.d/S40network stop >/dev/null 2>&1
    for i in $(seq 0 $((${ETHNUM:0} - 1))); do
      ip link set dev eth${i} name tmp${i}
    done
    I=0
    for i in ${ETHSEQ}; do
      ip link set dev tmp${i} name eth${I}
      I=$((${I} + 1))
    done
    /etc/init.d/S40network start >/dev/null 2>&1
    /etc/init.d/S41dhcpcd start >/dev/null 2>&1
  fi
  return 0
}

###############################################################################
# get bus of disk
# 1 - device path
function getBus() {
  local BUS=""
  # usb/ata(ide)/sata/sas/spi(scsi)/virtio/mmc/nvme
  [ -z "${BUS}" ] && BUS=$(lsblk -dpno KNAME,TRAN 2>/dev/null | grep "${1} " | awk '{print $2}' | sed 's/^ata$/ide/' | sed 's/^spi$/scsi/') #Spaces are intentional
  # usb/scsi(ide/sata/sas)/virtio/mmc/nvme/vmbus/xen(xvd)
  [ -z "${BUS}" ] && BUS=$(lsblk -dpno KNAME,SUBSYSTEMS 2>/dev/null | grep "${1} " | awk '{print $2}' | awk -F':' '{print $(NF-1)}' | sed 's/_host//' | sed 's/^.*xen.*$/xen/') # Spaces are intentional
  [ -z "${BUS}" ] && BUS="unknown"
  echo "${BUS}"
  return 0
}

###############################################################################
# get IP
# 1 - ethN
function getIP() {
  local IP=""
  if [ -n "${1}" -a -d "/sys/class/net/${1}" ]; then
    IP=$(ip route show dev ${1} 2>/dev/null | sed -n 's/.* via .* src \(.*\)  metric .*/\1/p')
    [ -z "${IP}" ] && IP=$(ip addr show ${1} scope global 2>/dev/null | grep -E "inet .* eth" | awk '{print $2}' | cut -f1 -d'/' | head -1)
  else
    IP=$(ip route show 2>/dev/null | sed -n 's/.* via .* src \(.*\)  metric .*/\1/p' | head -1)
    [ -z "${IP}" ] && IP=$(ip addr show scope global 2>/dev/null | grep -E "inet .* eth" | awk '{print $2}' | cut -f1 -d'/' | head -1)
  fi
  echo "${IP}"
  return 0
}

###############################################################################
# get logo of model
# 1 - model
function getLogo() {
  local MODEL="${1}"
  rm -f "${PART3_PATH}/logo.png"
  local fastest="www.synology.com" # $(_get_fastest "www.synology.com" "www.synology.cn")
  if [ $? -ne 0 ]; then
    return 1
  fi
  local STATUS=$(curl -skL --connect-timeout 10 -w "%{http_code}" "https://${fastest}/api/products/getPhoto?product=${MODEL/+/%2B}&type=img_s&sort=0" -o "${PART3_PATH}/logo.png")
  if [ $? -ne 0 -o ${STATUS:-0} -ne 200 -o ! -f "${PART3_PATH}/logo.png" ]; then
    rm -f "${PART3_PATH}/logo.png"
    return 1
  fi
  convert -rotate 180 "${PART3_PATH}/logo.png" "${PART3_PATH}/logo.png" 2>/dev/null
  magick montage "${PART3_PATH}/logo.png" -background 'none' -tile '3x3' -geometry '350x210' "${PART3_PATH}/logo.png" 2>/dev/null
  convert -rotate 180 "${PART3_PATH}/logo.png" "${PART3_PATH}/logo.png" 2>/dev/null
  return 0
}

###############################################################################
# check Cmdline
# 1 - key name
# 2 - key string
function checkCmdline() {
  return $(grub-editenv ${USER_GRUBENVFILE} list 2>/dev/null | grep "^${1}=" | cut -d'=' -f2- | grep -q "${2}")
}

###############################################################################
# get logo of model
# 1 - key name
# 2 - key string
function setCmdline() {
  [ -z "${1}" ] && return 1
  if [ -n "${2}" ]; then
    grub-editenv ${USER_GRUBENVFILE} set "${1}=${2}"
  else
    grub-editenv ${USER_GRUBENVFILE} unset "${1}"
  fi
}

###############################################################################
# get logo of model
# check Cmdline
# 1 - key name
# 2 - key string
function addCmdline() {
  local CMDLINE="$(grub-editenv ${USER_GRUBENVFILE} list 2>/dev/null | grep "^${1}=" | cut -d'=' -f2-)"
  [ -n "${CMDLINE}" ] && CMDLINE="${CMDLINE} ${2}" || CMDLINE="${2}"
  setCmdline "${1}" "${CMDLINE}"
}

###############################################################################
# get logo of model
# 1 - model
function delCmdline() {
  local CMDLINE="$(grub-editenv ${USER_GRUBENVFILE} list 2>/dev/null | grep "^${1}=" | cut -d'=' -f2-)"
  CMDLINE="$(echo "${CMDLINE}" | sed "s/ *${2}//; s/^[[:space:]]*//;s/[[:space:]]*$//")"
  setCmdline "${1}" "${CMDLINE}"
}

###############################################################################
# Rebooting
# 1 - mode
function rebootTo() {
  local MODES="config recovery junior bios memtest"
  if [ -z "${1}" ] || ! echo "${MODES}" | grep -qw "${1}"; then exit 1; fi
  # echo "Rebooting to ${1} mode"
  GRUBPATH="$(dirname $(find ${PART1_PATH}/ -name grub.cfg 2>/dev/null | head -1))"
  [ -z "${GRUBPATH}" ] && exit 1
  ENVFILE="${GRUBPATH}/grubenv"
  [ ! -f "${ENVFILE}" ] && grub-editenv ${ENVFILE} create
  grub-editenv ${ENVFILE} set next_entry="${1}"
  reboot
}

###############################################################################
# connect wlanif
# 1 netif name
function connectwlanif() {
  [ -z "${1}" -o ! -d "/sys/class/net/${1}" ] && return 1

  local CONF=""
  [ -z "${CONF}" -a -f "${PART1_PATH}/wpa_supplicant.conf.${1}" ] && CONF="${PART1_PATH}/wpa_supplicant.conf.${1}"
  [ -z "${CONF}" -a -f "${PART1_PATH}/wpa_supplicant.conf" ] && CONF="${PART1_PATH}/wpa_supplicant.conf"
  [ -z "${CONF}" ] && return 2

  if [ -f "/var/run/wpa_supplicant.pid.${1}" ]; then
    kill -9 $(cat /var/run/wpa_supplicant.pid.${1})
    rm -f /var/run/wpa_supplicant.pid.${1}
  fi
  wpa_supplicant -i ${1} -c "${CONF}" -B -P "/var/run/wpa_supplicant.pid.${1}" >/dev/null 2>&1
  return 0
}

###############################################################################
# Find and mount the DSM root filesystem
# (based on pocopico's TCRP code)
function findDSMRoot() {
  local DSMROOTS=""
  [ -z "${DSMROOTS}" ] && DSMROOTS="$(mdadm --detail --scan 2>/dev/null | grep -E "name=SynologyNAS:0|name=DiskStation:0|name=SynologyNVR:0|name=BeeStation:0" | awk '{print $2}' | uniq)"
  [ -z "${DSMROOTS}" ] && DSMROOTS="$(lsblk -pno KNAME,PARTN,FSTYPE,FSVER,LABEL | grep -E "sd[a-z]{1,2}1" | grep -w "linux_raid_member" | grep "0.9" | awk '{print $1}')"
  echo "${DSMROOTS}"
  return 0
}

###############################################################################
# Copy DSM files to the boot partition
# 1 - DSM root path
function copyDSMFiles() {
  if [ -f "${1}/VERSION" ] && [ -f "${1}/grub_cksum.syno" ] && [ -f "${1}/GRUB_VER" ] && [ -f "${1}/zImage" ] && [ -f "${1}/rd.gz" ]; then
    # Remove old model files
    rm -f "${PART1_PATH}/grub_cksum.syno" "${PART1_PATH}/GRUB_VER" "${PART2_PATH}/grub_cksum.syno" "${PART2_PATH}/GRUB_VER"
    rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}"
    # Remove old build files
    rm -f "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}" >/dev/null
    # Copy new model files
    cp -f "${1}/grub_cksum.syno" "${PART1_PATH}"
    cp -f "${1}/GRUB_VER" "${PART1_PATH}"
    cp -f "${1}/grub_cksum.syno" "${PART2_PATH}"
    cp -f "${1}/GRUB_VER" "${PART2_PATH}"
    cp -f "${1}/zImage" "${ORI_ZIMAGE_FILE}"
    cp -f "${1}/rd.gz" "${ORI_RDGZ_FILE}"
    return 0
  else
    return 1
  fi
}
