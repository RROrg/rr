#!/usr/bin/env bash

[ -z "${WORK_PATH}" -o ! -d "${WORK_PATH}/include" ] && WORK_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. ${WORK_PATH}/include/functions.sh
. ${WORK_PATH}/include/addons.sh
. ${WORK_PATH}/include/modules.sh

[ -z "${LOADER_DISK}" ] && die "$(TEXT "Loader is not init!")"

alias DIALOG='dialog --backtitle "$(backtitle)" --colors --aspect 50'

# Check partition 3 space, if < 2GiB is necessary clean cache folder
CLEARCACHE=0
if [ $(cat "/sys/block/${LOADER_DISK/\/dev\//}/${LOADER_DISK_PART3/\/dev\//}/size") -lt 4194304 ]; then
  CLEARCACHE=1
fi

# Get actual IP
IP="$(getIP)"

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
PRERELEASE="$(readConfigKey "prerelease" "${USER_CONFIG_FILE}")"
BOOTWAIT="$(readConfigKey "bootwait" "${USER_CONFIG_FILE}")"
BOOTIPWAIT="$(readConfigKey "bootipwait" "${USER_CONFIG_FILE}")"
KERNELWAY="$(readConfigKey "kernelway" "${USER_CONFIG_FILE}")"
KERNELPANIC="$(readConfigKey "kernelpanic" "${USER_CONFIG_FILE}")"
ODP="$(readConfigKey "odp" "${USER_CONFIG_FILE}")" # official drivers priorities
HDDSORT="$(readConfigKey "hddsort" "${USER_CONFIG_FILE}")"
SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"
MAC1="$(readConfigKey "mac1" "${USER_CONFIG_FILE}")"
MAC2="$(readConfigKey "mac2" "${USER_CONFIG_FILE}")"

PROXY=$(readConfigKey "global_proxy" "${USER_CONFIG_FILE}")
if [ -n "${PROXY}" ]; then
  export http_proxy="${PROXY}"
  export https_proxy="${PROXY}"
fi

###############################################################################
# Mounts backtitle dynamically
function backtitle() {
  BACKTITLE="${RR_TITLE}"
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
    DIALOG --title "$(TEXT "Model")" \
      --infobox "$(TEXT "Reading models")" 0 0
    echo -n "" >"${TMP_PATH}/modellist"
    while read M; do
      Y=$(echo ${M} | tr -cd "[0-9]")
      Y=${Y:0-2}
      echo "${M} ${Y}" >>"${TMP_PATH}/modellist"
    done < <(find "${WORK_PATH}/model-configs" -maxdepth 1 -name \*.yml | sed 's/.*\///; s/\.yml//')

    while true; do
      echo -n "" >"${TMP_PATH}/menu"
      echo "c \"\Z1$(TEXT "Compatibility judgment")\Zn\"" >>"${TMP_PATH}/menu"
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
        [ ${COMPATIBLE} -eq 1 ] && echo "${M} \"$(printf "\Zb%-15s %-2s\Zn" "${PLATFORM}" "${DT}")\" " >>"${TMP_PATH}/menu"
      done < <(cat "${TMP_PATH}/modellist" | sort -r -n -k 2)
      [ ${FLGNEX} -eq 1 ] && echo "f \"\Z1$(TEXT "Disable flags restriction")\Zn\"" >>"${TMP_PATH}/menu"
      [ ${FLGBETA} -eq 0 ] && echo "b \"\Z1$(TEXT "Show all models")\Zn\"" >>"${TMP_PATH}/menu"
      DIALOG --title "$(TEXT "Model")" \
        --menu "$(TEXT "Choose the model")" 0 0 0 --file "${TMP_PATH}/menu" \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && return
      resp=$(<${TMP_PATH}/resp)
      [ -z "${resp}" ] && return
      if [ "${resp}" = "c" ]; then
        models=(DS918+ RS1619xs+ DS419+ DS1019+ DS719+ DS1621xs+)
        [ $(lspci -d ::300 | grep 8086 | wc -l) -gt 0 ] && iGPU=1 || iGPU=0
        [ $(lspci -d ::107 | wc -l) -gt 0 ] && LSI=1 || LSI=0
        [ $(lspci -d ::108 | wc -l) -gt 0 ] && NVME=1 || NVME=0
        if [ "${NVME}" = "1" ]; then
          for PCI in $(lspci -d ::108 | awk '{print $1}'); do
            if [ ! -d "/sys/devices/pci0000:00/0000:${PCI}/nvme" ]; then
              NVME=2
              break
            fi
          done
        fi
        rm -f "${TMP_PATH}/opts"
        echo "$(printf "%-16s %8s %8s %8s" "model" "iGPU" "HBA" "M.2")" >>"${TMP_PATH}/opts"
        while read M Y; do
          PLATFORM=$(readModelKey "${M}" "platform")
          DT="$(readModelKey "${M}" "dt")"
          I915=" "
          HBA=" "
          M_2=" "
          if [ "${iGPU}" = "1" ]; then
            [ "${PLATFORM}" = "apollolake" -o "${PLATFORM}" = "geminilake" -o "${PLATFORM}" = "epyc7002" ] && I915="*"
          fi
          if [ "${LSI}" = "1" ]; then
            [ ! "${DT}" = "true" -o "${PLATFORM}" = "epyc7002" ] && HBA="*   "
          fi
          if [ "${NVME}" = "1" ]; then
            [ "${DT}" = "true" ] && M_2="*   "
          fi
          if [ "${NVME}" = "2" ]; then
            if echo ${models[@]} | grep -q ${M}; then
              M_2="*   "
            fi
          fi
          echo "$(printf "%-16s %8s %8s %8s" "${M}" "${I915}" "${HBA}" "${M_2}")" >>"${TMP_PATH}/opts"
        done < <(cat "${TMP_PATH}/modellist" | sort -r -n -k 2)
        DIALOG --title "$(TEXT "Model")" \
          --textbox "${TMP_PATH}/opts" 0 0
        continue
      fi
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
    NETIF_NUM=2
    MACS=($(generateMacAddress "${MODEL}" ${NETIF_NUM}))
    for I in $(seq 1 ${NETIF_NUM}); do
      writeConfigKey "mac${I}" "${MACS[$((${I} - 1))]}" "${USER_CONFIG_FILE}"
    done
    touch ${PART1_PATH}/.build
  fi
}

###############################################################################
# Shows available buildnumbers from a model to user choose one
function productversMenu() {
  ITEMS="$(readConfigEntriesArray "productvers" "${WORK_PATH}/model-configs/${MODEL}.yml" | sort -r)"
  if [ -z "${1}" ]; then
    DIALOG --title "$(TEXT "Product Version")" \
      --no-items --menu "$(TEXT "Choose a product version")" 0 0 0 ${ITEMS} \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    resp=$(<${TMP_PATH}/resp)
    [ -z "${resp}" ] && return
  else
    if ! arrayExistItem "${1}" ${ITEMS}; then return; fi
    resp="${1}"
  fi
  if [ "${PRODUCTVER}" = "${resp}" ]; then
    DIALOG --title "$(TEXT "Product Version")" \
      --yesno "$(printf "$(TEXT "The current version has been set to %s. Do you want to reset the version?")" "${PRODUCTVER}")" 0 0
    [ $? -ne 0 ] && return
  fi
  local KVER=$(readModelKey "${MODEL}" "productvers.[${resp}].kver")
  if [ -d "/sys/firmware/efi" -a "${KVER:0:1}" = "3" ]; then
    DIALOG --title "$(TEXT "Product Version")" \
      --msgbox "$(TEXT "This version does not support UEFI startup, Please select another version or switch the startup mode.")" 0 0
    return
  fi
  # if [ ! "usb" = "$(getBus "${LOADER_DISK}")" -a "${KVER:0:1}" = "5" ]; then
  #   DIALOG --title "$(TEXT "Product Version")" \
  #     --msgbox "$(TEXT "This version only support usb startup, Please select another version or switch the startup mode.")" 0 0
  #   # return
  # fi
  while true; do
    # get online pat data
    DIALOG --title "$(TEXT "Product Version")" \
      --infobox "$(TEXT "Get pat data ...")" 0 0
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
    DIALOG --title "$(TEXT "Product Version")" \
      --extra-button --extra-label "$(TEXT "Retry")" \
      --form "${MSG}" 10 110 2 "URL" 1 1 "${paturl}" 1 5 100 0 "MD5" 2 1 "${patsum}" 2 5 100 0 \
      2>"${TMP_PATH}/resp"
    RET=$?
    [ ${RET} -eq 0 ] && break    # ok-button
    [ ${RET} -eq 3 ] && continue # extra-button
    return                       # 1 or 255  # cancel-button or ESC
  done
  paturl="$(cat "${TMP_PATH}/resp" | sed -n '1p')"
  patsum="$(cat "${TMP_PATH}/resp" | sed -n '2p')"
  [ -z "${paturl}" -o -z "${patsum}" ] && return
  writeConfigKey "paturl" "${paturl}" "${USER_CONFIG_FILE}"
  writeConfigKey "patsum" "${patsum}" "${USER_CONFIG_FILE}"
  PRODUCTVER=${resp}
  writeConfigKey "productver" "${PRODUCTVER}" "${USER_CONFIG_FILE}"
  BUILDNUM=""
  SMALLNUM=""
  writeConfigKey "buildnum" "${BUILDNUM}" "${USER_CONFIG_FILE}"
  writeConfigKey "smallnum" "${SMALLNUM}" "${USER_CONFIG_FILE}"
  DIALOG --title "$(TEXT "Product Version")" \
    --infobox "$(TEXT "Reconfiguring Synoinfo, Addons and Modules")" 0 0
  # Delete synoinfo and reload model/build synoinfo
  writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
  while IFS=': ' read KEY VALUE; do
    writeConfigKey "synoinfo.\"${KEY}\"" "${VALUE}" "${USER_CONFIG_FILE}"
  done < <(readModelMap "${MODEL}" "productvers.[${PRODUCTVER}].synoinfo")
  # Check addons
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  KPRE="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kpre")"
  while IFS=': ' read ADDON PARAM; do
    [ -z "${ADDON}" ] && continue
    if ! checkAddonExist "${ADDON}" "${PLATFORM}" "${KVER}"; then
      deleteConfigKey "addons.\"${ADDON}\"" "${USER_CONFIG_FILE}"
    fi
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")
  # Rebuild modules
  writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
  while read ID DESC; do
    writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
  done < <(getAllModules "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}")
  # Remove old files
  rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
  touch ${PART1_PATH}/.build
}

###############################################################################
# Manage addons
function addonMenu() {
  # Read 'platform' and kernel version to check if addon exists
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  KPRE="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kpre")"

  NEXT="a"
  # Loop menu
  while true; do
    # Read addons from user config
    unset ADDONS
    declare -A ADDONS
    while IFS=': ' read KEY VALUE; do
      [ -n "${KEY}" ] && ADDONS["${KEY}"]="${VALUE}"
    done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")

    DIALOG --title "$(TEXT "Addons")" \
      --default-item ${NEXT} --menu "$(TEXT "Choose a option")" 0 0 0 \
      a "$(TEXT "Add an addon")" \
      d "$(TEXT "Delete addons")" \
      m "$(TEXT "Show all addons")" \
      o "$(TEXT "Upload a external addon")" \
      e "$(TEXT "Exit")" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "$(<${TMP_PATH}/resp)" in
    a)
      NEXT='a'
      rm -f "${TMP_PATH}/menu"
      while read ADDON DESC; do
        arrayExistItem "${ADDON}" "${!ADDONS[@]}" && continue # Check if addon has already been added
        echo "${ADDON} \"${DESC}\"" >>"${TMP_PATH}/menu"
      done < <(availableAddons "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}")
      if [ ! -f "${TMP_PATH}/menu" ]; then
        DIALOG --title "$(TEXT "Addons")" \
          --msgbox "$(TEXT "No available addons to add")" 0 0
        NEXT="e"
        continue
      fi
      DIALOG --title "$(TEXT "Addons")" \
        --menu "$(TEXT "Select an addon")" 0 0 0 --file "${TMP_PATH}/menu" \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && continue
      ADDON="$(<"${TMP_PATH}/resp")"
      [ -z "${ADDON}" ] && continue
      DIALOG --title "$(TEXT "Addons")" \
        --inputbox "$(TEXT "Type a optional params to addon")" 0 70 \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && continue
      VALUE="$(<"${TMP_PATH}/resp")"
      ADDONS[${ADDON}]="${VALUE}"
      writeConfigKey "addons.\"${ADDON}\"" "${VALUE}" "${USER_CONFIG_FILE}"
      touch ${PART1_PATH}/.build
      ;;
    d)
      NEXT='d'
      if [ ${#ADDONS[@]} -eq 0 ]; then
        DIALOG --title "$(TEXT "Addons")" \
          --msgbox "$(TEXT "No user addons to remove")" 0 0
        continue
      fi
      rm -f "${TMP_PATH}/opts"
      for I in "${!ADDONS[@]}"; do
        echo "\"${I}\" \"${I}\" \"off\"" >>"${TMP_PATH}/opts"
      done
      DIALOG --title "$(TEXT "Addons")" \
        --no-tags --checklist "$(TEXT "Select addon to remove")" 0 0 0 --file "${TMP_PATH}/opts" \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && continue
      ADDON="$(<"${TMP_PATH}/resp")"
      [ -z "${ADDON}" ] && continue
      for I in ${ADDON}; do
        unset ADDONS[${I}]
        deleteConfigKey "addons.\"${I}\"" "${USER_CONFIG_FILE}"
      done
      touch ${PART1_PATH}/.build
      ;;
    m)
      NEXT='m'
      MSG=""
      MSG+="$(TEXT "Name with color \"\Z4blue\Zn\" have been added, with color \"black\" are not added.\n\n")"
      while read MODULE DESC; do
        if arrayExistItem "${MODULE}" "${!ADDONS[@]}"; then
          MSG+="\Z4${MODULE}\Zn"
        else
          MSG+="${MODULE}"
        fi
        MSG+=": \Z5${DESC}\Zn\n"
      done < <(availableAddons "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}")
      DIALOG --title "$(TEXT "Addons")" \
        --msgbox "${MSG}" 0 0
      ;;
    o)
      if ! tty | grep -q "/dev/pts"; then
        DIALOG --title "$(TEXT "Addons")" \
          --msgbox "$(TEXT "This feature is only available when accessed via web/ssh.")" 0 0
        return
      fi
      DIALOG --title "$(TEXT "Addons")" \
        --msgbox "$(TEXT "Please upload the *.addons file.")" 0 0
      TMP_UP_PATH=${TMP_PATH}/users
      USER_FILE=""
      rm -rf ${TMP_UP_PATH}
      mkdir -p ${TMP_UP_PATH}
      pushd ${TMP_UP_PATH}
      rz -be -B 536870912
      for F in $(ls -A); do
        USER_FILE=${F}
        break
      done
      popd
      if [ -z "${USER_FILE}" ]; then
        DIALOG --title "$(TEXT "Addons")" \
          --msgbox "$(TEXT "Not a valid file, please try again!")" 0 0
      else
        if [ -d "${ADDONS_PATH}/$(basename ${USER_FILE} .addons)" ]; then
          DIALOG --title "$(TEXT "Addons")" \
            --yesno "$(TEXT "The addon already exists. Do you want to overwrite it?")" 0 0
          RET=$?
          [ ${RET} -eq 0 ] && return
        fi
        ADDON="$(untarAddon "${TMP_UP_PATH}/${USER_FILE}")"
        if [ -n "${ADDON}" ]; then
          [ -f "${PART3_PATH}/addons/VERSION" ] && rm -f "${PART3_PATH}/addons/VERSION"
          DIALOG --title "$(TEXT "Addons")" \
            --msgbox "$(printf "$(TEXT "Addon '%s' added to loader, Please enable it in 'Add an addon' menu.")" "${ADDON}")" 0 0
        else
          DIALOG --title "$(TEXT "Addons")" \
            --msgbox "$(TEXT "File format not recognized!")" 0 0
        fi
      fi
      ;;
    e)
      return
      ;;
    esac
  done
}
###############################################################################
function moduleMenu() {
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  KPRE="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kpre")"
  NEXT="c"
  # loop menu
  while true; do
    DIALOG --title "$(TEXT "Modules")" \
      --default-item ${NEXT} --menu "$(TEXT "Choose a option")" 0 0 0 \
      c "$(TEXT "Show/Select modules")" \
      l "$(TEXT "Select loaded modules")" \
      o "$(TEXT "Upload a external module")" \
      p "$(TEXT "Priority use of official drivers:") \Z4${ODP}\Zn" \
      e "$(TEXT "Exit")" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && break
    case "$(<${TMP_PATH}/resp)" in
    c)
      while true; do
        DIALOG --title "$(TEXT "Modules")" \
          --infobox "$(TEXT "Reading modules ...")" 0 0
        ALLMODULES=$(getAllModules "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}")
        unset USERMODULES
        declare -A USERMODULES
        while IFS=': ' read KEY VALUE; do
          [ -n "${KEY}" ] && USERMODULES["${KEY}"]="${VALUE}"
        done < <(readConfigMap "modules" "${USER_CONFIG_FILE}")
        rm -f "${TMP_PATH}/opts"
        while read ID DESC; do
          arrayExistItem "${ID}" "${!USERMODULES[@]}" && ACT="on" || ACT="off"
          echo "${ID} ${DESC} ${ACT}" >>"${TMP_PATH}/opts"
        done <<<${ALLMODULES}
        DIALOG --title "$(TEXT "Modules")" \
          --extra-button --extra-label "$(TEXT "Select all")" \
          --help-button --help-label "$(TEXT "Deselect all")" \
          --checklist "$(TEXT "Select modules to include")" 0 0 0 --file "${TMP_PATH}/opts" \
          2>${TMP_PATH}/resp
        RET=$?
        case ${RET} in
        0) # ok-button
          resp=$(<${TMP_PATH}/resp)
          writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
          for ID in ${resp}; do
            writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
          done
          touch ${PART1_PATH}/.build
          break
          ;;
        3) # extra-button
          writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
          while read ID DESC; do
            writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
          done <<<${ALLMODULES}
          touch ${PART1_PATH}/.build
          ;;
        2) # help-button
          writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
          touch ${PART1_PATH}/.build
          ;;
        1) # cancel-button
          break
          ;;
        255) # ESC
          break
          ;;
        esac
      done
      ;;
    l)
      DIALOG --title "$(TEXT "Modules")" \
        --infobox "$(TEXT "Selecting loaded modules")" 0 0
      KOLIST=""
      for I in $(lsmod | awk -F' ' '{print $1}' | grep -v 'Module'); do
        KOLIST+="$(getdepends "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}" "${I}") ${I} "
      done
      KOLIST=($(echo ${KOLIST} | tr ' ' '\n' | sort -u))
      writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
      for ID in ${KOLIST[@]}; do
        writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
      done
      touch ${PART1_PATH}/.build
      ;;
    o)
      if ! tty | grep -q "/dev/pts"; then
        DIALOG --title "$(TEXT "Modules")" \
          --msgbox "$(TEXT "This feature is only available when accessed via web/ssh.")" 0 0
        return
      fi
      MSG=""
      MSG+="$(TEXT "This function is experimental and dangerous. If you don't know much, please exit.\n")"
      MSG+="$(TEXT "The imported .ko of this function will be implanted into the corresponding arch's modules package, which will affect all models of the arch.\n")"
      MSG+="$(TEXT "This program will not determine the availability of imported modules or even make type judgments, as please double check if it is correct.\n")"
      MSG+="$(TEXT "If you want to remove it, please go to the \"Update Menu\" -> \"Update modules\" to forcibly update the modules. All imports will be reset.\n")"
      MSG+="$(TEXT "Do you want to continue?")"
      DIALOG --title "$(TEXT "Modules")" \
        --yesno "${MSG}" 0 0
      [ $? -ne 0 ] && return
      DIALOG --title "$(TEXT "Modules")" \
        --msgbox "$(TEXT "Please upload the *.ko file.")" 0 0
      TMP_UP_PATH=${TMP_PATH}/users
      USER_FILE=""
      rm -rf ${TMP_UP_PATH}
      mkdir -p ${TMP_UP_PATH}
      pushd ${TMP_UP_PATH}
      rz -be -B 536870912
      for F in $(ls -A); do
        USER_FILE=${F}
        break
      done
      popd
      if [ -n "${USER_FILE}" -a "${USER_FILE##*.}" = "ko" ]; then
        addToModules ${PLATFORM} "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}" "${TMP_UP_PATH}/${USER_FILE}"
        [ -f "${PART3_PATH}/modules/VERSION" ] && rm -f "${PART3_PATH}/modules/VERSION"
        DIALOG --title "$(TEXT "Modules")" \
          --msgbox "$(printf "$(TEXT "Module '%s' added to %s-%s")" "${USER_FILE}" "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}")" 0 0
        rm -f "${TMP_UP_PATH}/${USER_FILE}"
      else
        DIALOG --title "$(TEXT "Modules")" \
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
  # Loop menu
  while true; do
    echo "a \"$(TEXT "Add/Edit a cmdline item")\"" >"${TMP_PATH}/menu"
    echo "d \"$(TEXT "Show/Delete cmdline items")\"" >>"${TMP_PATH}/menu"
    if [ -n "${MODEL}" ]; then
      echo "s \"$(TEXT "Define SN/MAC")\"" >>"${TMP_PATH}/menu"
    fi
    echo "m \"$(TEXT "Show model inherent cmdline")\"" >>"${TMP_PATH}/menu"
    echo "e \"$(TEXT "Exit")\"" >>"${TMP_PATH}/menu"
    DIALOG --title "$(TEXT "Cmdline")" \
      --menu "$(TEXT "Choose a option")" 0 0 0 --file "${TMP_PATH}/menu" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "$(<${TMP_PATH}/resp)" in
    a)
      MSG=""
      MSG+="$(TEXT "Commonly used cmdlines:\n")"
      MSG+="$(TEXT " * \Z4disable_mtrr_trim=\Zn\n    disables kernel trim any uncacheable memory out.\n")"
      MSG+="$(TEXT " * \Z4intel_idle.max_cstate=1\Zn\n    Set the maximum C-state depth allowed by the intel_idle driver.\n")"
      MSG+="$(TEXT " * \Z4SataPortMap=??\Zn\n    Sata Port Map.\n")"
      MSG+="$(TEXT " * \Z4DiskIdxMap=??\Zn\n    Disk Index Map, Modify disk name sequence.\n")"
      MSG+="$(TEXT " * \Z4i915.enable_guc=2\Zn\n    Enable the GuC firmware on Intel graphics hardware.(value: 1,2 or 3)\n")"
      MSG+="$(TEXT " * \Z4i915.max_vfs=7\Zn\n     Set the maximum number of virtual functions (VFs) that can be created for Intel graphics hardware.\n")"
      MSG+="$(TEXT "\nEnter the parameter name and value you need to add.\n")"
      LINENUM=$(($(echo -e "${MSG}" | wc -l) + 8))
      while true; do
        DIALOG --title "$(TEXT "Cmdline")" \
          --form "${MSG}" ${LINENUM:-16} 70 2 "Name:" 1 1 "" 1 10 55 0 "Value:" 2 1 "" 2 10 55 0 \
          2>"${TMP_PATH}/resp"
        RET=$?
        case ${RET} in
        0) # ok-button
          NAME="$(cat "${TMP_PATH}/resp" | sed -n '1p')"
          VALUE="$(cat "${TMP_PATH}/resp" | sed -n '2p')"
          if [ -z "${NAME//\"/}" ]; then
            DIALOG --title "$(TEXT "Cmdline")" \
              --yesno "$(TEXT "Invalid parameter name, retry?")" 0 0
            [ $? -eq 0 ] && break
          fi
          writeConfigKey "cmdline.\"${NAME//\"/}\"" "${VALUE}" "${USER_CONFIG_FILE}"
          break
          ;;
        1) # cancel-button
          break
          ;;
        255) # ESC
          break
          ;;
        esac
      done
      ;;
    d)
      # Read cmdline from user config
      unset CMDLINE
      declare -A CMDLINE
      while IFS=': ' read KEY VALUE; do
        [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
      done < <(readConfigMap "cmdline" "${USER_CONFIG_FILE}")
      if [ ${#CMDLINE[@]} -eq 0 ]; then
        DIALOG --title "$(TEXT "Cmdline")" \
          --msgbox "$(TEXT "No user cmdline to remove")" 0 0
        continue
      fi
      rm -f "${TMP_PATH}/opts"
      for I in "${!CMDLINE[@]}"; do
        echo "\"${I}\" \"${CMDLINE[${I}]}\" \"off\"" >>"${TMP_PATH}/opts"
      done
      DIALOG --title "$(TEXT "Cmdline")" \
        --checklist "$(TEXT "Select cmdline to remove")" 0 0 0 --file "${TMP_PATH}/opts" \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && continue
      RESP=$(<"${TMP_PATH}/resp")
      [ -z "${RESP}" ] && continue
      for I in ${RESP}; do
        unset CMDLINE[${I}]
        deleteConfigKey "cmdline.\"${I}\"" "${USER_CONFIG_FILE}"
      done
      ;;
    s)
      MSG="$(TEXT "Note: (MAC will not be set to NIC)")"
      sn="${SN}"
      mac1="${MAC1}"
      mac2="${MAC2}"
      while true; do
        DIALOG --title "$(TEXT "Cmdline")" \
          --extra-button --extra-label "$(TEXT "Random")" \
          --form "${MSG}" 11 60 3 "sn" 1 1 "${sn}" 1 5 50 0 "mac1" 2 1 "${mac1}" 2 5 50 0 "mac2" 3 1 "${mac2}" 3 5 50 0 \
          2>"${TMP_PATH}/resp"
        RET=$?
        case ${RET} in
        0) # ok-button
          sn="$(cat "${TMP_PATH}/resp" | sed -n '1p')"
          mac1="$(cat "${TMP_PATH}/resp" | sed -n '2p')"
          mac2="$(cat "${TMP_PATH}/resp" | sed -n '3p')"
          if [ -z "${sn}" -o -z "${mac1}" ]; then
            DIALOG --title "$(TEXT "Cmdline")" \
              --yesno "$(TEXT "Invalid SN/MAC, retry?")" 0 0
            [ $? -eq 0 ] && break
          fi
          SN="${sn}"
          writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
          MAC1="${mac1}"
          writeConfigKey "mac1" "${MAC1}" "${USER_CONFIG_FILE}"
          MAC2="${mac2}"
          writeConfigKey "mac2" "${MAC2}" "${USER_CONFIG_FILE}"
          break
          ;;
        3) # extra-button
          sn=$(generateSerial "${MODEL}")
          MACS=($(generateMacAddress "${MODEL}" 2))
          mac1=${MACS[0]}
          mac2=${MACS[1]}
          ;;
        1) # cancel-button
          break
          ;;
        255) # ESC
          break
          ;;
        esac
      done
      ;;
    m)
      ITEMS=""
      while IFS=': ' read KEY VALUE; do
        ITEMS+="${KEY}: ${VALUE}\n"
      done < <(readModelMap "${MODEL}" "productvers.[${PRODUCTVER}].cmdline")
      DIALOG --title "$(TEXT "Cmdline")" \
        --msgbox "${ITEMS}" 0 0
      ;;
    e) return ;;
    esac
  done
}

###############################################################################
function synoinfoMenu() {
  # Loop menu
  while true; do
    echo "a \"$(TEXT "Add/edit a synoinfo item")\"" >"${TMP_PATH}/menu"
    echo "d \"$(TEXT "Show/Delete synoinfo items")\"" >>"${TMP_PATH}/menu"
    echo "e \"$(TEXT "Exit")\"" >>"${TMP_PATH}/menu"
    DIALOG --title "$(TEXT "Synoinfo")" \
      --menu "$(TEXT "Choose a option")" 0 0 0 --file "${TMP_PATH}/menu" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "$(<${TMP_PATH}/resp)" in
    a)
      MSG=""
      MSG+="$(TEXT "Commonly used synoinfo:\n")"
      MSG+="$(TEXT " * \Z4maxdisks=??\Zn\n    Maximum number of disks supported.\n")"
      MSG+="$(TEXT " * \Z4internalportcfg=0x????\Zn\n    Internal(sata) disks mask.\n")"
      MSG+="$(TEXT " * \Z4esataportcfg=0x????\Zn\n    Esata disks mask.\n")"
      MSG+="$(TEXT " * \Z4usbportcfg=0x????\Zn\n    USB disks mask.\n")"
      MSG+="$(TEXT "\nEnter the parameter name and value you need to add.\n")"
      LINENUM=$(($(echo -e "${MSG}" | wc -l) + 8))
      while true; do
        DIALOG --title "$(TEXT "Synoinfo")" \
          --form "${MSG}" ${LINENUM:-16} 70 2 "Name:" 1 1 "" 1 10 55 0 "Value:" 2 1 "" 2 10 55 0 \
          2>"${TMP_PATH}/resp"
        RET=$?
        case ${RET} in
        0) # ok-button
          NAME="$(cat "${TMP_PATH}/resp" | sed -n '1p')"
          VALUE="$(cat "${TMP_PATH}/resp" | sed -n '2p')"
          if [ -z "${NAME//\"/}" ]; then
            DIALOG --title "$(TEXT "Synoinfo")" \
              --yesno "$(TEXT "Invalid parameter name, retry?")" 0 0
            [ $? -eq 0 ] && break
          fi
          writeConfigKey "synoinfo.\"${NAME//\"/}\"" "${VALUE}" "${USER_CONFIG_FILE}"
          touch ${PART1_PATH}/.build
          break
          ;;
        1) # cancel-button
          break
          ;;
        255) # ESC
          break
          ;;
        esac
      done
      ;;
    d)
      # Read synoinfo from user config
      unset SYNOINFO
      declare -A SYNOINFO
      while IFS=': ' read KEY VALUE; do
        [ -n "${KEY}" ] && SYNOINFO["${KEY}"]="${VALUE}"
      done < <(readConfigMap "synoinfo" "${USER_CONFIG_FILE}")
      if [ ${#SYNOINFO[@]} -eq 0 ]; then
        DIALOG --title "$(TEXT "Synoinfo")" \
          --msgbox "$(TEXT "No synoinfo entries to remove")" 0 0
        continue
      fi
      rm -f "${TMP_PATH}/opts"
      for I in ${!SYNOINFO[@]}; do
        echo "\"${I}\" \"${SYNOINFO[${I}]}\" \"off\"" >>"${TMP_PATH}/opts"
      done
      DIALOG --title "$(TEXT "Synoinfo")" \
        --checklist "$(TEXT "Select synoinfo entry to remove")" 0 0 0 --file "${TMP_PATH}/opts" \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && continue
      RESP=$(<"${TMP_PATH}/resp")
      [ -z "${RESP}" ] && continue
      for I in ${RESP}; do
        unset SYNOINFO[${I}]
        deleteConfigKey "synoinfo.\"${I}\"" "${USER_CONFIG_FILE}"
      done
      touch ${PART1_PATH}/.build
      ;;
    e) return ;;
    esac
  done
}

###############################################################################
# Extract linux and ramdisk files from the DSM .pat
function extractDsmFiles() {
  MKERR_FILE="${1:-"${TMP_PATH}/makeerror.log"}"
  PATURL="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
  PATSUM="$(readConfigKey "patsum" "${USER_CONFIG_FILE}")"

  # Check disk space left
  SPACELEFT=$(df --block-size=1 | grep ${LOADER_DISK_PART3} | awk '{print $4}')

  PAT_FILE="${MODEL}-${PRODUCTVER}.pat"
  PAT_PATH="${PART3_PATH}/dl/${PAT_FILE}"
  EXTRACTOR_PATH="${PART3_PATH}/extractor"
  EXTRACTOR_BIN="syno_extract_system_patch"
  OLDPATURL="https://global.synologydownload.com/download/DSM/release/7.0.1/42218/DSM_DS3622xs%2B_42218.pat"

  if [ -f "${PAT_PATH}" ]; then
    echo "$(printf "$(TEXT "%s cached.")" "${PAT_FILE}")"
  else
    # If we have little disk space, clean cache folder
    if [ ${CLEARCACHE} -eq 1 ]; then
      echo "$(TEXT "Cleaning cache ...")"
      rm -rf "${PART3_PATH}/dl"
    fi
    mkdir -p "${PART3_PATH}/dl"
    mirrors=("global.synologydownload.com" "global.download.synology.com" "cndl.synology.cn")
    fastest=$(_get_fastest ${mirrors[@]})
    mirror="$(echo ${PATURL} | sed 's|^http[s]*://\([^/]*\).*|\1|')"
    if echo "${mirrors[@]}" | grep -wq "${mirror}" && [ "${mirror}" != "${fastest}" ]; then
      echo "$(printf "$(TEXT "Based on the current network situation, switch to %s mirror to downloading.")" "${fastest}")"
      PATURL="$(echo ${PATURL} | sed "s/${mirror}/${fastest}/")"
      OLDPATURL="https://${fastest}/download/DSM/release/7.0.1/42218/DSM_DS3622xs%2B_42218.pat"
    fi
    echo "$(printf "$(TEXT "Downloading %s ...")" "${PAT_FILE}")"
    # Discover remote file size
    FILESIZE=$(curl -k -sLI "${PATURL}" | grep -i Content-Length | awk '{print$2}')
    if [ 0${FILESIZE} -ge 0${SPACELEFT} ]; then
      # No disk space to download, change it to RAMDISK
      PAT_PATH="${TMP_PATH}/${PAT_FILE}"
    fi
    STATUS=$(curl -k -w "%{http_code}" -L "${PATURL}" -o "${PAT_PATH}")
    RET=$?
    if [ ${RET} -ne 0 -o ${STATUS} -ne 200 ]; then
      rm -f "${PAT_PATH}"
      MSG="$(printf "$(TEXT "Check internet or cache disk space.\nError: %d:%d")" "${RET}" "${STATUS}")"
      echo -e "${MSG}" >"${MKERR_FILE}"
      return 1
    fi
  fi

  echo -n "$(printf "$(TEXT "Checking hash of %s: ")" "${PAT_FILE}")"
  if [ "$(md5sum ${PAT_PATH} | awk '{print $1}')" != "${PATSUM}" ]; then
    rm -f ${PAT_PATH}
    echo -e "$(TEXT "md5 hash of pat not match, Please reget pat data from the version menu and try again!")" >"${MKERR_FILE}"
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
    echo -e "$(TEXT "Could not determine if pat file is encrypted or not, maybe corrupted, try again!")" >"${MKERR_FILE}"
    return 1
    ;;
  esac

  SPACELEFT=$(df --block-size=1 | grep ${LOADER_DISK_PART3} | awk '{print $4}') # Check disk space left

  if [ "${isencrypted}" = "yes" ]; then
    # Check existance of extractor
    if [ -f "${EXTRACTOR_PATH}/${EXTRACTOR_BIN}" ]; then
      echo "$(TEXT "Extractor cached.")"
    else
      # Extractor not exists, get it.
      mkdir -p "${EXTRACTOR_PATH}"
      # Check if old pat already downloaded
      OLDPAT_PATH="${PART3_PATH}/dl/DS3622xs+-42218.pat"
      if [ ! -f "${OLDPAT_PATH}" ]; then
        echo "$(TEXT "Downloading old pat to extract synology .pat extractor...")"
        # Discover remote file size
        FILESIZE=$(curl -k -sLI "${OLDPATURL}" | grep -i Content-Length | awk '{print$2}')
        if [ 0${FILESIZE} -ge 0${SPACELEFT} ]; then
          # No disk space to download, change it to RAMDISK
          OLDPAT_PATH="${TMP_PATH}/DS3622xs+-42218.pat"
        fi
        STATUS=$(curl -k -w "%{http_code}" -L "${OLDPATURL}" -o "${OLDPAT_PATH}")
        RET=$?
        if [ ${RET} -ne 0 -o ${STATUS} -ne 200 ]; then
          rm -f "${OLDPAT_PATH}"
          MSG="$(printf "$(TEXT "Check internet or cache disk space.\nError: %d:%d")" "${RET}" "${STATUS}")"
          echo -e "${MSG}" >"${MKERR_FILE}"
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
        echo -e "${LOG_FILE}" >"${MKERR_FILE}"
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
        cp -f "${RAMDISK_PATH}/usr/lib/${f}" "${EXTRACTOR_PATH}"
      done
      cp -f "${RAMDISK_PATH}/usr/syno/bin/scemd" "${EXTRACTOR_PATH}/${EXTRACTOR_BIN}"
      rm -rf "${RAMDISK_PATH}"
    fi
    # Uses the extractor to untar pat file
    echo "$(TEXT "Extracting...")"
    LD_LIBRARY_PATH=${EXTRACTOR_PATH} "${EXTRACTOR_PATH}/${EXTRACTOR_BIN}" "${PAT_PATH}" "${UNTAR_PAT_PATH}" || true
  else
    echo "$(TEXT "Extracting...")"
    tar -xf "${PAT_PATH}" -C "${UNTAR_PAT_PATH}" >"${LOG_FILE}" 2>&1
    if [ $? -ne 0 ]; then
      echo -e "${LOG_FILE}" >"${MKERR_FILE}"
      return 1
    fi
  fi
  if [ ! -f ${UNTAR_PAT_PATH}/grub_cksum.syno ] ||
    [ ! -f ${UNTAR_PAT_PATH}/GRUB_VER ] ||
    [ ! -f ${UNTAR_PAT_PATH}/zImage ] ||
    [ ! -f ${UNTAR_PAT_PATH}/rd.gz ]; then
    echo -e "$(TEXT "pat Invalid, try again!")" >"${MKERR_FILE}"
    return 1
  fi
  echo -n "$(TEXT "Setting hash: ")"
  ZIMAGE_HASH="$(sha256sum ${UNTAR_PAT_PATH}/zImage | awk '{print $1}')"
  writeConfigKey "zimage-hash" "${ZIMAGE_HASH}" "${USER_CONFIG_FILE}"
  RAMDISK_HASH="$(sha256sum ${UNTAR_PAT_PATH}/rd.gz | awk '{print $1}')"
  writeConfigKey "ramdisk-hash" "${RAMDISK_HASH}" "${USER_CONFIG_FILE}"
  echo "$(TEXT "OK")"

  echo -n "$(TEXT "Copying files: ")"
  cp -f "${UNTAR_PAT_PATH}/grub_cksum.syno" "${PART1_PATH}"
  cp -f "${UNTAR_PAT_PATH}/GRUB_VER" "${PART1_PATH}"
  cp -f "${UNTAR_PAT_PATH}/grub_cksum.syno" "${PART2_PATH}"
  cp -f "${UNTAR_PAT_PATH}/GRUB_VER" "${PART2_PATH}"
  cp -f "${UNTAR_PAT_PATH}/zImage" "${ORI_ZIMAGE_FILE}"
  cp -f "${UNTAR_PAT_PATH}/rd.gz" "${ORI_RDGZ_FILE}"
  rm -rf "${UNTAR_PAT_PATH}"
  echo "$(TEXT "OK")"
}

###############################################################################
# Where the magic happens!
function make() {
  MKERR_FILE="${TMP_PATH}/makeerror.log"
  rm -f "${MKERR_FILE}"
  while true; do
    PLATFORM="$(readModelKey "${MODEL}" "platform")"
    KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
    KPRE="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kpre")"
    # Check if all addon exists
    while IFS=': ' read ADDON PARAM; do
      [ -z "${ADDON}" ] && continue
      if ! checkAddonExist "${ADDON}" "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}"; then
        echo -e "$(printf "$(TEXT "Addon %s not found!")" "${ADDON}")" >"${MKERR_FILE}"
        break 2
      fi
    done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")

    if [ ! -f "${ORI_ZIMAGE_FILE}" -o ! -f "${ORI_RDGZ_FILE}" ]; then
      extractDsmFiles "${MKERR_FILE}"
      [ $? -ne 0 ] && break
    fi

    # Check disk space left
    SPACELEFT=$(df --block-size=1 | grep ${LOADER_DISK_PART3} | awk '{print $4}')
    [ ${SPACELEFT} -le 268435456 ] && rm -rf "${PART3_PATH}/dl"

    ${WORK_PATH}/zimage-patch.sh
    if [ $? -ne 0 ]; then
      echo -e "$(TEXT "zImage not patched,\nPlease upgrade the bootloader version and try again.\nPatch error:\n")$(<"${LOG_FILE}")" >"${MKERR_FILE}"
      break
    fi

    ${WORK_PATH}/ramdisk-patch.sh
    if [ $? -ne 0 ]; then
      echo -e "$(TEXT "Ramdisk not patched,\nPlease upgrade the bootloader version and try again.\nPatch error:\n")$(<"${LOG_FILE}")" >"${MKERR_FILE}"
      break
    fi
    rm -f ${PART1_PATH}/.build
    echo "$(TEXT "Cleaning ...")"
    rm -rf "${UNTAR_PAT_PATH}"
    echo "$(TEXT "Ready!")"
    rm -f "${MKERR_FILE}"
    sleep 3
    break
  done 2>&1 | DIALOG --title "$(TEXT "Main menu")" --cr-wrap --no-collapse \
    --progressbox "$(TEXT "Making ...")" 20 100
  if [ -f "${MKERR_FILE}" ]; then
    DIALOG --title "$(TEXT "Error")" \
      --msgbox "$(cat ${MKERR_FILE})" 0 0
    return 1
  else
    PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
    BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
    SMALLNUM="$(readConfigKey "smallnum" "${USER_CONFIG_FILE}")"
    return 0
  fi
}

###############################################################################
# Advanced menu
function advancedMenu() {
  NEXT="l"
  while true; do
    rm -f "${TMP_PATH}/menu"
    if [ -n "${PRODUCTVER}" ]; then
      echo "l \"$(TEXT "Switch LKM version:") \Z4${LKM}\Zn\"" >>"${TMP_PATH}/menu"
      echo "j \"$(TEXT "HDD sort(hotplug):") \Z4${HDDSORT}\Zn\"" >>"${TMP_PATH}/menu"
    fi
    if loaderIsConfigured; then
      echo "q \"$(TEXT "Switch direct boot:") \Z4${DIRECTBOOT}\Zn\"" >>"${TMP_PATH}/menu"
      if [ "${DIRECTBOOT}" = "false" ]; then
        echo "i \"$(TEXT "Timeout of get ip in boot:") \Z4${BOOTIPWAIT}\Zn\"" >>"${TMP_PATH}/menu"
        echo "w \"$(TEXT "Timeout of boot wait:") \Z4${BOOTWAIT}\Zn\"" >>"${TMP_PATH}/menu"
        echo "k \"$(TEXT "kernel switching method:") \Z4${KERNELWAY}\Zn\"" >>"${TMP_PATH}/menu"
      fi
      echo "n \"$(TEXT "Reboot on kernel panic:") \Z4${KERNELPANIC}\Zn\"" >>"${TMP_PATH}/menu"
    fi
    echo "m \"$(TEXT "Set static IP")\"" >>"${TMP_PATH}/menu"
    echo "y \"$(TEXT "Set wireless account")\"" >>"${TMP_PATH}/menu"
    echo "u \"$(TEXT "Edit user config file manually")\"" >>"${TMP_PATH}/menu"
    echo "h \"$(TEXT "Edit grub.cfg file manually")\"" >>"${TMP_PATH}/menu"
    echo "t \"$(TEXT "Try to recovery a DSM installed system")\"" >>"${TMP_PATH}/menu"
    echo "s \"$(TEXT "Show SATA(s) # ports and drives")\"" >>"${TMP_PATH}/menu"
    if [ -n "${MODEL}" -a -n "${PRODUCTVER}" ]; then
      echo "c \"$(TEXT "show/modify the current pat data")\"" >>"${TMP_PATH}/menu"
    fi
    echo "a \"$(TEXT "Allow downgrade installation")\"" >>"${TMP_PATH}/menu"
    echo "f \"$(TEXT "Format disk(s) # Without loader disk")\"" >>"${TMP_PATH}/menu"
    echo "x \"$(TEXT "Reset DSM system password")\"" >>"${TMP_PATH}/menu"
    echo "p \"$(TEXT "Save modifications of '/opt/rr'")\"" >>"${TMP_PATH}/menu"
    if [ -n "${MODEL}" -a "true" = "$(readModelKey "${MODEL}" "dt")" ]; then
      echo "d \"$(TEXT "Custom dts file # Need rebuild")\"" >>"${TMP_PATH}/menu"
    fi
    if [ -n "${DEBUG}" ]; then
      echo "b \"$(TEXT "Backup bootloader disk # test")\"" >>"${TMP_PATH}/menu"
      echo "r \"$(TEXT "Restore bootloader disk # test")\"" >>"${TMP_PATH}/menu"
    fi
    echo "v \"$(TEXT "Report bugs to the author")\"" >>"${TMP_PATH}/menu"
    echo "o \"$(TEXT "Install development tools")\"" >>"${TMP_PATH}/menu"
    echo "g \"$(TEXT "Show QR logo:") \Z4${DSMLOGO}\Zn\"" >>"${TMP_PATH}/menu"
    echo "1 \"$(TEXT "Set global proxy")\"" >>"${TMP_PATH}/menu"
    echo "2 \"$(TEXT "Set github proxy")\"" >>"${TMP_PATH}/menu"
    echo "e \"$(TEXT "Exit")\"" >>"${TMP_PATH}/menu"

    DIALOG --title "$(TEXT "Advanced")" \
      --default-item "${NEXT}" --menu "$(TEXT "Advanced option")" 0 0 0 --file "${TMP_PATH}/menu" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && break
    case $(<"${TMP_PATH}/resp") in
    l)
      LKM=$([ "${LKM}" = "dev" ] && echo 'prod' || ([ "${LKM}" = "test" ] && echo 'dev' || echo 'test'))
      writeConfigKey "lkm" "${LKM}" "${USER_CONFIG_FILE}"
      touch ${PART1_PATH}/.build
      NEXT="l"
      ;;
    j)
      [ "${HDDSORT}" = "true" ] && HDDSORT='false' || HDDSORT='true'
      writeConfigKey "hddsort" "${HDDSORT}" "${USER_CONFIG_FILE}"
      touch ${PART1_PATH}/.build
      NEXT="l"
      ;;
    q)
      [ "${DIRECTBOOT}" = "false" ] && DIRECTBOOT='true' || DIRECTBOOT='false'
      writeConfigKey "directboot" "${DIRECTBOOT}" "${USER_CONFIG_FILE}"
      NEXT="e"
      ;;
    i)
      ITEMS="$(echo -e "1 \n5 \n10 \n30 \n60 \n")"
      DIALOG --title "$(TEXT "Advanced")" \
        --default-item "${BOOTIPWAIT}" --no-items --menu "$(TEXT "Choose a time(seconds)")" 0 0 0 ${ITEMS} \
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
      DIALOG --title "$(TEXT "Advanced")" \
        --default-item "${BOOTWAIT}" --no-items --menu "$(TEXT "Choose a time(seconds)")" 0 0 0 ${ITEMS} \
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
    n)
      rm -f "${TMP_PATH}/opts"
      echo "5 \"Reboot after 5 seconds\"" >>"${TMP_PATH}/opts"
      echo "0 \"No reboot\"" >>"${TMP_PATH}/opts"
      echo "-1 \"Restart immediately\"" >>"${TMP_PATH}/opts"
      DIALOG --title "$(TEXT "Advanced")" \
        --default-item "${KERNELPANIC}" --menu "$(TEXT "Choose a time(seconds)")" 0 0 0 --file "${TMP_PATH}/opts" \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && return
      resp=$(cat ${TMP_PATH}/resp 2>/dev/null)
      [ -z "${resp}" ] && return
      KERNELPANIC=${resp}
      writeConfigKey "kernelpanic" "${KERNELPANIC}" "${USER_CONFIG_FILE}"
      NEXT="e"
      ;;
    m)
      MSG="$(TEXT "Temporary IP: (UI will not refresh)")"
      ITEMS=""
      IDX=0
      ETHX=$(ls /sys/class/net/ | grep -v lo)
      for ETH in ${ETHX}; do
        [ ${IDX} -gt 7 ] && break # Currently, only up to 8 are supported.  (<==> boot.sh L96, <==> lkm: MAX_NET_IFACES)
        IDX=$((${IDX} + 1))
        MACR="$(cat /sys/class/net/${ETH}/address | sed 's/://g')"
        IPR="$(readConfigKey "network.${MACR}" "${USER_CONFIG_FILE}")"
        ITEMS+="${ETH}(${MACR}) ${IDX} 1 ${IPR:-\"\"} ${IDX} 22 20 16 "
      done
      echo ${ITEMS} >"${TMP_PATH}/opts"
      DIALOG --title "$(TEXT "Advanced")" \
        --form "${MSG}" 10 44 ${IDX} --file "${TMP_PATH}/opts" \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && continue
      (
        IDX=1
        for ETH in ${ETHX}; do
          MACR="$(cat /sys/class/net/${ETH}/address | sed 's/://g')"
          IPR="$(readConfigKey "network.${MACR}" "${USER_CONFIG_FILE}")"
          IPC="$(cat "${TMP_PATH}/resp" | sed -n "${IDX}p")"
          if [ -n "${IPC}" -a "${IPR}" != "${IPC}" ]; then
            if ! echo "${IPC}" | grep -q "/"; then
              IPC="${IPC}/24"
            fi
            ip addr add ${IPC} dev ${ETH}
            writeConfigKey "network.${MACR}" "${IPC}" "${USER_CONFIG_FILE}"
            sleep 1
          elif [ -z "${IPC}" ]; then
            deleteConfigKey "network.${MACR}" "${USER_CONFIG_FILE}"
          fi
          IDX=$((${IDX} + 1))
        done
        sleep 1
        IP="$(getIP)"
      ) 2>&1 | DIALOG --title "$(TEXT "Advanced")" \
        --progressbox "$(TEXT "Setting IP ...")" 20 100
      NEXT="e"
      ;;
    y)
      DIALOG --title "$(TEXT "Advanced")" \
        --infobox "$(TEXT "Scanning ...")" 0 0
      ITEM=$(iw wlan0 scan | grep SSID: | awk '{print $2}')
      MSG=""
      MSG+="$(TEXT "Scanned SSIDs:\n")"
      for I in $(iw wlan0 scan | grep SSID: | awk '{print $2}'); do MSG+="${I}\n"; done
      LINENUM=$(($(echo -e "${MSG}" | wc -l) + 8))
      while true; do
        SSID=$(cat ${PART1_PATH}/wpa_supplicant.conf 2>/dev/null | grep -i SSID | cut -d'=' -f2)
        PSK=$(cat ${PART1_PATH}/wpa_supplicant.conf 2>/dev/null | grep -i PSK | cut -d'=' -f2)
        SSID="${SSID//\"/}"
        PSK="${PSK//\"/}"
        DIALOG --title "$(TEXT "Advanced")" \
          --form "${MSG}" ${LINENUM:-16} 62 2 "SSID" 1 1 "${SSID}" 1 7 50 0 " PSK" 2 1 "${PSK}" 2 7 50 0 \
          2>"${TMP_PATH}/resp"
        RET=$?
        case ${RET} in
        0) # ok-button
          SSID="$(cat "${TMP_PATH}/resp" | sed -n '1p')"
          PSK="$(cat "${TMP_PATH}/resp" | sed -n '2p')"
          if [ -z "${SSID}" -o -z "${PSK}" ]; then
            DIALOG --title "$(TEXT "Advanced")" \
              --yesno "$(TEXT "Invalid SSID/PSK, retry?")" 0 0
            [ $? -eq 0 ] && break
          fi
          (
            rm -f ${PART1_PATH}/wpa_supplicant.conf
            echo "ctrl_interface=/var/run/wpa_supplicant" >>${PART1_PATH}/wpa_supplicant.conf
            echo "update_config=1" >>${PART1_PATH}/wpa_supplicant.conf
            echo "network={" >>${PART1_PATH}/wpa_supplicant.conf
            echo "        ssid=\"${SSID}\"" >>${PART1_PATH}/wpa_supplicant.conf
            echo "        psk=\"${PSK}\"" >>${PART1_PATH}/wpa_supplicant.conf
            echo "}" >>${PART1_PATH}/wpa_supplicant.conf

            for ETH in $(ls /sys/class/net/ | grep wlan); do
              connectwlanif "${ETH}" && sleep 1
              MACR="$(cat /sys/class/net/${ETH}/address | sed 's/://g')"
              IPR="$(readConfigKey "network.${MACR}" "${USER_CONFIG_FILE}")"
              if [ -n "${IPR}" ]; then
                ip addr add ${IPC}/24 dev ${ETH}
                sleep 1
              fi
            done
          ) 2>&1 | DIALOG --title "$(TEXT "Advanced")" \
            --progressbox "$(TEXT "Setting ...")" 20 100
          break
          ;;
        1) # cancel-button
          break
          ;;
        255) # ESC
          break
          ;;
        esac
      done
      ;;
    u)
      editUserConfig
      NEXT="e"
      ;;
    h)
      editGrubCfg
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
      [ $(ls -l /sys/class/mmc_host | grep mmc_host | wc -l) -gt 0 ] && MSG+="\nMMC:\n"
      for PCI in $(lspci -d ::805 | awk '{print $1}'); do
        NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
        PORTNUM=$(ls -l /sys/block/mmc* | grep "${PCI}" | wc -l)
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
      DIALOG --title "$(TEXT "Advanced")" \
        --msgbox "${MSG}" 0 0
      ;;
    c)
      PATURL="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
      PATSUM="$(readConfigKey "patsum" "${USER_CONFIG_FILE}")"
      MSG="$(TEXT "pat: (editable)")"
      DIALOG --title "$(TEXT "Advanced")" \
        --form "${MSG}" 10 110 2 "URL" 1 1 "${PATURL}" 1 5 100 0 "MD5" 2 1 "${PATSUM}" 2 5 100 0 \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && return
      paturl="$(cat "${TMP_PATH}/resp" | sed -n '1p')"
      patsum="$(cat "${TMP_PATH}/resp" | sed -n '2p')"
      if [ ! ${paturl} = ${PATURL} ] || [ ! ${patsum} = ${PATSUM} ]; then
        writeConfigKey "paturl" "${paturl}" "${USER_CONFIG_FILE}"
        writeConfigKey "patsum" "${patsum}" "${USER_CONFIG_FILE}"
        rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
        touch ${PART1_PATH}/.build
      fi
      ;;
    a)
      MSG=""
      MSG+="$(TEXT "This feature will allow you to downgrade the installation by removing the VERSION file from the first partition of all disks.\n")"
      MSG+="$(TEXT "Therefore, please insert all disks before continuing.\n")"
      MSG+="$(TEXT "Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?")"
      DIALOG --title "$(TEXT "Advanced")" \
        --yesno "${MSG}" 0 0
      [ $? -ne 0 ] && return
      (
        mkdir -p "${TMP_PATH}/sdX1"
        for I in $(ls /dev/sd*1 2>/dev/null | grep -v "${LOADER_DISK_PART1}"); do
          mount "${I}" "${TMP_PATH}/sdX1"
          [ -f "${TMP_PATH}/sdX1/etc/VERSION" ] && rm -f "${TMP_PATH}/sdX1/etc/VERSION"
          [ -f "${TMP_PATH}/sdX1/etc.defaults/VERSION" ] && rm -f "${TMP_PATH}/sdX1/etc.defaults/VERSION"
          sync
          umount "${I}"
        done
        rm -rf "${TMP_PATH}/sdX1"
      ) 2>&1 | DIALOG --title "$(TEXT "Advanced")" \
        --progressbox "$(TEXT "Removing ...")" 20 100
      MSG="$(TEXT "Remove VERSION file for all disks completed.")"
      DIALOG --title "$(TEXT "Advanced")" \
        --msgbox "${MSG}" 0 0
      ;;
    f)
      rm -f "${TMP_PATH}/opts"
      while read POSITION NAME; do
        [ -z "${POSITION}" -o -z "${NAME}" ] && continue
        echo "${POSITION}" | grep -q "${LOADER_DISK}" && continue
        echo "\"${POSITION}\" \"${NAME}\" \"off\"" >>"${TMP_PATH}/opts"
      done < <(ls -l /dev/disk/by-id/ | sed 's|../..|/dev|g' | grep -E "/dev/sd|/dev/mmc|/dev/nvme" | awk -F' ' '{print $NF" "$(NF-2)}' | sort -uk 1,1)
      if [ ! -f "${TMP_PATH}/opts" ]; then
        DIALOG --title "$(TEXT "Advanced")" \
          --msgbox "$(TEXT "No disk found!")" 0 0
        return
      fi
      DIALOG --title "$(TEXT "Advanced")" \
        --checklist "$(TEXT "Advanced")" 0 0 0 --file "${TMP_PATH}/opts" \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && return
      RESP=$(<"${TMP_PATH}/resp")
      [ -z "${RESP}" ] && return
      DIALOG --title "$(TEXT "Advanced")" \
        --yesno "$(TEXT "Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?")" 0 0
      [ $? -ne 0 ] && return
      if [ $(ls /dev/md* | wc -l) -gt 0 ]; then
        DIALOG --title "$(TEXT "Advanced")" \
          --yesno "$(TEXT "Warning:\nThe current hds is in raid, do you still want to format them?")" 0 0
        [ $? -ne 0 ] && return
        for I in $(ls /dev/md*); do
          mdadm -S "${I}"
        done
      fi
      (
        for I in ${RESP}; do
          echo y | mkfs.ext4 -T largefile4 "${I}"
        done
      ) 2>&1 | DIALOG --title "$(TEXT "Advanced")" \
        --progressbox "$(TEXT "Formatting ...")" 20 100
      DIALOG --title "$(TEXT "Advanced")" \
        --msgbox "$(TEXT "Formatting is complete.")" 0 0
      ;;
    x)
      rm -f "${TMP_PATH}/menu"
      mkdir -p "${TMP_PATH}/sdX1"
      for I in $(ls /dev/sd*1 2>/dev/null | grep -v "${LOADER_DISK_PART1}"); do
        mount ${I} "${TMP_PATH}/sdX1"
        if [ -f "${TMP_PATH}/sdX1/etc/shadow" ]; then
          for U in $(cat "${TMP_PATH}/sdX1/etc/shadow" | awk -F ':' '{if ($2 != "*" && $2 != "!!") {print $1;}}'); do
            grep -q "status=on" "${TMP_PATH}/sdX1/usr/syno/etc/packages/SecureSignIn/preference/${U}/method.config" 2>/dev/null
            [ $? -eq 0 ] && SS="SecureSignIn" || SS="            "
            printf "\"%-36s %-16s\"\n" "${U}" "${SS}" >>"${TMP_PATH}/menu"
          done
        fi
        umount "${I}"
        [ -f "${TMP_PATH}/menu" ] && break
      done
      rm -rf "${TMP_PATH}/sdX1"
      if [ ! -f "${TMP_PATH}/menu" ]; then
        DIALOG --title "$(TEXT "Advanced")" \
          --msgbox "$(TEXT "The installed Syno system not found in the currently inserted disks!")" 0 0
        return
      fi
      DIALOG --title "$(TEXT "Advanced")" \
        --no-items --menu "$(TEXT "Choose a user name")" 0 0 0 --file "${TMP_PATH}/menu" \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && return
      USER="$(cat "${TMP_PATH}/resp" | awk '{print $1}')"
      [ -z "${USER}" ] && return
      while true; do
        DIALOG --title "$(TEXT "Advanced")" \
          --inputbox "$(printf "$(TEXT "Type a new password for user '%s'")" "${USER}")" 0 70 "${CMDLINE[${NAME}]}" \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && break 2
        VALUE="$(<"${TMP_PATH}/resp")"
        [ -n "${VALUE}" ] && break
        DIALOG --title "$(TEXT "Advanced")" \
          --msgbox "$(TEXT "Invalid password")" 0 0
      done
      NEWPASSWD="$(python -c "from passlib.hash import sha512_crypt;pw=\"${VALUE}\";print(sha512_crypt.using(rounds=5000).hash(pw))")"
      (
        mkdir -p "${TMP_PATH}/sdX1"
        for I in $(ls /dev/sd*1 2>/dev/null | grep -v "${LOADER_DISK_PART1}"); do
          mount "${I}" "${TMP_PATH}/sdX1"
          OLDPASSWD="$(cat "${TMP_PATH}/sdX1/etc/shadow" | grep "^${USER}:" | awk -F ':' '{print $2}')"
          [ -n "${NEWPASSWD}" -a -n "${OLDPASSWD}" ] && sed -i "s|${OLDPASSWD}|${NEWPASSWD}|g" "${TMP_PATH}/sdX1/etc/shadow"
          sed -i "s|status=on|status=off|g" "${TMP_PATH}/sdX1/usr/syno/etc/packages/SecureSignIn/preference/${USER}/method.config" 2>/dev/null
          sync
          umount "${I}"
        done
        rm -rf "${TMP_PATH}/sdX1"
      ) 2>&1 | DIALOG --title "$(TEXT "Advanced")" \
        --progressbox "$(TEXT "Resetting ...")" 20 100
      DIALOG --title "$(TEXT "Advanced")" \
        --msgbox "$(TEXT "Password reset completed.")" 0 0
      ;;
    p)
      DIALOG --title "$(TEXT "Advanced")" \
        --yesno "$(TEXT "Warning:\nDo not terminate midway, otherwise it may cause damage to the RR. Do you want to continue?")" 0 0
      [ $? -ne 0 ] && return
      DIALOG --title "$(TEXT "Advanced")" \
        --infobox "$(TEXT "Saving ...")" 0 0
      RDXZ_PATH="${TMP_PATH}/rdxz_tmp"
      mkdir -p "${RDXZ_PATH}"
      (
        cd "${RDXZ_PATH}"
        xz -dc <"${RR_RAMDISK_FILE}" | cpio -idm
      ) >/dev/null 2>&1 || true
      rm -rf "${RDXZ_PATH}/opt/rr"
      cp -Rf "/opt" "${RDXZ_PATH}/"
      (
        cd "${RDXZ_PATH}"
        find . 2>/dev/null | cpio -o -H newc -R root:root | xz --check=crc32 >"${RR_RAMDISK_FILE}"
      ) || true
      rm -rf "${RDXZ_PATH}"
      DIALOG --title "$(TEXT "Advanced")" \
        --msgbox ""$(TEXT "Save is complete.")"" 0 0
      ;;
    d)
      if ! tty | grep -q "/dev/pts"; then
        DIALOG --title "$(TEXT "Advanced")" \
          --msgbox "$(TEXT "This feature is only available when accessed via web/ssh.")" 0 0
        return
      fi
      DIALOG --title "$(TEXT "Advanced")" \
        --msgbox "$(TEXT "Currently, only dts format files are supported. Please prepare and click to confirm uploading.\n(saved in /mnt/p3/users/)")" 0 0
      TMP_UP_PATH="${TMP_PATH}/users"
      rm -rf "${TMP_UP_PATH}"
      mkdir -p "${TMP_UP_PATH}"
      pushd "${TMP_UP_PATH}"
      rz -be -B 536870912
      for F in $(ls -A); do
        USER_FILE="${TMP_UP_PATH}/${F}"
        dtc -q -I dts -O dtb "${F}" >"test.dtb"
        RET=$?
        break
      done
      popd
      if [ ${RET} -ne 0 -o -z "${USER_FILE}" ]; then
        DIALOG --title "$(TEXT "Advanced")" \
          --msgbox "$(TEXT "Not a valid dts file, please try again!")" 0 0
      else
        [ -d "{USER_UP_PATH}" ] || mkdir -p "${USER_UP_PATH}"
        cp -f "${USER_FILE}" "${USER_UP_PATH}/${MODEL}.dts"
        DIALOG --title "$(TEXT "Advanced")" \
          --msgbox "$(TEXT "A valid dts file, Automatically import at compile time.")" 0 0
      fi
      touch ${PART1_PATH}/.build
      ;;
    b)
      if ! tty | grep -q "/dev/pts"; then
        DIALOG --title "$(TEXT "Advanced")" \
          --msgbox "$(TEXT "This feature is only available when accessed via web/ssh.")" 0 0
        return
      fi
      DIALOG --title "$(TEXT "Advanced")" \
        --yesno "$(TEXT "Warning:\nDo not terminate midway, otherwise it may cause damage to the RR. Do you want to continue?")" 0 0
      [ $? -ne 0 ] && return
      DIALOG --title "$(TEXT "Advanced")" \
        --infobox "$(TEXT "Backuping...")" 0 0
      rm -f /var/www/data/backup.img.gz # thttpd root path
      dd if="${LOADER_DISK}" bs=1M conv=fsync | gzip >/var/www/data/backup.img.gz
      if [ $? -ne 0]; then
        DIALOG --title "$(TEXT "Advanced")" \
          --msgbox "$(TEXT "Failed to generate backup. There may be insufficient memory. Please clear the cache and try again!")" 0 0
        return
      fi
      if [ -z "${SSH_TTY}" ]; then # web
        IP_HEAD="$(getIP)"
        echo "http://${IP_HEAD}/backup.img.gz" >${TMP_PATH}/resp
        echo "            ↑                  " >>${TMP_PATH}/resp
        echo "$(TEXT "Click on the address above to download.")" >>${TMP_PATH}/resp
        echo "$(TEXT "Please confirm the completion of the download before closing this window.")" >>${TMP_PATH}/resp
        DIALOG --title "$(TEXT "Advanced")" \
          --editbox "${TMP_PATH}/resp" 10 100
      else # ssh
        sz -be -B 536870912 /var/www/data/backup.img.gz
      fi
      DIALOG --title "$(TEXT "Advanced")" \
        --msgbox "$(TEXT "backup is complete.")" 0 0
      rm -f /var/www/data/backup.img.gz
      ;;
    r)
      if ! tty | grep -q "/dev/pts"; then
        DIALOG --title "$(TEXT "Advanced")" \
          --msgbox "$(TEXT "This feature is only available when accessed via web/ssh.")" 0 0
        return
      fi
      DIALOG --title "$(TEXT "Advanced")" \
        --yesno "$(TEXT "Please upload the backup file.\nCurrently, zip(github) and img.gz(backup) compressed file formats are supported.")" 0 0
      [ $? -ne 0 ] && return
      IFTOOL=""
      TMP_UP_PATH="${TMP_PATH}/users"
      rm -rf "${TMP_UP_PATH}"
      mkdir -p "${TMP_UP_PATH}"
      pushd "${TMP_UP_PATH}"
      rz -be -B 536870912
      for F in $(ls -A); do
        USER_FILE="${F}"
        [ "${F##*.}" = "zip" -a $(unzip -l "${TMP_UP_PATH}/${USER_FILE}" | grep -c "\.img$") -eq 1 ] && IFTOOL="zip"
        [ "${F##*.}" = "gz" -a "${F#*.}" = "img.gz" ] && IFTOOL="gzip"
        break
      done
      popd
      if [ -z "${IFTOOL}" -o ! -f "${TMP_UP_PATH}/${USER_FILE}" ]; then
        DIALOG --title "$(TEXT "Advanced")" \
          --msgbox "$(printf "$(TEXT "Not a valid .zip/.img.gz file, please try again!")" "${USER_FILE}")" 0 0
      else
        DIALOG --title "$(TEXT "Advanced")" \
          --yesno "$(TEXT "Warning:\nDo not terminate midway, otherwise it may cause damage to the RR. Do you want to continue?")" 0 0
        [ $? -ne 0 ] && (
          rm -f "${TMP_UP_PATH}/${USER_FILE}"
          return
        )
        DIALOG --title "$(TEXT "Advanced")" \
          --infobox "$(TEXT "Writing...")" 0 0
        umount "${PART1_PATH}" "${PART2_PATH}" "${PART3_PATH}"
        if [ "${IFTOOL}" = "zip" ]; then
          unzip -p "${TMP_UP_PATH}/${USER_FILE}" | dd of="${LOADER_DISK}" bs=1M conv=fsync
        elif [ "${IFTOOL}" = "gzip" ]; then
          gzip -dc "${TMP_UP_PATH}/${USER_FILE}" | dd of="${LOADER_DISK}" bs=1M conv=fsync
        fi
        DIALOG --title "$(TEXT "Advanced")" \
          --yesno "$(printf "$(TEXT "Restore bootloader disk with success to %s!\nReboot?")" "${USER_FILE}")" 0 0
        [ $? -ne 0 ] && continue
        reboot
        exit
      fi
      ;;
      
    v)
      if [ -d "${PART1_PATH}/logs" ]; then
        rm -f "${TMP_PATH}/logs.tar.gz"
        tar -czf "${TMP_PATH}/logs.tar.gz" -C "${PART1_PATH}" logs
        if [ -z "${SSH_TTY}" ]; then # web
          mv -f "${TMP_PATH}/logs.tar.gz" "/var/www/data/logs.tar.gz"
          URL="http://$(getIP)/logs.tar.gz"
          DIALOG --title "$(TEXT "Advanced")" \
            --msgbox "$(printf "$(TEXT "Please via %s to download the logs,\nAnd go to github to create an issue and upload the logs.")" "${URL}")" 0 0
        else
          sz -be -B 536870912 "${TMP_PATH}/logs.tar.gz"
          DIALOG --title "$(TEXT "Advanced")" \
            --msgbox "$(TEXT "Please go to github to create an issue and upload the logs.")" 0 0
        fi
      else
        MSG=""
        MSG+="$(TEXT "\Z1No logs found!\Zn\n\n")"
        MSG+="$(TEXT "Please do as follows:\n")"
        MSG+="$(TEXT " 1. Add dbgutils in addons and rebuild.\n")"
        MSG+="$(TEXT " 2. Wait 10 minutes after booting.\n")"
        MSG+="$(TEXT " 3. Reboot into RR and go to this option.\n")"
        DIALOG --title "$(TEXT "Advanced")" \
          --msgbox "${MSG}" 0 0
      fi
      ;;
    o)
      DIALOG --title "$(TEXT "Advanced")" \
        --yesno "$(TEXT "This option only installs opkg package management, allowing you to install more tools for use and debugging. Do you want to continue?")" 0 0
      [ $? -ne 0 ] && return
      (
        wget -O - http://bin.entware.net/x64-k3.2/installer/generic.sh | /bin/sh
        opkg update
        #opkg install python3 python3-pip
      ) 2>&1 | DIALOG --title "$(TEXT "Advanced")" \
        --progressbox "$(TEXT "opkg installing ...")" 20 100
      DIALOG --title "$(TEXT "Advanced")" \
        --msgbox "$(TEXT "opkg install is complete. Please reconnect to SSH/web, or execute 'source ~/.bashrc'")" 0 0
      ;;
    g)
      [ "${DSMLOGO}" = "true" ] && DSMLOGO='false' || DSMLOGO='true'
      writeConfigKey "dsmlogo" "${DSMLOGO}" "${USER_CONFIG_FILE}"
      NEXT="e"
      ;;
    1)
      RET=1
      PROXY=$(readConfigKey "global_proxy" "${USER_CONFIG_FILE}")
      while true; do
        DIALOG --title "$(TEXT "Advanced")" \
          --inputbox "$(TEXT "Please enter a proxy server url.(e.g., http://192.168.1.1:7981/)")" 0 70 "${PROXY}" \
          2>${TMP_PATH}/resp
        RET=$?
        [ ${RET} -ne 0 ] && break
        PROXY=$(cat ${TMP_PATH}/resp)
        if [ -z "${PROXY}" ]; then
          break
        elif echo "${PROXY}" | grep -Eq "^(https?|socks5)://[^\s/$.?#].[^\s]*$"; then
          break
        else
          DIALOG --title "$(TEXT "Advanced")" \
            --yesno "$(TEXT "Invalid proxy server url, continue?")" 0 0
          RET=$?
          [ ${RET} -eq 0 ] && break
        fi
      done
      [ ${RET} -ne 0 ] && return

      if [ -z "${PROXY}" ]; then
        deleteConfigKey "global_proxy" "${USER_CONFIG_FILE}"
        unset http_proxy
        unset https_proxy
      else
        writeConfigKey "global_proxy" "${PROXY}" "${USER_CONFIG_FILE}"
        export http_proxy="${PROXY}"
        export https_proxy="${PROXY}"
      fi
      ;;
    2)
      RET=1
      PROXY=$(readConfigKey "github_proxy" "${USER_CONFIG_FILE}")
      while true; do
        DIALOG --title "$(TEXT "Advanced")" \
          --inputbox "$(TEXT "Please enter a proxy server url.(e.g., https://mirror.ghproxy.com/)")" 0 70 "${PROXY}" \
          2>${TMP_PATH}/resp
        RET=$?
        [ ${RET} -ne 0 ] && break
        PROXY=$(cat ${TMP_PATH}/resp)
        if [ -z "${PROXY}" ]; then
          break
        elif echo "${PROXY}" | grep -Eq "^(https?|socks5)://[^\s/$.?#].[^\s]*$"; then
          break
        else
          DIALOG --title "$(TEXT "Advanced")" \
            --yesno "$(TEXT "Invalid proxy server url, continue?")" 0 0
          RET=$?
          [ ${RET} -eq 0 ] && break
        fi
      done
      [ ${RET} -ne 0 ] && return
      if [ -z "${PROXY}" ]; then
        deleteConfigKey "github_proxy" "${USER_CONFIG_FILE}"
      else
        writeConfigKey "github_proxy" "${PROXY}" "${USER_CONFIG_FILE}"
      fi
      ;;
    e) break ;;
    esac
  done
}

###############################################################################
# Try to recovery a DSM already installed
function tryRecoveryDSM() {
  DIALOG --title "$(TEXT "Try recovery DSM")" \
    --infobox "$(TEXT "Trying to recovery a DSM installed system ...")" 0 0
  if findAndMountDSMRoot; then
    MODEL=""
    PRODUCTVER=""
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
        done < <(find "${WORK_PATH}/model-configs" -maxdepth 1 -name \*.yml | sort)
        if [ -n "${MODEL}" ]; then
          productversMenu "${majorversion}.${minorversion}"
          if [ -n "${PRODUCTVER}" ]; then
            cp -f "${DSMROOT_PATH}/.syno/patch/zImage" "${PART2_PATH}"
            cp -f "${DSMROOT_PATH}/.syno/patch/rd.gz" "${PART2_PATH}"
            BUILDNUM=${buildnumber}
            SMALLNUM=${smallfixnumber}
            writeConfigKey "buildnum" "${BUILDNUM}" "${USER_CONFIG_FILE}"
            writeConfigKey "smallnum" "${SMALLNUM}" "${USER_CONFIG_FILE}"
            MSG="$(printf "$(TEXT "Found a installation:\nModel: %s\nProductversion: %s")" "${MODEL}" "${PRODUCTVER}(${BUILDNUM}$([ ${SMALLNUM:-0} -ne 0 ] && echo "u${SMALLNUM}"))")"
            SN=$(_get_conf_kv SN "${DSMROOT_PATH}/etc/synoinfo.conf")
            if [ -n "${SN}" ]; then
              writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
              MSG+="$(printf "$(TEXT "\nSerial: %s")" "${SN}")"
            fi
            DIALOG --title "$(TEXT "Try recovery DSM")" \
              --msgbox "${MSG}" 0 0
          fi
        fi
      fi
    fi
  else
    DIALOG --title "$(TEXT "Try recovery DSM")" \
      --msgbox "$(TEXT "Unfortunately I couldn't mount the DSM partition!")" 0 0
  fi
}

###############################################################################
# Permits user edit the user config
function editUserConfig() {
  while true; do
    DIALOG --title "$(TEXT "Edit with caution")" \
      --editbox "${USER_CONFIG_FILE}" 0 0 2>"${TMP_PATH}/userconfig"
    [ $? -ne 0 ] && return
    mv -f "${TMP_PATH}/userconfig" "${USER_CONFIG_FILE}"
    ERRORS=$(yq eval "${USER_CONFIG_FILE}" 2>&1)
    [ $? -eq 0 ] && break
    DIALOG --title "$(TEXT "Edit with caution")" \
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
  touch ${PART1_PATH}/.build
}

###############################################################################
# Permits user edit the grub.cfg
function editGrubCfg() {
  while true; do
    DIALOG --title "$(TEXT "Edit with caution")" \
      --editbox "${GRUB_PATH}/grub.cfg" 0 0 2>"${TMP_PATH}/usergrub.cfg"
    [ $? -ne 0 ] && return
    mv -f "${TMP_PATH}/usergrub.cfg" "${GRUB_PATH}/grub.cfg"
    break
  done
}

###############################################################################
# Calls boot.sh to boot into DSM kernel/ramdisk
function boot() {
  [ -f ${PART1_PATH}/.build ] && DIALOG --title "$(TEXT "Alert")" \
    --yesno "$(TEXT "Config changed, would you like to rebuild the loader?")" 0 0
  if [ $? -eq 0 ]; then
    make || return
  fi
  ${WORK_PATH}/boot.sh
}

###############################################################################
# Shows language to user choose one
function languageMenu() {
  ITEMS="$(ls /usr/share/locale)"
  DIALOG \
    --default-item "${LAYOUT}" --no-items --menu "$(TEXT "Choose a language")" 0 0 0 ${ITEMS} 2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  resp=$(cat ${TMP_PATH}/resp 2>/dev/null)
  [ -z "${resp}" ] && return
  LANGUAGE=${resp}
  echo "${LANGUAGE}.UTF-8" >${PART1_PATH}/.locale
  export LANG="${LANGUAGE}.UTF-8"
}

###############################################################################
# Shows available keymaps to user choose one
function keymapMenu() {
  OPTIONS="$(ls /usr/share/keymaps/i386 | grep -v include)"
  DIALOG \
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
  DIALOG \
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
  PROXY="$(readConfigKey "github_proxy" "${USER_CONFIG_FILE}")"
  [ -n "${PROXY}" ] && [[ "${PROXY: -1}" != "/" ]] && PROXY="${PROXY}/"
  T="$(printf "$(TEXT "Update %s")" "${1}")"

  DIALOG --title "${T}" \
    --infobox "$(TEXT "Checking last version ...")" 0 0
  if [ "${PRERELEASE}" = "true" ]; then
    TAG="$(curl -skL "${PROXY}${3}/tags" | grep /refs/tags/.*\.zip | head -1 | sed -r 's/.*\/refs\/tags\/(.*)\.zip.*$/\1/')"
  else
    # TAG=`curl -skL "${PROXY}https://api.github.com/repos/wjz304/rr-addons/releases/latest" | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`
    # In the absence of authentication, the default API access count for GitHub is 60 per hour, so removing the use of api.github.com
    LATESTURL="$(curl -skL -w %{url_effective} -o /dev/null "${PROXY}${3}/releases/latest")"
    TAG="${LATESTURL##*/}"
  fi
  [ "${TAG:0:1}" = "v" ] && TAG="${TAG:1}"
  if [ -z "${TAG}" -o "${TAG}" = "latest" ]; then
    if [ ! "${5}" = "0" ]; then
      DIALOG --title "${T}" \
        --infobox "$(printf "$(TEXT "Error checking new version.\nError: TAG is %s")" "${TAG}")" 0 0
    else
      DIALOG --title "${T}" \
        --msgbox "$(printf "$(TEXT "Error checking new version.\nError: TAG is %s")" "${TAG}")" 0 0
    fi
    return 1
  fi
  if [ "${2}" = "${TAG}" ]; then
    if [ ! "${5}" = "0" ]; then
      DIALOG --title "${T}" \
        --infobox "$(TEXT "No new version.")" 0 0
      return 1
    else
      DIALOG --title "${T}" \
        --yesno "$(printf "$(TEXT "No new version. Actual version is %s\nForce update?")" "${2}")" 0 0
      [ $? -ne 0 ] && return 1
    fi
  fi
  (
    rm -f "${TMP_PATH}/${4}.zip"
    STATUS=$(curl -kL -w "%{http_code}" "${PROXY}${3}/releases/download/${TAG}/${4}.zip" -o "${TMP_PATH}/${4}.zip")
    RET=$?
  ) 2>&1 | DIALOG --title "${T}" \
    --progressbox "$(TEXT "Downloading ...")" 20 100
  if [ ${RET} -ne 0 -o ${STATUS} -ne 200 ]; then
    if [ ! "${5}" = "0" ]; then
      DIALOG --title "${T}" \
        --infobox "$(printf "$(TEXT "Error downloading new version.\nError: %d:%d")" "${RET}" "${STATUS}")" 0 0
    else
      DIALOG --title "${T}" \
        --msgbox "$(printf "$(TEXT "Error downloading new version.\nError: %d:%d")" "${RET}" "${STATUS}")" 0 0
    fi
    return 1
  fi
  return 0
}

# 1 - ext name
function updateRR() {
  T="$(printf "$(TEXT "Update %s")" "${1}")"
  DIALOG --title "${T}" \
    --infobox "$(TEXT "Extracting last version")" 0 0
  unzip -oq "${TMP_PATH}/update.zip" -d "${TMP_PATH}/"
  if [ $? -ne 0 ]; then
    DIALOG --title "${T}" \
      --msgbox "$(TEXT "Error extracting update file")" 0 0
    return 1
  fi
  # Check checksums
  (cd /tmp && sha256sum --status -c sha256sum)
  if [ $? -ne 0 ]; then
    DIALOG --title "${T}" \
      --msgbox "$(TEXT "Checksum do not match!")" 0 0
    return 1
  fi
  # Check conditions
  if [ -f "${TMP_PATH}/update-check.sh" ]; then
    chmod +x "${TMP_PATH}/update-check.sh"
    ${TMP_PATH}/update-check.sh
    if [ $? -ne 0 ]; then
      DIALOG --title "${T}" \
        --msgbox "$(TEXT "The current version does not support upgrading to the latest update.zip. Please remake the bootloader disk!")" 0 0
      return 1
    fi
  fi
  DIALOG --title "${T}" \
    --infobox "$(TEXT "Installing new files ...")" 0 0
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
      mv -f "${TMP_PATH}/$(basename "${KEY}")" "${VALUE}"
    fi
  done < <(readConfigMap "replace" "${TMP_PATH}/update-list.yml")
  DIALOG --title "${T}" \
    --msgbox "$(printf "$(TEXT "RR updated with success to %s!\nReboot?")" "${TAG}")" 0 0
  rebootTo config
}

# 1 - ext name
# 2 - silent
function updateExts() {
  T="$(printf "$(TEXT "Update %s")" "${1}")"
  DIALOG --title "${T}" \
    --infobox "$(TEXT "Extracting last version")" 0 0
  if [ "${1}" = "addons" ]; then
    rm -rf "${TMP_PATH}/addons"
    mkdir -p "${TMP_PATH}/addons"
    unzip "${TMP_PATH}/addons.zip" -d "${TMP_PATH}/addons" >/dev/null 2>&1
    DIALOG --title "${T}" \
      --infobox "$(printf "$(TEXT "Installing new %s ...")" "${1}")" 0 0
    rm -Rf "${ADDONS_PATH}/"*
    [ -f "${TMP_PATH}/addons/VERSION" ] && cp -f "${TMP_PATH}/addons/VERSION" "${ADDONS_PATH}/"
    for PKG in $(ls ${TMP_PATH}/addons/*.addon); do
      ADDON=$(basename ${PKG} | sed 's|.addon||')
      rm -rf "${ADDONS_PATH}/${ADDON}"
      mkdir -p "${ADDONS_PATH}/${ADDON}"
      tar -xaf "${PKG}" -C "${ADDONS_PATH}/${ADDON}" >/dev/null 2>&1
    done
  elif [ "${1}" = "modules" ]; then
    rm -rf "${MODULES_PATH}/"*
    unzip ${TMP_PATH}/modules.zip -d "${MODULES_PATH}" >/dev/null 2>&1
    # Rebuild modules if model/buildnumber is selected
    PLATFORM="$(readModelKey "${MODEL}" "platform")"
    KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
    KPRE="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kpre")"
    if [ -n "${PLATFORM}" -a -n "${KVER}" ]; then
      writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
      while read ID DESC; do
        writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
      done < <(getAllModules "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}")
    fi
  elif [ "${1}" = "LKMs" ]; then
    rm -rf "${LKM_PATH}/"*
    unzip "${TMP_PATH}/rp-lkms.zip" -d "${LKM_PATH}" >/dev/null 2>&1
  fi
  touch ${PART1_PATH}/.build
  if [ ! "${2}" = "0" ]; then
    DIALOG --title "${T}" \
      --infobox "$(printf "$(TEXT "%s updated with success!")" "${1}")" 0 0
  else
    DIALOG --title "${T}" \
      --msgbox "$(printf "$(TEXT "%s updated with success!")" "${1}")" 0 0
  fi
}

###############################################################################
function updateMenu() {
  while true; do
    CUR_RR_VER="${RR_VERSION:-0}"
    CUR_ADDONS_VER="$(cat "${PART3_PATH}/addons/VERSION" 2>/dev/null)"
    CUR_MODULES_VER="$(cat "${PART3_PATH}/modules/VERSION" 2>/dev/null)"
    CUR_LKMS_VER="$(cat "${PART3_PATH}/lkms/VERSION" 2>/dev/null)"
    rm -f "${TMP_PATH}/menu"
    echo "a \"$(TEXT "Update all")\"" >>"${TMP_PATH}/menu"
    echo "r \"$(TEXT "Update RR")(${CUR_RR_VER:-None})\"" >>"${TMP_PATH}/menu"
    echo "d \"$(TEXT "Update addons")(${CUR_ADDONS_VER:-None})\"" >>"${TMP_PATH}/menu"
    echo "m \"$(TEXT "Update modules")(${CUR_MODULES_VER:-None})\"" >>"${TMP_PATH}/menu"
    echo "l \"$(TEXT "Update LKMs")(${CUR_LKMS_VER:-None})\"" >>"${TMP_PATH}/menu"
    echo "u \"$(TEXT "Local upload")\"" >>"${TMP_PATH}/menu"
    echo "b \"$(TEXT "Pre Release:") \Z4${PRERELEASE}\Zn\"" >>"${TMP_PATH}/menu"
    echo "e \"$(TEXT "Exit")\"" >>"${TMP_PATH}/menu"

    DIALOG --title "$(TEXT "Update")" \
      --menu "$(TEXT "Choose a option")" 0 0 0 --file "${TMP_PATH}/menu" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "$(<${TMP_PATH}/resp)" in
    a)
      T="$(printf "$(TEXT "Update %s")" "$(TEXT "addons")")"
      downloadExts "addons" "${CUR_ADDONS_VER:-None}" "https://github.com/wjz304/rr-addons" "addons" "1"
      [ $? -eq 0 ] && updateExts "addons" "1"
      T="$(printf "$(TEXT "Update %s")" "$(TEXT "modules")")"
      downloadExts "modules" "${CUR_MODULES_VER:-None}" "https://github.com/wjz304/rr-modules" "modules" "1"
      [ $? -eq 0 ] && updateExts "modules" "1"
      T="$(printf "$(TEXT "Update %s")" "$(TEXT "LKMs")")"
      downloadExts "LKMs" "${CUR_LKMS_VER:-None}" "https://github.com/wjz304/rr-lkms" "rp-lkms" "1"
      [ $? -eq 0 ] && updateExts "LKMs" "1"
      T="$(printf "$(TEXT "Update %s")" "$(TEXT "RR")")"
      downloadExts "RR" "${CUR_RR_VER:-None}" "https://github.com/wjz304/rr" "update" "0"
      [ $? -ne 0 ] && continue
      updateRR "RR"
      ;;
    r)
      T="$(printf "$(TEXT "Update %s")" "$(TEXT "RR")")"
      downloadExts "RR" "${CUR_RR_VER:-None}" "https://github.com/wjz304/rr" "update" "0"
      [ $? -ne 0 ] && continue
      updateRR "RR"
      ;;
    d)
      T="$(printf "$(TEXT "Update %s")" "$(TEXT "addons")")"
      downloadExts "addons" "${CUR_ADDONS_VER:-None}" "https://github.com/wjz304/rr-addons" "addons" "0"
      [ $? -ne 0 ] && continue
      updateExts "addons" "0"
      ;;
    m)
      T="$(printf "$(TEXT "Update %s")" "$(TEXT "modules")")"
      downloadExts "modules" "${CUR_MODULES_VER:-None}" "https://github.com/wjz304/rr-modules" "modules" "0"
      [ $? -ne 0 ] && continue
      updateExts "modules" "0"
      ;;
    l)
      T="$(printf "$(TEXT "Update %s")" "$(TEXT "LKMs")")"
      downloadExts "LKMs" "${CUR_LKMS_VER:-None}" "https://github.com/wjz304/rr-lkms" "rp-lkms" "0"
      [ $? -ne 0 ] && continue
      updateExts "LKMs" "0"
      ;;
    u)
      if ! tty | grep -q "/dev/pts"; then
        DIALOG --title "$(TEXT "Update")" \
          --msgbox "$(TEXT "This feature is only available when accessed via web/ssh.")" 0 0
        return
      fi
      MSG=""
      MSG+="$(TEXT "Please keep the attachment name consistent with the attachment name on Github.\n")"
      MSG+="$(TEXT "Upload update.zip will update RR.\n")"
      MSG+="$(TEXT "Upload addons.zip will update Addons.\n")"
      MSG+="$(TEXT "Upload modules.zip will update Modules.\n")"
      MSG+="$(TEXT "Upload rp-lkms.zip will update LKMs.\n")"
      DIALOG --title "$(TEXT "Update")" \
        --msgbox "${MSG}" 0 0
      EXTS=("update.zip" "addons.zip" "modules.zip" "rp-lkms.zip")
      TMP_UP_PATH="${TMP_PATH}/users"
      USER_FILE=""
      rm -rf "${TMP_UP_PATH}"
      mkdir -p "${TMP_UP_PATH}"
      pushd "${TMP_UP_PATH}"
      rz -be -B 536870912
      for F in $(ls -A); do
        for I in ${EXTS[@]}; do
          [[ "${I}" == "${F}" ]] && USER_FILE="${F}"
        done
        break
      done
      popd
      if [ -z "${USER_FILE}" ]; then
        DIALOG --title "$(TEXT "Update")" \
          --msgbox "$(TEXT "Not a valid file, please try again!")" 0 0
      else
        rm -f "${TMP_PATH}/${USER_FILE}"
        mv -f "${TMP_UP_PATH}/${USER_FILE}" "${TMP_PATH}/${USER_FILE}"
        if [ "${USER_FILE}" = "update.zip" ]; then
          updateRR "RR"
        elif [ "${USER_FILE}" = "addons.zip" ]; then
          updateExts "addons" "0"
        elif [ "${USER_FILE}" = "modules.zip" ]; then
          updateExts "modules" "0"
        elif [ "${USER_FILE}" = "rp-lkms.zip" ]; then
          updateExts "LKMs" "0"
        else
          DIALOG --title "$(TEXT "Update")" \
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
  DIALOG \
    --editbox "${USER_UP_PATH}/notepad" 0 0 2>"${TMP_PATH}/notepad"
  [ $? -ne 0 ] && return
  mv -f "${TMP_PATH}/notepad" "${USER_UP_PATH}/notepad"
}

###############################################################################
###############################################################################

if [ "x$1" = "xb" -a -n "${MODEL}" -a -n "${PRODUCTVER}" -a loaderIsConfigured ]; then
  updateAddons
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
  if [ ${CLEARCACHE} -eq 1 -a -d "${PART3_PATH}/dl" ]; then
    echo "c \"$(TEXT "Clean disk cache")\"" >>"${TMP_PATH}/menu"
  fi
  echo "p \"$(TEXT "Update menu")\"" >>"${TMP_PATH}/menu"
  echo "t \"$(TEXT "Notepad")\"" >>"${TMP_PATH}/menu"
  echo "e \"$(TEXT "Exit")\"" >>"${TMP_PATH}/menu"

  DIALOG --title "$(TEXT "Main menu")" \
    --default-item ${NEXT} --menu "$(TEXT "Choose a option")" 0 0 0 --file "${TMP_PATH}/menu" \
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
    DIALOG \
      --prgbox "rm -rfv \"${PART3_PATH}/dl\"" 0 0
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
      DIALOG \
        --default-item ${NEXT} --menu "$(TEXT "Choose a action")" 0 0 0 \
        p "$(TEXT "Poweroff")" \
        r "$(TEXT "Reboot")" \
        c "$(TEXT "Reboot to RR")" \
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
        rebootTo config
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
