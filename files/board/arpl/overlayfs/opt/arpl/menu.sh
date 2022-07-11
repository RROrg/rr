#!/usr/bin/env bash

. /opt/arpl/include/functions.sh
. /opt/arpl/include/addons.sh

# Check partition 3 space, if < 2GiB uses ramdisk
RAMCACHE=0
LOADER_DISK="`blkid | grep 'LABEL="ARPL3"' | cut -d3 -f1`"
LOADER_DEVICE_NAME=`echo ${LOADER_DISK} | sed 's|/dev/||'`
if [ `cat /sys/block/${LOADER_DEVICE_NAME}/${LOADER_DEVICE_NAME}3/size` -lt 4194304 ]; then
  RAMCACHE=1
fi

# Get actual IP
IP=`ip route get 1.1.1.1 2>/dev/null | awk '{print$7}'`

# Define classes for hw detection
declare -A CLASSES
CLASSES["0100"]="SCSI"
CLASSES["0106"]="SATA"
CLASSES["0101"]="IDE"
CLASSES["0107"]="SAS"
CLASSES["0200"]="Ethernet"
CLASSES["0300"]="VGA"
CLASSES["0c03"]="USB Controller"
CLASSES["0c04"]="Fiber Channel"

# Dirty flag
DIRTY=0

MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"
BUILD="`readConfigKey "build" "${USER_CONFIG_FILE}"`"
KEYMAP="`readConfigKey "keymap" "${USER_CONFIG_FILE}"`"
LKM="`readConfigKey "lkm" "${USER_CONFIG_FILE}"`"
SN="`readConfigKey "sn" "${USER_CONFIG_FILE}"`"

###############################################################################
# Mounts backtitle dynamically
function backtitle() {
  BACKTITLE="ARPL ${ARPL_VERSION}"
  if [ -n "${MODEL}" ]; then
    BACKTITLE+=" ${MODEL}"
  else
    BACKTITLE+=" (no model)"
  fi
  if [ -n "${BUILD}" ]; then
    BACKTITLE+=" ${BUILD}"
  else
    BACKTITLE+=" (no build)"
  fi
  if [ -n "${SN}" ]; then
    BACKTITLE+=" ${SN}"
  else
    BACKTITLE+=" (no SN)"
  fi
  if [ -n "${IP}" ]; then
    BACKTITLE+=" ${IP}"
  else
    BACKTITLE+=" (no IP)"
  fi
  if [ -n "${KEYMAP}" ]; then
    BACKTITLE+=" (${KEYMAP})"
  else
    BACKTITLE+=" (us)"
  fi
  echo ${BACKTITLE}
}

###############################################################################
# Shows available models to user choose one
function modelMenu() {
  ITEMS=""
  while read M; do
    M="`basename ${M}`"
    M="${M::-4}"
    # Check id model is compatible with CPU
    COMPATIBLE=1
    for F in `readModelArray "${M}" "flags"`; do
      if ! grep -q "^flags.*${F}.*" /proc/cpuinfo; then
        COMPATIBLE=0
        break
      fi
    done
    [ ${COMPATIBLE} -eq 1 ] && ITEMS+="${M} "
  done < <(find "${MODEL_CONFIG_PATH}" -maxdepth 1 -name \*.yml | sort)
  dialog --clear --no-items \
    --backtitle "`backtitle`" \
    --menu "Choose the model" 0 0 0 \
    ${ITEMS} \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  resp=$(<${TMP_PATH}/resp)
  [ -z "${resp}" ] && return
  # If user change model, clean buildnumber and S/N
  if [ "${MODEL}" != "${resp}" ]; then
    MODEL=${resp}
    writeConfigKey "model" "${MODEL}" "${USER_CONFIG_FILE}"
    BUILD=""
    writeConfigKey "build" "${BUILD}" "${USER_CONFIG_FILE}"
    SN=""
    writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
    # Delete old files
    rm -f "${MOD_ZIMAGE_FILE}"
    rm -f "${MOD_RDGZ_FILE}"
    DIRTY=1
    # Remove addons
    writeConfigKey "addons" "{}" "${USER_CONFIG_FILE}"
  fi
}

###############################################################################
# Shows available buildnumbers from a model to user choose one
function buildMenu() {
  ITEMS="`readConfigEntriesArray "builds" "${MODEL_CONFIG_PATH}/${MODEL}.yml"`"
  dialog --clear --no-items --backtitle "`backtitle`" \
    --menu "Choose a build number" 0 0 0 ${ITEMS} 2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  resp=$(<${TMP_PATH}/resp)
  [ -z "${resp}" ] && return
  if [ "${BUILD}" != "${resp}" ]; then
    BUILD=${resp}
    writeConfigKey "build" "${BUILD}" "${USER_CONFIG_FILE}"
    DIRTY=1
    # Remove old files
    rm -f "${MOD_ZIMAGE_FILE}"
    rm -f "${MOD_RDGZ_FILE}"
  fi
}

###############################################################################
# Shows menu to user type one or generate randomly
function serialMenu() {
  while true; do
    dialog --clear --backtitle "`backtitle`" \
      --menu "Choose a option" 0 0 0 \
      a "Generate a random serial number" \
      m "Enter a serial number" \
    2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    resp=$(<${TMP_PATH}/resp)
    [ -z "${resp}" ] && return
    if [ "${resp}" = "m" ]; then
      while true; do
        dialog --backtitle "`backtitle`" \
          --inputbox "Please enter a serial number " 0 0 "" \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && return
        SERIAL=`cat ${TMP_PATH}/resp`
        if [ -z "${SERIAL}" ]; then
          return
        elif [ `validateSerial ${MODEL} ${SERIAL}` -eq 1 ]; then
          break
        fi
        dialog --backtitle "`backtitle`" \
          --msgbox "Invalid serial, please type a right one" 0 0
      done
      break
    elif [ "${resp}" = "a" ]; then
      SERIAL=`generateSerial "${MODEL}"`
      break
    fi
  done
  SN="${SERIAL}"
  writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
}

###############################################################################
# Detect hardware
function detectHw() {
  PLATFORM="`readModelKey "${MODEL}" "platform"`"
  KVER="`readModelKey "${MODEL}" "builds.${BUILD}.kver"`"
  # Get modules not needed
  unset NOTNEEDED
  declare -A NOTNEEDED
  while read M; do
    NOTNEEDED[${M}]="1"
  done < <(readModelArray "${MODEL}" "builds.${BUILD}.modules-notneeded")
  unset DEVC DEVN
  declare -A DEVC
  declare -A DEVN
  while read L; do
    F=` sed -E 's/^([0-9a-z]{2}:[0-9a-z]{2}.[0-9a-z]{1})[^\[]*\[([0-9a-z]{4})\]: (.*)/\1|\2|\3/' <<<"${L}"`
    PCI="`cut -d'|' -f1 <<<"${F}"`"
    CLASS="`cut -d'|' -f2 <<<"${F}"`"
    NAME="`cut -d'|' -f3 <<<"${F}"`"
    MODULE="`lspci -ks "${PCI}" | awk '/Kernel driver in use/{print$5}'`"
    [ -z "${MODULE}" ] && continue
    # If is a virtio module, change id
    if grep -q "virtio" <<<"$MODULE"; then
      MODULE="virtio"
    fi
    CLASS=${CLASSES[${CLASS}]}                             # Get class name of module
    [ -z "${CLASS}" ] && continue                          # If no class, skip
    arrayExistItem "${MODULE}" "${!ADDONS[@]}" && continue # Check if module already added
    [ -n "${NOTNEEDED[${MODULE}]}" ] && continue           # Check if module is not necessary
    # Add module to list
    DEVC[${MODULE}]="${CLASS}"
    DEVN[${MODULE}]="${NAME}"
  done < <(lspci -nn)
  if [ ${#DEVC[@]} -eq 0 ]; then
    dialog --backtitle "`backtitle`" --aspect 18 \
      --msgbox "No device detected or already added!" 0 0
    return
  fi
  for MODULE in ${!DEVC[@]}; do
    CLASS="${DEVC[${MODULE}]}"
    NAME="${DEVN[${MODULE}]}"
    TEXT="Found a ${NAME}\nClass ${CLASS}\nModule ${MODULE}\nAccept?"
    checkAddonExist "${MODULE}" "${PLATFORM}" "${KVER}" || TEXT+="\n\n\Z1PS: Addon for this module not found\Zn"
    dialog --backtitle "`backtitle`" --title "Found Hardware" \
      --colors --yesno "${TEXT}" 12 70
    [ $? -ne 0 ] && continue
    dialog --backtitle "`backtitle`" --title "params" \
      --inputbox "Type a opcional params to module" 0 0 \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && continue
    VALUE="`<${TMP_PATH}/resp`"
    ADDONS["${MODULE}"]="${VALUE}"
    writeConfigKey "addons.${MODULE}" "${VALUE}" "${USER_CONFIG_FILE}"
    DIRTY=1
  done
}

###############################################################################
# Manage addons/drivers
function addonMenu() {
  # Read 'platform' and kernel version to check if addon exists
  PLATFORM="`readModelKey "${MODEL}" "platform"`"
  KVER="`readModelKey "${MODEL}" "builds.${BUILD}.kver"`"
  # Read addons from user config
  unset ADDONS
  declare -A ADDONS
  while IFS="=" read KEY VALUE; do
    [ -n "${KEY}" ] && ADDONS["${KEY}"]="${VALUE}"
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")
  NEXT="h"
  # Loop menu
  while true; do
    dialog --backtitle "`backtitle`" --default-item ${NEXT} \
      --menu "Choose a option" 0 0 0 \
      h "Detect hardware" \
      a "Add an addon" \
      d "Delete addon(s)" \
      s "Show user addons" \
      m "Show all available addons" \
      o "Download an addon" \
      e "Exit" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "`<${TMP_PATH}/resp`" in
      h)
        detectHw
        NEXT='e'
        ;;
      a) NEXT='a'
        rm "${TMP_PATH}/menu"
        while read ADDON DESC; do
          arrayExistItem "${ADDON}" "${!ADDONS[@]}" && continue          # Check if addon has already been added
          echo "${ADDON} \"${DESC}\"" >> "${TMP_PATH}/menu"
        done < <(availableAddons "${PLATFORM}" "${KVER}")
        if [ ! -f "${TMP_PATH}/menu" ] ; then 
          dialog --backtitle "`backtitle`" --msgbox "No available addons to add" 0 0 
          continue
        fi
        dialog --backtitle "`backtitle`" --menu "Select an addon" 0 0 0 \
          --file "${TMP_PATH}/menu" 2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        ADDON="`<"${TMP_PATH}/resp"`"
        [ -z "${ADDON}" ] && continue
        dialog --backtitle "`backtitle`" --title "params" \
          --inputbox "Type a opcional params to addon" 0 0 \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && continue
        ADDONS[${ADDON}]="`<"${TMP_PATH}/resp"`"
        writeConfigKey "addons.${ADDON}" "${VALUE}" "${USER_CONFIG_FILE}"
        DIRTY=1
        ;;
      d) NEXT='d'
        if [ ${#ADDONS[@]} -eq 0 ]; then
          dialog --backtitle "`backtitle`" --msgbox "No user addons to remove" 0 0 
          continue
        fi
        ITEMS=""
        for I in "${!ADDONS[@]}"; do
          ITEMS+="${I} ${I} off "
        done
        dialog --backtitle "`backtitle`" --no-tags \
          --checklist "Select addon to remove" 0 0 0 ${ITEMS} \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        ADDON="`<"${TMP_PATH}/resp"`"
        [ -z "${ADDON}" ] && continue
        for I in ${ADDON}; do
          unset ADDONS[${I}]
          deleteConfigKey "addons.${I}" "${USER_CONFIG_FILE}"
        done
        DIRTY=1
        ;;
      s) NEXT='s'
        ITEMS=""
        for KEY in ${!ADDONS[@]}; do
          ITEMS+="${KEY}: ${ADDONS[$KEY]}\n"
        done
        dialog --backtitle "`backtitle`" --title "User addons" \
          --msgbox "${ITEMS}" 0 0
        ;;
      m) NEXT='m'
        MSG=""
        while read MODULE DESC; do
          if arrayExistItem "${MODULE}" "${!ADDONS[@]}"; then
            MSG+="\Z4${MODULE}\Zn"
          else
            MSG+="${MODULE}"
          fi
          MSG+=": \Z5${DESC}\Zn\n"
        done < <(availableAddons "${PLATFORM}" "${KVER}")
        dialog --backtitle "`backtitle`" --title "Available addons" \
          --colors --msgbox "${MSG}" 0 0
        ;;
      o)
        TEXT="please enter the complete URL to download.\n"
        TEXT+="\Zb(Official addons location: https://github.com/fbelavenuto/arpl-addons/releases)\Zn\n"
        TEXT+="Ex: https://github.com/fbelavenuto/arpl-addons/releases/download/v0.2/9p.addon"
        dialog --backtitle "`backtitle`" --aspect 18 --colors --inputbox "${TEXT}" 0 0 \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && continue
        URL="`<"${TMP_PATH}/resp"`"
        [ -z "${URL}" ] && continue
        clear
        echo "Downloading ${URL}"
        curl --insecure -L "${URL}" -o "${TMP_PATH}/addon.tgz" --progress-bar
        if [ $? -ne 0 ]; then
          dialog --backtitle "`backtitle`" --title "Error downloading" --aspect 18 \
            --msgbox "Check internet or cache disk space" 0 0
          return 1
        fi
        ADDON="`untarAddon "${TMP_PATH}/addon.tgz"`"
        if [ -n "${ADDON}" ]; then
          dialog --backtitle "`backtitle`" --title "Success" --aspect 18 \
            --msgbox "Addon '${ADDON}' added to loader" 0 0
        else
          dialog --backtitle "`backtitle`" --title "Invalid addon" --aspect 18 \
            --msgbox "File format not recognized!" 0 0
        fi
        ;;
      e) return ;;
    esac
  done
}

###############################################################################
function cmdlineMenu() {
  unset CMDLINE
  declare -A CMDLINE
  while IFS="=" read KEY VALUE; do
    [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
  done < <(readConfigMap "cmdline" "${USER_CONFIG_FILE}")
  echo "a \"Add/edit an cmdline item\""                        > "${TMP_PATH}/menu"
  echo "d \"Delete cmdline item(s)\""                          >> "${TMP_PATH}/menu"
  echo "s \"Show user cmdline\""                               >> "${TMP_PATH}/menu"
  echo "m \"Show model/build cmdline\""                        >> "${TMP_PATH}/menu"
  echo "u \"Show SATA(s) # ports and drives\""                 >> "${TMP_PATH}/menu"
  echo "e \"Exit\""                                            >> "${TMP_PATH}/menu"
  # Loop menu
  while true; do
    dialog --backtitle "`backtitle`" --menu "Choose a option" 0 0 0 \
      --file "${TMP_PATH}/menu" 2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "`<${TMP_PATH}/resp`" in
      a)
        dialog --backtitle "`backtitle`" --title "User cmdline" \
          --inputbox "Type a name of cmdline" 0 0 \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && continue
        NAME="`sed 's/://g' <"${TMP_PATH}/resp"`"
        [ -z "${NAME}" ] && continue
        dialog --backtitle "`backtitle`" --title "User cmdline" \
          --inputbox "Type a value of '${NAME}' cmdline" 0 0 "${CMDLINE[${NAME}]}" \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && continue
        VALUE="`<"${TMP_PATH}/resp"`"
        CMDLINE[${NAME}]="${VALUE}"
        writeConfigKey "cmdline.${NAME}" "${VALUE}" "${USER_CONFIG_FILE}"
        ;;
      d)
        if [ ${#CMDLINE[@]} -eq 0 ]; then
          dialog --backtitle "`backtitle`" --msgbox "No user cmdline to remove" 0 0 
          continue
        fi
        ITEMS=""
        for I in "${!CMDLINE[@]}"; do
          ITEMS+="${I} ${CMDLINE[${I}]} off "
        done
        dialog --backtitle "`backtitle`" \
          --checklist "Select cmdline to remove" 0 0 0 ${ITEMS} \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        RESP=`<"${TMP_PATH}/resp"`
        [ -z "${RESP}" ] && continue
        for I in ${RESP}; do
          unset CMDLINE[${I}]
          deleteConfigKey "cmdline.${I}" "${USER_CONFIG_FILE}"
        done
        ;;
      s)
        ITEMS=""
        for KEY in ${!CMDLINE[@]}; do
          ITEMS+="${KEY}: ${CMDLINE[$KEY]}\n"
        done
        dialog --backtitle "`backtitle`" --title "User cmdline" \
          --aspect 18 --msgbox "${ITEMS}" 0 0
        ;;
      m)
        ITEMS=""
        while IFS="=" read KEY VALUE; do
          ITEMS+="${KEY}: ${VALUE}\n"
        done < <(readModelMap "${MODEL}" "builds.${BUILD}.cmdline")
        dialog --backtitle "`backtitle`" --title "Model/build cmdline" \
          --aspect 18 --msgbox "${ITEMS}" 0 0
        ;;
      u) TEXT=""
        NUMPORTS=0
        for PCI in `lspci -d ::106 | awk '{print$1}'`; do
          NAME=`lspci -s "${PCI}" | sed "s/\ .*://"`
          TEXT+="\Zb${NAME}\Zn\nPorts: "
          unset HOSTPORTS
          declare -A HOSTPORTS
          while read LINE; do
            ATAPORT="`echo ${LINE} | grep -o 'ata[0-9]*'`"
            PORT=`echo ${ATAPORT} | sed 's/ata//'`
            HOSTPORTS[${PORT}]=`echo ${LINE} | grep -o 'host[0-9]*$'`
          done < <(ls -l /sys/class/scsi_host | fgrep "${PCI}")
          while read PORT; do
            ls -l /sys/block | fgrep -q "${PCI}/ata${PORT}" && ATTACH=1 || ATTACH=0
            PCMD=`cat /sys/class/scsi_host/${HOSTPORTS[${PORT}]}/ahci_port_cmd`
            [ "${PCMD}" = "0" ] && DUMMY=1 || DUMMY=0
            [ ${ATTACH} -eq 1 ] && TEXT+="\Z2\Zb"
            [ ${DUMMY} -eq 1 ] && TEXT+="\Z1"
            TEXT+="${PORT}\Zn "
            NUMPORTS=$((${NUMPORTS}+1))
          done < <(echo ${!HOSTPORTS[@]} | tr ' ' '\n' | sort -n)
          TEXT+="\n"
        done
        TEXT+="\nTotal of ports: ${NUMPORTS}\n"
        TEXT+="\nPorts with color \Z1red\Zn as DUMMY, color \Z2\Zbgreen\Zn has drive connected."
        dialog --backtitle "`backtitle`" --colors --aspect 18 \
          --msgbox "${TEXT}" 0 0
        ;;
      e) return ;;
    esac
  done
}

###############################################################################
function synoinfoMenu() {
  # Read synoinfo from user config
  unset SYNOINFO
  declare -A SYNOINFO
  while IFS="=" read KEY VALUE; do
    [ -n "${KEY}" ] && SYNOINFO["${KEY}"]="${VALUE}"
  done < <(readConfigMap "synoinfo" "${USER_CONFIG_FILE}")

  echo "a \"Add/edit an synoinfo item\""   > "${TMP_PATH}/menu"
  echo "d \"Delete synoinfo item(s)\""    >> "${TMP_PATH}/menu"
  echo "s \"Show user synoinfo\""         >> "${TMP_PATH}/menu"
  echo "m \"Show model/build synoinfo\""  >> "${TMP_PATH}/menu"
  echo "e \"Exit\""                       >> "${TMP_PATH}/menu"

  # menu loop
  while true; do
    dialog --backtitle "`backtitle`" --menu "Choose a option" 0 0 0 \
      --file "${TMP_PATH}/menu" 2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "`<${TMP_PATH}/resp`" in
      a)
        dialog --backtitle "`backtitle`" --title "User synoinfo" \
          --inputbox "Type a name of synoinfo variable" 0 0 \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && continue
        NAME="`sed 's/://g' <"${TMP_PATH}/resp"`"
        dialog --backtitle "`backtitle`" --title "User synoinfo" \
          --inputbox "Type a value of '${NAME}' variable" 0 0 "${SYNOINFO[${NAME}]}" \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && continue
        VALUE="`<"${TMP_PATH}/resp"`"
        SYNOINFO[${NAME}]="${VALUE}"
        writeConfigKey "synoinfo.${NAME}" "${VALUE}" "${USER_CONFIG_FILE}"
        DIRTY=1
        ;;
      d)
        if [ ${#SYNOINFO[@]} -eq 0 ]; then
          dialog --backtitle "`backtitle`" --msgbox "No user synoinfo to remove" 0 0 
          continue
        fi
        ITEMS=""
        for I in "${!SYNOINFO[@]}"; do
          ITEMS+="${I} ${SYNOINFO[${I}]} off "
        done
        dialog --backtitle "`backtitle`" \
          --checklist "Select synoinfo to remove" 0 0 0 ${ITEMS} \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        RESP=`<"${TMP_PATH}/resp"`
        [ -z "${RESP}" ] && continue
        for I in ${RESP}; do
          unset SYNOINFO[${I}]
          deleteConfigKey "synoinfo.${I}" "${USER_CONFIG_FILE}"
        done
        DIRTY=1
        ;;
      s)
        ITEMS=""
        for KEY in ${!SYNOINFO[@]}; do
          ITEMS+="${KEY}: ${SYNOINFO[$KEY]}\n"
        done
        dialog --backtitle "`backtitle`" --title "User synoinfo" \
          --aspect 18 --msgbox "${ITEMS}" 0 0
        ;;
      m)
        ITEMS=""
        while IFS="=" read KEY VALUE; do
          ITEMS+="${KEY}: ${VALUE}\n"
        done < <(readModelMap "${MODEL}" "builds.${BUILD}.synoinfo")
        dialog --backtitle "`backtitle`" --title "Model/build synoinfo" \
          --aspect 18 --msgbox "${ITEMS}" 0 0
        ;;
      e) return ;;
    esac
  done
}

###############################################################################
# Where the magic happens :D
function make() {
  clear
  PLATFORM="`readModelKey "${MODEL}" "platform"`"
  KVER="`readModelKey "${MODEL}" "builds.${BUILD}.kver"`"
  PAT_URL="`readModelKey "${MODEL}" "builds.${BUILD}.pat.url"`"
  PAT_HASH="`readModelKey "${MODEL}" "builds.${BUILD}.pat.hash"`"
  RAMDISK_HASH="`readModelKey "${MODEL}" "builds.${BUILD}.pat.ramdisk-hash"`"
  ZIMAGE_HASH="`readModelKey "${MODEL}" "builds.${BUILD}.pat.zimage-hash"`"

  # Check if all addon exists
  while IFS="=" read ADDON PARAM; do
    [ -z "${ADDON}" ] && continue
    if ! checkAddonExist "${ADDON}" "${PLATFORM}" "${KVER}"; then
      dialog --backtitle "`backtitle`" --title "Error" --aspect 18 \
        --msgbox "Addon ${ADDON} not found!" 0 0
      return 1
    fi
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")

  if [ ${RAMCACHE} -eq 0 ]; then
    OUT_PATH="${CACHE_PATH}/dl"
    echo "Cache in disk"
  else
    OUT_PATH="${TMP_PATH}/dl"
    echo "Cache in ram"
  fi
  mkdir -p "${OUT_PATH}"

  UNTAR_PAT_PATH="${TMP_PATH}/pat"
  PAT_FILE="${MODEL}-${BUILD}.pat"
  PAT_PATH="${OUT_PATH}/${PAT_FILE}"
  EXTRACTOR_PATH="${CACHE_PATH}/extractor"
  EXTRACTOR_BIN="syno_extract_system_patch"
  OLDPAT_URL="https://global.download.synology.com/download/DSM/release/7.0.1/42218/DSM_DS3622xs%2B_42218.pat"
  OLDPAT_PATH="${OUT_PATH}/DS3622xs+-42218.pat"

  if [ -f "${PAT_PATH}" ]; then
    echo "${PAT_FILE} cached."
  else
    echo "Downloading ${PAT_FILE}"
    curl --insecure -L "${PAT_URL}" -o "${PAT_PATH}" --progress-bar
    if [ $? -ne 0 ]; then
      dialog --backtitle "`backtitle`" --title "Error downloading" --aspect 18 \
        --msgbox "Check internet or cache disk space" 0 0
      return 1
    fi
  fi

  echo -n "Checking hash of ${PAT_FILE}: "
  if [ "`sha256sum ${PAT_PATH} | awk '{print$1}'`" != "${PAT_HASH}" ]; then
    dialog --backtitle "`backtitle`" --title "Error" --aspect 18 \
      --msgbox "Hash of pat not match, try again!" 0 0
    rm -f ${PAT_PATH}
    return 1
  fi
  echo "OK"

  rm -rf "${UNTAR_PAT_PATH}"
  mkdir "${UNTAR_PAT_PATH}"
  echo -n "Disassembling ${PAT_FILE}: "

  header="$(od -bcN2 ${PAT_PATH} | head -1 | awk '{print $3}')"
  case ${header} in
    105)
      echo "Uncompressed tar"
      isencrypted="no"
      ;;
    213)
      echo "Compressed tar"
      isencrypted="no"
      ;;
    255)
      echo "Encrypted"
      isencrypted="yes"
      ;;
    *)
      dialog --backtitle "`backtitle`" --title "Error" --aspect 18 \
        --msgbox "Could not determine if pat file is encrypted or not, maybe corrupted, try again!" \
        0 0
      return 1
      ;;
  esac

  if [ "${isencrypted}" = "yes" ]; then
    # Check existance of extractor
    if [ -f "${EXTRACTOR_PATH}/${EXTRACTOR_BIN}" ]; then
      echo "Extractor cached."
    else
      # Extractor not exists, get it.
      mkdir -p "${EXTRACTOR_PATH}"
      # Check if old pat already downloaded
      if [ ! -f "${OLDPAT_PATH}" ]; then
        echo "Downloading old pat to extract synology .pat extractor..."
        curl --insecure -L "${OLDPAT_URL}" \
          -o "${OLDPAT_PATH}"  --progress-bar
        if [ $? -ne 0 ]; then
          dialog --backtitle "`backtitle`" --title "Error downloading" --aspect 18 \
            --msgbox "Check internet or cache disk space" 0 0
          return 1
        fi
      fi
      # Extract ramdisk from PAT
      rm -rf "${RAMDISK_PATH}"
      mkdir -p "${RAMDISK_PATH}"
      tar -xf "${OLDPAT_PATH}" -C "${RAMDISK_PATH}" rd.gz >"${LOG_FILE}" 2>&1
      if [ $? -ne 0 ]; then
        dialog --backtitle "`backtitle`" --title "Error extracting" --textbox "${LOG_FILE}" 0 0
      fi

      # Extract all files from rd.gz
      (cd "${RAMDISK_PATH}"; xz -dc < rd.gz | cpio -idm) >/dev/null 2>&1 || true
      # Copy only necessary files
      for f in libcurl.so.4 libmbedcrypto.so.5 libmbedtls.so.13 libmbedx509.so.1 libmsgpackc.so.2 libsodium.so libsynocodesign-ng-virtual-junior-wins.so.7; do
        cp "${RAMDISK_PATH}/usr/lib/${f}" "${EXTRACTOR_PATH}"
      done
      cp "${RAMDISK_PATH}/usr/syno/bin/scemd" "${EXTRACTOR_PATH}/${EXTRACTOR_BIN}"
      rm -rf "${RAMDISK_PATH}"
    fi
    # Uses the extractor to untar pat file
    echo "Extracting..."
    LD_LIBRARY_PATH=${EXTRACTOR_PATH} "${EXTRACTOR_PATH}/${EXTRACTOR_BIN}" "${PAT_PATH}" "${UNTAR_PAT_PATH}" || true
  else
    echo "Extracting..."
    tar -xf "${PAT_PATH}" -C "${UNTAR_PAT_PATH}" >"${LOG_FILE}" 2>&1
    if [ $? -ne 0 ]; then
      dialog --backtitle "`backtitle`" --title "Error extracting" --textbox "${LOG_FILE}" 0 0
    fi
  fi

  echo -n "Checking hash of zImage: "
  HASH="`sha256sum ${UNTAR_PAT_PATH}/zImage | awk '{print$1}'`"
  if [ "${HASH}" != "${ZIMAGE_HASH}" ]; then
    sleep 1
    dialog --backtitle "`backtitle`" --title "Error" --aspect 18 \
      --msgbox "Hash of zImage not match, try again!" 0 0
    return 1
  fi
  echo "OK"
  writeConfigKey "zimage-hash" "${ZIMAGE_HASH}" "${USER_CONFIG_FILE}"

  echo -n "Checking hash of ramdisk: "
  HASH="`sha256sum ${UNTAR_PAT_PATH}/rd.gz | awk '{print$1}'`"
  if [ "${HASH}" != "${RAMDISK_HASH}" ]; then
    sleep 1
    dialog --backtitle "`backtitle`" --title "Error" --aspect 18 \
      --msgbox "Hash of ramdisk not match, try again!" 0 0
    return 1
  fi
  echo "OK"
  writeConfigKey "ramdisk-hash" "${RAMDISK_HASH}" "${USER_CONFIG_FILE}"

  echo -n "Copying files: "
  cp "${UNTAR_PAT_PATH}/grub_cksum.syno" "${BOOTLOADER_PATH}"
  cp "${UNTAR_PAT_PATH}/GRUB_VER"        "${BOOTLOADER_PATH}"
  cp "${UNTAR_PAT_PATH}/grub_cksum.syno" "${SLPART_PATH}"
  cp "${UNTAR_PAT_PATH}/GRUB_VER"        "${SLPART_PATH}"
  cp "${UNTAR_PAT_PATH}/zImage"          "${ORI_ZIMAGE_FILE}"
  cp "${UNTAR_PAT_PATH}/rd.gz"           "${ORI_RDGZ_FILE}"
  echo "OK"

  /opt/arpl/zimage-patch.sh
  if [ $? -ne 0 ]; then
    dialog --backtitle "`backtitle`" --title "Error" --aspect 18 \
      --msgbox "zImage not patched:\n`<"${LOG_FILE}"`" 0 0
    return 1
  fi

  /opt/arpl/ramdisk-patch.sh
  if [ $? -ne 0 ]; then
    dialog --backtitle "`backtitle`" --title "Error" --aspect 18 \
      --msgbox "Ramdisk not patched:\n`<"${LOG_FILE}"`" 0 0
    return 1
  fi

  echo "Cleaning"
  rm -rf "${UNTAR_PAT_PATH}"

  echo "Ready!"
  sleep 3
  DIRTY=0
  return 0
}

###############################################################################
# Calls boot.sh to boot into DSM kernel/ramdisk
function boot() {
  [ ${DIRTY} -eq 1 ] && dialog --backtitle "`backtitle`" --title "Alert" \
    --yesno "Config changed, would you like to rebuild the loader?" 0 0
  if [ $? -eq 0 ]; then
    make || return
  fi
  boot.sh
}

###############################################################################
# Permits user edit the user config
function editUserConfig() {
  while true; do
    dialog --backtitle "`backtitle`" --title "Edit with caution" \
      --editbox "${USER_CONFIG_FILE}" 0 0 2>"${TMP_PATH}/userconfig"
    [ $? -ne 0 ] && return
    mv "${TMP_PATH}/userconfig" "${USER_CONFIG_FILE}"
    ERRORS=`yq eval "${USER_CONFIG_FILE}" 2>&1`
    [ $? -eq 0 ] && break
    dialog --backtitle "`backtitle`" --title "Invalid YAML format" --msgbox "${ERRORS}" 0 0
  done
  OLDMODEL=${MODEL}
  OLDBUILD=${BUILD}
  MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"
  BUILD="`readConfigKey "build" "${USER_CONFIG_FILE}"`"
  SN="`readConfigKey "sn" "${USER_CONFIG_FILE}"`"

  if [ "${MODEL}" != "${OLDMODEL}" -o "${BUILD}" != "${OLDBUILD}" ]; then
    # Remove old files
    rm -f "${MOD_ZIMAGE_FILE}"
    rm -f "${MOD_RDGZ_FILE}"
  fi
  DIRTY=1
}

###############################################################################
# Shows available keymaps to user choose one
function keymapMenu() {
  OPTIONS=""
  while read KM; do
    OPTIONS+="${KM::-7} "
  done < <(cd /usr/share/keymaps/i386/qwerty; ls *.map.gz)
  dialog --backtitle "`backtitle`" --no-items \
    --menu "Choice a keymap" 0 0 0 ${OPTIONS} \
    2>/tmp/resp
  [ $? -ne 0 ] && return
  resp=`cat /tmp/resp 2>/dev/null`
  [ -z "${resp}" ] && return
  KEYMAP=${resp}
  writeConfigKey "keymap" "${KEYMAP}" "${USER_CONFIG_FILE}"
  zcat /usr/share/keymaps/i386/qwerty/${KEYMAP}.map.gz | loadkeys
}

###############################################################################
function updateMenu() {
  while true; do
    dialog --backtitle "`backtitle`" --menu "Choose a option" 0 0 0 \
      a "Update arpl" \
      d "Update addons" \
      l "Update LKMs" \
      e "Exit" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "`<${TMP_PATH}/resp`" in
      a)
        dialog --backtitle "`backtitle`" --title "Update arpl" --aspect 18 \
          --infobox "Checking last version" 0 0
        ACTUALVERSION="v${ARPL_VERSION}"
        TAG="`curl --insecure -s https://api.github.com/repos/fbelavenuto/arpl/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`"
        if [ $? -ne 0 -o -z "${TAG}" ]; then
          dialog --backtitle "`backtitle`" --title "Update arpl" --aspect 18 \
            --msgbox "Error checking new version" 0 0
          continue
        fi
        if [ "${ACTUALVERSION}" = "${TAG}" ]; then
          dialog --backtitle "`backtitle`" --title "Update arpl" --aspect 18 \
            --yesno "No new version. Actual version is ${ACTUALVERSION}\nForce update?" 0 0
          [ $? -ne 0 ] && continue
        fi
        dialog --backtitle "`backtitle`" --title "Update arpl" --aspect 18 \
          --infobox "Downloading last version ${TAG}" 0 0
        curl --insecure -s -L "https://github.com/fbelavenuto/arpl/releases/download/${TAG}/bzImage" -o /tmp/bzImage
        if [ $? -ne 0 ]; then
          dialog --backtitle "`backtitle`" --title "Update arpl" --aspect 18 \
            --msgbox "Error downloading bzImage" 0 0
          continue
        fi
        curl --insecure -s -L "https://github.com/fbelavenuto/arpl/releases/download/${TAG}/rootfs.cpio.xz" -o /tmp/rootfs.cpio.xz
        if [ $? -ne 0 ]; then
          dialog --backtitle "`backtitle`" --title "Update arpl" --aspect 18 \
            --msgbox "Error downloading rootfs.cpio.xz" 0 0
          continue
        fi
        dialog --backtitle "`backtitle`" --title "Update arpl" --aspect 18 \
          --infobox "Installing new files" 0 0
        mv /tmp/bzImage /mnt/p1/bzImage-arpl
        mv /tmp/rootfs.cpio.xz /mnt/p1/initrd-arpl
        dialog --backtitle "`backtitle`" --title "Update arpl" --aspect 18 \
          --yesno "Arpl updated with success to ${TAG}!\nReboot?" 0 0
        [ $? -ne 0 ] && continue
        reboot
        exit
        ;;

      d)
        dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
          --infobox "Checking last version" 0 0
        TAG=`curl --insecure -s https://api.github.com/repos/fbelavenuto/arpl-addons/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`
        if [ $? -ne 0 -o -z "${TAG}" ]; then
          dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
            --msgbox "Error checking new version" 0 0
          continue
        fi
        dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
          --infobox "Downloading last version" 0 0
        curl --insecure -s -L "https://github.com/fbelavenuto/arpl-addons/releases/download/${TAG}/addons.zip" -o /tmp/addons.zip
        if [ $? -ne 0 ]; then
          dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
            --msgbox "Error downloading new version" 0 0
          continue
        fi
        dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
          --infobox "Extracting last version" 0 0
        rm -rf /tmp/addons
        mkdir -p /tmp/addons
        unzip /tmp/addons.zip -d /tmp/addons >/dev/null 2>&1
        dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
          --infobox "Installing new addons" 0 0
        DEST_PATH="/mnt/p3/addons"
        for PKG in `ls /tmp/addons/*.addon`; do
          ADDON=`basename ${PKG} | sed 's|.addon||'`
          rm -rf "${DEST_PATH}/${ADDON}"
          mkdir -p "${DEST_PATH}/${ADDON}"
          tar xaf "${PKG}" -C "${DEST_PATH}/${ADDON}" >/dev/null 2>&1
        done
        dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
          --msgbox "Addons updated with success!" 0 0
        ;;

      l)
        dialog --backtitle "`backtitle`" --title "Update LKMs" --aspect 18 \
          --infobox "Checking last version" 0 0
        TAG=`curl --insecure -s https://api.github.com/repos/fbelavenuto/redpill-lkm/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`
        if [ $? -ne 0 -o -z "${TAG}" ]; then
          dialog --backtitle "`backtitle`" --title "Update LKMs" --aspect 18 \
            --msgbox "Error checking new version" 0 0
          continue
        fi
        dialog --backtitle "`backtitle`" --title "Update LKMs" --aspect 18 \
          --infobox "Downloading last version" 0 0
        curl --insecure -s -L "https://github.com/fbelavenuto/redpill-lkm/releases/download/${TAG}/rp-lkms.zip" -o /tmp/rp-lkms.zip
        if [ $? -ne 0 ]; then
          dialog --backtitle "`backtitle`" --title "Update LKMs" --aspect 18 \
            --msgbox "Error downloading new version" 0 0
          continue
        fi
        dialog --backtitle "`backtitle`" --title "Update LKMs" --aspect 18 \
          --infobox "Extracting last version" 0 0
        rm -rf /mnt/p3/lkms/*
        unzip /tmp/rp-lkms.zip -d /mnt/p3/lkms >/dev/null 2>&1
        dialog --backtitle "`backtitle`" --title "Update LKMs" --aspect 18 \
          --msgbox "LKMs updated with success!" 0 0
        ;;

      e) return ;;
    esac
  done
}

###############################################################################
###############################################################################

# Main loop
NEXT="m"
while true; do
  echo "m \"Choose a model\""                          > "${TMP_PATH}/menu"
  if [ -n "${MODEL}" ]; then
    echo "n \"Choose a Build Number\""                >> "${TMP_PATH}/menu"
    echo "s \"Choose a serial number\""               >> "${TMP_PATH}/menu"
    if [ -n "${BUILD}" ]; then
      echo "a \"Addons/drivers\""                     >> "${TMP_PATH}/menu"
      echo "x \"Cmdline menu\""                       >> "${TMP_PATH}/menu"
      echo "i \"Synoinfo menu\""                      >> "${TMP_PATH}/menu"
      echo "l \"Switch LKM version: \Z4${LKM}\Zn\""   >> "${TMP_PATH}/menu"
      echo "d \"Build the loader\""                   >> "${TMP_PATH}/menu"
    fi
  fi
  loaderIsConfigured && echo "b \"Boot the loader\" " >> "${TMP_PATH}/menu"
  echo "u \"Edit user config file manually\""         >> "${TMP_PATH}/menu"
  echo "k \"Choose a keymap\" "                       >> "${TMP_PATH}/menu"
  [ ${RAMCACHE} -eq 0 -a -d "${CACHE_PATH}/dl" ] && echo "c \"Clean disk cache\"" >> "${TMP_PATH}/menu"
  echo "p \"Update menu\""                            >> "${TMP_PATH}/menu"
  echo "e \"Exit\"" >> "${TMP_PATH}/menu"
  dialog --clear --default-item ${NEXT} --backtitle "`backtitle`" --colors \
    --menu "Choose the option" 0 0 0 --file "${TMP_PATH}/menu" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && break
  case `<"${TMP_PATH}/resp"` in
    m) modelMenu; NEXT="n" ;;
    n) buildMenu; NEXT="s" ;;
    s) serialMenu; NEXT="a" ;;
    a) addonMenu; NEXT="x" ;;
    x) cmdlineMenu; NEXT="i" ;;
    i) synoinfoMenu; NEXT="l" ;;
    l) [ "${LKM}" = "dev" ] && LKM='prod' || LKM='dev'
      writeConfigKey "lkm" "${LKM}" "${USER_CONFIG_FILE}"
      NEXT="d"
      ;;
    d) make; NEXT="b" ;;
    b) boot ;;
    u) editUserConfig; NEXT="u" ;;
    k) keymapMenu ;;
    c) dialog --backtitle "`backtitle`" --title "Cleaning" --aspect 18 \
      --prgbox "rm -rfv \"${CACHE_PATH}/dl\"" 0 0 ;;
    p) updateMenu ;;
    e) break ;;
  esac
done
clear
echo -e "Call \033[1;32mmenu.sh\033[0m to return to menu"

