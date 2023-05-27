#!/usr/bin/env bash

. /opt/arpl/include/functions.sh
. /opt/arpl/include/addons.sh
. /opt/arpl/include/modules.sh

# Check partition 3 space, if < 2GiB is necessary clean cache folder
CLEARCACHE=0
LOADER_DISK="`blkid | grep 'LABEL="ARPL3"' | cut -d3 -f1`"
LOADER_DEVICE_NAME=`echo ${LOADER_DISK} | sed 's|/dev/||'`
if [ `cat /sys/block/${LOADER_DEVICE_NAME}/${LOADER_DEVICE_NAME}3/size` -lt 4194304 ]; then
  CLEARCACHE=1
fi

# Get actual IP
IP=`ip route 2>/dev/null | sed -n 's/.* via .* dev \(.*\)  src \(.*\)  metric .*/\1: \2 /p' | head -1`

# Dirty flag
DIRTY=0
# Debug flag
# DEBUG=0

MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"
BUILD="`readConfigKey "build" "${USER_CONFIG_FILE}"`"
LAYOUT="`readConfigKey "layout" "${USER_CONFIG_FILE}"`"
KEYMAP="`readConfigKey "keymap" "${USER_CONFIG_FILE}"`"
LKM="`readConfigKey "lkm" "${USER_CONFIG_FILE}"`"
DIRECTBOOT="`readConfigKey "directboot" "${USER_CONFIG_FILE}"`"
SN="`readConfigKey "sn" "${USER_CONFIG_FILE}"`"

###############################################################################
# Mounts backtitle dynamically
function backtitle() {
  BACKTITLE="${ARPL_TITLE}"
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
    BACKTITLE+=" (${LAYOUT}/${KEYMAP})"
  else
    BACKTITLE+=" (qwerty/us)"
  fi
  if [ -d "/sys/firmware/efi" ]; then
    BACKTITLE+=" [UEFI]"
  else
    BACKTITLE+=" [BIOS]"
  fi
  echo ${BACKTITLE}
}

###############################################################################
# Shows available models to user choose one
function modelMenu() {
  if [ -z "${1}" ]; then
    RESTRICT=1
    FLGBETA=0
    dialog --backtitle "`backtitle`" --title "$(TEXT "Model")" --aspect 18 \
      --infobox "$(TEXT "Reading models")" 0 0
    while true; do
      echo "" > "${TMP_PATH}/menu"
      FLGNEX=0
      while read M; do
        M="`basename ${M}`"
        M="${M::-4}"
        PLATFORM=`readModelKey "${M}" "platform"`
        DT="`readModelKey "${M}" "dt"`"
        BETA="`readModelKey "${M}" "beta"`"
        [ "${BETA}" = "true" -a ${FLGBETA} -eq 0 ] && continue
        # Check id model is compatible with CPU
        COMPATIBLE=1
        if [ ${RESTRICT} -eq 1 ]; then
          for F in `readModelArray "${M}" "flags"`; do
            if ! grep -q "^flags.*${F}.*" /proc/cpuinfo; then
              COMPATIBLE=0
              FLGNEX=1
              break
            fi
          done
        fi
        [ "${DT}" = "true" ] && DT="-DT" || DT=""
        [ ${COMPATIBLE} -eq 1 ] && echo "${M} \"\Zb${PLATFORM}${DT}\Zn\" " >> "${TMP_PATH}/menu"
      done < <(find "${MODEL_CONFIG_PATH}" -maxdepth 1 -name \*.yml | sort)
      [ ${FLGNEX} -eq 1 ] && echo "f \"\Z1$(TEXT "Disable flags restriction")\Zn\"" >> "${TMP_PATH}/menu"
      [ ${FLGBETA} -eq 0 ] && echo "b \"\Z1$(TEXT "Show beta models")\Zn\"" >> "${TMP_PATH}/menu"
      dialog --backtitle "`backtitle`" --colors --menu "$(TEXT "Choose the model")" 0 0 0 \
        --file "${TMP_PATH}/menu" 2>${TMP_PATH}/resp
      [ $? -ne 0 ] && return
      resp=$(<${TMP_PATH}/resp)
      [ -z "${resp}" ] && return
      if [ "${resp}" = "f" ]; then
        RESTRICT=0
        continue
      fi
      if [ "${resp}" = "b" ]; then
        FLGBETA=1
        continue
      fi
      break
    done
  else
    resp="${1}"
  fi
  # If user change model, clean buildnumber and S/N
  if [ "${MODEL}" != "${resp}" ]; then
    MODEL=${resp}
    writeConfigKey "model" "${MODEL}" "${USER_CONFIG_FILE}"
    BUILD=""
    writeConfigKey "build" "${BUILD}" "${USER_CONFIG_FILE}"
    SN=""
    writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
    # Delete old files
    rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
    rm -f "${TMP_PATH}/patdownloadurl"
    DIRTY=1
  fi
}

###############################################################################
# Shows available buildnumbers from a model to user choose one
function buildMenu() {
  ITEMS="`readConfigEntriesArray "builds" "${MODEL_CONFIG_PATH}/${MODEL}.yml" | sort -r`"
  if [ -z "${1}" ]; then
    dialog --clear --no-items --backtitle "`backtitle`" \
      --menu "$(TEXT "Choose a build number")" 0 0 0 ${ITEMS} 2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    resp=$(<${TMP_PATH}/resp)
    [ -z "${resp}" ] && return
  else
    if ! arrayExistItem "${1}" ${ITEMS}; then return; fi
    resp="${1}"
  fi
  if [ "${BUILD}" != "${resp}" ]; then
    local KVER=`readModelKey "${MODEL}" "builds.${resp}.kver"`
    if [ -d "/sys/firmware/efi" -a "${KVER:0:1}" = "3" ]; then
      dialog --backtitle "`backtitle`" --title "$(TEXT "Build Number")" --aspect 18 \
       --msgbox "$(TEXT "This version does not support UEFI startup, Please select another version or switch the startup mode.")" 0 0
      buildMenu
    fi
    if [ ! "usb" = "`udevadm info --query property --name ${LOADER_DISK} | grep BUS | cut -d= -f2`" -a "${KVER:0:1}" = "5" ]; then
      dialog --backtitle "`backtitle`" --title "$(TEXT "Build Number")" --aspect 18 \
       --msgbox "$(TEXT "This version only support usb startup, Please select another version or switch the startup mode.")" 0 0
      buildMenu
    fi
    dialog --backtitle "`backtitle`" --title "$(TEXT "Build Number")" \
      --infobox "$(TEXT "Reconfiguring Synoinfo, Addons and Modules")" 0 0
    BUILD=${resp}
    writeConfigKey "build" "${BUILD}" "${USER_CONFIG_FILE}"
    # Delete synoinfo and reload model/build synoinfo
    writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
    while IFS=': ' read KEY VALUE; do
      writeConfigKey "synoinfo.${KEY}" "${VALUE}" "${USER_CONFIG_FILE}"
    done < <(readModelMap "${MODEL}" "builds.${BUILD}.synoinfo")
    # Check addons
    PLATFORM="`readModelKey "${MODEL}" "platform"`"
    KVER="`readModelKey "${MODEL}" "builds.${BUILD}.kver"`"
    while IFS=': ' read ADDON PARAM; do
      [ -z "${ADDON}" ] && continue
      if ! checkAddonExist "${ADDON}" "${PLATFORM}" "${KVER}"; then
        deleteConfigKey "addons.${ADDON}" "${USER_CONFIG_FILE}"
      fi
    done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")
    # Rebuild modules
    writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
    while read ID DESC; do
      writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
    done < <(getAllModules "${PLATFORM}" "${KVER}")
    # Remove old files
    rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
    rm -f "${TMP_PATH}/patdownloadurl"
    DIRTY=1
  fi
}

###############################################################################
# Shows menu to user type one or generate randomly
function serialMenu() {
  while true; do
    dialog --clear --backtitle "`backtitle`" \
      --menu "$(TEXT "Choose a option")" 0 0 0 \
      a "$(TEXT "Generate a random serial number")" \
      m "$(TEXT "Enter a serial number")" \
    2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    resp=$(<${TMP_PATH}/resp)
    [ -z "${resp}" ] && return
    if [ "${resp}" = "m" ]; then
      while true; do
        dialog --backtitle "`backtitle`" \
          --inputbox "$(TEXT "Please enter a serial number ")" 0 0 "" \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && return
        SERIAL=`cat ${TMP_PATH}/resp`
        if [ -z "${SERIAL}" ]; then
          return
        elif [ `validateSerial ${MODEL} ${SERIAL}` -eq 1 ]; then
          break
        fi
        dialog --backtitle "`backtitle`" --title "$(TEXT "Alert")" \
          --yesno "$(TEXT "Invalid serial, continue?")" 0 0
        [ $? -eq 0 ] && break
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
# Manage addons
function addonMenu() {
  # Read 'platform' and kernel version to check if addon exists
  PLATFORM="`readModelKey "${MODEL}" "platform"`"
  KVER="`readModelKey "${MODEL}" "builds.${BUILD}.kver"`"
  # Read addons from user config
  unset ADDONS
  declare -A ADDONS
  while IFS=': ' read KEY VALUE; do
    [ -n "${KEY}" ] && ADDONS["${KEY}"]="${VALUE}"
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")
  NEXT="a"
  # Loop menu
  while true; do
    dialog --backtitle "`backtitle`" --default-item ${NEXT} \
      --menu "$(TEXT "Choose a option")" 0 0 0 \
      a "$(TEXT "Add an addon")" \
      d "$(TEXT "Delete addon(s)")" \
      s "$(TEXT "Show user addons")" \
      m "$(TEXT "Show all available addons")" \
      o "$(TEXT "Download a external addon")" \
      e "$(TEXT "Exit")" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "`<${TMP_PATH}/resp`" in
      a) NEXT='a'
        rm "${TMP_PATH}/menu"
        while read ADDON DESC; do
          arrayExistItem "${ADDON}" "${!ADDONS[@]}" && continue          # Check if addon has already been added
          echo "${ADDON} \"${DESC}\"" >> "${TMP_PATH}/menu"
        done < <(availableAddons "${PLATFORM}" "${KVER}")
        if [ ! -f "${TMP_PATH}/menu" ] ; then 
          dialog --backtitle "`backtitle`" --msgbox "$(TEXT "No available addons to add")" 0 0 
          NEXT="e"
          continue
        fi
        dialog --backtitle "`backtitle`" --menu "$(TEXT "Select an addon")" 0 0 0 \
          --file "${TMP_PATH}/menu" 2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        ADDON="`<"${TMP_PATH}/resp"`"
        [ -z "${ADDON}" ] && continue
        dialog --backtitle "`backtitle`" --title "$(TEXT "Params")" \
          --inputbox "$(TEXT "Type a opcional params to addon")" 0 0 \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && continue
        ADDONS[${ADDON}]="`<"${TMP_PATH}/resp"`"
        writeConfigKey "addons.${ADDON}" "${VALUE}" "${USER_CONFIG_FILE}"
        DIRTY=1
        ;;
      d) NEXT='d'
        if [ ${#ADDONS[@]} -eq 0 ]; then
          dialog --backtitle "`backtitle`" --msgbox "$(TEXT "No user addons to remove")" 0 0 
          continue
        fi
        ITEMS=""
        for I in "${!ADDONS[@]}"; do
          ITEMS+="${I} ${I} off "
        done
        dialog --backtitle "`backtitle`" --no-tags \
          --checklist "$(TEXT "Select addon to remove")" 0 0 0 ${ITEMS} \
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
        dialog --backtitle "`backtitle`" --title "$(TEXT "User addons")" \
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
        dialog --backtitle "`backtitle`" --title "$(TEXT "Available addons")" \
          --colors --msgbox "${MSG}" 0 0
        ;;
      o)
        dialog --backtitle "`backtitle`" --aspect 18 --colors --inputbox "$(TEXT "please enter the complete URL to download.\n")" 0 0 \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && continue
        URL="`<"${TMP_PATH}/resp"`"
        [ -z "${URL}" ] && continue
        clear
        echo "`printf "$(TEXT "Downloading %s")" "${URL}"`"
        STATUS=`curl -k -w "%{http_code}" -L "${URL}" -o "${TMP_PATH}/addon.tgz" --progress-bar`
        if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
          dialog --backtitle "`backtitle`" --title "$(TEXT "Error downloading")" --aspect 18 \
            --msgbox "$(TEXT "Check internet, URL or cache disk space")" 0 0
          return 1
        fi
        ADDON="`untarAddon "${TMP_PATH}/addon.tgz"`"
        if [ -n "${ADDON}" ]; then
          dialog --backtitle "`backtitle`" --title "$(TEXT "Success")" --aspect 18 \
            --msgbox "`printf "$(TEXT "Addon '%s' added to loader")" "${ADDON}"`" 0 0
        else
          dialog --backtitle "`backtitle`" --title "$(TEXT "Invalid addon")" --aspect 18 \
            --msgbox "$(TEXT "File format not recognized!")" 0 0
        fi
        ;;
      e) return ;;
    esac
  done
}
###############################################################################
function moduleMenu() {
  PLATFORM="`readModelKey "${MODEL}" "platform"`"
  KVER="`readModelKey "${MODEL}" "builds.${BUILD}.kver"`"
  dialog --backtitle "`backtitle`" --title "$(TEXT "Modules")" --aspect 18 \
    --infobox "$(TEXT "Reading modules")" 0 0
  ALLMODULES=`getAllModules "${PLATFORM}" "${KVER}"`
  unset USERMODULES
  declare -A USERMODULES
  while IFS=': ' read KEY VALUE; do
    [ -n "${KEY}" ] && USERMODULES["${KEY}"]="${VALUE}"
  done < <(readConfigMap "modules" "${USER_CONFIG_FILE}")
  NEXT="s"
  # loop menu
  while true; do
    dialog --backtitle "`backtitle`"  --default-item ${NEXT} \
      --menu "$(TEXT "Choose a option")" 0 0 0 \
      s "$(TEXT "Show selected modules")" \
      l "$(TEXT "Select loaded modules")" \
      a "$(TEXT "Select all modules")" \
      d "$(TEXT "Deselect all modules")" \
      c "$(TEXT "Choose modules to include")" \
      o "$(TEXT "Download a external module")" \
      e "$(TEXT "Exit")" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && break
    case "`<${TMP_PATH}/resp`" in
      s) ITEMS=""
        for KEY in ${!USERMODULES[@]}; do
          ITEMS+="${KEY}: ${USERMODULES[$KEY]}\n"
        done
        dialog --backtitle "`backtitle`" --title "$(TEXT "User modules")" \
          --msgbox "${ITEMS}" 0 0
        ;;
      l) dialog --backtitle "`backtitle`" --title "$(TEXT "Modules")" \
           --infobox "$(TEXT "Selecting loaded modules")" 0 0
        KOLIST=""
        for I in `lsmod | awk -F' ' '{print $1}' | grep -v 'Module'`; do
          KOLIST+="`getdepends ${PLATFORM} ${KVER} ${I}` ${I} "
        done
        KOLIST=(`echo ${KOLIST} | tr ' ' '\n' | sort -u`)
        unset USERMODULES
        declare -A USERMODULES
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        for ID in ${KOLIST[@]}; do
          USERMODULES["${ID}"]=""
          writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
        done
        ;;
      a) dialog --backtitle "`backtitle`" --title "$(TEXT "Modules")" \
           --infobox "$(TEXT "Selecting all modules")" 0 0
        unset USERMODULES
        declare -A USERMODULES
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        while read ID DESC; do
          USERMODULES["${ID}"]=""
          writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
        done <<<${ALLMODULES}
        ;;

      d) dialog --backtitle "`backtitle`" --title "$(TEXT "Modules")" \
           --infobox "$(TEXT "Deselecting all modules")" 0 0
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        unset USERMODULES
        declare -A USERMODULES
        ;;

      c)
        rm -f "${TMP_PATH}/opts"
        while read ID DESC; do
          arrayExistItem "${ID}" "${!USERMODULES[@]}" && ACT="on" || ACT="off"
          echo "${ID} ${DESC} ${ACT}" >> "${TMP_PATH}/opts"
        done <<<${ALLMODULES}
        dialog --backtitle "`backtitle`" --title "$(TEXT "Modules")" --aspect 18 \
          --checklist "$(TEXT "Select modules to include")" 0 0 0 \
          --file "${TMP_PATH}/opts" 2>${TMP_PATH}/resp
        [ $? -ne 0 ] && continue
        resp=$(<${TMP_PATH}/resp)
        [ -z "${resp}" ] && continue
        dialog --backtitle "`backtitle`" --title "$(TEXT "Modules")" \
           --infobox "$(TEXT "Writing to user config")" 0 0
        unset USERMODULES
        declare -A USERMODULES
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        for ID in ${resp}; do
          USERMODULES["${ID}"]=""
          writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
        done
        ;;

      o)
        MSG=""
        MSG+="$(TEXT "This function is experimental and dangerous. If you don't know much, please exit.\n")" 
        MSG+="$(TEXT "The imported .ko of this function will be implanted into the corresponding arch's modules package, which will affect all models of the arch.\n")" 
        MSG+="$(TEXT "This program will not determine the availability of imported modules or even make type judgments, as please double check if it is correct.\n")" 
        MSG+="$(TEXT "If you want to remove it, please go to the \"Update Menu\" -> \"Update modules\" to forcibly update the modules. All imports will be reset.\n")" 
        MSG+="$(TEXT "Do you want to continue?")" 
        dialog --backtitle "`backtitle`" --title "$(TEXT "Download a external module")" \
            --yesno "${MSG}" 0 0
        [ $? -ne 0 ] && return
        dialog --backtitle "`backtitle`" --aspect 18 --colors --inputbox "$(TEXT "please enter the complete URL to download.\n")" 0 0 \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && continue
        URL="`<"${TMP_PATH}/resp"`"
        [ -z "${URL}" ] && continue
        clear
        echo "`printf "$(TEXT "Downloading %s")" "${URL}"`"
        STATUS=`curl -kLJO -w "%{http_code}" "${URL}" --progress-bar`
        if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
          dialog --backtitle "`backtitle`" --title "$(TEXT "Error downloading")" --aspect 18 \
            --msgbox "$(TEXT "Check internet, URL or cache disk space")" 0 0
          return 1
        fi
        KONAME=$(basename "$URL")
        if [ -n "${KONAME}" -a "${KONAME##*.}" = "ko" ]; then
          addToModules ${PLATFORM} ${KVER} ${KONAME}
          dialog --backtitle "`backtitle`" --title "$(TEXT "Success")" --aspect 18 \
            --msgbox "`printf "$(TEXT "Module '%s' added to %s-%s")" "${KONAME}" ${PLATFORM} ${KVER}`" 0 0
          rm -f ${KONAME}
        else
          dialog --backtitle "`backtitle`" --title "$(TEXT "Invalid module")" --aspect 18 \
            --msgbox "$(TEXT "File format not recognized!")" 0 0
        fi
        ;;
      e)
        break
        ;;
    esac
  done
}

###############################################################################
function cmdlineMenu() {
  unset CMDLINE
  declare -A CMDLINE
  while IFS=': ' read KEY VALUE; do
    [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
  done < <(readConfigMap "cmdline" "${USER_CONFIG_FILE}")
  echo "a \"$(TEXT "Add/edit a cmdline item")\""                           > "${TMP_PATH}/menu"
  echo "d \"$(TEXT "Delete cmdline item(s)")\""                           >> "${TMP_PATH}/menu"
  echo "c \"$(TEXT "Define a custom MAC")\""                              >> "${TMP_PATH}/menu"
  echo "s \"$(TEXT "Show user cmdline")\""                                >> "${TMP_PATH}/menu"
  echo "m \"$(TEXT "Show model/build cmdline")\""                         >> "${TMP_PATH}/menu"
  echo "e \"$(TEXT "Exit")\""                                             >> "${TMP_PATH}/menu"
  # Loop menu
  while true; do
    dialog --backtitle "`backtitle`" --menu "$(TEXT "Choose a option")" 0 0 0 \
      --file "${TMP_PATH}/menu" 2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "`<${TMP_PATH}/resp`" in
      a)
        dialog --backtitle "`backtitle`" --title "$(TEXT "User cmdline")" \
          --inputbox "$(TEXT "Type a name of cmdline")" 0 0 \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && continue
        NAME="`sed 's/://g' <"${TMP_PATH}/resp"`"
        [ -z "${NAME}" ] && continue
        dialog --backtitle "`backtitle`" --title "$(TEXT "User cmdline")" \
          --inputbox "`printf "$(TEXT "Type a value of '%s' cmdline")" "${NAME}"`" 0 0 "${CMDLINE[${NAME}]}" \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && continue
        VALUE="`<"${TMP_PATH}/resp"`"
        CMDLINE[${NAME}]="${VALUE}"
        writeConfigKey "cmdline.${NAME}" "${VALUE}" "${USER_CONFIG_FILE}"
        ;;
      d)
        if [ ${#CMDLINE[@]} -eq 0 ]; then
          dialog --backtitle "`backtitle`" --msgbox "$(TEXT "No user cmdline to remove")" 0 0 
          continue
        fi
        ITEMS=""
        for I in "${!CMDLINE[@]}"; do
          [ -z "${CMDLINE[${I}]}" ] && ITEMS+="${I} \"\" off " || ITEMS+="${I} ${CMDLINE[${I}]} off "
        done
        dialog --backtitle "`backtitle`" \
          --checklist "$(TEXT "Select cmdline to remove")" 0 0 0 ${ITEMS} \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        RESP=`<"${TMP_PATH}/resp"`
        [ -z "${RESP}" ] && continue
        for I in ${RESP}; do
          unset CMDLINE[${I}]
          deleteConfigKey "cmdline.${I}" "${USER_CONFIG_FILE}"
        done
        ;;
      c)
        ETHX=(`ls /sys/class/net/ | grep eth`)  # real network cards list
        for N in `seq 1 8`; do # Currently, only up to 8 are supported.  (<==> boot.sh L96, <==> lkm: MAX_NET_IFACES)
          MACR="`cat /sys/class/net/${ETHX[$(expr ${N} - 1)]}/address | sed 's/://g'`"
          MACF=${CMDLINE["mac${N}"]}
          [ -n "${MACF}" ] && MAC=${MACF} || MAC=${MACR}
          RET=1
          while true; do
            dialog --backtitle "`backtitle`" --title "$(TEXT "User cmdline")" \
              --inputbox "`printf "$(TEXT "Type a custom MAC address of %s")" "mac${N}"`" 0 0 "${MAC}"\
              2>${TMP_PATH}/resp
            RET=$?
            [ ${RET} -ne 0 ] && break 2
            MAC="`<"${TMP_PATH}/resp"`"
            [ -z "${MAC}" ] && MAC="`readConfigKey "original-mac${i}" "${USER_CONFIG_FILE}"`"
            [ -z "${MAC}" ] && MAC="${MACFS[$(expr ${i} - 1)]}"
            MACF="`echo "${MAC}" | sed 's/://g'`"
            [ ${#MACF} -eq 12 ] && break
            dialog --backtitle "`backtitle`" --title "$(TEXT "User cmdline")" --msgbox "$(TEXT "Invalid MAC")" 0 0
          done
          if [ ${RET} -eq 0 ]; then
            CMDLINE["mac${N}"]="${MACF}"
            CMDLINE["netif_num"]=${N}
            writeConfigKey "cmdline.mac${N}"      "${MACF}" "${USER_CONFIG_FILE}"
            writeConfigKey "cmdline.netif_num"    "${N}"    "${USER_CONFIG_FILE}"
            MAC="${MACF:0:2}:${MACF:2:2}:${MACF:4:2}:${MACF:6:2}:${MACF:8:2}:${MACF:10:2}"
            ip link set dev ${ETHX[$(expr ${N} - 1)]} address ${MAC} 2>&1 | dialog --backtitle "`backtitle`" \
              --title "$(TEXT "User cmdline")" --progressbox "$(TEXT "Changing MAC")" 20 70
            /etc/init.d/S41dhcpcd restart 2>&1 | dialog --backtitle "`backtitle`" \
              --title "$(TEXT "User cmdline")" --progressbox "$(TEXT "Renewing IP")" 20 70
            # IP=`ip route 2>/dev/null | sed -n 's/.* via .* dev \(.*\)  src \(.*\)  metric .*/\1: \2 /p' | head -1`
            dialog --backtitle "`backtitle`" --title "$(TEXT "Alert")" \
              --yesno "$(TEXT "Continue to custom MAC?")" 0 0
            [ $? -ne 0 ] && break
          fi
        done
        ;;
      s)
        ITEMS=""
        for KEY in ${!CMDLINE[@]}; do
          ITEMS+="${KEY}: ${CMDLINE[$KEY]}\n"
        done
        dialog --backtitle "`backtitle`" --title "$(TEXT "User cmdline")" \
          --aspect 18 --msgbox "${ITEMS}" 0 0
        ;;
      m)
        ITEMS=""
        while IFS=': ' read KEY VALUE; do
          ITEMS+="${KEY}: ${VALUE}\n"
        done < <(readModelMap "${MODEL}" "builds.${BUILD}.cmdline")
        dialog --backtitle "`backtitle`" --title "$(TEXT "Model/build cmdline")" \
          --aspect 18 --msgbox "${ITEMS}" 0 0
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
  while IFS=': ' read KEY VALUE; do
    [ -n "${KEY}" ] && SYNOINFO["${KEY}"]="${VALUE}"
  done < <(readConfigMap "synoinfo" "${USER_CONFIG_FILE}")

  echo "a \"$(TEXT "Add/edit a synoinfo item")\""   > "${TMP_PATH}/menu"
  echo "d \"$(TEXT "Delete synoinfo item(s)")\""    >> "${TMP_PATH}/menu"
  echo "s \"$(TEXT "Show synoinfo entries")\""      >> "${TMP_PATH}/menu"
  echo "e \"$(TEXT "Exit")\""                       >> "${TMP_PATH}/menu"

  # menu loop
  while true; do
    dialog --backtitle "`backtitle`" --menu "$(TEXT "Choose a option")" 0 0 0 \
      --file "${TMP_PATH}/menu" 2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "`<${TMP_PATH}/resp`" in
      a)
        dialog --backtitle "`backtitle`" --title "$(TEXT "Synoinfo entries")" \
          --inputbox "$(TEXT "Type a name of synoinfo entry")" 0 0 \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && continue
        NAME="`<"${TMP_PATH}/resp"`"
        [ -z "${NAME}" ] && continue
        dialog --backtitle "`backtitle`" --title "$(TEXT "Synoinfo entries")" \
          --inputbox "`printf "$(TEXT "Type a value of '%s' synoinfo entry")" "${NAME}"`" 0 0 "${SYNOINFO[${NAME}]}" \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && continue
        VALUE="`<"${TMP_PATH}/resp"`"
        SYNOINFO[${NAME}]="${VALUE}"
        writeConfigKey "synoinfo.${NAME}" "${VALUE}" "${USER_CONFIG_FILE}"
        DIRTY=1
        ;;
      d)
        if [ ${#SYNOINFO[@]} -eq 0 ]; then
          dialog --backtitle "`backtitle`" --msgbox "$(TEXT "No synoinfo entries to remove")" 0 0 
          continue
        fi
        ITEMS=""
        for I in "${!SYNOINFO[@]}"; do
          [ -z "${SYNOINFO[${I}]}" ] && ITEMS+="${I} \"\" off " || ITEMS+="${I} ${SYNOINFO[${I}]} off "
        done
        dialog --backtitle "`backtitle`" \
          --checklist "$(TEXT "Select synoinfo entry to remove")" 0 0 0 ${ITEMS} \
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
        dialog --backtitle "`backtitle`" --title "$(TEXT "Synoinfo entries")" \
          --aspect 18 --msgbox "${ITEMS}" 0 0
        ;;
      e) return ;;
    esac
  done
}

###############################################################################
# Extract linux and ramdisk files from the DSM .pat
function extractDsmFiles() {
  PAT_URL="`readModelKey "${MODEL}" "builds.${BUILD}.pat.url"`"
  PAT_HASH="`readModelKey "${MODEL}" "builds.${BUILD}.pat.hash"`"
  RAMDISK_HASH="`readModelKey "${MODEL}" "builds.${BUILD}.pat.ramdisk-hash"`"
  ZIMAGE_HASH="`readModelKey "${MODEL}" "builds.${BUILD}.pat.zimage-hash"`"

  SPACELEFT=`df --block-size=1 | awk '/'${LOADER_DEVICE_NAME}'3/{print $4}'`  # Check disk space left

  PAT_FILE="${MODEL}-${BUILD}.pat"
  PAT_PATH="${CACHE_PATH}/dl/${PAT_FILE}"
  EXTRACTOR_PATH="${CACHE_PATH}/extractor"
  EXTRACTOR_BIN="syno_extract_system_patch"
  OLDPAT_URL="https://global.synologydownload.com/download/DSM/release/7.0.1/42218/DSM_DS3622xs%2B_42218.pat"

  if [ -f "${PAT_PATH}" ]; then
    echo "`printf "$(TEXT "%s cached.")" "${PAT_FILE}"`"
  else
    # If we have little disk space, clean cache folder
    if [ ${CLEARCACHE} -eq 1 ]; then
      echo "$(TEXT "Cleaning cache")"
      rm -rf "${CACHE_PATH}/dl"
    fi
    mkdir -p "${CACHE_PATH}/dl"

    speed_a=`ping -c 1 -W 5 global.synologydownload.com | awk '/time=/ {print $7}' | cut -d '=' -f 2`
    speed_b=`ping -c 1 -W 5 global.download.synology.com | awk '/time=/ {print $7}' | cut -d '=' -f 2`
    speed_c=`ping -c 1 -W 5 cndl.synology.cn | awk '/time=/ {print $7}' | cut -d '=' -f 2`
    fastest="`echo -e "global.synologydownload.com ${speed_a:-999}\nglobal.download.synology.com ${speed_b:-999}\ncndl.synology.cn ${speed_c:-999}" | sort -k2n | head -1 | awk '{print $1}'`"
    
    mirror="`echo ${PAT_URL} | sed 's|^http[s]*://\([^/]*\).*|\1|'`"
    if [ "${mirror}" != "${fastest}" ]; then
      echo "`printf "$(TEXT "Based on the current network situation, switch to %s mirror to downloading.")" "${fastest}"`"
      PAT_URL="`echo ${PAT_URL} | sed "s/${mirror}/${fastest}/"`"
      OLDPAT_URL="https://${fastest}/download/DSM/release/7.0.1/42218/DSM_DS3622xs%2B_42218.pat"
    fi
    echo ${PAT_URL} > "${TMP_PATH}/patdownloadurl"
    echo "`printf "$(TEXT "Downloading %s")" "${PAT_FILE}"`"
    # Discover remote file size
    FILESIZE=`curl -k -sLI "${PAT_URL}" | grep -i Content-Length | awk '{print$2}'`
    if [ 0${FILESIZE} -ge 0${SPACELEFT} ]; then
      # No disk space to download, change it to RAMDISK
      PAT_PATH="${TMP_PATH}/${PAT_FILE}"
    fi
    STATUS=`curl -k -w "%{http_code}" -L "${PAT_URL}" -o "${PAT_PATH}" --progress-bar`
    if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
      rm "${PAT_PATH}"
      dialog --backtitle "`backtitle`" --title "$(TEXT "Error downloading")" --aspect 18 \
        --msgbox "$(TEXT "Check internet or cache disk space")" 0 0
      return 1
    fi
  fi

  echo -n "`printf "$(TEXT "Checking hash of %s: ")" "${PAT_FILE}"`"
  if [ "`sha256sum ${PAT_PATH} | awk '{print$1}'`" != "${PAT_HASH}" ]; then
    dialog --backtitle "`backtitle`" --title "$(TEXT "Error")" --aspect 18 \
      --msgbox "$(TEXT "Hash of pat not match, try again!")" 0 0
    rm -f ${PAT_PATH}
    return 1
  fi
  echo "$(TEXT "OK")"

  rm -rf "${UNTAR_PAT_PATH}"
  mkdir "${UNTAR_PAT_PATH}"
  echo -n "`printf "$(TEXT "Disassembling %s: ")" "${PAT_FILE}"`"

  header="$(od -bcN2 ${PAT_PATH} | head -1 | awk '{print $3}')"
  case ${header} in
    105)
      echo "$(TEXT "Uncompressed tar")"
      isencrypted="no"
      ;;
    213)
      echo "$(TEXT "Compressed tar")"
      isencrypted="no"
      ;;
    255)
      echo "$(TEXT "Encrypted")"
      isencrypted="yes"
      ;;
    *)
      dialog --backtitle "`backtitle`" --title "$(TEXT "Error")" --aspect 18 \
        --msgbox "$(TEXT "Could not determine if pat file is encrypted or not, maybe corrupted, try again!")" \
        0 0
      return 1
      ;;
  esac

  SPACELEFT=`df --block-size=1 | awk '/'${LOADER_DEVICE_NAME}'3/{print$4}'`  # Check disk space left

  if [ "${isencrypted}" = "yes" ]; then
    # Check existance of extractor
    if [ -f "${EXTRACTOR_PATH}/${EXTRACTOR_BIN}" ]; then
      echo "$(TEXT "Extractor cached.")"
    else
      # Extractor not exists, get it.
      mkdir -p "${EXTRACTOR_PATH}"
      # Check if old pat already downloaded
      OLDPAT_PATH="${CACHE_PATH}/dl/DS3622xs+-42218.pat"
      if [ ! -f "${OLDPAT_PATH}" ]; then
        echo "$(TEXT "Downloading old pat to extract synology .pat extractor...")"
        # Discover remote file size
        FILESIZE=`curl -k -sLI "${OLDPAT_URL}" | grep -i Content-Length | awk '{print$2}'`
        if [ 0${FILESIZE} -ge 0${SPACELEFT} ]; then
          # No disk space to download, change it to RAMDISK
          OLDPAT_PATH="${TMP_PATH}/DS3622xs+-42218.pat"
        fi
        STATUS=`curl -k -w "%{http_code}" -L "${OLDPAT_URL}" -o "${OLDPAT_PATH}"  --progress-bar`
        if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
          rm "${OLDPAT_PATH}"
          dialog --backtitle "`backtitle`" --title "$(TEXT "Error downloading")" --aspect 18 \
            --msgbox "$(TEXT "Check internet or cache disk space")" 0 0
          return 1
        fi
      fi
      # Extract DSM ramdisk file from PAT
      rm -rf "${RAMDISK_PATH}"
      mkdir -p "${RAMDISK_PATH}"
      tar -xf "${OLDPAT_PATH}" -C "${RAMDISK_PATH}" rd.gz >"${LOG_FILE}" 2>&1
      if [ $? -ne 0 ]; then
        rm -f "${OLDPAT_PATH}"
        rm -rf "${RAMDISK_PATH}"
        dialog --backtitle "`backtitle`" --title "$(TEXT "Error extracting")" --textbox "${LOG_FILE}" 0 0
        return 1
      fi
      [ ${CLEARCACHE} -eq 1 ] && rm -f "${OLDPAT_PATH}"
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
    echo "$(TEXT "Extracting...")"
    LD_LIBRARY_PATH=${EXTRACTOR_PATH} "${EXTRACTOR_PATH}/${EXTRACTOR_BIN}" "${PAT_PATH}" "${UNTAR_PAT_PATH}" || true
  else
    echo "$(TEXT "Extracting...")"
    tar -xf "${PAT_PATH}" -C "${UNTAR_PAT_PATH}" >"${LOG_FILE}" 2>&1
    if [ $? -ne 0 ]; then
      dialog --backtitle "`backtitle`" --title "$(TEXT "Error extracting")" --textbox "${LOG_FILE}" 0 0
    fi
  fi

  echo -n "$(TEXT "Checking hash of zImage: ")"
  HASH="`sha256sum ${UNTAR_PAT_PATH}/zImage | awk '{print$1}'`"
  if [ "${HASH}" != "${ZIMAGE_HASH}" ]; then
    sleep 1
    dialog --backtitle "`backtitle`" --title "$(TEXT "Error")" --aspect 18 \
      --msgbox "$(TEXT "Hash of zImage not match, try again!")" 0 0
    return 1
  fi
  echo "$(TEXT "OK")"
  writeConfigKey "zimage-hash" "${ZIMAGE_HASH}" "${USER_CONFIG_FILE}"

  echo -n "$(TEXT "Checking hash of ramdisk: ")"
  HASH="`sha256sum ${UNTAR_PAT_PATH}/rd.gz | awk '{print$1}'`"
  if [ "${HASH}" != "${RAMDISK_HASH}" ]; then
    sleep 1
    dialog --backtitle "`backtitle`" --title "$(TEXT "Error")" --aspect 18 \
      --msgbox "$(TEXT "Hash of ramdisk not match, try again!")" 0 0
    return 1
  fi
  echo "$(TEXT "OK")"
  writeConfigKey "ramdisk-hash" "${RAMDISK_HASH}" "${USER_CONFIG_FILE}"

  echo -n "$(TEXT "Copying files: ")"
  cp "${UNTAR_PAT_PATH}/grub_cksum.syno" "${BOOTLOADER_PATH}"
  cp "${UNTAR_PAT_PATH}/GRUB_VER"        "${BOOTLOADER_PATH}"
  cp "${UNTAR_PAT_PATH}/grub_cksum.syno" "${SLPART_PATH}"
  cp "${UNTAR_PAT_PATH}/GRUB_VER"        "${SLPART_PATH}"
  cp "${UNTAR_PAT_PATH}/zImage"          "${ORI_ZIMAGE_FILE}"
  cp "${UNTAR_PAT_PATH}/rd.gz"           "${ORI_RDGZ_FILE}"
  rm -rf "${UNTAR_PAT_PATH}"
  echo "$(TEXT "OK")"
}

###############################################################################
# Where the magic happens!
function make() {
  clear
  PLATFORM="`readModelKey "${MODEL}" "platform"`"
  KVER="`readModelKey "${MODEL}" "builds.${BUILD}.kver"`"

  # Check if all addon exists
  while IFS=': ' read ADDON PARAM; do
    [ -z "${ADDON}" ] && continue
    if ! checkAddonExist "${ADDON}" "${PLATFORM}" "${KVER}"; then
      dialog --backtitle "`backtitle`" --title "$(TEXT "Error")" --aspect 18 \
        --msgbox "`printf "$(TEXT "Addon %s not found!")" "${ADDON}"`" 0 0
      return 1
    fi
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")

  if [ ! -f "${ORI_ZIMAGE_FILE}" -o ! -f "${ORI_RDGZ_FILE}" ]; then
    extractDsmFiles
    [ $? -ne 0 ] && return 1
  fi

  /opt/arpl/zimage-patch.sh
  if [ $? -ne 0 ]; then
    dialog --backtitle "`backtitle`" --title "$(TEXT "Error")" --aspect 18 \
      --msgbox "$(TEXT "zImage not patched:\n")`<"${LOG_FILE}"`" 0 0
    return 1
  fi

  /opt/arpl/ramdisk-patch.sh
  if [ $? -ne 0 ]; then
    dialog --backtitle "`backtitle`" --title "$(TEXT "Error")" --aspect 18 \
      --msgbox "$(TEXT "Ramdisk not patched:\n")`<"${LOG_FILE}"`" 0 0
    return 1
  fi

  echo "$(TEXT "Cleaning")"
  rm -rf "${UNTAR_PAT_PATH}"

  echo "$(TEXT "Ready!")"
  sleep 3
  DIRTY=0
  return 0
}

###############################################################################
# Advanced menu
function advancedMenu() {
  NEXT="l"
  while true; do
    rm "${TMP_PATH}/menu"
    if [ -n "${BUILD}" ]; then
      echo "l \"$(TEXT "Switch LKM version:") \Z4${LKM}\Zn\""        >> "${TMP_PATH}/menu"
    fi
    if loaderIsConfigured; then
      echo "q \"$(TEXT "Switch direct boot:") \Z4${DIRECTBOOT}\Zn\"" >> "${TMP_PATH}/menu"
    fi
    echo "u \"$(TEXT "Edit user config file manually")\""            >> "${TMP_PATH}/menu"
    echo "t \"$(TEXT "Try to recovery a DSM installed system")\""    >> "${TMP_PATH}/menu"
    echo "s \"$(TEXT "Show SATA(s) # ports and drives")\""           >> "${TMP_PATH}/menu"
    if [ -n "${MODEL}" -a -n "${BUILD}" ]; then
      echo "k \"$(TEXT "show pat download link")\""                  >> "${TMP_PATH}/menu"
    fi
    echo "a \"$(TEXT "Allow downgrade installation")\""              >> "${TMP_PATH}/menu"
    echo "f \"$(TEXT "Format disk(s) # Without loader disk")\""      >> "${TMP_PATH}/menu"
    echo "x \"$(TEXT "Reset syno system password")\""                >> "${TMP_PATH}/menu"
    echo "p \"$(TEXT "Persistence of arpl modifications")\""         >> "${TMP_PATH}/menu"
    if [ -n "${MODEL}" -a "true" = "`readModelKey "${MODEL}" "dt"`" ]; then
      echo "d \"$(TEXT "Custom dts file # Need rebuild")\""          >> "${TMP_PATH}/menu"
    fi
    if [ -n "${DEBUG}" ]; then
      echo "b \"$(TEXT "Backup bootloader disk # test")\""             >> "${TMP_PATH}/menu"
      echo "r \"$(TEXT "Restore bootloader disk # test")\""            >> "${TMP_PATH}/menu"
    fi
    echo "o \"$(TEXT "Development tools")\""                         >> "${TMP_PATH}/menu"
    echo "e \"$(TEXT "Exit")\""                                      >> "${TMP_PATH}/menu"

    dialog --default-item ${NEXT} --backtitle "`backtitle`" --title "$(TEXT "Advanced")" \
      --colors --menu "$(TEXT "Choose the option")" 0 0 0 --file "${TMP_PATH}/menu" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && break
    case `<"${TMP_PATH}/resp"` in
      l) LKM=$([ "${LKM}" = "dev" ] && echo 'prod' || ([ "${LKM}" = "test" ] && echo 'dev' || echo 'test'))
        writeConfigKey "lkm" "${LKM}" "${USER_CONFIG_FILE}"
        DIRTY=1
        NEXT="l"
        ;;
      q) [ "${DIRECTBOOT}" = "false" ] && DIRECTBOOT='true' || DIRECTBOOT='false'
        writeConfigKey "directboot" "${DIRECTBOOT}" "${USER_CONFIG_FILE}"
        NEXT="e"
        ;;
      u) editUserConfig; NEXT="e" ;;
      t) tryRecoveryDSM ;;
      s) MSG=""
        NUMPORTS=0
        ATTACHTNUM=0
        DiskIdxMap=""
        for PCI in `lspci -d ::106 | awk '{print$1}'`; do
          NAME=`lspci -s "${PCI}" | sed "s/\ .*://"`
          MSG+="\Zb${NAME}\Zn\nPorts: "
          unset HOSTPORTS
          declare -A HOSTPORTS
          ATTACHTIDX=0
          while read LINE; do
            ATAPORT="`echo ${LINE} | grep -o 'ata[0-9]*'`"
            PORT=`echo ${ATAPORT} | sed 's/ata//'`
            HOSTPORTS[${PORT}]=`echo ${LINE} | grep -o 'host[0-9]*$'`
          done < <(ls -l /sys/class/scsi_host | fgrep "${PCI}")
          while read PORT; do
            ls -l /sys/block | fgrep -q "${PCI}/ata${PORT}" && ATTACH=1 || ATTACH=0
            PCMD=`cat /sys/class/scsi_host/${HOSTPORTS[${PORT}]}/ahci_port_cmd`
            [ "${PCMD}" = "0" ] && DUMMY=1 || DUMMY=0
            [ ${ATTACH} -eq 1 ] && MSG+="\Z2\Zb" && ATTACHTIDX=$((${ATTACHTIDX}+1))
            [ ${DUMMY} -eq 1 ] && MSG+="\Z1"
            MSG+="${PORT}\Zn "
            NUMPORTS=$((${NUMPORTS}+1))
          done < <(echo ${!HOSTPORTS[@]} | tr ' ' '\n' | sort -n)
          MSG+="\n"
          [ ${ATTACHTIDX} -gt 0 ] && DiskIdxMap+=`printf '%02x' ${ATTACHTNUM}` || DiskIdxMap+="ff"
          ATTACHTNUM=$((${ATTACHTNUM}+${ATTACHTIDX}))
        done
        MSG+="`printf "$(TEXT "\nTotal of ports: %s\n")" "${NUMPORTS}"`"
        MSG+="$(TEXT "\nPorts with color \Z1red\Zn as DUMMY, color \Z2\Zbgreen\Zn has drive connected.")"
        MSG+="$(TEXT "\nRecommended value:")"
        MSG+="$(TEXT "\nDiskIdxMap:") ${DiskIdxMap}"
        dialog --backtitle "`backtitle`" --colors --aspect 18 \
          --msgbox "${MSG}" 0 0
        ;;
      k) 
        # output pat download link
        if [ ! -f "${TMP_PATH}/patdownloadurl" ]; then
          echo "`readModelKey "${MODEL}" "builds.${BUILD}.pat.url"`" > "${TMP_PATH}/patdownloadurl"
        fi
        dialog --backtitle "`backtitle`" --title "$(TEXT "*.pat download link")" --aspect 18 \
          --editbox "${TMP_PATH}/patdownloadurl" 10 100
        ;;
      a)
        MSG=""
        MSG+="$(TEXT "This feature will allow you to downgrade the installation by removing the VERSION file from the first partition of all disks.\n")"
        MSG+="$(TEXT "Therefore, please insert all disks before continuing.\n")"
        MSG+="$(TEXT "Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?")"
        dialog --backtitle "`backtitle`" --title "$(TEXT "Allow downgrade installation")" \
            --yesno "${MSG}" 0 0
        [ $? -ne 0 ] && return
        (
          mkdir -p /tmp/sdX1
          for I in `ls /dev/sd*1 2>/dev/null | grep -v ${LOADER_DISK}1`; do
            mount ${I} /tmp/sdX1
            [ -f "/tmp/sdX1/etc/VERSION" ] && rm -f "/tmp/sdX1/etc/VERSION"
            [ -f "/tmp/sdX1/etc.defaults/VERSION" ] && rm -f "/tmp/sdX1/etc.defaults/VERSION"
            sync
            umount ${I}
          done
          rm -rf /tmp/sdX1
        ) | dialog --backtitle "`backtitle`" --title "$(TEXT "Allow downgrade installation")" \
            --progressbox "$(TEXT "Removing ...")" 20 70
        MSG="$(TEXT "Remove VERSION file for all disks completed.")"
        dialog --backtitle "`backtitle`" --colors --aspect 18 \
          --msgbox "${MSG}" 0 0
        ;;
      f) ITEMS=""
        while read POSITION NAME; do
          [ -z "${POSITION}" -o -z "${NAME}" ] && continue
          echo "${POSITION}" | grep -q "${LOADER_DEVICE_NAME}" && continue
          ITEMS+="`printf "%s %s off " "${POSITION}" "${NAME}"`"
        done < <(ls -l /dev/disk/by-id/ | sed 's|../..|/dev|g' | grep -E "/dev/sd*" | awk -F' ' '{print $10" "$8}' | sort -uk 1,1)
        dialog --backtitle "`backtitle`" --title "$(TEXT "Format disk")" \
          --checklist "$(TEXT "Advanced")" 0 0 0 ${ITEMS} 2>${TMP_PATH}/resp
        [ $? -ne 0 ] && return
        RESP=`<"${TMP_PATH}/resp"`
        [ -z "${RESP}" ] && return
        dialog --backtitle "`backtitle`" --title "$(TEXT "Format disk")" \
            --yesno "$(TEXT "Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?")" 0 0
        [ $? -ne 0 ] && return
        if [ `ls /dev/md* | wc -l` -gt 0 ]; then
          dialog --backtitle "`backtitle`" --title "$(TEXT "Format disk")" \
              --yesno "$(TEXT "Warning:\nThe current hds is in raid, do you still want to format them?")" 0 0
          [ $? -ne 0 ] && return
          for I in `ls /dev/md*`; do
            mdadm -S ${I}
          done
        fi
        (
          for I in ${RESP}; do
            mkfs.ext4 -F -O ^metadata_csum ${I}
          done
        ) | dialog --backtitle "`backtitle`" --title "$(TEXT "Format disk")" \
            --progressbox "$(TEXT "Formatting ...")" 20 70
        dialog --backtitle "`backtitle`" --colors --aspect 18 \
          --msgbox "$(TEXT "Formatting is complete.")" 0 0
        ;;
      x)
        dialog --backtitle "`backtitle`" --colors --aspect 18 \
          --msgbox "$(TEXT "You came early, this function has not been implemented yet, hahaha!")" 0 0
        ;;
      p) 
        dialog --backtitle "`backtitle`" --title "$(TEXT "Persistence of arpl modifications")" \
            --yesno "$(TEXT "Warning:\nDo not terminate midway, otherwise it may cause damage to the arpl. Do you want to continue?")" 0 0
        [ $? -ne 0 ] && return
        dialog --backtitle "`backtitle`" --title "$(TEXT "Persistence of arpl modifications")" \
            --infobox "$(TEXT "Persisting ...")" 0 0 
        RDXZ_PATH=/tmp/rdxz_tmp
        mkdir -p "${RDXZ_PATH}"
        (cd "${RDXZ_PATH}"; xz -dc < "/mnt/p3/initrd-arpl" | cpio -idm) >/dev/null 2>&1 || true
        rm -rf "${RDXZ_PATH}/opt/arpl"
        cp -rf "/opt" "${RDXZ_PATH}/"
        (cd "${RDXZ_PATH}"; find . 2>/dev/null | cpio -o -H newc -R root:root | xz --check=crc32 > "/mnt/p3/initrd-arpl") || true
        rm -rf "${RDXZ_PATH}"
        dialog --backtitle "`backtitle`" --colors --aspect 18 \
          --msgbox ""$(TEXT "Persisting is complete.")"" 0 0
        ;;
      d)
        if ! tty | grep -q "/dev/pts"; then
          dialog --backtitle "`backtitle`" --colors --aspect 18 \
            --msgbox "$(TEXT "This feature is only available when accessed via web/ssh.")" 0 0
          return
        fi 
        dialog --backtitle "`backtitle`" --colors --aspect 18 \
          --msgbox "$(TEXT "Currently, only dts format files are supported. Please prepare and click to confirm uploading.\n(saved in /mnt/p3/users/)")" 0 0
        TMP_PATH=/tmp/users
        rm -rf ${TMP_PATH}
        mkdir -p ${TMP_PATH}
        pushd ${TMP_PATH}
        rz -be
        for F in `ls -A`; do
          USER_FILE=${TMP_PATH}/${F}
          dtc -q -I dts -O dtb ${F} > test.dtb
          RET=$?
          break 
        done
        popd
        if [ ${RET} -ne 0 -o -z "${USER_FILE}" ]; then
          dialog --backtitle "`backtitle`" --title "$(TEXT "Custom dts file")" --aspect 18 \
            --msgbox "$(TEXT "Not a valid dts file, please try again!")" 0 0
        else
          mkdir -p ${USER_UP_PATH}
          cp -f ${USER_FILE} ${USER_UP_PATH}/${MODEL}.dts
          dialog --backtitle "`backtitle`" --title "$(TEXT "Custom dts file")" --aspect 18 \
            --msgbox "$(TEXT "A valid dts file, Automatically import at compile time.")" 0 0
        fi
        ;;
      b)
        if ! tty | grep -q "/dev/pts"; then
          dialog --backtitle "`backtitle`" --colors --aspect 18 \
            --msgbox "$(TEXT "This feature is only available when accessed via web/ssh.")" 0 0
          return
        fi 
        dialog --backtitle "`backtitle`" --title "$(TEXT "Backup bootloader disk")" \
            --yesno "$(TEXT "Warning:\nDo not terminate midway, otherwise it may cause damage to the arpl. Do you want to continue?")" 0 0
        [ $? -ne 0 ] && return
        dialog --backtitle "`backtitle`" --title "$(TEXT "Backup bootloader disk")" \
          --infobox "$(TEXT "Backuping...")" 0 0
        rm -f /var/www/data/backup.img.gz  # thttpd root path
        dd if="${LOADER_DISK}" bs=1M conv=fsync | gzip > /var/www/data/backup.img.gz
        if [ $? -ne 0]; then
          dialog --backtitle "`backtitle`" --title "$(TEXT "Error")" --aspect 18 \
            --msgbox "$(TEXT "Failed to generate backup. There may be insufficient memory. Please clear the cache and try again!")" 0 0
          return
        fi
        if [ -z "${SSH_TTY}" ]; then  # web
          IP_HEAD="`ip route show 2>/dev/null | sed -n 's/.* via .* src \(.*\)  metric .*/\1/p' | head -1`"
          echo "http://${IP_HEAD}/backup.img.gz"  > ${TMP_PATH}/resp
          echo "            ↑                  " >> ${TMP_PATH}/resp
          echo "$(TEXT "Click on the address above to download.")" >> ${TMP_PATH}/resp
          echo "$(TEXT "Please confirm the completion of the download before closing this window.")" >> ${TMP_PATH}/resp
          dialog --backtitle "`backtitle`" --title "$(TEXT "backup.img.gz download link")" --aspect 18 \
           --editbox "${TMP_PATH}/resp" 10 100
        else                          # ssh
          sz -be /var/www/data/backup.img.gz
        fi
        dialog --backtitle "`backtitle`" --colors --aspect 18 \
            --msgbox "$(TEXT "backup is complete.")" 0 0
        rm -f /var/www/data/backup.img.gz
        ;;
      r)
        if ! tty | grep -q "/dev/pts"; then
          dialog --backtitle "`backtitle`" --colors --aspect 18 \
            --msgbox "$(TEXT "This feature is only available when accessed via web/ssh.")" 0 0
          return
        fi 
        dialog --backtitle "`backtitle`" --title "$(TEXT "Restore bootloader disk")" --aspect 18 \
            --yesno "$(TEXT "Please upload the backup file.\nCurrently, zip(github) and img.gz(backup) compressed file formats are supported.")" 0 0
        [ $? -ne 0 ] && return
        IFTOOL=""
        TMP_PATH=/tmp/users
        rm -rf ${TMP_PATH}
        mkdir -p ${TMP_PATH}
        pushd ${TMP_PATH}
        rz -be
        for F in `ls -A`; do
          USER_FILE="${F}"
          [ "${F##*.}" = "zip" -a `unzip -l "${TMP_PATH}/${USER_FILE}" | grep -c "\.img$"` -eq 1 ] && IFTOOL="zip"
          [ "${F##*.}" = "gz" -a "${F#*.}" = "img.gz" ] && IFTOOL="gzip"
          break 
        done
        popd
        if [ -z "${IFTOOL}" -o -z "${TMP_PATH}/${USER_FILE}" ]; then
          dialog --backtitle "`backtitle`" --title "$(TEXT "Restore bootloader disk")" --aspect 18 \
            --msgbox "`printf "$(TEXT "Not a valid .zip/.img.gz file, please try again!")" "${USER_FILE}"`" 0 0
        else
          dialog --backtitle "`backtitle`" --title "$(TEXT "Restore bootloader disk")" \
              --yesno "$(TEXT "Warning:\nDo not terminate midway, otherwise it may cause damage to the arpl. Do you want to continue?")" 0 0
          [ $? -ne 0 ] && ( rm -f ${LOADER_DISK}; return )
          dialog --backtitle "`backtitle`" --title "$(TEXT "Restore bootloader disk")" --aspect 18 \
            --infobox "$(TEXT "Writing...")" 0 0
          umount /mnt/p1 /mnt/p2 /mnt/p3
          if [ "${IFTOOL}" = "zip" ]; then
            unzip -p "${TMP_PATH}/${USER_FILE}" | dd of="${LOADER_DISK}" bs=1M conv=fsync
          elif [ "${IFTOOL}" = "gzip" ]; then
            gzip -dc "${TMP_PATH}/${USER_FILE}" | dd of="${LOADER_DISK}" bs=1M conv=fsync
          fi
          dialog --backtitle "`backtitle`" --title "$(TEXT "Restore bootloader disk")" --aspect 18 \
            --yesno "`printf "$(TEXT "Restore bootloader disk with success to %s!\nReboot?")" "${USER_FILE}"`" 0 0
          [ $? -ne 0 ] && continue
          reboot
          exit
        fi
        ;;
      o)
        dialog --backtitle "`backtitle`" --title "$(TEXT "Development tools")" --aspect 18 \
            --yesno "$(TEXT "This option only installs opkg package management, allowing you to install more tools for use and debugging. Do you want to continue?")" 0 0
        [ $? -ne 0 ] && return
        (
          wget -O - http://bin.entware.net/x64-k3.2/installer/generic.sh | /bin/sh
          sed -i 's|:/opt/arpl|:/opt/bin:/opt/arpl|' ~/.bashrc
          source ~/.bashrc
          opkg update
          #opkg install python3 python3-pip
        ) | dialog --backtitle "`backtitle`" --title "$(TEXT "Development tools")" \
            --progressbox "$(TEXT "opkg installing ...")" 20 70
        dialog --backtitle "`backtitle`" --colors --aspect 18 \
          --msgbox "$(TEXT "opkg install is complete. Please reconnect to SSH/web, or execute 'source ~/.bashrc'")" 0 0
        ;;
      e) break ;;
    esac
  done
}

###############################################################################
# Try to recovery a DSM already installed
function tryRecoveryDSM() {
  dialog --backtitle "`backtitle`" --title "$(TEXT "Try recovery DSM")" --aspect 18 \
    --infobox "$(TEXT "Trying to recovery a DSM installed system")" 0 0
  if findAndMountDSMRoot; then
    MODEL=""
    BUILD=""
    if [ -f "${DSMROOT_PATH}/.syno/patch/VERSION" ]; then
      eval `cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep unique`
      eval `cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep base`
      if [ -n "${unique}" ] ; then
        while read F; do
          M="`basename ${F}`"
          M="${M::-4}"
          UNIQUE=`readModelKey "${M}" "unique"`
          [ "${unique}" = "${UNIQUE}" ] || continue
          # Found
          modelMenu "${M}"
        done < <(find "${MODEL_CONFIG_PATH}" -maxdepth 1 -name \*.yml | sort)
        if [ -n "${MODEL}" ]; then
          buildMenu ${base}
          if [ -n "${BUILD}" ]; then
            cp "${DSMROOT_PATH}/.syno/patch/zImage" "${SLPART_PATH}"
            cp "${DSMROOT_PATH}/.syno/patch/rd.gz" "${SLPART_PATH}"
            MSG="`printf "$(TEXT "Found a installation:\nModel: %s\nBuildnumber: %s")" "${MODEL}" "${BUILD}"`"
            SN=`_get_conf_kv SN "${DSMROOT_PATH}/etc/synoinfo.conf"`
            if [ -n "${SN}" ]; then
              writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
              MSG+="`printf "$(TEXT "\nSerial: %s")" "${SN}"`"
            fi
            dialog --backtitle "`backtitle`" --title "$(TEXT "Try recovery DSM")" \
              --aspect 18 --msgbox "${MSG}" 0 0
          fi
        fi
      fi
    fi
  else
    dialog --backtitle "`backtitle`" --title "$(TEXT "Try recovery DSM")" --aspect 18 \
      --msgbox "$(TEXT "Unfortunately I couldn't mount the DSM partition!")" 0 0
  fi
}

###############################################################################
# Permits user edit the user config
function editUserConfig() {
  while true; do
    dialog --backtitle "`backtitle`" --title "$(TEXT "Edit with caution")" --aspect 18 \
      --editbox "${USER_CONFIG_FILE}" 0 0 2>"${TMP_PATH}/userconfig"
    [ $? -ne 0 ] && return
    mv "${TMP_PATH}/userconfig" "${USER_CONFIG_FILE}"
    ERRORS=`yq eval "${USER_CONFIG_FILE}" 2>&1`
    [ $? -eq 0 ] && break
    dialog --backtitle "`backtitle`" --title "$(TEXT "Invalid YAML format")" --msgbox "${ERRORS}" 0 0
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
# Calls boot.sh to boot into DSM kernel/ramdisk
function boot() {
  [ ${DIRTY} -eq 1 ] && dialog --backtitle "`backtitle`" --title "$(TEXT "Alert")" \
    --yesno "$(TEXT "Config changed, would you like to rebuild the loader?")" 0 0
  if [ $? -eq 0 ]; then
    make || return
  fi
  boot.sh
}

###############################################################################
# Shows language to user choose one
function languageMenu() {
  ITEMS="`ls /usr/share/locale`"
  dialog --backtitle "`backtitle`" --default-item "${LAYOUT}" --no-items \
    --menu "$(TEXT "Choose a language")" 0 0 0 ${ITEMS} 2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  resp=`cat /tmp/resp 2>/dev/null`
  [ -z "${resp}" ] && return
  LANGUAGE=${resp}
  echo "${LANGUAGE}.UTF-8" > ${BOOTLOADER_PATH}/.locale
  export LANG="${LANGUAGE}.UTF-8"
}

###############################################################################
# Shows available keymaps to user choose one
function keymapMenu() {
  dialog --backtitle "`backtitle`" --default-item "${LAYOUT}" --no-items \
    --menu "$(TEXT "Choose a layout")" 0 0 0 "azerty" "bepo" "carpalx" "colemak" \
    "dvorak" "fgGIod" "neo" "olpc" "qwerty" "qwertz" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  LAYOUT="`<${TMP_PATH}/resp`"
  OPTIONS=""
  while read KM; do
    OPTIONS+="${KM::-7} "
  done < <(cd /usr/share/keymaps/i386/${LAYOUT}; ls *.map.gz)
  dialog --backtitle "`backtitle`" --no-items --default-item "${KEYMAP}" \
    --menu "$(TEXT "Choice a keymap")" 0 0 0 ${OPTIONS} \
    2>/tmp/resp
  [ $? -ne 0 ] && return
  resp=`cat /tmp/resp 2>/dev/null`
  [ -z "${resp}" ] && return
  KEYMAP=${resp}
  writeConfigKey "layout" "${LAYOUT}" "${USER_CONFIG_FILE}"
  writeConfigKey "keymap" "${KEYMAP}" "${USER_CONFIG_FILE}"
  loadkeys /usr/share/keymaps/i386/${LAYOUT}/${KEYMAP}.map.gz
}

###############################################################################
function updateMenu() {
  PLATFORM="`readModelKey "${MODEL}" "platform"`"
  KVER="`readModelKey "${MODEL}" "builds.${BUILD}.kver"`"
  PROXY="`readConfigKey "proxy" "${USER_CONFIG_FILE}"`"; [ -n "${PROXY}" ] && [[ "${PROXY: -1}" != "/" ]] && PROXY="${PROXY}/"
  while true; do
    dialog --backtitle "`backtitle`" --menu "$(TEXT "Choose a option")" 0 0 0 \
      a "$(TEXT "Update arpl")" \
      d "$(TEXT "Update addons")" \
      m "$(TEXT "Update modules")" \
      l "$(TEXT "Update LKMs")" \
      p "$(TEXT "Set proxy server")" \
      e "$(TEXT "Exit")" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "`<${TMP_PATH}/resp`" in
      a)
        dialog --backtitle "`backtitle`" --title "$(TEXT "Update arpl")" --aspect 18 \
          --infobox "$(TEXT "Checking last version")" 0 0
        # TAG="`curl -skL "${PROXY}https://api.github.com/repos/wjz304/arpl-i18n/releases/latest" | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`"
        # In the absence of authentication, the default API access count for GitHub is 60 per hour, so removing the use of api.github.com
        LATESTURL="`curl -skL -w %{url_effective} -o /dev/null "${PROXY}https://github.com/wjz304/arpl-i18n/releases/latest"`"
        TAG="${LATESTURL##*/}"
        [ "${TAG:0:1}" = "v" ] && TAG="${TAG:1}"
        if [ -z "${TAG}" ]; then
          dialog --backtitle "`backtitle`" --title "$(TEXT "Update arpl")" --aspect 18 \
            --msgbox "$(TEXT "Error checking new version")" 0 0
          continue
        fi
        ACTUALVERSION="${ARPL_VERSION}"
        if [ "${ACTUALVERSION}" = "${TAG}" ]; then
          dialog --backtitle "`backtitle`" --title "$(TEXT "Update arpl")" --aspect 18 \
            --yesno "`printf "$(TEXT "No new version. Actual version is %s\nForce update?")" "${ACTUALVERSION}"`" 0 0
          [ $? -ne 0 ] && continue
        fi
        dialog --backtitle "`backtitle`" --title "$(TEXT "Update arpl")" --aspect 18 \
          --infobox "`printf "$(TEXT "Downloading last version %s")" "${TAG}"`" 0 0
        # Download update file
        STATUS=`curl -kL -w "%{http_code}" "${PROXY}https://github.com/wjz304/arpl-i18n/releases/download/${TAG}/update.zip" -o "/tmp/update.zip"`
        if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
          dialog --backtitle "`backtitle`" --title "$(TEXT "Update arpl")" --aspect 18 \
            --msgbox "$(TEXT "Error downloading update file")" 0 0
          continue
        fi
        unzip -oq /tmp/update.zip -d /tmp
        if [ $? -ne 0 ]; then
          dialog --backtitle "`backtitle`" --title "$(TEXT "Update arpl")" --aspect 18 \
            --msgbox "$(TEXT "Error extracting update file")" 0 0
          continue
        fi
        # Check checksums
        (cd /tmp && sha256sum --status -c sha256sum)
        if [ $? -ne 0 ]; then
          dialog --backtitle "`backtitle`" --title "$(TEXT "Update arpl")" --aspect 18 \
            --msgbox "$(TEXT "Checksum do not match!")" 0 0
          continue
        fi
        # Check conditions
        if [ -f "/tmp/update-check.sh" ]; then
          chmod +x /tmp/update-check.sh
          /tmp/update-check.sh
          if [ $? -ne 0 ]; then
            dialog --backtitle "`backtitle`" --title "$(TEXT "Update arpl")" --aspect 18 \
              --msgbox "$(TEXT "The current version does not support upgrading to the latest update.zip. Please remake the bootloader disk!")" 0 0
            continue
          fi
        fi
        dialog --backtitle "`backtitle`" --title "$(TEXT "Update arpl")" --aspect 18 \
          --infobox "$(TEXT "Installing new files")" 0 0
        # Process update-list.yml
        while read F; do
          [ -f "${F}" ] && rm -f "${F}"
          [ -d "${F}" ] && rm -Rf "${F}"
        done < <(readConfigArray "remove" "/tmp/update-list.yml")
        while IFS=': ' read KEY VALUE; do
          if [ "${KEY: -1}" = "/" ]; then
            rm -Rf "${VALUE}"
            mkdir -p "${VALUE}"
            tar -zxf "/tmp/`basename "${KEY}"`.tgz" -C "${VALUE}"
          else
            mkdir -p "`dirname "${VALUE}"`"
            mv "/tmp/`basename "${KEY}"`" "${VALUE}"
          fi
        done < <(readConfigMap "replace" "/tmp/update-list.yml")
        dialog --backtitle "`backtitle`" --title "$(TEXT "Update arpl")" --aspect 18 \
          --yesno "`printf "$(TEXT "Arpl updated with success to %s!\nReboot?")" "${TAG}"`" 0 0
        [ $? -ne 0 ] && continue
        arpl-reboot.sh config
        exit
        ;;

      d)
        dialog --backtitle "`backtitle`" --title "$(TEXT "Update addons")" --aspect 18 \
          --infobox "$(TEXT "Checking last version")" 0 0
        # TAG=`curl -skL "${PROXY}https://api.github.com/repos/wjz304/arpl-addons/releases/latest" | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`
        # In the absence of authentication, the default API access count for GitHub is 60 per hour, so removing the use of api.github.com
        LATESTURL="`curl -skL -w %{url_effective} -o /dev/null "${PROXY}https://github.com/wjz304/arpl-addons/releases/latest"`"
        TAG="${LATESTURL##*/}"
        [ "${TAG:0:1}" = "v" ] && TAG="${TAG:1}"
        if [ -z "${TAG}" ]; then
          dialog --backtitle "`backtitle`" --title "$(TEXT "Update addons")" --aspect 18 \
            --msgbox "$(TEXT "Error checking new version")" 0 0
          continue
        fi
        ACTUALVERSION="`cat "/mnt/p3/addons/VERSION" 2>/dev/null`"
        if [ "${ACTUALVERSION}" = "${TAG}" ]; then
          dialog --backtitle "`backtitle`" --title "$(TEXT "Update addons")" --aspect 18 \
            --yesno "`printf "$(TEXT "No new version. Actual version is %s\nForce update?")" "${ACTUALVERSION}"`" 0 0
          [ $? -ne 0 ] && continue
        fi
        dialog --backtitle "`backtitle`" --title "$(TEXT "Update addons")" --aspect 18 \
          --infobox "$(TEXT "Downloading last version")" 0 0
        STATUS=`curl -kL -w "%{http_code}" "${PROXY}https://github.com/wjz304/arpl-addons/releases/download/${TAG}/addons.zip" -o "/tmp/addons.zip"`
        if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
          dialog --backtitle "`backtitle`" --title "$(TEXT "Update addons")" --aspect 18 \
            --msgbox "$(TEXT "Error downloading new version")" 0 0
          continue
        fi
        dialog --backtitle "`backtitle`" --title "$(TEXT "Update addons")" --aspect 18 \
          --infobox "$(TEXT "Extracting last version")" 0 0
        rm -rf /tmp/addons
        mkdir -p /tmp/addons
        unzip /tmp/addons.zip -d /tmp/addons >/dev/null 2>&1
        dialog --backtitle "`backtitle`" --title "$(TEXT "Update addons")" --aspect 18 \
          --infobox "$(TEXT "Installing new addons")" 0 0
        rm -Rf "${ADDONS_PATH}/"*
        [ -f /tmp/addons/VERSION ] && cp -f /tmp/addons/VERSION ${ADDONS_PATH}/
        for PKG in `ls /tmp/addons/*.addon`; do
          ADDON=`basename ${PKG} | sed 's|.addon||'`
          rm -rf "${ADDONS_PATH}/${ADDON}"
          mkdir -p "${ADDONS_PATH}/${ADDON}"
          tar -xaf "${PKG}" -C "${ADDONS_PATH}/${ADDON}" >/dev/null 2>&1
        done
        DIRTY=1
        dialog --backtitle "`backtitle`" --title "$(TEXT "Update addons")" --aspect 18 \
          --msgbox "$(TEXT "Addons updated with success!")" 0 0
        ;;

      m)
        dialog --backtitle "`backtitle`" --title "$(TEXT "Update modules")" --aspect 18 \
          --infobox "$(TEXT "Checking last version")" 0 0
        # TAG=`curl -skL "${PROXY}https://api.github.com/repos/wjz304/arpl-modules/releases/latest" | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`
        # In the absence of authentication, the default API access count for GitHub is 60 per hour, so removing the use of api.github.com
        LATESTURL="`curl -skL -w %{url_effective} -o /dev/null "${PROXY}https://github.com/wjz304/arpl-modules/releases/latest"`"
        TAG="${LATESTURL##*/}"
        [ "${TAG:0:1}" = "v" ] && TAG="${TAG:1}"
        if [ -z "${TAG}" ]; then
          dialog --backtitle "`backtitle`" --title "$(TEXT "Update modules")" --aspect 18 \
            --msgbox "$(TEXT "Error checking new version")" 0 0
          continue
        fi
        ACTUALVERSION="`cat "/mnt/p3/modules/VERSION" 2>/dev/null`"
        if [ "${ACTUALVERSION}" = "${TAG}" ]; then
          dialog --backtitle "`backtitle`" --title "$(TEXT "Update modules")" --aspect 18 \
            --yesno "`printf "$(TEXT "No new version. Actual version is %s\nForce update?")" "${ACTUALVERSION}"`" 0 0
          [ $? -ne 0 ] && continue
        fi
        dialog --backtitle "`backtitle`" --title "$(TEXT "Update modules")" --aspect 18 \
          --infobox "$(TEXT "Downloading last version")" 0 0
        STATUS=`curl -kL -w "%{http_code}" "${PROXY}https://github.com/wjz304/arpl-modules/releases/download/${TAG}/modules.zip" -o "/tmp/modules.zip"`
        if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
          dialog --backtitle "`backtitle`" --title "$(TEXT "Update modules")" --aspect 18 \
            --msgbox "$(TEXT "Error downloading last version")" 0 0
          continue
        fi
        rm "${MODULES_PATH}/"*
        unzip /tmp/modules.zip -d "${MODULES_PATH}" >/dev/null 2>&1

        # Rebuild modules if model/buildnumber is selected
        if [ -n "${PLATFORM}" -a -n "${KVER}" ]; then
          writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
          while read ID DESC; do
            writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
          done < <(getAllModules "${PLATFORM}" "${KVER}")
        fi
        DIRTY=1
        dialog --backtitle "`backtitle`" --title "$(TEXT "Update modules")" --aspect 18 \
          --msgbox "$(TEXT "Modules updated with success!")" 0 0
        ;;

      l)
        dialog --backtitle "`backtitle`" --title "$(TEXT "Update LKMs")" --aspect 18 \
          --infobox "$(TEXT "Checking last version")" 0 0
        # TAG=`curl -skL "${PROXY}https://api.github.com/repos/wjz304/redpill-lkm/releases/latest" | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`
        # In the absence of authentication, the default API access count for GitHub is 60 per hour, so removing the use of api.github.com
        LATESTURL="`curl -skL -w %{url_effective} -o /dev/null "${PROXY}https://github.com/wjz304/redpill-lkm/releases/latest"`"
        TAG="${LATESTURL##*/}"
        [ "${TAG:0:1}" = "v" ] && TAG="${TAG:1}"
        if [ -z "${TAG}" ]; then
          dialog --backtitle "`backtitle`" --title "$(TEXT "Update LKMs")" --aspect 18 \
            --msgbox "$(TEXT "Error checking new version")" 0 0
          continue
        fi
        ACTUALVERSION="`cat "/mnt/p3/lkms/VERSION" 2>/dev/null`"
        if [ "${ACTUALVERSION}" = "${TAG}" ]; then
          dialog --backtitle "`backtitle`" --title "$(TEXT "Update LKMs")" --aspect 18 \
            --yesno "`printf "$(TEXT "No new version. Actual version is %s\nForce update?")" "${ACTUALVERSION}"`" 0 0
          [ $? -ne 0 ] && continue
        fi
        dialog --backtitle "`backtitle`" --title "$(TEXT "Update LKMs")" --aspect 18 \
          --infobox "$(TEXT "Downloading last version")" 0 0
        STATUS=`curl -kL -w "%{http_code}" "${PROXY}https://github.com/wjz304/redpill-lkm/releases/download/${TAG}/rp-lkms.zip" -o "/tmp/rp-lkms.zip"`
        if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
          dialog --backtitle "`backtitle`" --title "$(TEXT "Update LKMs")" --aspect 18 \
            --msgbox "$(TEXT "Error downloading last version")" 0 0
          continue
        fi
        dialog --backtitle "`backtitle`" --title "$(TEXT "Update LKMs")" --aspect 18 \
          --infobox "$(TEXT "Extracting last version")" 0 0
        rm -rf "${LKM_PATH}/"*
        unzip /tmp/rp-lkms.zip -d "${LKM_PATH}" >/dev/null 2>&1
        DIRTY=1
        dialog --backtitle "`backtitle`" --title "$(TEXT "Update LKMs")" --aspect 18 \
          --msgbox "$(TEXT "LKMs updated with success!")" 0 0
        ;;

      p)
        RET=1
        while true; do
          dialog --backtitle "`backtitle`" --title "$(TEXT "Set Proxy Server")" \
            --inputbox "$(TEXT "Please enter a proxy server url")" 0 0 "${PROXY}" \
            2>${TMP_PATH}/resp
          RET=$?
          [ ${RET} -ne 0 ] && break
          PROXY=`cat ${TMP_PATH}/resp`
          if [ -z "${PROXYSERVER}" ]; then
            break
          elif [[ "${PROXYSERVER}" =~ "^(https?|ftp)://[^\s/$.?#].[^\s]*$" ]]; then
            break
          else
            dialog --backtitle "`backtitle`" --title "$(TEXT "Alert")" \
              --yesno "$(TEXT "Invalid proxy server url, continue?")" 0 0
            RET=$?
            [ ${RET} -eq 0 ] && break
          fi
        done
        [ ${RET} -eq 0 ] && writeConfigKey "proxy" "${PROXY}" "${USER_CONFIG_FILE}"
        ;;
      e) return ;;
    esac
  done
}

###############################################################################
###############################################################################

if [ "x$1" = "xb" -a -n "${MODEL}" -a -n "${BUILD}" -a loaderIsConfigured ]; then
  install-addons.sh
  make
  boot && exit 0 || sleep 5
fi
# Main loop
NEXT="m"
while true; do
  echo "m \"$(TEXT "Choose a model")\""                          > "${TMP_PATH}/menu"
  if [ -n "${MODEL}" ]; then
    echo "n \"$(TEXT "Choose a Build Number")\""                >> "${TMP_PATH}/menu"
    echo "s \"$(TEXT "Choose a serial number")\""               >> "${TMP_PATH}/menu"
    if [ -n "${BUILD}" ]; then
      echo "a \"$(TEXT "Addons")\""                             >> "${TMP_PATH}/menu"
      echo "o \"$(TEXT "Modules")\""                            >> "${TMP_PATH}/menu"
      echo "x \"$(TEXT "Cmdline menu")\""                       >> "${TMP_PATH}/menu"
      echo "i \"$(TEXT "Synoinfo menu")\""                      >> "${TMP_PATH}/menu"
    fi
  fi
  echo "v \"$(TEXT "Advanced menu")\""                          >> "${TMP_PATH}/menu"
  if [ -n "${MODEL}" ]; then
    if [ -n "${BUILD}" ]; then
      echo "d \"$(TEXT "Build the loader")\""                   >> "${TMP_PATH}/menu"
    fi
  fi
  if loaderIsConfigured; then
    echo "b \"$(TEXT "Boot the loader")\""                      >> "${TMP_PATH}/menu"
  fi
  echo "l \"$(TEXT "Choose a language")\""                      >> "${TMP_PATH}/menu"
  echo "k \"$(TEXT "Choose a keymap")\""                        >> "${TMP_PATH}/menu"
  if [ ${CLEARCACHE} -eq 1 -a -d "${CACHE_PATH}/dl" ]; then
    echo "c \"$(TEXT "Clean disk cache")\""                     >> "${TMP_PATH}/menu"
  fi
  echo "p \"$(TEXT "Update menu")\""                            >> "${TMP_PATH}/menu"
  echo "e \"$(TEXT "Exit")\""                                   >> "${TMP_PATH}/menu"

  dialog --default-item ${NEXT} --backtitle "`backtitle`" --colors \
    --menu "$(TEXT "Choose the option")" 0 0 0 --file "${TMP_PATH}/menu" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && break
  case `<"${TMP_PATH}/resp"` in
    m) modelMenu; NEXT="n" ;;
    n) buildMenu; NEXT="s" ;;
    s) serialMenu; NEXT="a" ;;
    a) addonMenu; NEXT="o" ;;
    o) moduleMenu; NEXT="x" ;;
    x) cmdlineMenu; NEXT="i" ;;
    i) synoinfoMenu; NEXT="v" ;;
    v) advancedMenu; NEXT="d" ;;
    d) make; NEXT="b" ;;
    b) boot && exit 0 || sleep 5 ;;
    l) languageMenu ;;
    k) keymapMenu ;;
    c) dialog --backtitle "`backtitle`" --title "$(TEXT "Cleaning")" --aspect 18 \
      --prgbox "rm -rfv \"${CACHE_PATH}/dl\"" 0 0 ;;
    p) updateMenu ;;
    e) break ;;
  esac
done
clear
echo -e "$(TEXT "Call \033[1;32mmenu.sh\033[0m to return to menu")"
