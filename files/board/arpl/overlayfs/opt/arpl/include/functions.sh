
. /opt/arpl/include/consts.sh
. /opt/arpl/include/configFile.sh

###############################################################################
# Read key value from model config file
# 1 - Model
# 2 - Key
# Return Value
function readModelKey() {
  readConfigKey "${2}" "${MODEL_CONFIG_PATH}/${1}.yml"
}

###############################################################################
# Read Entries as map(key=value) from model config
# 1 - Model
# 2 - Path of key
# Returns map of values
function readModelMap() {
  readConfigMap "${2}" "${MODEL_CONFIG_PATH}/${1}.yml"
}

###############################################################################
# Read an array from model config
# 1 - Model
# 2 - Path of key
# Returns array/map of values
function readModelArray() {
  readConfigArray "${2}" "${MODEL_CONFIG_PATH}/${1}.yml"
}

###############################################################################
# Check if loader is fully configured
# Returns 1 if not
function loaderIsConfigured() {
  SN="`readConfigKey "sn" "${USER_CONFIG_FILE}"`"
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
  printf "%06d" $(($RANDOM %30000 +1 ))
}

###############################################################################
# Generate a hexa number from 0x00 to 0xFF
function randomhex() {
  printf "&02X" "$(( $RANDOM %255 +1 ))"
}

###############################################################################
# Generate a random letter
function generateRandomLetter() {
  for i in A B C D E F G H J K L M N P Q R S T V W X Y Z; do
    echo $i
  done | sort -R | tail -1
}

###############################################################################
# Generate a random digit (0-9A-Z)
function generateRandomValue() {
	 for i in 0 1 2 3 4 5 6 7 8 9 A B C D E F G H J K L M N P Q R S T V W X Y Z; do
     echo $i
	 done | sort -R | tail -1
}

###############################################################################
# Generate a random serial number for a model
# 1 - Model
# Returns serial number
function generateSerial() {
  SERIAL="`readModelArray "${1}" "serial.prefix" | sort -R | tail -1`"
  SERIAL+=`readModelKey "${1}" "serial.middle"`
  case "`readModelKey "${1}" "serial.suffix"`" in
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
# Validate a serial number for a model
# 1 - Model
# 2 - Serial number to test
# Returns 1 if serial number is valid
function validateSerial() {
  PREFIX=`readModelArray "${1}" "serial.prefix"`
  MIDDLE=`readModelKey "${1}" "serial.middle"`
  S=${2:0:4}
  P=${2:4:3}
  L=${#2}
  if [ ${L} -ne 13 ]; then
    echo 0
    return
  fi
  echo ${PREFIX} | grep -q ${S}
  if [ $? -eq 1 ]; then
    echo 0
    return
  fi
  if [ "${MIDDLE}" != "${P}" ]; then
    echo 0
    return
  fi
  echo 1
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
  grep "${1}" "${2}" | sed "s|^${1}=\"\(.*\)\"$|\1|g"
}

###############################################################################
# Replace/remove/add values in .conf K=V file
# 1 - name
# 2 - new_val
# 3 - path
function _set_conf_kv() {
  # Delete
  if [ -z "$2" ]; then
    sed -i "$3" -e "s/^$1=.*$//"
    return $?;
  fi

  # Replace
  if grep -q "^$1=" "$3"; then
    sed -i "$3" -e "s\"^$1=.*\"$1=\\\"$2\\\"\""
    return $?
  fi

  # Add if doesn't exist
  echo "$1=\"$2\"" >> $3
}

###############################################################################
# Find and mount the DSM root filesystem
# (based on pocopico's TCRP code)
function findAndMountDSMRoot() {
  [ $(mount | grep -i "${DSMROOT_PATH}" | wc -l) -gt 0 ] && return 0
  dsmrootdisk="$(blkid /dev/sd* | grep -i raid | awk '{print $1 " " $4}' | grep UUID | grep sd[a-z]1 | head -1 | awk -F ":" '{print $1}')"
  [ -z "${dsmrootdisk}" ] && return -1
  [ $(mount | grep -i "${DSMROOT_PATH}" | wc -l) -eq 0 ] && mount -t ext4 $dsmrootdisk "${DSMROOT_PATH}"
  if [ $(mount | grep -i "${DSMROOT_PATH}" | wc -l) -eq 0 ]; then
    echo "Failed to mount"
    return -1
  fi
  return 0
}
