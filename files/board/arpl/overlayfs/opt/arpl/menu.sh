#!/usr/bin/env bash

. /opt/arpl/include/functions.sh
. /opt/arpl/include/addons.sh
. /opt/arpl/include/modules.sh

# Check partition 3 space, if < 2GiB is necessary clean cache folder
CLEARCACHE=0
LOADER_DISK="$(blkid | grep 'LABEL="ARPL3"' | cut -d3 -f1)"
LOADER_DEVICE_NAME=$(echo "${LOADER_DISK}" | sed 's|/dev/||')
if [ $(cat "/sys/block/${LOADER_DEVICE_NAME}/${LOADER_DEVICE_NAME}3/size") -lt 4194304 ]; then
  CLEARCACHE=1
fi

# Get actual IP
IP=$(ip route 2>/dev/null | sed -n 's/.* via .* dev \(.*\)  src \(.*\)  metric .*/\1: \2 /p' | head -1)

# Dirty flag
DIRTY=0
# Debug flag
# DEBUG=0

MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
SMALLNUM="$(readConfigKey "smallnum" "${USER_CONFIG_FILE}")"
LAYOUT="$(readConfigKey "layout" "${USER_CONFIG_FILE}")"
KEYMAP="$(readConfigKey "keymap" "${USER_CONFIG_FILE}")"
LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
DSMLOGO="$(readConfigKey "dsmlogo" "${USER_CONFIG_FILE}")"
DIRECTBOOT="$(readConfigKey "directboot" "${USER_CONFIG_FILE}")"
NOTSETMACS="$(readConfigKey "notsetmacs" "${USER_CONFIG_FILE}")"
PRERELEASE="$(readConfigKey "prerelease" "${USER_CONFIG_FILE}")"
BOOTWAIT="$(readConfigKey "bootwait" "${USER_CONFIG_FILE}")"
BOOTIPWAIT="$(readConfigKey "bootipwait" "${USER_CONFIG_FILE}")"
KERNELWAY="$(readConfigKey "kernelway" "${USER_CONFIG_FILE}")"
ODP="$(readConfigKey "odp" "${USER_CONFIG_FILE}")"  # official drivers priorities
SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"

###############################################################################
# Mounts backtitle dynamically
function backtitle() {
  BACKTITLE="${ARPL_TITLE}"
  if [ -n "${MODEL}" ]; then
    BACKTITLE+=" ${MODEL}"
  else
    BACKTITLE+=" (no model)"
  fi
  if [ -n "${PRODUCTVER}" ]; then
    BACKTITLE+=" ${PRODUCTVER}"
    if [ -n "${BUILDNUM}" ]; then
      BACKTITLE+="(${BUILDNUM}$([ ${SMALLNUM:-0} -ne 0 ] && echo "u${SMALLNUM}"))"
    else
      BACKTITLE+="(no build)"
    fi
  else
    BACKTITLE+=" (no productver)"
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
    dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Model")" \
      --infobox "$(TEXT "Reading models")" 0 0
    echo -n "" >"${TMP_PATH}/modellist"
    while read M; do
      Y=$(echo ${M} | tr -cd "[0-9]")
      Y=${Y:0-2}
      echo "${M} ${Y}" >>"${TMP_PATH}/modellist"
    done < <(find "${MODEL_CONFIG_PATH}" -maxdepth 1 -name \*.yml | sed 's/.*\///; s/\.yml//')

    while true; do
      echo -n "" >"${TMP_PATH}/menu"
      FLGNEX=0
      while read M Y; do
        PLATFORM=$(readModelKey "${M}" "platform")
        DT="$(readModelKey "${M}" "dt")"
        BETA="$(readModelKey "${M}" "beta")"
        [ "${BETA}" = "true" -a ${FLGBETA} -eq 0 ] && continue
        # Check id model is compatible with CPU
        COMPATIBLE=1
        if [ ${RESTRICT} -eq 1 ]; then
          for F in $(readModelArray "${M}" "flags"); do
            if ! grep -q "^flags.*${F}.*" /proc/cpuinfo; then
              COMPATIBLE=0
              FLGNEX=1
              break
            fi
          done
        fi
        [ "${DT}" = "true" ] && DT="DT" || DT=""
        [ ${COMPATIBLE} -eq 1 ] && echo "${M} \"$(printf "\Zb%-12s\Zn \Z4%-2s\Zn" "${PLATFORM}" "${DT}")\" " >>"${TMP_PATH}/menu"
      done < <(cat "${TMP_PATH}/modellist" | sort -r -n -k 2)
      [ ${FLGNEX} -eq 1 ] && echo "f \"\Z1$(TEXT "Disable flags restriction")\Zn\"" >>"${TMP_PATH}/menu"
      [ ${FLGBETA} -eq 0 ] && echo "b \"\Z1$(TEXT "Show beta models")\Zn\"" >>"${TMP_PATH}/menu"
      dialog --backtitle "$(backtitle)" --colors \
        --menu "$(TEXT "Choose the model")" 0 0 0 --file "${TMP_PATH}/menu" \
        2>${TMP_PATH}/resp
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
  # If user change model, clean build* and pat* and SN
  if [ "${MODEL}" != "${resp}" ]; then
    MODEL=${resp}
    writeConfigKey "model" "${MODEL}" "${USER_CONFIG_FILE}"
    PRODUCTVER=""
    BUILDNUM=""
    SMALLNUM=""
    writeConfigKey "productver" "" "${USER_CONFIG_FILE}"
    writeConfigKey "buildnum" "" "${USER_CONFIG_FILE}"
    writeConfigKey "smallnum" "" "${USER_CONFIG_FILE}"
    writeConfigKey "paturl" "" "${USER_CONFIG_FILE}"
    writeConfigKey "patsum" "" "${USER_CONFIG_FILE}"
    SN=$(generateSerial "${MODEL}")
    writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
    DIRTY=1
  fi
}

###############################################################################
# Shows available buildnumbers from a model to user choose one
function productversMenu() {
  ITEMS="$(readConfigEntriesArray "productvers" "${MODEL_CONFIG_PATH}/${MODEL}.yml" | sort -r)"
  if [ -z "${1}" ]; then
    dialog --backtitle "$(backtitle)" --colors \
      --no-items --menu "$(TEXT "Choose a product version")" 0 0 0 ${ITEMS} \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    resp=$(<${TMP_PATH}/resp)
    [ -z "${resp}" ] && return
  else
    if ! arrayExistItem "${1}" ${ITEMS}; then return; fi
    resp="${1}"
  fi
  if [ "${PRODUCTVER}" != "${resp}" ]; then
    local KVER=$(readModelKey "${MODEL}" "productvers.[${resp}].kver")
    if [ -d "/sys/firmware/efi" -a "${KVER:0:1}" = "3" ]; then
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Product Version")" \
        --msgbox "$(TEXT "This version does not support UEFI startup, Please select another version or switch the startup mode.")" 0 0
      return
    fi
    if [ ! "usb" = "$(udevadm info --query property --name ${LOADER_DISK} | grep ID_BUS | cut -d= -f2)" -a "${KVER:0:1}" = "5" ]; then
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Product Version")" \
        --msgbox "$(TEXT "This version only support usb startup, Please select another version or switch the startup mode.")" 0 0
      # return
    fi
    # get online pat data
    dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Product Version")" \
      --infobox "$(TEXT "Get pat data ..")" 0 0
    idx=0
    while [ ${idx} -le 3 ]; do # Loop 3 times, if successful, break
      fastest=$(_get_fastest "www.synology.com" "www.synology.cn")
      [ "${fastest}" = "www.synology.cn" ] &&
        fastest="https://www.synology.cn/api/support/findDownloadInfo?lang=zh-cn" ||
        fastest="https://www.synology.com/api/support/findDownloadInfo?lang=en-us"
      patdata=$(curl -skL "${fastest}&product=${MODEL/+/%2B}&major=${resp%%.*}&minor=${resp##*.}")
      if [ "$(echo ${patdata} | jq -r '.success' 2>/dev/null)" = "true" ]; then
        if echo ${patdata} | jq -r '.info.system.detail[0].items[0].files[0].label_ext' 2>/dev/null | grep -q 'pat'; then
          paturl=$(echo ${patdata} | jq -r '.info.system.detail[0].items[0].files[0].url')
          patsum=$(echo ${patdata} | jq -r '.info.system.detail[0].items[0].files[0].checksum')
          paturl=${paturl%%\?*}
          break
        fi
      fi
      idx=$((${idx} + 1))
    done
    if [ -z "${paturl}" -o -z "${patsum}" ]; then
      MSG="$(TEXT "Failed to get pat data,\nPlease manually fill in the URL and md5sum of the corresponding version of pat.")"
      paturl=""
      patsum=""
    else
      MSG="$(TEXT "Successfully to get pat data,\nPlease confirm or modify as needed.")"
    fi
    dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Product Version")" \
      --form "${MSG}" 10 110 2 "URL" 1 1 "${paturl}" 1 5 100 0 "MD5" 2 1 "${patsum}" 2 5 100 0 \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return
    paturl="$(cat "${TMP_PATH}/resp" | tail -n +1 | head -1)"
    patsum="$(cat "${TMP_PATH}/resp" | tail -n +2 | head -1)"
    [ -z "${paturl}" -o -z "${patsum}" ] && return
    writeConfigKey "paturl" "${paturl}" "${USER_CONFIG_FILE}"
    writeConfigKey "patsum" "${patsum}" "${USER_CONFIG_FILE}"
    PRODUCTVER=${resp}
    writeConfigKey "productver" "${PRODUCTVER}" "${USER_CONFIG_FILE}"
    BUILDNUM=""
    SMALLNUM=""
    writeConfigKey "buildnum" "${BUILDNUM}" "${USER_CONFIG_FILE}"
    writeConfigKey "smallnum" "${SMALLNUM}" "${USER_CONFIG_FILE}"
    dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Product Version")" \
      --infobox "$(TEXT "Reconfiguring Synoinfo, Addons and Modules")" 0 0
    # Delete synoinfo and reload model/build synoinfo
    writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
    while IFS=': ' read KEY VALUE; do
      writeConfigKey "synoinfo.${KEY}" "${VALUE}" "${USER_CONFIG_FILE}"
    done < <(readModelMap "${MODEL}" "productvers.[${PRODUCTVER}].synoinfo")
    # Check addons
    PLATFORM="$(readModelKey "${MODEL}" "platform")"
    KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
    KPRE="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kpre")"
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
    done < <(getAllModules "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}")
    # Remove old files
    rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
    DIRTY=1
  fi
}

###############################################################################
# Manage addons
function addonMenu() {
  # Read 'platform' and kernel version to check if addon exists
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  KPRE="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kpre")"
  # Read addons from user config
  unset ADDONS
  declare -A ADDONS
  while IFS=': ' read KEY VALUE; do
    [ -n "${KEY}" ] && ADDONS["${KEY}"]="${VALUE}"
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")
  NEXT="a"
  # Loop menu
  while true; do
    dialog --backtitle "$(backtitle)" --colors \
      --default-item ${NEXT} --menu "$(TEXT "Choose a option")" 0 0 0 \
      a "$(TEXT "Add an addon")" \
      d "$(TEXT "Delete addon(s)")" \
      s "$(TEXT "Show user addons")" \
      m "$(TEXT "Show all available addons")" \
      o "$(TEXT "Upload a external addon")" \
      e "$(TEXT "Exit")" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "$(<${TMP_PATH}/resp)" in
    a)
      NEXT='a'
      rm "${TMP_PATH}/menu"
      while read ADDON DESC; do
        arrayExistItem "${ADDON}" "${!ADDONS[@]}" && continue # Check if addon has already been added
        echo "${ADDON} \"${DESC}\"" >>"${TMP_PATH}/menu"
      done < <(availableAddons "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}")
      if [ ! -f "${TMP_PATH}/menu" ]; then
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Addons")" \
          --msgbox "$(TEXT "No available addons to add")" 0 0
        NEXT="e"
        continue
      fi
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Addons")" \
        --menu "$(TEXT "Select an addon")" 0 0 0 --file "${TMP_PATH}/menu" \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && continue
      ADDON="$(<"${TMP_PATH}/resp")"
      [ -z "${ADDON}" ] && continue
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Addons")" \
        --inputbox "$(TEXT "Type a optional params to addon")" 0 0 \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && continue
      VALUE="$(<"${TMP_PATH}/resp")"
      ADDONS[${ADDON}]="${VALUE}"
      writeConfigKey "addons.${ADDON}" "${VALUE}" "${USER_CONFIG_FILE}"
      DIRTY=1
      ;;
    d)
      NEXT='d'
      if [ ${#ADDONS[@]} -eq 0 ]; then
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Addons")" \
          --msgbox "$(TEXT "No user addons to remove")" 0 0
        continue
      fi
      rm -f "${TMP_PATH}/opts"
      for I in "${!ADDONS[@]}"; do
        echo "\"${I}\" \"${I}\" \"off\"" >>"${TMP_PATH}/opts"
      done
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Addons")" \
        --no-tags --checklist "$(TEXT "Select addon to remove")" 0 0 0 --file "${TMP_PATH}/opts" \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && continue
      ADDON="$(<"${TMP_PATH}/resp")"
      [ -z "${ADDON}" ] && continue
      for I in ${ADDON}; do
        unset ADDONS[${I}]
        deleteConfigKey "addons.${I}" "${USER_CONFIG_FILE}"
      done
      DIRTY=1
      ;;
    s)
      NEXT='s'
      ITEMS=""
      for KEY in ${!ADDONS[@]}; do
        ITEMS+="${KEY}: ${ADDONS[$KEY]}\n"
      done
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Addons")" \
        --msgbox "${ITEMS}" 0 0
      ;;
    m)
      NEXT='m'
      MSG=""
      while read MODULE DESC; do
        if arrayExistItem "${MODULE}" "${!ADDONS[@]}"; then
          MSG+="\Z4${MODULE}\Zn"
        else
          MSG+="${MODULE}"
        fi
        MSG+=": \Z5${DESC}\Zn\n"
      done < <(availableAddons "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}")
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Addons")" \
        --msgbox "${MSG}" 0 0
      ;;
    o)
      if ! tty | grep -q "/dev/pts"; then
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Addons")" \
          --msgbox "$(TEXT "This feature is only available when accessed via web/ssh.")" 0 0
        return
      fi
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Addons")" \
        --msgbox "$(TEXT "Please upload the *.addons file.")" 0 0
      TMP_UP_PATH=${TMP_PATH}/users
      USER_FILE=""
      rm -rf ${TMP_UP_PATH}
      mkdir -p ${TMP_UP_PATH}
      pushd ${TMP_UP_PATH}
      rz -be
      for F in $(ls -A); do
        USER_FILE=${F}
        break
      done
      popd
      if [ -z "${USER_FILE}" ]; then
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Addons")" \
          --msgbox "$(TEXT "Not a valid file, please try again!")" 0 0
      else
        if [ -d "${ADDONS_PATH}/$(basename ${USER_FILE} .addons)" ]; then
          dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Addons")" \
            --yesno "$(TEXT "The addon already exists. Do you want to overwrite it?")" 0 0
          RET=$?
          [ ${RET} -eq 0 ] && return
        fi
        ADDON="$(untarAddon "${TMP_UP_PATH}/${USER_FILE}")"
        if [ -n "${ADDON}" ]; then
          dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Addons")" \
            --msgbox "$(printf "$(TEXT "Addon '%s' added to loader, Please enable it in 'Add an addon' menu.")" "${ADDON}")" 0 0
        else
          dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Addons")" \
            --msgbox "$(TEXT "File format not recognized!")" 0 0
        fi
      fi
      ;;

    e) return ;;
    esac
  done
}
###############################################################################
function moduleMenu() {
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  KPRE="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kpre")"

  dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Modules")" \
    --infobox "$(TEXT "Reading modules")" 0 0
  ALLMODULES=$(getAllModules "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}")
  unset USERMODULES
  declare -A USERMODULES
  while IFS=': ' read KEY VALUE; do
    [ -n "${KEY}" ] && USERMODULES["${KEY}"]="${VALUE}"
  done < <(readConfigMap "modules" "${USER_CONFIG_FILE}")
  NEXT="s"
  # loop menu
  while true; do
    dialog --backtitle "$(backtitle)" --colors \
      --default-item ${NEXT} --menu "$(TEXT "Choose a option")" 0 0 0 \
      s "$(TEXT "Show selected modules")" \
      l "$(TEXT "Select loaded modules")" \
      a "$(TEXT "Select all modules")" \
      d "$(TEXT "Deselect all modules")" \
      c "$(TEXT "Choose modules to include")" \
      o "$(TEXT "Upload a external module")" \
      p "$(TEXT "Priority use of official drivers:") \Z4${ODP}\Zn" \
      e "$(TEXT "Exit")" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && break
    case "$(<${TMP_PATH}/resp)" in
    s)
      ITEMS=""
      for KEY in ${!USERMODULES[@]}; do
        ITEMS+="${KEY}: ${USERMODULES[$KEY]}\n"
      done
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Modules")" \
        --msgbox "${ITEMS}" 0 0
      ;;
    l)
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Modules")" \
        --infobox "$(TEXT "Selecting loaded modules")" 0 0
      KOLIST=""
      for I in $(lsmod | awk -F' ' '{print $1}' | grep -v 'Module'); do
        KOLIST+="$(getdepends "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}" "${I}") ${I} "
      done
      KOLIST=($(echo ${KOLIST} | tr ' ' '\n' | sort -u))
      unset USERMODULES
      declare -A USERMODULES
      writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
      for ID in ${KOLIST[@]}; do
        USERMODULES["${ID}"]=""
        writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
      done
      DIRTY=1
      ;;
    a)
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Modules")" \
        --infobox "$(TEXT "Selecting all modules")" 0 0
      unset USERMODULES
      declare -A USERMODULES
      writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
      while read ID DESC; do
        USERMODULES["${ID}"]=""
        writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
      done <<<${ALLMODULES}
      DIRTY=1
      ;;

    d)
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Modules")" \
        --infobox "$(TEXT "Deselecting all modules")" 0 0
      writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
      unset USERMODULES
      declare -A USERMODULES
      DIRTY=1
      ;;

    c)
      rm -f "${TMP_PATH}/opts"
      while read ID DESC; do
        arrayExistItem "${ID}" "${!USERMODULES[@]}" && ACT="on" || ACT="off"
        echo "${ID} ${DESC} ${ACT}" >>"${TMP_PATH}/opts"
      done <<<${ALLMODULES}
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Modules")" \
        --checklist "$(TEXT "Select modules to include")" 0 0 0 --file "${TMP_PATH}/opts" \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && continue
      resp=$(<${TMP_PATH}/resp)
      [ -z "${resp}" ] && continue
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Modules")" \
        --infobox "$(TEXT "Writing to user config")" 0 0
      unset USERMODULES
      declare -A USERMODULES
      writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
      for ID in ${resp}; do
        USERMODULES["${ID}"]=""
        writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
      done
      DIRTY=1
      ;;

    o)
      MSG=""
      MSG+="$(TEXT "This function is experimental and dangerous. If you don't know much, please exit.\n")"
      MSG+="$(TEXT "The imported .ko of this function will be implanted into the corresponding arch's modules package, which will affect all models of the arch.\n")"
      MSG+="$(TEXT "This program will not determine the availability of imported modules or even make type judgments, as please double check if it is correct.\n")"
      MSG+="$(TEXT "If you want to remove it, please go to the \"Update Menu\" -> \"Update modules\" to forcibly update the modules. All imports will be reset.\n")"
      MSG+="$(TEXT "Do you want to continue?")"
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Modules")" \
        --yesno "${MSG}" 0 0
      [ $? -ne 0 ] && return
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Modules")" \
        --msgbox "$(TEXT "Please upload the *.ko file.")" 0 0
      TMP_UP_PATH=${TMP_PATH}/users
      USER_FILE=""
      rm -rf ${TMP_UP_PATH}
      mkdir -p ${TMP_UP_PATH}
      pushd ${TMP_UP_PATH}
      rz -be
      for F in $(ls -A); do
        USER_FILE=${F}
        break
      done
      popd
      if [ -n "${USER_FILE}" -a "${USER_FILE##*.}" = "ko" ]; then
        addToModules ${PLATFORM} "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}" "${TMP_UP_PATH}/${USER_FILE}"
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Modules")" \
          --msgbox "$(printf "$(TEXT "Module '%s' added to %s-%s")" "${USER_FILE}" "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}")" 0 0
        rm -f "${TMP_UP_PATH}/${USER_FILE}"
      else
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Modules")" \
          --msgbox "$(TEXT "Not a valid file, please try again!")" 0 0
      fi
      ;;
    p)
      [ "${ODP}" = "false" ] && ODP='true' || ODP='false'
      writeConfigKey "odp" "${ODP}" "${USER_CONFIG_FILE}"
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
  echo "a \"$(TEXT "Add/edit a cmdline item")\"" >"${TMP_PATH}/menu"
  echo "d \"$(TEXT "Delete cmdline item(s)")\"" >>"${TMP_PATH}/menu"
  if [ -n "${MODEL}" ]; then
    echo "s \"$(TEXT "Define a serial number")\"" >>"${TMP_PATH}/menu"
  fi
  echo "c \"$(TEXT "Define a custom MAC")\"" >>"${TMP_PATH}/menu"
  echo "v \"$(TEXT "Show user added cmdline")\"" >>"${TMP_PATH}/menu"
  echo "m \"$(TEXT "Show model inherent cmdline")\"" >>"${TMP_PATH}/menu"
  echo "e \"$(TEXT "Exit")\"" >>"${TMP_PATH}/menu"
  # Loop menu
  while true; do
    dialog --backtitle "$(backtitle)" --colors \
      --menu "$(TEXT "Choose a option")" 0 0 0 --file "${TMP_PATH}/menu" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "$(<${TMP_PATH}/resp)" in
    a)
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Cmdline")" \
        --inputbox "$(TEXT "Type a name of cmdline")" 0 0 \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && continue
      NAME="$(sed 's/://g' <"${TMP_PATH}/resp")"
      [ -z "${NAME}" ] && continue
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Cmdline")" \
        --inputbox "$(printf "$(TEXT "Type a value of '%s' cmdline")" "${NAME}")" 0 0 "${CMDLINE[${NAME}]}" \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && continue
      VALUE="$(<"${TMP_PATH}/resp")"
      CMDLINE[${NAME}]="${VALUE}"
      writeConfigKey "cmdline.${NAME}" "${VALUE}" "${USER_CONFIG_FILE}"
      ;;
    d)
      if [ ${#CMDLINE[@]} -eq 0 ]; then
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Cmdline")" \
          --msgbox "$(TEXT "No user cmdline to remove")" 0 0
        continue
      fi
      rm -f "${TMP_PATH}/opts"
      for I in "${!CMDLINE[@]}"; do
        echo "\"${I}\" \"${CMDLINE[${I}]}\" \"off\"" >>"${TMP_PATH}/opts"
      done
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Cmdline")" \
        --checklist "$(TEXT "Select cmdline to remove")" 0 0 0 --file "${TMP_PATH}/opts" \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && continue
      RESP=$(<"${TMP_PATH}/resp")
      [ -z "${RESP}" ] && continue
      for I in ${RESP}; do
        unset CMDLINE[${I}]
        deleteConfigKey "cmdline.${I}" "${USER_CONFIG_FILE}"
      done
      ;;
    s)
      while true; do
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Cmdline")" \
          --inputbox "$(TEXT "Please enter a serial number ")" 0 0 "" \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && break 2
        SERIAL=$(cat ${TMP_PATH}/resp)
        if [ -z "${SERIAL}" ]; then
          return
        elif [ $(validateSerial ${MODEL} ${SERIAL}) -eq 1 ]; then
          break
        fi
        # At present, the SN rules are not complete, and many SNs are not truly invalid, so not provide tips now.
        break
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Cmdline")" \
          --yesno "$(TEXT "Invalid serial, continue?")" 0 0
        [ $? -eq 0 ] && break
      done
      SN="${SERIAL}"
      writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
      ;;
    c)
      ETHX=($(ls /sys/class/net/ | grep eth)) # real network cards list
      for N in $( # Currently, only up to 8 are supported.  (<==> boot.sh L96, <==> lkm: MAX_NET_IFACES)
        seq 1 8
      ); do
        MACR="$(cat /sys/class/net/${ETHX[$(expr ${N} - 1)]}/address | sed 's/://g')"
        MACF=${CMDLINE["mac${N}"]}
        [ -n "${MACF}" ] && MAC=${MACF} || MAC=${MACR}
        RET=1
        while true; do
          dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Cmdline")" \
            --inputbox "$(printf "$(TEXT "Type a custom MAC address of %s")" "mac${N}")" 0 0 "${MAC}" \
            2>${TMP_PATH}/resp
          RET=$?
          [ ${RET} -ne 0 ] && break 2
          MAC="$(<"${TMP_PATH}/resp")"
          [ -z "${MAC}" ] && MAC="$(readConfigKey "original-mac${i}" "${USER_CONFIG_FILE}")"
          [ -z "${MAC}" ] && MAC="${MACFS[$(expr ${i} - 1)]}"
          MACF="$(echo "${MAC}" | sed "s/:\|-\| //g")"
          [ ${#MACF} -eq 12 ] && break
          dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Cmdline")" \
            --msgbox "$(TEXT "Invalid MAC")" 0 0
        done
        if [ ${RET} -eq 0 ]; then
          CMDLINE["mac${N}"]="${MACF}"
          CMDLINE["netif_num"]=${N}
          writeConfigKey "cmdline.mac${N}" "${MACF}" "${USER_CONFIG_FILE}"
          writeConfigKey "cmdline.netif_num" "${N}" "${USER_CONFIG_FILE}"
          MAC="${MACF:0:2}:${MACF:2:2}:${MACF:4:2}:${MACF:6:2}:${MACF:8:2}:${MACF:10:2}"
          ip link set dev ${ETHX[$(expr ${N} - 1)]} address "${MAC}" 2>&1 |
            dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Cmdline")" \
              --progressbox "$(TEXT "Changing MAC")" 20 70
          /etc/init.d/S41dhcpcd restart 2>&1 |
            dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Cmdline")" \
              --progressbox "$(TEXT "Renewing IP")" 20 70
          # IP=`ip route 2>/dev/null | sed -n 's/.* via .* dev \(.*\)  src \(.*\)  metric .*/\1: \2 /p' | head -1`
          dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Cmdline")" \
            --yesno "$(TEXT "Continue to custom MAC?")" 0 0
          [ $? -ne 0 ] && break
        fi
      done
      ;;
    v)
      ITEMS=""
      for KEY in ${!CMDLINE[@]}; do
        ITEMS+="${KEY}: ${CMDLINE[$KEY]}\n"
      done
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Cmdline")" \
        --msgbox "${ITEMS}" 0 0
      ;;
    m)
      ITEMS=""
      while IFS=': ' read KEY VALUE; do
        ITEMS+="${KEY}: ${VALUE}\n"
      done < <(readModelMap "${MODEL}" "productvers.[${PRODUCTVER}].cmdline")
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Cmdline")" \
        --msgbox "${ITEMS}" 0 0
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

  echo "a \"$(TEXT "Add/edit a synoinfo item")\"" >"${TMP_PATH}/menu"
  echo "d \"$(TEXT "Delete synoinfo item(s)")\"" >>"${TMP_PATH}/menu"
  echo "s \"$(TEXT "Show synoinfo entries")\"" >>"${TMP_PATH}/menu"
  echo "e \"$(TEXT "Exit")\"" >>"${TMP_PATH}/menu"

  # menu loop
  while true; do
    dialog --backtitle "$(backtitle)" --colors \
      --menu "$(TEXT "Choose a option")" 0 0 0 --file "${TMP_PATH}/menu" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "$(<${TMP_PATH}/resp)" in
    a)
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Synoinfo")" \
        --inputbox "$(TEXT "Type a name of synoinfo entry")" 0 0 \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && continue
      NAME="$(<"${TMP_PATH}/resp")"
      [ -z "${NAME}" ] && continue
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Synoinfo")" \
        --inputbox "$(printf "$(TEXT "Type a value of '%s' synoinfo entry")" "${NAME}")" 0 0 "${SYNOINFO[${NAME}]}" \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && continue
      VALUE="$(<"${TMP_PATH}/resp")"
      SYNOINFO[${NAME}]="${VALUE}"
      writeConfigKey "synoinfo.${NAME}" "${VALUE}" "${USER_CONFIG_FILE}"
      DIRTY=1
      ;;
    d)
      if [ ${#SYNOINFO[@]} -eq 0 ]; then
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Synoinfo")" \
          --msgbox "$(TEXT "No synoinfo entries to remove")" 0 0
        continue
      fi
      rm -f "${TMP_PATH}/opts"
      for I in ${!SYNOINFO[@]}; do
        echo "\"${I}\" \"${SYNOINFO[${I}]}\" \"off\"" >>"${TMP_PATH}/opts"
      done
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Synoinfo")" \
        --checklist "$(TEXT "Select synoinfo entry to remove")" 0 0 0 --file "${TMP_PATH}/opts" \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && continue
      RESP=$(<"${TMP_PATH}/resp")
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
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Synoinfo")" \
        --msgbox "${ITEMS}" 0 0
      ;;
    e) return ;;
    esac
  done
}

###############################################################################
# Extract linux and ramdisk files from the DSM .pat
function extractDsmFiles() {
  PATURL="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
  PATSUM="$(readConfigKey "patsum" "${USER_CONFIG_FILE}")"

  SPACELEFT=$(df --block-size=1 | awk '/'${LOADER_DEVICE_NAME}'3/{print $4}') # Check disk space left

  PAT_FILE="${MODEL}-${PRODUCTVER}.pat"
  PAT_PATH="${CACHE_PATH}/dl/${PAT_FILE}"
  EXTRACTOR_PATH="${CACHE_PATH}/extractor"
  EXTRACTOR_BIN="syno_extract_system_patch"
  OLDPATURL="https://global.synologydownload.com/download/DSM/release/7.0.1/42218/DSM_DS3622xs%2B_42218.pat"

  if [ -f "${PAT_PATH}" ]; then
    echo "$(printf "$(TEXT "%s cached.")" "${PAT_FILE}")"
  else
    # If we have little disk space, clean cache folder
    if [ ${CLEARCACHE} -eq 1 ]; then
      echo "$(TEXT "Cleaning cache")"
      rm -rf "${CACHE_PATH}/dl"
    fi
    mkdir -p "${CACHE_PATH}/dl"
    fastest=$(_get_fastest "global.synologydownload.com" "global.download.synology.com" "cndl.synology.cn")
    mirror="$(echo ${PATURL} | sed 's|^http[s]*://\([^/]*\).*|\1|')"
    if echo "${mirrors[@]}" | grep -wq "${mirror}" && [ "${mirror}" != "${fastest}" ]; then
      echo "$(printf "$(TEXT "Based on the current network situation, switch to %s mirror to downloading.")" "${fastest}")"
      PATURL="$(echo ${PATURL} | sed "s/${mirror}/${fastest}/")"
      OLDPATURL="https://${fastest}/download/DSM/release/7.0.1/42218/DSM_DS3622xs%2B_42218.pat"
    fi
    echo "$(printf "$(TEXT "Downloading %s")" "${PAT_FILE}")"
    # Discover remote file size
    FILESIZE=$(curl -k -sLI "${PATURL}" | grep -i Content-Length | awk '{print$2}')
    if [ 0${FILESIZE} -ge 0${SPACELEFT} ]; then
      # No disk space to download, change it to RAMDISK
      PAT_PATH="${TMP_PATH}/${PAT_FILE}"
    fi
    STATUS=$(curl -k -w "%{http_code}" -L "${PATURL}" -o "${PAT_PATH}" --progress-bar)
    if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
      rm "${PAT_PATH}"
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Error")" \
        --msgbox "$(TEXT "Check internet or cache disk space")" 0 0
      return 1
    fi
  fi

  echo -n "$(printf "$(TEXT "Checking hash of %s: ")" "${PAT_FILE}")"
  if [ "$(md5sum ${PAT_PATH} | awk '{print $1}')" != "${PATSUM}" ]; then
    dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Error")" \
      --msgbox "$(TEXT "md5 Hash of pat not match, try again!")" 0 0
    rm -f ${PAT_PATH}
    return 1
  fi
  echo "$(TEXT "OK")"

  rm -rf "${UNTAR_PAT_PATH}"
  mkdir "${UNTAR_PAT_PATH}"
  echo -n "$(printf "$(TEXT "Disassembling %s: ")" "${PAT_FILE}")"

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
    dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Error")" \
      --msgbox "$(TEXT "Could not determine if pat file is encrypted or not, maybe corrupted, try again!")" 0 0
    return 1
    ;;
  esac

  SPACELEFT=$(df --block-size=1 | awk '/'${LOADER_DEVICE_NAME}'3/{print$4}') # Check disk space left

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
        FILESIZE=$(curl -k -sLI "${OLDPATURL}" | grep -i Content-Length | awk '{print$2}')
        if [ 0${FILESIZE} -ge 0${SPACELEFT} ]; then
          # No disk space to download, change it to RAMDISK
          OLDPAT_PATH="${TMP_PATH}/DS3622xs+-42218.pat"
        fi
        STATUS=$(curl -k -w "%{http_code}" -L "${OLDPATURL}" -o "${OLDPAT_PATH}" --progress-bar)
        if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
          rm "${OLDPAT_PATH}"
          dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Error")" \
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
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Error")" \
          --textbox "${LOG_FILE}" 0 0
        return 1
      fi
      [ ${CLEARCACHE} -eq 1 ] && rm -f "${OLDPAT_PATH}"
      # Extract all files from rd.gz
      (
        cd "${RAMDISK_PATH}"
        xz -dc <rd.gz | cpio -idm
      ) >/dev/null 2>&1 || true
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
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Error")" \
        --textbox "${LOG_FILE}" 0 0
    fi
  fi
  if [ ! -f ${UNTAR_PAT_PATH}/grub_cksum.syno ] ||
    [ ! -f ${UNTAR_PAT_PATH}/GRUB_VER ] ||
    [ ! -f ${UNTAR_PAT_PATH}/zImage ] ||
    [ ! -f ${UNTAR_PAT_PATH}/rd.gz ]; then
    dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Error")" \
      --msgbox "$(TEXT "pat Invalid, try again!")" 0 0
    return 1
  fi
  echo -n "$(TEXT "Setting hash: ")"
  ZIMAGE_HASH="$(sha256sum ${UNTAR_PAT_PATH}/zImage | awk '{print $1}')"
  writeConfigKey "zimage-hash" "${ZIMAGE_HASH}" "${USER_CONFIG_FILE}"
  RAMDISK_HASH="$(sha256sum ${UNTAR_PAT_PATH}/rd.gz | awk '{print $1}')"
  writeConfigKey "ramdisk-hash" "${RAMDISK_HASH}" "${USER_CONFIG_FILE}"
  echo "$(TEXT "OK")"

  echo -n "$(TEXT "Copying files: ")"
  cp "${UNTAR_PAT_PATH}/grub_cksum.syno" "${BOOTLOADER_PATH}"
  cp "${UNTAR_PAT_PATH}/GRUB_VER" "${BOOTLOADER_PATH}"
  cp "${UNTAR_PAT_PATH}/grub_cksum.syno" "${SLPART_PATH}"
  cp "${UNTAR_PAT_PATH}/GRUB_VER" "${SLPART_PATH}"
  cp "${UNTAR_PAT_PATH}/zImage" "${ORI_ZIMAGE_FILE}"
  cp "${UNTAR_PAT_PATH}/rd.gz" "${ORI_RDGZ_FILE}"
  rm -rf "${UNTAR_PAT_PATH}"
  echo "$(TEXT "OK")"
}

# 1 - model
function getLogo() {
  rm -f "${CACHE_PATH}/logo.png"
  if [ "${DSMLOGO}" = "true" ]; then
    fastest=$(_get_fastest "www.synology.com" "www.synology.cn")
    STATUS=$(curl -skL -w "%{http_code}" "https://${fastest}/api/products/getPhoto?product=${MODEL/+/%2B}&type=img_s&sort=0" -o "${CACHE_PATH}/logo.png")
    if [ $? -ne 0 -o ${STATUS} -ne 200 -o -f "${CACHE_PATH}/logo.png" ]; then
      convert -rotate 180 "${CACHE_PATH}/logo.png" "${CACHE_PATH}/logo.png" 2>/dev/null
      magick montage "${CACHE_PATH}/logo.png" -background 'none' -tile '3x3' -geometry '350x210' "${CACHE_PATH}/logo.png" 2>/dev/null
      convert -rotate 180 "${CACHE_PATH}/logo.png" "${CACHE_PATH}/logo.png" 2>/dev/null
    fi
  fi
}

###############################################################################
# Where the magic happens!
function make() {
  # clear
  clear
  # get logo.png
  getLogo "${MODEL}"

  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  KPRE="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kpre")"
  # Check if all addon exists
  while IFS=': ' read ADDON PARAM; do
    [ -z "${ADDON}" ] && continue
    if ! checkAddonExist "${ADDON}" "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}"; then
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Error")" \
        --msgbox "$(printf "$(TEXT "Addon %s not found!")" "${ADDON}")" 0 0
      return 1
    fi
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")

  if [ ! -f "${ORI_ZIMAGE_FILE}" -o ! -f "${ORI_RDGZ_FILE}" ]; then
    extractDsmFiles
    [ $? -ne 0 ] && return 1
  fi

  /opt/arpl/zimage-patch.sh
  if [ $? -ne 0 ]; then
    dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Error")" \
      --msgbox "$(TEXT "zImage not patched:\n")$(<"${LOG_FILE}")" 0 0
    return 1
  fi

  /opt/arpl/ramdisk-patch.sh
  if [ $? -ne 0 ]; then
    dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Error")" \
      --msgbox "$(TEXT "Ramdisk not patched:\n")$(<"${LOG_FILE}")" 0 0
    return 1
  fi
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
  SMALLNUM="$(readConfigKey "smallnum" "${USER_CONFIG_FILE}")"
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
    if [ -n "${PRODUCTVER}" ]; then
      echo "l \"$(TEXT "Switch LKM version:") \Z4${LKM}\Zn\"" >>"${TMP_PATH}/menu"
    fi
    if loaderIsConfigured; then
      echo "q \"$(TEXT "Switch direct boot:") \Z4${DIRECTBOOT}\Zn\"" >>"${TMP_PATH}/menu"
      if [ "${DIRECTBOOT}" = "false" ]; then
        echo "i \"$(TEXT "Timeout of get ip in boot:") \Z4${BOOTIPWAIT}\Zn\"" >>"${TMP_PATH}/menu"
        echo "w \"$(TEXT "Timeout of boot wait:") \Z4${BOOTWAIT}\Zn\"" >>"${TMP_PATH}/menu"
        echo "k \"$(TEXT "kernel switching method:") \Z4${KERNELWAY}\Zn\"" >>"${TMP_PATH}/menu"
      fi
    fi
    echo "m \"$(TEXT "Switch 'Do not set MACs':") \Z4${NOTSETMACS}\Zn\"" >>"${TMP_PATH}/menu"
    echo "u \"$(TEXT "Edit user config file manually")\"" >>"${TMP_PATH}/menu"
    echo "t \"$(TEXT "Try to recovery a DSM installed system")\"" >>"${TMP_PATH}/menu"
    echo "s \"$(TEXT "Show SATA(s) # ports and drives")\"" >>"${TMP_PATH}/menu"
    if [ -n "${MODEL}" -a -n "${PRODUCTVER}" ]; then
      echo "c \"$(TEXT "show/modify the current pat data")\"" >>"${TMP_PATH}/menu"
    fi
    echo "a \"$(TEXT "Allow downgrade installation")\"" >>"${TMP_PATH}/menu"
    echo "f \"$(TEXT "Format disk(s) # Without loader disk")\"" >>"${TMP_PATH}/menu"
    echo "x \"$(TEXT "Reset DSM system password")\"" >>"${TMP_PATH}/menu"
    echo "p \"$(TEXT "Save modifications of '/opt/arpl'")\"" >>"${TMP_PATH}/menu"
    if [ -n "${MODEL}" -a "true" = "$(readModelKey "${MODEL}" "dt")" ]; then
      echo "d \"$(TEXT "Custom dts file # Need rebuild")\"" >>"${TMP_PATH}/menu"
    fi
    if [ -n "${DEBUG}" ]; then
      echo "b \"$(TEXT "Backup bootloader disk # test")\"" >>"${TMP_PATH}/menu"
      echo "r \"$(TEXT "Restore bootloader disk # test")\"" >>"${TMP_PATH}/menu"
    fi
    echo "o \"$(TEXT "Install development tools")\"" >>"${TMP_PATH}/menu"
    echo "g \"$(TEXT "Show dsm logo:") \Z4${DSMLOGO}\Zn\"" >>"${TMP_PATH}/menu"
    echo "e \"$(TEXT "Exit")\"" >>"${TMP_PATH}/menu"

    dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
      --default-item "${NEXT}" --menu "$(TEXT "Choose the option")" 0 0 0 --file "${TMP_PATH}/menu" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && break
    case $(<"${TMP_PATH}/resp") in
    l)
      LKM=$([ "${LKM}" = "dev" ] && echo 'prod' || ([ "${LKM}" = "test" ] && echo 'dev' || echo 'test'))
      writeConfigKey "lkm" "${LKM}" "${USER_CONFIG_FILE}"
      DIRTY=1
      NEXT="l"
      ;;
    q)
      [ "${DIRECTBOOT}" = "false" ] && DIRECTBOOT='true' || DIRECTBOOT='false'
      writeConfigKey "directboot" "${DIRECTBOOT}" "${USER_CONFIG_FILE}"
      NEXT="e"
      ;;
    i)
      ITEMS="$(echo -e "1 \n5 \n10 \n30 \n60 \n")"
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
        --default-item "${BOOTIPWAIT}" --no-items --menu "$(TEXT "Choose a waiting time(seconds)")" 0 0 0 ${ITEMS} \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && return
      resp=$(cat ${TMP_PATH}/resp 2>/dev/null)
      [ -z "${resp}" ] && return
      BOOTIPWAIT=${resp}
      writeConfigKey "bootipwait" "${BOOTIPWAIT}" "${USER_CONFIG_FILE}"
      NEXT="e"
      ;;
    w)
      ITEMS="$(echo -e "1 \n5 \n10 \n30 \n60 \n")"
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
        --default-item "${BOOTWAIT}" --no-items --menu "$(TEXT "Choose a waiting time(seconds)")" 0 0 0 ${ITEMS} \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && return
      resp=$(cat ${TMP_PATH}/resp 2>/dev/null)
      [ -z "${resp}" ] && return
      BOOTWAIT=${resp}
      writeConfigKey "bootwait" "${BOOTWAIT}" "${USER_CONFIG_FILE}"
      NEXT="e"
      ;;
    k)
      [ "${KERNELWAY}" = "kexec" ] && KERNELWAY='power' || KERNELWAY='kexec'
      writeConfigKey "kernelway" "${KERNELWAY}" "${USER_CONFIG_FILE}"
      NEXT="e"
      ;;
    m)
      [ "${NOTSETMACS}" = "false" ] && NOTSETMACS='true' || NOTSETMACS='false'
      writeConfigKey "notsetmacs" "${NOTSETMACS}" "${USER_CONFIG_FILE}"
      NEXT="e"
      ;;
    u)
      editUserConfig
      NEXT="e"
      ;;
    t) tryRecoveryDSM ;;
    s)
      MSG=""
      NUMPORTS=0
      [ $(lspci -d ::106 | wc -l) -gt 0 ] && MSG+="\nATA:\n"
      for PCI in $(lspci -d ::106 | awk '{print $1}'); do
        NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
        MSG+="\Zb${NAME}\Zn\nPorts: "
        PORTS=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
        for P in ${PORTS}; do
          if lsscsi -b | grep -v - | grep -q "\[${P}:"; then
            DUMMY="$([ "$(cat /sys/class/scsi_host/host${P}/ahci_port_cmd)" = "0" ] && echo 1 || echo 2)"
            if [ "$(cat /sys/class/scsi_host/host${P}/ahci_port_cmd)" = "0" ]; then
              MSG+="\Z1$(printf "%02d" ${P})\Zn "
            else
              MSG+="\Z2$(printf "%02d" ${P})\Zn "
            fi
          else
            MSG+="$(printf "%02d" ${P}) "
          fi
          NUMPORTS=$((${NUMPORTS} + 1))
        done
        MSG+="\n"
      done
      [ $(lspci -d ::107 | wc -l) -gt 0 ] && MSG+="\nLSI:\n"
      for PCI in $(lspci -d ::107 | awk '{print $1}'); do
        NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
        PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
        PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
        MSG+="\Zb${NAME}\Zn\nNumber: ${PORTNUM}\n"
        NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
      done
      [ $(ls -l /sys/class/scsi_host | grep usb | wc -l) -gt 0 ] && MSG+="\nUSB:\n"
      for PCI in $(lspci -d ::c03 | awk '{print $1}'); do
        NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
        PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
        PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
        [ ${PORTNUM} -eq 0 ] && continue
        MSG+="\Zb${NAME}\Zn\nNumber: ${PORTNUM}\n"
        NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
      done
      [ $(lspci -d ::108 | wc -l) -gt 0 ] && MSG+="\nNVME:\n"
      for PCI in $(lspci -d ::108 | awk '{print $1}'); do
        NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
        PORT=$(ls -l /sys/class/nvme | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/nvme//' | sort -n)
        PORTNUM=$(lsscsi -b | grep -v - | grep "\[N:${PORT}:" | wc -l)
        MSG+="\Zb${NAME}\Zn\nNumber: ${PORTNUM}\n"
        NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
      done
      MSG+="\n"
      MSG+="$(printf "$(TEXT "\nTotal of ports: %s\n")" "${NUMPORTS}")"
      MSG+="$(TEXT "\nPorts with color \Z1red\Zn as DUMMY, color \Z2\Zbgreen\Zn has drive connected.")"
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
        --msgbox "${MSG}" 0 0
      ;;
    c)
      PATURL="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
      PATSUM="$(readConfigKey "patsum" "${USER_CONFIG_FILE}")"
      MSG="$(TEXT "pat: (editable)")"
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
        --form "${MSG}" 10 110 2 "URL" 1 1 "${PATURL}" 1 5 100 0 "MD5" 2 1 "${PATSUM}" 2 5 100 0 \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && return
      paturl="$(cat "${TMP_PATH}/resp" | tail -n +1 | head -1)"
      patsum="$(cat "${TMP_PATH}/resp" | tail -n +2 | head -1)"
      if [ ! ${paturl} = ${PATURL} ] || [ ! ${patsum} = ${PATSUM} ]; then
        writeConfigKey "paturl" "${paturl}" "${USER_CONFIG_FILE}"
        writeConfigKey "patsum" "${patsum}" "${USER_CONFIG_FILE}"
        rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
        DIRTY=1
      fi
      ;;
    a)
      MSG=""
      MSG+="$(TEXT "This feature will allow you to downgrade the installation by removing the VERSION file from the first partition of all disks.\n")"
      MSG+="$(TEXT "Therefore, please insert all disks before continuing.\n")"
      MSG+="$(TEXT "Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?")"
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
        --yesno "${MSG}" 0 0
      [ $? -ne 0 ] && return
      (
        mkdir -p "${TMP_PATH}/sdX1"
        for I in $(ls /dev/sd*1 2>/dev/null | grep -v "${LOADER_DISK}1"); do
          mount "${I}" "${TMP_PATH}/sdX1"
          [ -f "${TMP_PATH}/sdX1/etc/VERSION" ] && rm -f "${TMP_PATH}/sdX1/etc/VERSION"
          [ -f "${TMP_PATH}/sdX1/etc.defaults/VERSION" ] && rm -f "${TMP_PATH}/sdX1/etc.defaults/VERSION"
          sync
          umount "${I}"
        done
        rm -rf "${TMP_PATH}/sdX1"
      ) | dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
        --progressbox "$(TEXT "Removing ...")" 20 70
      MSG="$(TEXT "Remove VERSION file for all disks completed.")"
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
        --msgbox "${MSG}" 0 0
      ;;
    f)
      rm -f "${TMP_PATH}/opts"
      while read POSITION NAME; do
        [ -z "${POSITION}" -o -z "${NAME}" ] && continue
        echo "${POSITION}" | grep -q "${LOADER_DEVICE_NAME}" && continue
        echo "\"${POSITION}\" \"${NAME}\" \"off\"" >>"${TMP_PATH}/opts"
      done < <(ls -l /dev/disk/by-id/ | sed 's|../..|/dev|g' | grep -E "/dev/sd|/dev/nvme" | awk -F' ' '{print $NF" "$(NF-2)}' | sort -uk 1,1)
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
        --checklist "$(TEXT "Advanced")" 0 0 0 --file "${TMP_PATH}/opts" \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && return
      RESP=$(<"${TMP_PATH}/resp")
      [ -z "${RESP}" ] && return
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
        --yesno "$(TEXT "Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?")" 0 0
      [ $? -ne 0 ] && return
      if [ $(ls /dev/md* | wc -l) -gt 0 ]; then
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
          --yesno "$(TEXT "Warning:\nThe current hds is in raid, do you still want to format them?")" 0 0
        [ $? -ne 0 ] && return
        for I in $(ls /dev/md*); do
          mdadm -S "${I}"
        done
      fi
      (
        for I in ${RESP}; do
          mkfs.ext4 -T largefile4 "${I}"
        done
      ) | dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
        --progressbox "$(TEXT "Formatting ...")" 20 70
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
        --msgbox "$(TEXT "Formatting is complete.")" 0 0
      ;;
    x)
      SHADOW_FILE=""
      mkdir -p "${TMP_PATH}/sdX1"
      for I in $(ls /dev/sd*1 2>/dev/null | grep -v "${LOADER_DISK}1"); do
        mount ${I} "${TMP_PATH}/sdX1"
        if [ -f "${TMP_PATH}/sdX1/etc/shadow" ]; then
          cp "${TMP_PATH}/sdX1/etc/shadow" "${TMP_PATH}/shadow_bak"
          SHADOW_FILE="${TMP_PATH}/shadow_bak"
        fi
        umount "${I}"
        [ -n "${SHADOW_FILE}" ] && break
      done
      rm -rf "${TMP_PATH}/sdX1"
      if [ -z "${SHADOW_FILE}" ]; then
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
          --msgbox "$(TEXT "The installed Syno system not found in the currently inserted disks!")" 0 0
        return
      fi
      ITEMS="$(cat "${SHADOW_FILE}" | awk -F ':' '{if ($2 != "*" && $2 != "!!") {print $1;}}')"
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
        --no-items --menu "$(TEXT "Choose a user name")" 0 0 0 ${ITEMS} \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && return
      USER="$(<${TMP_PATH}/resp)"
      [ -z "${USER}" ] && return
      OLDPASSWD="$(cat "${SHADOW_FILE}" | grep "^${USER}:" | awk -F ':' '{print $2}')"
      while true; do
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
          --inputbox "$(printf "$(TEXT "Type a new password for user '%s'")" "${USER}")" 0 0 "${CMDLINE[${NAME}]}" \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && break 2
        VALUE="$(<"${TMP_PATH}/resp")"
        [ -n "${VALUE}" ] && break
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
          --msgbox "$(TEXT "Invalid password")" 0 0
      done
      NEWPASSWD="$(python -c "import crypt,getpass;pw=\"${VALUE}\";print(crypt.crypt(pw))")"
      (
        mkdir -p "${TMP_PATH}/sdX1"
        for I in $(ls /dev/sd*1 2>/dev/null | grep -v ${LOADER_DISK}1); do
          mount "${I}" "${TMP_PATH}/sdX1"
          sed -i "s|${OLDPASSWD}|${NEWPASSWD}|g" "${TMP_PATH}/sdX1/etc/shadow"
          sync
          umount "${I}"
        done
        rm -rf "${TMP_PATH}/sdX1"
      ) | dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
        --progressbox "$(TEXT "Resetting ...")" 20 70
      [ -f "${SHADOW_FILE}" ] && rm -rf "${SHADOW_FILE}"
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
        --msgbox "$(TEXT "Password reset completed.")" 0 0
      # dialog --backtitle "`backtitle`" --title "$(TEXT "Advanced")" \
      #   --msgbox "$(TEXT "You came early, this function has not been implemented yet, hahaha!")" 0 0
      ;;
    p)
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
        --yesno "$(TEXT "Warning:\nDo not terminate midway, otherwise it may cause damage to the arpl. Do you want to continue?")" 0 0
      [ $? -ne 0 ] && return
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
        --infobox "$(TEXT "Saving ...")" 0 0
      RDXZ_PATH="${TMP_PATH}/rdxz_tmp"
      mkdir -p "${RDXZ_PATH}"
      (
        cd "${RDXZ_PATH}"
        xz -dc <"${ARPL_RAMDISK_FILE}" | cpio -idm
      ) >/dev/null 2>&1 || true
      rm -rf "${RDXZ_PATH}/opt/arpl"
      cp -rf "/opt" "${RDXZ_PATH}/"
      (
        cd "${RDXZ_PATH}"
        find . 2>/dev/null | cpio -o -H newc -R root:root | xz --check=crc32 >"${ARPL_RAMDISK_FILE}"
      ) || true
      rm -rf "${RDXZ_PATH}"
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
        --msgbox ""$(TEXT "Save is complete.")"" 0 0
      ;;
    d)
      if ! tty | grep -q "/dev/pts"; then
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
          --msgbox "$(TEXT "This feature is only available when accessed via web/ssh.")" 0 0
        return
      fi
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
        --msgbox "$(TEXT "Currently, only dts format files are supported. Please prepare and click to confirm uploading.\n(saved in /mnt/p3/users/)")" 0 0
      TMP_UP_PATH="${TMP_PATH}/users"
      rm -rf "${TMP_UP_PATH}"
      mkdir -p "${TMP_UP_PATH}"
      pushd "${TMP_UP_PATH}"
      rz -be
      for F in $(ls -A); do
        USER_FILE="${TMP_UP_PATH}/${F}"
        dtc -q -I dts -O dtb "${F}" >"test.dtb"
        RET=$?
        break
      done
      popd
      if [ ${RET} -ne 0 -o -z "${USER_FILE}" ]; then
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
          --msgbox "$(TEXT "Not a valid dts file, please try again!")" 0 0
      else
        [ -d "{USER_UP_PATH}" ] || mkdir -p "${USER_UP_PATH}"
        cp -f "${USER_FILE}" "${USER_UP_PATH}/${MODEL}.dts"
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
          --msgbox "$(TEXT "A valid dts file, Automatically import at compile time.")" 0 0
      fi
      DIRTY=1
      ;;
    b)
      if ! tty | grep -q "/dev/pts"; then
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
          --msgbox "$(TEXT "This feature is only available when accessed via web/ssh.")" 0 0
        return
      fi
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
        --yesno "$(TEXT "Warning:\nDo not terminate midway, otherwise it may cause damage to the arpl. Do you want to continue?")" 0 0
      [ $? -ne 0 ] && return
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
        --infobox "$(TEXT "Backuping...")" 0 0
      rm -f /var/www/data/backup.img.gz # thttpd root path
      dd if="${LOADER_DISK}" bs=1M conv=fsync | gzip >/var/www/data/backup.img.gz
      if [ $? -ne 0]; then
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
          --msgbox "$(TEXT "Failed to generate backup. There may be insufficient memory. Please clear the cache and try again!")" 0 0
        return
      fi
      if [ -z "${SSH_TTY}" ]; then # web
        IP_HEAD="$(ip route show 2>/dev/null | sed -n 's/.* via .* src \(.*\)  metric .*/\1/p' | head -1)"
        echo "http://${IP_HEAD}/backup.img.gz" >${TMP_PATH}/resp
        echo "            ↑                  " >>${TMP_PATH}/resp
        echo "$(TEXT "Click on the address above to download.")" >>${TMP_PATH}/resp
        echo "$(TEXT "Please confirm the completion of the download before closing this window.")" >>${TMP_PATH}/resp
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
          --editbox "${TMP_PATH}/resp" 10 100
      else # ssh
        sz -be /var/www/data/backup.img.gz
      fi
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
        --msgbox "$(TEXT "backup is complete.")" 0 0
      rm -f /var/www/data/backup.img.gz
      ;;
    r)
      if ! tty | grep -q "/dev/pts"; then
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
          --msgbox "$(TEXT "This feature is only available when accessed via web/ssh.")" 0 0
        return
      fi
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
        --yesno "$(TEXT "Please upload the backup file.\nCurrently, zip(github) and img.gz(backup) compressed file formats are supported.")" 0 0
      [ $? -ne 0 ] && return
      IFTOOL=""
      TMP_UP_PATH="${TMP_PATH}/users"
      rm -rf "${TMP_UP_PATH}"
      mkdir -p "${TMP_UP_PATH}"
      pushd "${TMP_UP_PATH}"
      rz -be
      for F in $(ls -A); do
        USER_FILE="${F}"
        [ "${F##*.}" = "zip" -a $(unzip -l "${TMP_UP_PATH}/${USER_FILE}" | grep -c "\.img$") -eq 1 ] && IFTOOL="zip"
        [ "${F##*.}" = "gz" -a "${F#*.}" = "img.gz" ] && IFTOOL="gzip"
        break
      done
      popd
      if [ -z "${IFTOOL}" -o -z "${TMP_UP_PATH}/${USER_FILE}" ]; then
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
          --msgbox "$(printf "$(TEXT "Not a valid .zip/.img.gz file, please try again!")" "${USER_FILE}")" 0 0
      else
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
          --yesno "$(TEXT "Warning:\nDo not terminate midway, otherwise it may cause damage to the arpl. Do you want to continue?")" 0 0
        [ $? -ne 0 ] && (
          rm -f "${LOADER_DISK}"
          return
        )
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
          --infobox "$(TEXT "Writing...")" 0 0
        umount "${BOOTLOADER_PATH}" "${SLPART_PATH}" "${CACHE_PATH}"
        if [ "${IFTOOL}" = "zip" ]; then
          unzip -p "${TMP_UP_PATH}/${USER_FILE}" | dd of="${LOADER_DISK}" bs=1M conv=fsync
        elif [ "${IFTOOL}" = "gzip" ]; then
          gzip -dc "${TMP_UP_PATH}/${USER_FILE}" | dd of="${LOADER_DISK}" bs=1M conv=fsync
        fi
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
          --yesno "$(printf "$(TEXT "Restore bootloader disk with success to %s!\nReboot?")" "${USER_FILE}")" 0 0
        [ $? -ne 0 ] && continue
        reboot
        exit
      fi
      ;;
    o)
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
        --yesno "$(TEXT "This option only installs opkg package management, allowing you to install more tools for use and debugging. Do you want to continue?")" 0 0
      [ $? -ne 0 ] && return
      (
        wget -O - http://bin.entware.net/x64-k3.2/installer/generic.sh | /bin/sh
        sed -i 's|:/opt/arpl|:/opt/bin:/opt/arpl|' ~/.bashrc
        source ~/.bashrc
        opkg update
        #opkg install python3 python3-pip
      ) | dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
        --progressbox "$(TEXT "opkg installing ...")" 20 70
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Advanced")" \
        --msgbox "$(TEXT "opkg install is complete. Please reconnect to SSH/web, or execute 'source ~/.bashrc'")" 0 0
      ;;
    g)
      [ "${DSMLOGO}" = "true" ] && DSMLOGO='false' || DSMLOGO='true'
      writeConfigKey "dsmlogo" "${DSMLOGO}" "${USER_CONFIG_FILE}"
      NEXT="e"
      ;;
    e) break ;;
    esac
  done
}

###############################################################################
# Try to recovery a DSM already installed
function tryRecoveryDSM() {
  dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Try recovery DSM")" \
    --infobox "$(TEXT "Trying to recovery a DSM installed system")" 0 0
  if findAndMountDSMRoot; then
    MODEL=""
    PRODUCTVER=""
    BUILDNUM=""
    SMALLNUM=""
    if [ -f "${DSMROOT_PATH}/.syno/patch/VERSION" ]; then
      eval $(cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep unique)
      eval $(cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep majorversion)
      eval $(cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep minorversion)
      eval $(cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep buildnumber)
      eval $(cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep smallfixnumber)
      if [ -n "${unique}" ]; then
        while read F; do
          M="$(basename ${F})"
          M="${M::-4}"
          UNIQUE=$(readModelKey "${M}" "unique")
          [ "${unique}" = "${UNIQUE}" ] || continue
          # Found
          modelMenu "${M}"
        done < <(find "${MODEL_CONFIG_PATH}" -maxdepth 1 -name \*.yml | sort)
        if [ -n "${MODEL}" ]; then
          productversMenu "${majorversion}.${minorversion}"
          if [ -n "${PRODUCTVER}" ]; then
            cp "${DSMROOT_PATH}/.syno/patch/zImage" "${SLPART_PATH}"
            cp "${DSMROOT_PATH}/.syno/patch/rd.gz" "${SLPART_PATH}"
            MSG="$(printf "$(TEXT "Found a installation:\nModel: %s\nProductversion: %s")" "${MODEL}" "${PRODUCTVER}")"
            SN=$(_get_conf_kv SN "${DSMROOT_PATH}/etc/synoinfo.conf")
            if [ -n "${SN}" ]; then
              writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
              MSG+="$(printf "$(TEXT "\nSerial: %s")" "${SN}")"
            fi
            BUILDNUM=${buildnumber}
            SMALLNUM=${smallfixnumber}
            writeConfigKey "buildnum" "${BUILDNUM}" "${USER_CONFIG_FILE}"
            writeConfigKey "smallnum" "${SMALLNUM}" "${USER_CONFIG_FILE}"
            dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Try recovery DSM")" \
              --msgbox "${MSG}" 0 0
          fi
        fi
      fi
    fi
  else
    dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Try recovery DSM")" \
      --msgbox "$(TEXT "Unfortunately I couldn't mount the DSM partition!")" 0 0
  fi
}

###############################################################################
# Permits user edit the user config
function editUserConfig() {
  while true; do
    dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Edit with caution")" \
      --editbox "${USER_CONFIG_FILE}" 0 0 2>"${TMP_PATH}/userconfig"
    [ $? -ne 0 ] && return
    mv "${TMP_PATH}/userconfig" "${USER_CONFIG_FILE}"
    ERRORS=$(yq eval "${USER_CONFIG_FILE}" 2>&1)
    [ $? -eq 0 ] && break
    dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Edit with caution")" \
      --msgbox "${ERRORS}" 0 0
  done
  OLDMODEL=${MODEL}
  OLDPRODUCTVER=${PRODUCTVER}
  OLDBUILDNUM=${BUILDNUM}
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
  SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"

  if [ "${MODEL}" != "${OLDMODEL}" -o "${PRODUCTVER}" != "${OLDPRODUCTVER}" -o "${BUILDNUM}" != "${OLDBUILDNUM}" ]; then
    # Remove old files
    rm -f "${MOD_ZIMAGE_FILE}"
    rm -f "${MOD_RDGZ_FILE}"
  fi
  DIRTY=1
}

###############################################################################
# Calls boot.sh to boot into DSM kernel/ramdisk
function boot() {
  [ ${DIRTY} -eq 1 ] && dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Alert")" \
    --yesno "$(TEXT "Config changed, would you like to rebuild the loader?")" 0 0
  if [ $? -eq 0 ]; then
    make || return
  fi
  boot.sh
}

###############################################################################
# Shows language to user choose one
function languageMenu() {
  ITEMS="$(ls /usr/share/locale)"
  dialog --backtitle "$(backtitle)" --colors \
    --default-item "${LAYOUT}" --no-items --menu "$(TEXT "Choose a language")" 0 0 0 ${ITEMS} 2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  resp=$(cat ${TMP_PATH}/resp 2>/dev/null)
  [ -z "${resp}" ] && return
  LANGUAGE=${resp}
  echo "${LANGUAGE}.UTF-8" >${BOOTLOADER_PATH}/.locale
  export LANG="${LANGUAGE}.UTF-8"
}

###############################################################################
# Shows available keymaps to user choose one
function keymapMenu() {
  OPTIONS="azerty bepo carpalx colemak dvorak fgGIod neo olpc qwerty qwertz"
  dialog --backtitle "$(backtitle)" --colors \
    --default-item "${LAYOUT}" --no-items --menu "$(TEXT "Choose a layout")" 0 0 0 ${OPTIONS} \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  LAYOUT="$(<${TMP_PATH}/resp)"
  OPTIONS=""
  while read KM; do
    OPTIONS+="${KM::-7} "
  done < <(
    cd /usr/share/keymaps/i386/${LAYOUT}
    ls *.map.gz
  )
  dialog --backtitle "$(backtitle)" --colors \
    --default-item "${KEYMAP}" --no-items --menu "$(TEXT "Choice a keymap")" 0 0 0 ${OPTIONS} \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  resp=$(cat ${TMP_PATH}/resp 2>/dev/null)
  [ -z "${resp}" ] && return
  KEYMAP=${resp}
  writeConfigKey "layout" "${LAYOUT}" "${USER_CONFIG_FILE}"
  writeConfigKey "keymap" "${KEYMAP}" "${USER_CONFIG_FILE}"
  loadkeys /usr/share/keymaps/i386/${LAYOUT}/${KEYMAP}.map.gz
}

# 1 - ext name
# 2 - current version
# 3 - repo url
# 4 - attachment name
# 5 - silent
function downloadExts() {
  PROXY="$(readConfigKey "proxy" "${USER_CONFIG_FILE}")"
  [ -n "${PROXY}" ] && [[ "${PROXY: -1}" != "/" ]] && PROXY="${PROXY}/"
  T="$(printf "$(TEXT "Update %s")" "${1}")"

  dialog --backtitle "$(backtitle)" --colors --title "${T}" \
    --infobox "$(TEXT "Checking last version")" 0 0
  if [ "${PRERELEASE}" = "true" ]; then
    TAG="$(curl -skL "${PROXY}${3}/tags" | grep /refs/tags/.*\.zip | head -1 | sed -r 's/.*\/refs\/tags\/(.*)\.zip.*$/\1/')"
  else
    # TAG=`curl -skL "${PROXY}https://api.github.com/repos/wjz304/arpl-addons/releases/latest" | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`
    # In the absence of authentication, the default API access count for GitHub is 60 per hour, so removing the use of api.github.com
    LATESTURL="$(curl -skL -w %{url_effective} -o /dev/null "${PROXY}${3}/releases/latest")"
    TAG="${LATESTURL##*/}"
  fi
  [ "${TAG:0:1}" = "v" ] && TAG="${TAG:1}"
  if [ -z "${TAG}" -o "${TAG}" = "latest" ]; then
    if [ ! "${5}" = "0" ]; then
      dialog --backtitle "$(backtitle)" --colors --title "${T}" \
        --infobox "$(TEXT "Error checking new version")" 0 0
    else
      dialog --backtitle "$(backtitle)" --colors --title "${T}" \
        --msgbox "$(TEXT "Error checking new version")" 0 0
    fi
    return 1
  fi
  if [ "${2}" = "${TAG}" ]; then
    if [ ! "${5}" = "0" ]; then
      dialog --backtitle "$(backtitle)" --colors --title "${T}" \
        --infobox "$(TEXT "No new version.")" 0 0
      return 1
    else
      dialog --backtitle "$(backtitle)" --colors --title "${T}" \
        --yesno "$(printf "$(TEXT "No new version. Actual version is %s\nForce update?")" "${2}")" 0 0
      [ $? -ne 0 ] && return 1
    fi
  fi
  dialog --backtitle "$(backtitle)" --colors --title "${T}" \
    --infobox "$(TEXT "Downloading last version")" 0 0
  rm -f "${TMP_PATH}/${4}.zip"
  STATUS=$(curl -kL -w "%{http_code}" "${PROXY}${3}/releases/download/${TAG}/${4}.zip" -o "${TMP_PATH}/${4}.zip")
  if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
    if [ ! "${5}" = "0" ]; then
      dialog --backtitle "$(backtitle)" --colors --title "${T}" \
        --infobox "$(TEXT "Error downloading new version")" 0 0
    else
      dialog --backtitle "$(backtitle)" --colors --title "${T}" \
        --msgbox "$(TEXT "Error downloading new version")" 0 0
    fi
    return 1
  fi
  return 0
}

# 1 - ext name
function updateArpl() {
  T="$(printf "$(TEXT "Update %s")" "${1}")"
  dialog --backtitle "$(backtitle)" --colors --title "${T}" \
    --infobox "$(TEXT "Extracting last version")" 0 0
  unzip -oq "${TMP_PATH}/update.zip" -d "${TMP_PATH}/"
  if [ $? -ne 0 ]; then
    dialog --backtitle "$(backtitle)" --colors --title "${T}" \
      --msgbox "$(TEXT "Error extracting update file")" 0 0
    return 1
  fi
  # Check checksums
  (cd /tmp && sha256sum --status -c sha256sum)
  if [ $? -ne 0 ]; then
    dialog --backtitle "$(backtitle)" --colors --title "${T}" \
      --msgbox "$(TEXT "Checksum do not match!")" 0 0
    return 1
  fi
  # Check conditions
  if [ -f "${TMP_PATH}/update-check.sh" ]; then
    chmod +x "${TMP_PATH}/update-check.sh"
    ${TMP_PATH}/update-check.sh
    if [ $? -ne 0 ]; then
      dialog --backtitle "$(backtitle)" --colors --title "${T}" \
        --msgbox "$(TEXT "The current version does not support upgrading to the latest update.zip. Please remake the bootloader disk!")" 0 0
      return 1
    fi
  fi
  dialog --backtitle "$(backtitle)" --colors --title "${T}" \
    --infobox "$(TEXT "Installing new files")" 0 0
  # Process update-list.yml
  while read F; do
    [ -f "${F}" ] && rm -f "${F}"
    [ -d "${F}" ] && rm -Rf "${F}"
  done < <(readConfigArray "remove" "${TMP_PATH}/update-list.yml")
  while IFS=': ' read KEY VALUE; do
    if [ "${KEY: -1}" = "/" ]; then
      rm -Rf "${VALUE}"
      mkdir -p "${VALUE}"
      tar -zxf "${TMP_PATH}/$(basename "${KEY}").tgz" -C "${VALUE}"
    else
      mkdir -p "$(dirname "${VALUE}")"
      mv "${TMP_PATH}/$(basename "${KEY}")" "${VALUE}"
    fi
  done < <(readConfigMap "replace" "${TMP_PATH}/update-list.yml")
  dialog --backtitle "$(backtitle)" --colors --title "${T}" \
    --msgbox "$(printf "$(TEXT "Arpl updated with success to %s!\nReboot?")" "${TAG}")" 0 0
  arpl-reboot.sh config
}

# 1 - ext name
# 2 - silent
function updateExts() {
  T="$(printf "$(TEXT "Update %s")" "${1}")"
  dialog --backtitle "$(backtitle)" --colors --title "${T}" \
    --infobox "$(TEXT "Extracting last version")" 0 0
  if [ "${1}" = "addons" ]; then
    rm -rf "${TMP_PATH}/addons"
    mkdir -p "${TMP_PATH}/addons"
    unzip "${TMP_PATH}/addons.zip" -d "${TMP_PATH}/addons" >/dev/null 2>&1
    dialog --backtitle "$(backtitle)" --colors --title "${T}" \
      --infobox "$(printf "$(TEXT "Installing new %s")" "${1}")" 0 0
    rm -Rf "${ADDONS_PATH}/"*
    [ -f "${TMP_PATH}/addons/VERSION" ] && cp -f "${TMP_PATH}/addons/VERSION" "${ADDONS_PATH}/"
    for PKG in $(ls ${TMP_PATH}/addons/*.addon); do
      ADDON=$(basename ${PKG} | sed 's|.addon||')
      rm -rf "${ADDONS_PATH}/${ADDON}"
      mkdir -p "${ADDONS_PATH}/${ADDON}"
      tar -xaf "${PKG}" -C "${ADDONS_PATH}/${ADDON}" >/dev/null 2>&1
    done
  elif [ "${1}" = "modules" ]; then
    rm "${MODULES_PATH}/"*
    unzip ${TMP_PATH}/modules.zip -d "${MODULES_PATH}" >/dev/null 2>&1
    # Rebuild modules if model/buildnumber is selected
    PLATFORM="$(readModelKey "${MODEL}" "platform")"
    KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
    KPRE="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kpre")"
    if [ -n "${PLATFORM}" -a -n "${KVER}" ]; then
      writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
      while read ID DESC; do
        writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
      done < <(getAllModules "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}")
    fi
  elif [ "${1}" = "LKMs" ]; then
    rm -rf "${LKM_PATH}/"*
    unzip "${TMP_PATH}/rp-lkms.zip" -d "${LKM_PATH}" >/dev/null 2>&1
  fi
  DIRTY=1
  if [ ! "${2}" = "0" ]; then
    dialog --backtitle "$(backtitle)" --colors --title "${T}" \
      --infobox "$(printf "$(TEXT "%s updated with success!")" "${1}")" 0 0
  else
    dialog --backtitle "$(backtitle)" --colors --title "${T}" \
      --msgbox "$(printf "$(TEXT "%s updated with success!")" "${1}")" 0 0
  fi
}

###############################################################################
function updateMenu() {
  PROXY="$(readConfigKey "proxy" "${USER_CONFIG_FILE}")"
  [ -n "${PROXY}" ] && [[ "${PROXY: -1}" != "/" ]] && PROXY="${PROXY}/"
  while true; do
    rm "${TMP_PATH}/menu"
    echo "a \"$(TEXT "Update all")\"" >>"${TMP_PATH}/menu"
    echo "r \"$(TEXT "Update arpl")\"" >>"${TMP_PATH}/menu"
    echo "d \"$(TEXT "Update addons")\"" >>"${TMP_PATH}/menu"
    echo "m \"$(TEXT "Update modules")\"" >>"${TMP_PATH}/menu"
    echo "l \"$(TEXT "Update LKMs")\"" >>"${TMP_PATH}/menu"
    if [ -n "${DEBUG}" ]; then
      echo "p \"$(TEXT "Set proxy server")\"" >>"${TMP_PATH}/menu"
    fi
    echo "u \"$(TEXT "Local upload")\"" >>"${TMP_PATH}/menu"
    echo "b \"$(TEXT "Pre Release:") \Z4${PRERELEASE}\Zn\"" >>"${TMP_PATH}/menu"
    echo "e \"$(TEXT "Exit")\"" >>"${TMP_PATH}/menu"

    dialog --backtitle "$(backtitle)" --colors \
      --menu "$(TEXT "Choose a option")" 0 0 0 --file "${TMP_PATH}/menu" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "$(<${TMP_PATH}/resp)" in
    a)
      T="$(printf "$(TEXT "Update %s")" "$(TEXT "addons")")"
      CURVER="$(cat "${CACHE_PATH}/addons/VERSION" 2>/dev/null)"
      downloadExts "addons" "${CURVER:-0}" "https://github.com/wjz304/arpl-addons" "addons" "1"
      [ $? -eq 0 ] && updateExts "addons" "1"
      T="$(printf "$(TEXT "Update %s")" "$(TEXT "modules")")"
      CURVER="$(cat "${CACHE_PATH}/modules/VERSION" 2>/dev/null)"
      downloadExts "modules" "${CURVER:-0}" "https://github.com/wjz304/arpl-modules" "modules" "1"
      [ $? -eq 0 ] && updateExts "modules" "1"
      T="$(printf "$(TEXT "Update %s")" "$(TEXT "LKMs")")"
      CURVER="$(cat "${CACHE_PATH}/lkms/VERSION" 2>/dev/null)"
      downloadExts "LKMs" "${CURVER:-0}" "https://github.com/wjz304/redpill-lkm" "rp-lkms" "1"
      [ $? -eq 0 ] && updateExts "LKMs" "1"
      T="$(printf "$(TEXT "Update %s")" "$(TEXT "arpl")")"
      CURVER="${ARPL_VERSION:-0}"
      downloadExts "arpl" "${CURVER}" "https://github.com/wjz304/arpl-i18n" "update" "0"
      [ $? -ne 0 ] && continue
      updateArpl "arpl"
      ;;

    r)
      T="$(printf "$(TEXT "Update %s")" "$(TEXT "arpl")")"
      CURVER="${ARPL_VERSION:-0}"
      downloadExts "arpl" "${CURVER}" "https://github.com/wjz304/arpl-i18n" "update" "0"
      [ $? -ne 0 ] && continue
      updateArpl "arpl"
      ;;

    d)
      T="$(printf "$(TEXT "Update %s")" "$(TEXT "addons")")"
      CURVER="$(cat "${CACHE_PATH}/addons/VERSION" 2>/dev/null)"
      downloadExts "addons" "${CURVER:-0}" "https://github.com/wjz304/arpl-addons" "addons" "0"
      [ $? -ne 0 ] && continue
      updateExts "addons" "0"
      ;;

    m)
      T="$(printf "$(TEXT "Update %s")" "$(TEXT "modules")")"
      CURVER="$(cat "${CACHE_PATH}/modules/VERSION" 2>/dev/null)"
      downloadExts "modules" "${CURVER:-0}" "https://github.com/wjz304/arpl-modules" "modules" "0"
      [ $? -ne 0 ] && continue
      updateExts "modules" "0"
      ;;

    l)
      T="$(printf "$(TEXT "Update %s")" "$(TEXT "LKMs")")"
      CURVER="$(cat "${CACHE_PATH}/lkms/VERSION" 2>/dev/null)"
      downloadExts "LKMs" "${CURVER:-0}" "https://github.com/wjz304/redpill-lkm" "rp-lkms" "0"
      [ $? -ne 0 ] && continue
      updateExts "LKMs" "0"
      ;;

    p)
      RET=1
      while true; do
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Update")" \
          --inputbox "$(TEXT "Please enter a proxy server url")" 0 0 "${PROXY}" \
          2>${TMP_PATH}/resp
        RET=$?
        [ ${RET} -ne 0 ] && break
        PROXY=$(cat ${TMP_PATH}/resp)
        if [ -z "${PROXYSERVER}" ]; then
          break
        elif [[ "${PROXYSERVER}" =~ "^(https?|ftp)://[^\s/$.?#].[^\s]*$" ]]; then
          break
        else
          dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Update")" \
            --yesno "$(TEXT "Invalid proxy server url, continue?")" 0 0
          RET=$?
          [ ${RET} -eq 0 ] && break
        fi
      done
      [ ${RET} -eq 0 ] && writeConfigKey "proxy" "${PROXY}" "${USER_CONFIG_FILE}"
      ;;

    u)
      if ! tty | grep -q "/dev/pts"; then
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Update")" \
          --msgbox "$(TEXT "This feature is only available when accessed via web/ssh.")" 0 0
        return
      fi
      MSG=""
      MSG+="$(TEXT "Please keep the attachment name consistent with the attachment name on Github.\n")"
      MSG+="$(TEXT "Upload update.zip will update arpl.\n")"
      MSG+="$(TEXT "Upload addons.zip will update Addons.\n")"
      MSG+="$(TEXT "Upload modules.zip will update Modules.\n")"
      MSG+="$(TEXT "Upload rp-lkms.zip will update LKMs.\n")"
      dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Update")" \
        --msgbox "${MSG}" 0 0
      EXTS=("update.zip" "addons.zip" "modules.zip" "rp-lkms.zip")
      TMP_UP_PATH="${TMP_PATH}/users"
      USER_FILE=""
      rm -rf "${TMP_UP_PATH}"
      mkdir -p "${TMP_UP_PATH}"
      pushd "${TMP_UP_PATH}"
      rz -be
      for F in $(ls -A); do
        for I in ${EXTS[@]}; do
          [[ "${I}" == "${F}" ]] && USER_FILE="${F}"
        done
        break
      done
      popd
      if [ -z "${USER_FILE}" ]; then
        dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Update")" \
          --msgbox "$(TEXT "Not a valid file, please try again!")" 0 0
      else
        rm "${TMP_PATH}/${USER_FILE}"
        mv "${TMP_UP_PATH}/${USER_FILE}" "${TMP_PATH}/${USER_FILE}"
        if [ "${USER_FILE}" = "update.zip" ]; then
          updateArpl "arpl"
        elif [ "${USER_FILE}" = "addons.zip" ]; then
          updateExts "addons" "0"
        elif [ "${USER_FILE}" = "modules.zip" ]; then
          updateExts "modules" "0"
        elif [ "${USER_FILE}" = "rp-lkms.zip" ]; then
          updateExts "LKMs" "0"
        else
          dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Update")" \
            --msgbox "$(TEXT "Not a valid file, please try again!")" 0 0
        fi
      fi
      ;;
    b)
      [ "${PRERELEASE}" = "false" ] && PRERELEASE='true' || PRERELEASE='false'
      writeConfigKey "prerelease" "${PRERELEASE}" "${USER_CONFIG_FILE}"
      NEXT="e"
      ;;
    e) return ;;
    esac
  done
}

function notepadMenu() {
  [ -d "${USER_UP_PATH}" ] || mkdir -p "${USER_UP_PATH}"
  [ -f "${USER_UP_PATH}/notepad" ] || echo "$(TEXT "This person is very lazy and hasn't written anything.")" >"${USER_UP_PATH}/notepad"
  dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Edit")" \
    --editbox "${USER_UP_PATH}/notepad" 0 0 2>"${TMP_PATH}/notepad"
  [ $? -ne 0 ] && return
  mv "${TMP_PATH}/notepad" "${USER_UP_PATH}/notepad"
}

###############################################################################
###############################################################################

if [ "x$1" = "xb" -a -n "${MODEL}" -a -n "${PRODUCTVER}" -a loaderIsConfigured ]; then
  install-addons.sh
  make
  boot && exit 0 || sleep 5
fi
# Main loop
[ -n "${MODEL}" ] && NEXT="v" || NEXT="m"
while true; do
  echo "m \"$(TEXT "Choose a model")\"" >"${TMP_PATH}/menu"
  if [ -n "${MODEL}" ]; then
    echo "n \"$(TEXT "Choose a version")\"" >>"${TMP_PATH}/menu"
    if [ -n "${PRODUCTVER}" ]; then
      echo "a \"$(TEXT "Addons menu")\"" >>"${TMP_PATH}/menu"
      echo "o \"$(TEXT "Modules menu")\"" >>"${TMP_PATH}/menu"
      echo "x \"$(TEXT "Cmdline menu")\"" >>"${TMP_PATH}/menu"
      echo "i \"$(TEXT "Synoinfo menu")\"" >>"${TMP_PATH}/menu"
    fi
  fi
  echo "v \"$(TEXT "Advanced menu")\"" >>"${TMP_PATH}/menu"
  if [ -n "${MODEL}" ]; then
    if [ -n "${PRODUCTVER}" ]; then
      echo "d \"$(TEXT "Build the loader")\"" >>"${TMP_PATH}/menu"
    fi
  fi
  if loaderIsConfigured; then
    echo "b \"$(TEXT "Boot the loader")\"" >>"${TMP_PATH}/menu"
  fi
  echo "l \"$(TEXT "Choose a language")\"" >>"${TMP_PATH}/menu"
  echo "k \"$(TEXT "Choose a keymap")\"" >>"${TMP_PATH}/menu"
  if [ ${CLEARCACHE} -eq 1 -a -d "${CACHE_PATH}/dl" ]; then
    echo "c \"$(TEXT "Clean disk cache")\"" >>"${TMP_PATH}/menu"
  fi
  echo "p \"$(TEXT "Update menu")\"" >>"${TMP_PATH}/menu"
  echo "t \"$(TEXT "Notepad")\"" >>"${TMP_PATH}/menu"
  echo "e \"$(TEXT "Exit")\"" >>"${TMP_PATH}/menu"

  dialog --backtitle "$(backtitle)" --colors \
    --default-item ${NEXT} --menu "$(TEXT "Choose the option")" 0 0 0 --file "${TMP_PATH}/menu" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && break
  case $(<"${TMP_PATH}/resp") in
  m)
    modelMenu
    NEXT="n"
    ;;
  n)
    productversMenu
    NEXT="d"
    ;;
  a)
    addonMenu
    NEXT="d"
    ;;
  o)
    moduleMenu
    NEXT="d"
    ;;
  x)
    cmdlineMenu
    NEXT="d"
    ;;
  i)
    synoinfoMenu
    NEXT="d"
    ;;
  v)
    advancedMenu
    NEXT="d"
    ;;
  d)
    make
    NEXT="b"
    ;;
  b)
    boot && exit 0 || sleep 5
    ;;
  l)
    languageMenu
    NEXT="m"
    ;;
  k)
    keymapMenu
    NEXT="m"
    ;;
  c)
    dialog --backtitle "$(backtitle)" --colors --title "$(TEXT "Cleaning")" \
      --prgbox "rm -rfv \"${CACHE_PATH}/dl\"" 0 0
    NEXT="d"
    ;;
  p)
    updateMenu
    NEXT="d"
    ;;
  t)
    notepadMenu
    NEXT="d"
    ;;
  e)
    NEXT="e"
    while true; do
      dialog --backtitle "$(backtitle)" --colors \
        --default-item ${NEXT} --menu "$(TEXT "Choose a action")" 0 0 0 \
        p "$(TEXT "Poweroff")" \
        r "$(TEXT "Reboot")" \
        c "$(TEXT "Reboot to arpl")" \
        s "$(TEXT "Back to shell")" \
        e "$(TEXT "Exit")" \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && break
      case "$(<${TMP_PATH}/resp)" in
      p)
        poweroff
        ;;
      r)
        reboot
        ;;
      c)
        arpl-reboot.sh config
        ;;
      s)
        break 2
        ;;
      e)
        break
        ;;
      esac
    done
    ;;
  esac
done
clear
echo -e "$(TEXT "Call \033[1;32mmenu.sh\033[0m to return to menu")"
