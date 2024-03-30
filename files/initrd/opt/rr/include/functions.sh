[ -z "${WORK_PATH}" -o ! -d "${WORK_PATH}/include" ] && WORK_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../" >/dev/null 2>&1 && pwd)"

. ${WORK_PATH}/include/consts.sh
. ${WORK_PATH}/include/configFile.sh
. ${WORK_PATH}/include/i18n.sh

###############################################################################
# Read key value from model config file
# 1 - Model
# 2 - Key
# Return Value
function readModelKey() {
  readConfigKey "${2}" "${WORK_PATH}/model-configs/${1}.yml" 2>/dev/null
}

###############################################################################
# Read Entries as map(key=value) from model config
# 1 - Model
# 2 - Path of key
# Returns map of values
function readModelMap() {
  readConfigMap "${2}" "${WORK_PATH}/model-configs/${1}.yml" 2>/dev/null
}

###############################################################################
# Read an array from model config
# 1 - Model
# 2 - Path of key
# Returns array/map of values
function readModelArray() {
  readConfigArray "${2}" "${WORK_PATH}/model-configs/${1}.yml" 2>/dev/null
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
function generateRandomLetter() {
  for i in A B C D E F G H J K L M N P Q R S T V W X Y Z; do
    echo ${i}
  done | sort -R | tail -1
}

###############################################################################
# Generate a random digit (0-9A-Z)
function generateRandomValue() {
  for i in 0 1 2 3 4 5 6 7 8 9 A B C D E F G H J K L M N P Q R S T V W X Y Z; do
    echo ${i}
  done | sort -R | tail -1
}

###############################################################################
# Generate a random serial number for a model
# 1 - Model
# Returns serial number
function generateSerial() {
  SERIAL="$(readModelArray "${1}" "serial.prefix" | sort -R | tail -1)"
  SERIAL+=$(readModelKey "${1}" "serial.middle")
  case "$(readModelKey "${1}" "serial.suffix")" in
  numeric)
    SERIAL+=$(random)
    ;;
  alpha)
    SERIAL+=$(generateRandomLetter)$(generateRandomValue)$(generateRandomValue)$(generateRandomValue)$(generateRandomValue)$(generateRandomLetter)
    ;;
  esac
  echo ${SERIAL}
}

###############################################################################
# Generate a MAC address for a model
# 1 - Model
# 2 - number
# Returns serial number
function generateMacAddress() {
  PRE="$(readModelArray "${1}" "serial.macpre")"
  SUF="$(printf '%02x%02x%02x' $((${RANDOM} % 256)) $((${RANDOM} % 256)) $((${RANDOM} % 256)))"
  NUM=${2:-1}
  MACS=""
  for I in $(seq 1 ${NUM}); do
    MACS+="$(printf '%06x%06x' $((0x${PRE:-"001132"})) $(($((0x${SUF})) + ${I})))"
    [ ${I} -lt ${NUM} ] && MACS+=" "
  done
  echo "${MACS}"
  return 0
}

###############################################################################
# Validate a serial number for a model
# 1 - Model
# 2 - Serial number to test
# Returns 1 if serial number is valid
function validateSerial() {
  PREFIX=$(readModelArray "${1}" "serial.prefix")
  MIDDLE=$(readModelKey "${1}" "serial.middle")
  S=${2:0:4}
  P=${2:4:3}
  L=${#2}
  if [ ${L} -ne 13 ]; then
    return 0
  fi
  echo "${PREFIX}" | grep -q "${S}"
  if [ $? -eq 1 ]; then
    return 0
  fi
  if [ "${MIDDLE}" != "${P}" ]; then
    return 0
  fi
  return 1
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
  fastest="$(echo -e "${speedlist}" | tr -s '\n' | sort -k2n | head -1)"
  URL="$(echo "${fastest}" | awk '{print $1}')"
  SPD="$(echo "${fastest}" | awk '{print $2}')" # It is a float type
  echo "${URL}"
  [ $(printf "%.0f" ${SPD:-999}) -ge 999 ] && return 1 || return 0
}

###############################################################################
# sort netif name
# @1 -mac1,mac2,mac3...
function _sort_netif() {
  ETHLIST=""
  ETHX=$(ls /sys/class/net/ 2>/dev/null | grep eth) # real network cards list
  for ETH in ${ETHX}; do
    MAC="$(cat /sys/class/net/${ETH}/address 2>/dev/null | sed 's/://g' | tr '[:upper:]' '[:lower:]')"
    BUS=$(ethtool -i ${ETH} 2>/dev/null | grep bus-info | awk '{print $2}')
    ETHLIST="${ETHLIST}${BUS} ${MAC} ${ETH}\n"
  done

  if [ -n "${1}" ]; then
    MACS=$(echo "${1}" | sed 's/://g' | tr '[:upper:]' '[:lower:]' | tr ',' ' ')
    ETHLISTTMPC=""
    ETHLISTTMPF=""

    for MACX in ${MACS}; do
      ETHLISTTMPC="${ETHLISTTMPC}$(echo -e "${ETHLIST}" | grep "${MACX}")\n"
    done

    while read -r BUS MAC ETH; do
      [ -z "${MAC}" ] && continue
      if echo "${MACS}" | grep -q "${MAC}"; then continue; fi
      ETHLISTTMPF="${ETHLISTTMPF}${BUS} ${MAC} ${ETH}\n"
    done <<EOF
$(echo -e ${ETHLIST} | sort)
EOF
    ETHLIST="${ETHLISTTMPC}${ETHLISTTMPF}"
  else
    ETHLIST="$(echo -e "${ETHLIST}" | sort)"
  fi
  ETHLIST="$(echo -e "${ETHLIST}" | grep -v '^$')"

  echo -e "${ETHLIST}" >${TMP_PATH}/ethlist
  # cat ${TMP_PATH}/ethlist

  # sort
  IDX=0
  while true; do
    # cat ${TMP_PATH}/ethlist
    [ ${IDX} -ge $(wc -l <${TMP_PATH}/ethlist) ] && break
    ETH=$(cat ${TMP_PATH}/ethlist | sed -n "$((${IDX} + 1))p" | awk '{print $3}')
    # echo "ETH: ${ETH}"
    if [ -n "${ETH}" ] && [ ! "${ETH}" = "eth${IDX}" ]; then
      # echo "change ${ETH} <=> eth${IDX}"
      ip link set dev eth${IDX} down
      ip link set dev ${ETH} down
      sleep 1
      ip link set dev eth${IDX} name ethN
      ip link set dev ${ETH} name eth${IDX}
      ip link set dev ethN name ${ETH}
      sleep 1
      ip link set dev eth${IDX} up
      ip link set dev ${ETH} up
      sleep 1
      sed -i "s/eth${IDX}/ethN/" ${TMP_PATH}/ethlist
      sed -i "s/${ETH}/eth${IDX}/" ${TMP_PATH}/ethlist
      sed -i "s/ethN/${ETH}/" ${TMP_PATH}/ethlist
      sleep 1
    fi
    IDX=$((${IDX} + 1))
  done

  rm -f ${TMP_PATH}/ethlist
  return 0
}

###############################################################################
# get bus of disk
# 1 - device path
function getBus() {
  BUS=""
  # usb/ata(sata/ide)/scsi
  [ -z "${BUS}" ] && BUS=$(udevadm info --query property --name "${1}" 2>/dev/null | grep ID_BUS | cut -d= -f2 | sed 's/ata/sata/')
  # usb/sata(sata/ide)/nvme
  [ -z "${BUS}" ] && BUS=$(lsblk -dpno KNAME,TRAN 2>/dev/null | grep "${1} " | awk '{print $2}') #Spaces are intentional
  # usb/scsi(sata/ide)/virtio(scsi/virtio)/mmc/nvme
  [ -z "${BUS}" ] && BUS=$(lsblk -dpno KNAME,SUBSYSTEMS 2>/dev/null | grep "${1} " | awk -F':' '{print $(NF-1)}' | sed 's/_host//') #Spaces are intentional
  echo "${BUS}"
  return 0
}

###############################################################################
# get IP
# 1 - ethN
function getIP() {
  IP=""
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
  MODEL="${1}"
  rm -f "${PART3_PATH}/logo.png"
  fastest=$(_get_fastest "www.synology.com" "www.synology.cn")
  if [ $? -ne 0 ]; then
    return 1
  fi
  STATUS=$(curl -skL --connect-timeout 10 -w "%{http_code}" "https://${fastest}/api/products/getPhoto?product=${MODEL/+/%2B}&type=img_s&sort=0" -o "${PART3_PATH}/logo.png")
  if [ $? -ne 0 -o ${STATUS:-0} -ne 200 -o ! -f "${PART3_PATH}/logo.png" ]; then
    return 1
  fi
  convert -rotate 180 "${PART3_PATH}/logo.png" "${PART3_PATH}/logo.png" 2>/dev/null
  magick montage "${PART3_PATH}/logo.png" -background 'none' -tile '3x3' -geometry '350x210' "${PART3_PATH}/logo.png" 2>/dev/null
  convert -rotate 180 "${PART3_PATH}/logo.png" "${PART3_PATH}/logo.png" 2>/dev/null
  return 0
}

###############################################################################
# Rebooting
# 1 - mode
function rebootTo() {
  MODES="config recovery junior"
  [ -z "${1}" ] && exit 1
  if ! echo "${MODES}" | grep -qw "${1}"; then exit 1; fi
  # echo "Rebooting to ${1} mode"
  GRUBPATH="$(dirname $(find ${PART1_PATH}/ -name grub.cfg 2>/dev/null | head -1))"
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

  CONF=""
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
