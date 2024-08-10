#!/usr/bin/env bash

[ -z "${WORK_PATH}" -o ! -d "${WORK_PATH}/include" ] && WORK_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. ${WORK_PATH}/include/functions.sh
. ${WORK_PATH}/include/addons.sh
. ${WORK_PATH}/include/modules.sh

[ -z "${LOADER_DISK}" ] && die "$(TEXT "Loader is not init!")"

alias DIALOG='dialog --backtitle "$(backtitle)" --colors --aspect 50'

# Check partition 3 space, if < 2GiB is necessary clean cache folder
SPACELEFT=$(df -m ${PART3_PATH} 2>/dev/null | awk 'NR==2 {print $4}')
CLEARCACHE=0
if [ ${SPACELEFT:-0} -lt 430 ]; then
  CLEARCACHE=1
fi

# Get actual IP
IP="$(getIP)"
[[ "${IP}" =~ ^169\.254\..* ]] && IP=""

# Debug flag
# DEBUG=""

PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
MODELID="$(readConfigKey "modelid" "${USER_CONFIG_FILE}")"
PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
SMALLNUM="$(readConfigKey "smallnum" "${USER_CONFIG_FILE}")"
LAYOUT="$(readConfigKey "layout" "${USER_CONFIG_FILE}")"
KEYMAP="$(readConfigKey "keymap" "${USER_CONFIG_FILE}")"
KERNEL="$(readConfigKey "kernel" "${USER_CONFIG_FILE}")"
RD_COMPRESSED="$(readConfigKey "rd-compressed" "${USER_CONFIG_FILE}")"
SATADOM="$(readConfigKey "satadom" "${USER_CONFIG_FILE}")"
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
EMMCBOOT="$(readConfigKey "emmcboot" "${USER_CONFIG_FILE}")"
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
  BACKTITLE=""
  if [ "LOCALBUILD" = "${LOADER_DISK}" ]; then
    BACKTITLE="LOCAL "
  fi
  BACKTITLE+="$([ -z "${RR_RELEASE}" ] && echo "${RR_TITLE}" || echo "${RR_TITLE}(${RR_RELEASE})")"
  if [ -n "${MODEL}" ]; then
    BACKTITLE+=" ${MODEL}(${PLATFORM})"
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
    DIALOG --title "$(TEXT "Model")" \
      --infobox "$(TEXT "Getting models ...")" 0 0
  fi
  PS="$(readConfigEntriesArray "platforms" "${WORK_PATH}/platforms.yml" | sort)"
  MJ="$(python ${WORK_PATH}/include/functions.py getmodels -p "${PS[*]}")"
  if [ -z "${MJ}" -o "${MJ}" = "[]" ]; then
    if _get_fastest synology.com >/dev/null 2>&1; then
      DIALOG --title "$(TEXT "Model")" \
        --msgbox "$(TEXT "Failed to get models, Please check the network and try again, or use 'Parse Pat'!")" 0 0
    else
      DIALOG --title "$(TEXT "Model")" \
        --msgbox "$(TEXT "Unable to connect to Synology website, Please check the network and try again, or use 'Parse Pat'!")" 0 0
    fi
    return 1
  fi
  echo -n "" >"${TMP_PATH}/modellist"
  echo "${MJ}" | jq -c '.[]' | while read -r item; do
    name=$(echo "$item" | jq -r '.name')
    arch=$(echo "$item" | jq -r '.arch')
    echo "${name} ${arch}" >>"${TMP_PATH}/modellist"
  done

  if [ -z "${1}" ]; then
    RESTRICT=1
    while true; do
      echo -n "" >"${TMP_PATH}/menu"
      FLGNEX=0
      while read M A; do
        COMPATIBLE=1
        if [ ${RESTRICT} -eq 1 ]; then
          for F in $(readConfigArray "platforms.${A}.flags" "${WORK_PATH}/platforms.yml"); do
            if ! grep -q "^flags.*${F}.*" /proc/cpuinfo; then
              COMPATIBLE=0
              FLGNEX=1
              break
            fi
          done
        fi
        [ "$(readConfigKey "platforms.${A}.dt" "${WORK_PATH}/platforms.yml")" = "true" ] && DT="DT" || DT=""
        [ ${COMPATIBLE} -eq 1 ] && echo "${M} \"$(printf "\Zb%-15s %-2s\Zn" "${A}" "${DT}")\" " >>"${TMP_PATH}/menu"
      done <<<$(cat "${TMP_PATH}/modellist")
      [ ${FLGNEX} -eq 1 ] && echo "f \"\Z1$(TEXT "Disable flags restriction")\Zn\"" >>"${TMP_PATH}/menu"
      DIALOG --title "$(TEXT "Model")" \
        --menu "$(TEXT "Choose the model")" 0 0 20 --file "${TMP_PATH}/menu" \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && return 0
      resp=$(cat ${TMP_PATH}/resp)
      [ -z "${resp}" ] && return 1
      if [ "${resp}" = "f" ]; then
        RESTRICT=0
        continue
      fi
      break
    done
  else
    cat "${TMP_PATH}/modellist" | awk '{print $1}' | grep -qw "${1}" || return 1
    resp="${1}"
  fi
  # If user change model, clean build* and pat* and SN
  if [ "${MODEL}" != "${resp}" ]; then
    PLATFORM="$(grep -w "${resp}" "${TMP_PATH}/modellist" | awk '{print $2}' | head -n 1)"
    MODEL="${resp}"
    writeConfigKey "platform" "${PLATFORM}" "${USER_CONFIG_FILE}"
    writeConfigKey "model" "${MODEL}" "${USER_CONFIG_FILE}"
    MODELID=""
    PRODUCTVER=""
    BUILDNUM=""
    SMALLNUM=""
    writeConfigKey "modelid" "${MODELID}" "${USER_CONFIG_FILE}"
    writeConfigKey "productver" "${PRODUCTVER}" "${USER_CONFIG_FILE}"
    writeConfigKey "buildnum" "${BUILDNUM}" "${USER_CONFIG_FILE}"
    writeConfigKey "smallnum" "${SMALLNUM}" "${USER_CONFIG_FILE}"
    writeConfigKey "paturl" "" "${USER_CONFIG_FILE}"
    writeConfigKey "patsum" "" "${USER_CONFIG_FILE}"
    SN="$(generateSerial "${MODEL}")"
    writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
    NETIF_NUM=2
    MACS=($(generateMacAddress "${MODEL}" ${NETIF_NUM}))
    for I in $(seq 1 ${NETIF_NUM}); do
      writeConfigKey "mac${I}" "${MACS[$((${I} - 1))]}" "${USER_CONFIG_FILE}"
    done
    writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
    writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
    # Remove old files
    rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}" >/dev/null 2>&1 || true
    rm -f "${PART1_PATH}/grub_cksum.syno" "${PART1_PATH}/GRUB_VER" "${PART2_PATH}/"* >/dev/null 2>&1 || true
    touch ${PART1_PATH}/.build
  fi
  rm -f "${TMP_PATH}/modellist"
  return 0
}

###############################################################################
# Shows available buildnumbers from a model to user choose one
function productversMenu() {
  ITEMS="$(readConfigEntriesArray "platforms.${PLATFORM}.productvers" "${WORK_PATH}/platforms.yml" | sort -r)"
  if [ -z "${1}" ]; then
    DIALOG --title "$(TEXT "Product Version")" \
      --no-items --menu "$(TEXT "Choose a product version")" 0 0 0 ${ITEMS} \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return 0
    resp=$(cat ${TMP_PATH}/resp)
    [ -z "${resp}" ] && return 1

    if [ "${PRODUCTVER}" = "${resp}" ]; then
      DIALOG --title "$(TEXT "Product Version")" \
        --yesno "$(printf "$(TEXT "The current version has been set to %s. Do you want to reset the version?")" "${PRODUCTVER}")" 0 0
      [ $? -ne 0 ] && return 0
    fi
  else
    arrayExistItem "${1}" ${ITEMS} || return 1
    resp="${1}"
  fi
  selver="${resp}"
  urlver=""
  paturl=""
  patsum=""
  # KVER=$(readConfigKey "platforms.${PLATFORM}.productvers.[${resp}].kver" "${WORK_PATH}/platforms.yml")
  # if [ $(echo "${KVER:-4}" | cut -d'.' -f1) -lt 4 ] && [ -d "/sys/firmware/efi" ]; then
  #   if [ -z "${1}" ]; then
  #     DIALOG --title "$(TEXT "Product Version")" \
  #       --msgbox "$(TEXT "This version does not support UEFI startup, Please select another version or switch the startup mode.")" 0 0
  #   fi
  #   return 1
  # fi
  # if [ ! "usb" = "$(getBus "${LOADER_DISK}")" ] && [ $(echo "${KVER:-4}" | cut -d'.' -f1) -gt 4 ]; then
  #   if [ -z "${1}" ]; then
  #     DIALOG --title "$(TEXT "Product Version")" \
  #       --msgbox "$(TEXT "This version only support usb startup, Please select another version or switch the startup mode.")" 0 0
  #   fi
  #   return
  # fi
  if [ -z "${2}" -a -z "${3}" ]; then
    while true; do
      # get online pat data
      idx=1
      NETERR=0
      while [ ${idx} -le 3 ]; do # Loop 3 times, if successful, break
        if [ -z "${1}" ]; then
          DIALOG --title "$(TEXT "Product Version")" \
            --infobox "$(TEXT "Get pat data ...") (${idx}/3)" 0 0
        fi
        idx=$((${idx} + 1))
        NETERR=0
        fastest=$(_get_fastest "www.synology.com" "www.synology.cn")
        if [ $? -ne 0 ]; then
          NETERR=1
          continue
        fi
        [ "${fastest}" = "www.synology.cn" ] &&
          fastest="https://www.synology.cn/api/support/findDownloadInfo?lang=zh-cn" ||
          fastest="https://www.synology.com/api/support/findDownloadInfo?lang=en-us"
        patdata=$(curl -skL --connect-timeout 10 "${fastest}&product=${MODEL/+/%2B}&major=${selver%%.*}&minor=${selver##*.}")
        if [ "$(echo ${patdata} | jq -r '.success' 2>/dev/null)" = "true" ]; then
          if echo ${patdata} | jq -r '.info.system.detail[0].items[0].files[0].label_ext' 2>/dev/null | grep -q 'pat'; then
            major=$(echo ${patdata} | jq -r '.info.system.detail[0].items[0].major')
            minor=$(echo ${patdata} | jq -r '.info.system.detail[0].items[0].minor')
            urlver="${major}.${minor}"
            paturl=$(echo ${patdata} | jq -r '.info.system.detail[0].items[0].files[0].url')
            patsum=$(echo ${patdata} | jq -r '.info.system.detail[0].items[0].files[0].checksum')
            paturl=${paturl%%\?*}
            break
          fi
        fi
      done
      if [ -z "${paturl}" -o -z "${patsum}" ]; then
        if [ ${NETERR} -ne 0 ]; then
          MSG=""
          MSG+="$(TEXT "Unable to connect to Synology website, Please check the network and try again, or use 'Parse Pat'!")"
        else
          MSG="$(TEXT "Failed to get pat data,\nPlease manually fill in the URL and md5sum of the corresponding version of pat.\nOr click 'Retry'.")"
        fi
        paturl=""
        patsum=""
      else
        MSG=""
        MSG+="$(TEXT "Successfully to get pat data.")\n"
        if [ ! "${selver}" = "${urlver}" ]; then
          MSG+="$(printf "$(TEXT "Note: There is no version %s and automatically returns to version %s.")" "${selver}" "${urlver}")\n"
          selver=${urlver}
        fi
        MSG+="$(TEXT "Please confirm or modify the URL and md5sum to you need.")"
      fi
      if [ -z "${1}" ]; then
        DIALOG --title "$(TEXT "Product Version")" \
          --extra-button --extra-label "$(TEXT "Retry")" \
          --form "${MSG}" 10 110 2 "URL" 1 1 "${paturl}" 1 5 100 0 "MD5" 2 1 "${patsum}" 2 5 100 0 \
          2>"${TMP_PATH}/resp"
        RET=$?
      else
        echo -e "${paturl}\n${patsum}" >"${TMP_PATH}/resp"
        RET=0
      fi
      [ ${RET} -eq 0 ] && break    # ok-button
      [ ${RET} -eq 3 ] && continue # extra-button
      return 0                     # 1 or 255  # cancel-button or ESC
    done
    paturl="$(cat "${TMP_PATH}/resp" | sed -n '1p')"
    patsum="$(cat "${TMP_PATH}/resp" | sed -n '2p')"
  else
    paturl="${2}"
    patsum="${3}"
  fi
  [ -z "${paturl}" -o -z "${patsum}" ] && return 1
  writeConfigKey "paturl" "${paturl}" "${USER_CONFIG_FILE}"
  writeConfigKey "patsum" "${patsum}" "${USER_CONFIG_FILE}"
  PRODUCTVER=${selver}
  writeConfigKey "productver" "${PRODUCTVER}" "${USER_CONFIG_FILE}"
  BUILDNUM=""
  SMALLNUM=""
  writeConfigKey "buildnum" "${BUILDNUM}" "${USER_CONFIG_FILE}"
  writeConfigKey "smallnum" "${SMALLNUM}" "${USER_CONFIG_FILE}"
  if [ -z "${1}" ]; then
    DIALOG --title "$(TEXT "Product Version")" \
      --infobox "$(TEXT "Reconfiguring Synoinfo, Addons and Modules ...")" 0 0
  fi
  # Delete synoinfo and reload model/build synoinfo
  writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
  while IFS=': ' read KEY VALUE; do
    writeConfigKey "synoinfo.\"${KEY}\"" "${VALUE}" "${USER_CONFIG_FILE}"
  done <<<$(readConfigMap "platforms.${PLATFORM}.synoinfo" "${WORK_PATH}/platforms.yml")
  KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${WORK_PATH}/platforms.yml")"
  KPRE="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kpre" "${WORK_PATH}/platforms.yml")"
  # Check kernel
  if [ -f "${CKS_PATH}/bzImage-${PLATFORM}-$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}.gz" ] &&
    [ -f "${CKS_PATH}/modules-${PLATFORM}-$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}.tgz" ]; then
    :
  else
    KERNEL='official'
    writeConfigKey "kernel" "${KERNEL}" "${USER_CONFIG_FILE}"
  fi
  # Check addons
  while IFS=': ' read ADDON PARAM; do
    [ -z "${ADDON}" ] && continue
    if ! checkAddonExist "${ADDON}" "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}"; then
      deleteConfigKey "addons.\"${ADDON}\"" "${USER_CONFIG_FILE}"
    fi
  done <<<$(readConfigMap "addons" "${USER_CONFIG_FILE}")
  # Rewrite modules
  writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
  while read ID DESC; do
    writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
  done <<<$(getAllModules "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}")
  # Remove old files
  rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}" >/dev/null 2>&1 || true
  rm -f "${PART1_PATH}/grub_cksum.syno" "${PART1_PATH}/GRUB_VER" "${PART2_PATH}/"* >/dev/null 2>&1 || true
  touch ${PART1_PATH}/.build
  return 0
}

function setConfigFromDSM() {
  DSM_ROOT="${1}"
  if [ ! -f "${DSM_ROOT}/GRUB_VER" -o ! -f "${DSM_ROOT}/VERSION" ]; then
    echo -e "$(TEXT "DSM Invalid, try again!")" >"${LOG_FILE}"
    return 1
  fi

  PLATFORMTMP="$(_get_conf_kv "PLATFORM" ${DSM_ROOT}/GRUB_VER)"
  MODELTMP="$(_get_conf_kv "MODEL" ${DSM_ROOT}/GRUB_VER)"
  majorversion="$(_get_conf_kv "majorversion" ${DSM_ROOT}/VERSION)"
  minorversion="$(_get_conf_kv "minorversion" ${DSM_ROOT}/VERSION)"
  buildnumber="$(_get_conf_kv "buildnumber" ${DSM_ROOT}/VERSION)"
  smallfixnumber="$(_get_conf_kv "smallfixnumber" ${DSM_ROOT}/VERSION)"
  if [ -z "${PLATFORMTMP}" -o -z "${MODELTMP}" -o -z "${majorversion}" -o -z "${minorversion}" ]; then
    echo -e "$(TEXT "DSM Invalid, try again!")" >"${LOG_FILE}"
    return 1
  fi
  PS="$(readConfigEntriesArray "platforms" "${WORK_PATH}/platforms.yml" | sort)"
  VS="$(readConfigEntriesArray "platforms.${PLATFORMTMP,,}.productvers" "${WORK_PATH}/platforms.yml" | sort -r)"
  if arrayExistItem "${PLATFORMTMP,,}" ${PS} && arrayExistItem "${majorversion}.${minorversion}" ${VS}; then
    PLATFORM="${PLATFORMTMP,,}"
    MODEL="$(echo ${MODELTMP} | sed 's/d$/D/; s/rp$/RP/; s/rp+/RP+/')"
    MODELID="${MODELTMP}"
    PRODUCTVER="${majorversion}.${minorversion}"
    BUILDNUM="${buildnumber}"
    SMALLNUM="${smallfixnumber}"
  else
    echo "$(printf "$(TEXT "Currently, %s is not supported.")" "${MODELTMP}-${majorversion}.${minorversion}")" >"${LOG_FILE}"
    return 1
  fi

  echo "$(TEXT "Reconfiguring Synoinfo, Addons and Modules ...")"

  writeConfigKey "platform" "${PLATFORM}" "${USER_CONFIG_FILE}"
  writeConfigKey "model" "${MODEL}" "${USER_CONFIG_FILE}"
  writeConfigKey "modelid" "${MODELID}" "${USER_CONFIG_FILE}"
  SN="$(generateSerial "${MODEL}")"
  writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
  NETIF_NUM=2
  MACS=($(generateMacAddress "${MODEL}" ${NETIF_NUM}))
  for I in $(seq 1 ${NETIF_NUM}); do
    writeConfigKey "mac${I}" "${MACS[$((${I} - 1))]}" "${USER_CONFIG_FILE}"
  done

  writeConfigKey "productver" "${PRODUCTVER}" "${USER_CONFIG_FILE}"
  writeConfigKey "buildnum" "${BUILDNUM}" "${USER_CONFIG_FILE}"
  writeConfigKey "smallnum" "${SMALLNUM}" "${USER_CONFIG_FILE}"

  writeConfigKey "paturl" "#" "${USER_CONFIG_FILE}"
  writeConfigKey "patsum" "#" "${USER_CONFIG_FILE}"

  # Delete synoinfo and reload model/build synoinfo
  writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
  while IFS=': ' read KEY VALUE; do
    writeConfigKey "synoinfo.\"${KEY}\"" "${VALUE}" "${USER_CONFIG_FILE}"
  done <<<$(readConfigMap "platforms.${PLATFORM}.synoinfo" "${WORK_PATH}/platforms.yml")

  # Check addons
  KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${WORK_PATH}/platforms.yml")"
  KPRE="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kpre" "${WORK_PATH}/platforms.yml")"
  while IFS=': ' read ADDON PARAM; do
    [ -z "${ADDON}" ] && continue
    if ! checkAddonExist "${ADDON}" "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}"; then
      deleteConfigKey "addons.\"${ADDON}\"" "${USER_CONFIG_FILE}"
    fi
  done <<<$(readConfigMap "addons" "${USER_CONFIG_FILE}")
  # Rebuild modules
  writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
  while read ID DESC; do
    writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
  done <<<$(getAllModules "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}")
  touch ${PART1_PATH}/.build
  return 0
}

###############################################################################
# Parse Pat
function ParsePat() {
  if [ -n "${MODEL}" -a -n "${PRODUCTVER}" ]; then
    MSG="$(printf "$(TEXT "You have selected the %s and %s.\n'Parse Pat' will overwrite the previous selection.\nDo you want to continue?")" "${MODEL}" "${PRODUCTVER}")"
    DIALOG --title "$(TEXT "Parse Pat")" \
      --yesno "${MSG}" 0 0
    [ $? -ne 0 ] && return
  fi
  mkdir -p "${TMP_PATH}/pats"
  PAT_PATH=""
  ITEMS="$(ls ${TMP_PATH}/pats/*.pat 2>/dev/null)"
  if [ -z "${ITEMS}" ]; then
    MSG=""
    MSG+="$(TEXT "No pat file found in /tmp/pats/ folder!\n")"
    MSG+="$(TEXT "Please upload the pat file to /tmp/pats/ folder via DUFS and re-enter this option.\n")"
    DIALOG --title "$(TEXT "Update")" \
      --msgbox "${MSG}" 0 0
    return
  fi
  DIALOG --title "$(TEXT "Parse Pat")" \
    --no-items --menu "$(TEXT "Choose a pat file")" 0 0 0 ${ITEMS} \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  PAT_PATH=$(cat ${TMP_PATH}/resp)
  if [ ! -f "${PAT_PATH}" ]; then
    DIALOG --title "$(TEXT "Parse Pat")" \
      --msgbox "$(TEXT "pat Invalid, try again!")" 0 0
    return
  fi

  while true; do
    rm -f "${LOG_FILE}"
    echo "$(printf "$(TEXT "Parse %s ...")" "$(basename "${PAT_PATH}")")"
    extractPatFiles "${PAT_PATH}" "${UNTAR_PAT_PATH}"
    if [ $? -ne 0 ]; then
      rm -rf "${UNTAR_PAT_PATH}"
      break
    fi

    mkdir -p "${PART3_PATH}/dl"
    # Check disk space left
    SPACELEFT=$(df -m ${PART3_PATH} 2>/dev/null | awk 'NR==2 {print $4}')
    # Discover remote file size
    FILESIZE=$(du -sm "${PAT_PATH}" 2>/dev/null | awk '{print $1}')
    if [ ${FILESIZE:-0} -ge ${SPACELEFT:-0} ]; then
      # No disk space to copy, mv it to dl
      mv -f "${PAT_PATH}" "${PART3_PATH}/dl/${MODEL}-${PRODUCTVER}.pat"
    else
      cp -f "${PAT_PATH}" "${PART3_PATH}/dl/${MODEL}-${PRODUCTVER}.pat"
    fi

    setConfigFromDSM "${UNTAR_PAT_PATH}"
    if [ $? -ne 0 ]; then
      rm -rf "${UNTAR_PAT_PATH}"
      break
    fi
    writeConfigKey "paturl" "#PARSEPAT" "${USER_CONFIG_FILE}"
    writeConfigKey "patsum" "" "${USER_CONFIG_FILE}"
    copyDSMFiles "${UNTAR_PAT_PATH}"

    touch ${PART1_PATH}/.build
    rm -rf "${UNTAR_PAT_PATH}"
    rm -f "${LOG_FILE}"
    echo "$(TEXT "Ready!")"
    sleep 3
    break
  done 2>&1 | DIALOG --title "$(TEXT "Parse Pat")" \
    --progressbox "$(TEXT "Making ...")" 20 100
  if [ -f "${LOG_FILE}" ]; then
    DIALOG --title "$(TEXT "Parse Pat")" \
      --msgbox "$(cat ${LOG_FILE})" 0 0
    rm -f "${LOG_FILE}"
    return 1
  else
    PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
    MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
    MODELID="$(readConfigKey "modelid" "${USER_CONFIG_FILE}")"
    PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
    BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
    SMALLNUM="$(readConfigKey "smallnum" "${USER_CONFIG_FILE}")"
    SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"
    MAC1="$(readConfigKey "mac1" "${USER_CONFIG_FILE}")"
    MAC2="$(readConfigKey "mac2" "${USER_CONFIG_FILE}")"
    return 0
  fi
}

###############################################################################
# Manage addons
function addonMenu() {
  # Read 'platform' and kernel version to check if addon exists
  KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${WORK_PATH}/platforms.yml")"
  KPRE="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kpre" "${WORK_PATH}/platforms.yml")"

  NEXT="a"
  # Loop menu
  while true; do
    # Read addons from user config
    unset ADDONS
    declare -A ADDONS
    while IFS=': ' read KEY VALUE; do
      [ -n "${KEY}" ] && ADDONS["${KEY}"]="${VALUE}"
    done <<<$(readConfigMap "addons" "${USER_CONFIG_FILE}")

    DIALOG --title "$(TEXT "Addons")" \
      --default-item ${NEXT} --menu "$(TEXT "Choose a option")" 0 0 0 \
      a "$(TEXT "Add an addon")" \
      d "$(TEXT "Delete addons")" \
      s "$(TEXT "Show all addons")" \
      u "$(TEXT "Upload a external addon")" \
      e "$(TEXT "Exit")" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "$(cat ${TMP_PATH}/resp)" in
    a)
      rm -f "${TMP_PATH}/menu"
      while read ADDON DESC; do
        arrayExistItem "${ADDON}" "${!ADDONS[@]}" && continue # Check if addon has already been added
        echo "${ADDON} \"${DESC}\"" >>"${TMP_PATH}/menu"
      done <<<$(availableAddons "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}")
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
      ADDON="$(cat "${TMP_PATH}/resp")"
      [ -z "${ADDON}" ] && continue
      DIALOG --title "$(TEXT "Addons")" \
        --inputbox "$(TEXT "Type a optional params to addon")" 0 70 \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && continue
      VALUE="$(cat "${TMP_PATH}/resp")"
      ADDONS[${ADDON}]="${VALUE}"
      writeConfigKey "addons.\"${ADDON}\"" "${VALUE}" "${USER_CONFIG_FILE}"
      touch ${PART1_PATH}/.build
      ;;
    d)
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
      ADDON="$(cat "${TMP_PATH}/resp")"
      [ -z "${ADDON}" ] && continue
      for I in ${ADDON}; do
        unset ADDONS[${I}]
        deleteConfigKey "addons.\"${I}\"" "${USER_CONFIG_FILE}"
      done
      touch ${PART1_PATH}/.build
      ;;
    s)
      MSG=""
      MSG+="$(TEXT "Name with color \"\Z4blue\Zn\" have been added, with color \"black\" are not added.\n\n")"
      while read MODULE DESC; do
        if arrayExistItem "${MODULE}" "${!ADDONS[@]}"; then
          MSG+="\Z4${MODULE}\Zn"
        else
          MSG+="${MODULE}"
        fi
        MSG+=": \Z5${DESC}\Zn\n"
      done <<<$(availableAddons "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}")
      DIALOG --title "$(TEXT "Addons")" \
        --msgbox "${MSG}" 0 0
      ;;
    u)
      if ! tty 2>/dev/null | grep -q "/dev/pts"; then #if ! tty 2>/dev/null | grep -q "/dev/pts" || [ -z "${SSH_TTY}" ]; then
        MSG=""
        MSG+="$(TEXT "This feature is only available when accessed via ssh (Requires a terminal that supports ZModem protocol).\n")"
        DIALOG --title "$(TEXT "Addons")" \
          --msgbox "${MSG}" 0 0
        continue
      fi
      DIALOG --title "$(TEXT "Addons")" \
        --msgbox "$(TEXT "Please upload the *.addons file.")" 0 0
      TMP_UP_PATH=${TMP_PATH}/users
      USER_FILE=""
      rm -rf ${TMP_UP_PATH}
      mkdir -p ${TMP_UP_PATH}
      pushd ${TMP_UP_PATH}
      rz -be
      for F in $(ls -A 2>/dev/null); do
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
          [ ${RET} -ne 0 ] && return
        fi
        ADDON="$(untarAddon "${TMP_UP_PATH}/${USER_FILE}")"
        if [ -n "${ADDON}" ]; then
          [ -f "${ADDONS_PATH}/VERSION" ] && rm -f "${ADDONS_PATH}/VERSION"
          DIALOG --title "$(TEXT "Addons")" \
            --msgbox "$(printf "$(TEXT "Addon '%s' added to loader, Please enable it in 'Add an addon' menu.")" "${ADDON}")" 0 0
          touch ${PART1_PATH}/.build
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
  KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${WORK_PATH}/platforms.yml")"
  KPRE="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kpre" "${WORK_PATH}/platforms.yml")"
  NEXT="c"
  # loop menu
  while true; do
    DIALOG --title "$(TEXT "Modules")" \
      --default-item ${NEXT} --menu "$(TEXT "Choose a option")" 0 0 0 \
      s "$(TEXT "Show/Select modules")" \
      l "$(TEXT "Select loaded modules")" \
      u "$(TEXT "Upload a external module")" \
      i "$(TEXT "Deselect i915 with dependencies")" \
      p "$(TEXT "Priority use of official drivers:") \Z4${ODP}\Zn" \
      f "$(TEXT "Edit modules that need to be copied to DSM")" \
      b "$(TEXT "modprobe blacklist")" \
      e "$(TEXT "Exit")" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && break
    case "$(cat ${TMP_PATH}/resp)" in
    s)
      while true; do
        DIALOG --title "$(TEXT "Modules")" \
          --infobox "$(TEXT "Reading modules ...")" 0 0
        ALLMODULES=$(getAllModules "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}")
        unset USERMODULES
        declare -A USERMODULES
        while IFS=': ' read KEY VALUE; do
          [ -n "${KEY}" ] && USERMODULES["${KEY}"]="${VALUE}"
        done <<<$(readConfigMap "modules" "${USER_CONFIG_FILE}")
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
          resp=$(cat ${TMP_PATH}/resp)
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
      for I in $(lsmod 2>/dev/null | awk -F' ' '{print $1}' | grep -v 'Module'); do
        KOLIST+="$(getdepends "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}" "${I}") ${I} "
      done
      KOLIST=($(echo ${KOLIST} | tr ' ' '\n' | sort -u))
      writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
      for ID in ${KOLIST[@]}; do
        writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
      done
      touch ${PART1_PATH}/.build
      ;;
    u)
      if ! tty 2>/dev/null | grep -q "/dev/pts"; then #if ! tty 2>/dev/null | grep -q "/dev/pts" || [ -z "${SSH_TTY}" ]; then
        MSG=""
        MSG+="$(TEXT "This feature is only available when accessed via ssh (Requires a terminal that supports ZModem protocol).\n")"
        DIALOG --title "$(TEXT "Modules")" \
          --msgbox "${MSG}" 0 0
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
      [ $? -ne 0 ] && continue
      DIALOG --title "$(TEXT "Modules")" \
        --msgbox "$(TEXT "Please upload the *.ko file.")" 0 0
      TMP_UP_PATH=${TMP_PATH}/users
      USER_FILE=""
      rm -rf ${TMP_UP_PATH}
      mkdir -p ${TMP_UP_PATH}
      pushd ${TMP_UP_PATH}
      rz -be
      for F in $(ls -A 2>/dev/null); do
        USER_FILE=${F}
        break
      done
      popd
      if [ -n "${USER_FILE}" -a "${USER_FILE##*.}" = "ko" ]; then
        addToModules ${PLATFORM} "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}" "${TMP_UP_PATH}/${USER_FILE}"
        [ -f "${MODULES_PATH}/VERSION" ] && rm -f "${MODULES_PATH}/VERSION"
        DIALOG --title "$(TEXT "Modules")" \
          --msgbox "$(printf "$(TEXT "Module '%s' added to %s-%s")" "${USER_FILE}" "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}")" 0 0
        rm -f "${TMP_UP_PATH}/${USER_FILE}"
        touch ${PART1_PATH}/.build
      else
        DIALOG --title "$(TEXT "Modules")" \
          --msgbox "$(TEXT "Not a valid file, please try again!")" 0 0
      fi
      ;;
    i)
      DEPS="$(getdepends "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}" i915) i915"
      DELS=()
      while IFS=': ' read KEY VALUE; do
        [ -z "${KEY}" ] && continue
        if echo "${DEPS}" | grep -wq "${KEY}"; then
          DELS+=("${KEY}")
        fi
      done <<<$(readConfigMap "modules" "${USER_CONFIG_FILE}")
      if [ ${#DELS[@]} -eq 0 ]; then
        DIALOG --title "$(TEXT "Modules")" \
          --msgbox "$(TEXT "No i915 with dependencies module to deselect.")" 0 0
      else
        for ID in ${DELS[@]}; do
          deleteConfigKey "modules.\"${ID}\"" "${USER_CONFIG_FILE}"
        done
        DIALOG --title "$(TEXT "Modules")" \
          --msgbox "$(printf "$(TEXT "Module %s deselected.\n")" "${DELS[@]}")" 0 0
      fi
      touch ${PART1_PATH}/.build
      ;;
    p)
      [ "${ODP}" = "false" ] && ODP='true' || ODP='false'
      writeConfigKey "odp" "${ODP}" "${USER_CONFIG_FILE}"
      touch ${PART1_PATH}/.build
      ;;
    f)
      if [ -f ${USER_UP_PATH}/modulelist ]; then
        cp -f "${USER_UP_PATH}/modulelist" "${TMP_PATH}/modulelist.tmp"
      else
        cp -f "${WORK_PATH}/patch/modulelist" "${TMP_PATH}/modulelist.tmp"
      fi
      while true; do
        DIALOG --title "$(TEXT "Edit with caution")" \
          --editbox "${TMP_PATH}/modulelist.tmp" 0 0 2>"${TMP_PATH}/modulelist.user"
        [ $? -ne 0 ] && break
        [ ! -d "${USER_UP_PATH}" ] && mkdir -p "${USER_UP_PATH}"
        mv -f "${TMP_PATH}/modulelist.user" "${USER_UP_PATH}/modulelist"
        dos2unix "${USER_UP_PATH}/modulelist"
        touch ${PART1_PATH}/.build
        break
      done
      ;;
    b)
      # modprobe.blacklist
      MSG=""
      MSG+="$(TEXT "The blacklist is used to prevent the kernel from loading specific modules.\n")"
      MSG+="$(TEXT "The blacklist is a list of module names separated by ','.\n")"
      MSG+="$(TEXT "For example: \Z4evbug,cdc_ether\Zn\n")"
      while true; do
        modblacklist="$(readConfigKey "modblacklist" "${USER_CONFIG_FILE}")"
        DIALOG --title "$(TEXT "Modules")" \
          --inputbox "${MSG}" 12 70 "${modblacklist}" \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && break
        VALUE="$(cat "${TMP_PATH}/resp")"
        if [[ ${VALUE} = *" "* ]]; then
          DIALOG --title "$(TEXT "Cmdline")" \
            --yesno "$(TEXT "Invalid list, No spaces should appear, retry?")" 0 0
          [ $? -eq 0 ] && continue || break
        fi
        writeConfigKey "modblacklist" "${VALUE}" "${USER_CONFIG_FILE}"
        break
      done
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
    # echo "m \"$(TEXT "Show model inherent cmdline")\"" >>"${TMP_PATH}/menu"
    echo "e \"$(TEXT "Exit")\"" >>"${TMP_PATH}/menu"
    DIALOG --title "$(TEXT "Cmdline")" \
      --menu "$(TEXT "Choose a option")" 0 0 0 --file "${TMP_PATH}/menu" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "$(cat ${TMP_PATH}/resp)" in
    a)
      MSG=""
      MSG+="$(TEXT "Commonly used cmdlines:\n")"
      MSG+="$(TEXT " * \Z4SpectreAll_on=\Zn\n    Enable Spectre and Meltdown protection to mitigate the threat of speculative execution vulnerability.\n")"
      MSG+="$(TEXT " * \Z4disable_mtrr_trim=\Zn\n    disables kernel trim any uncacheable memory out.\n")"
      MSG+="$(TEXT " * \Z4intel_idle.max_cstate=1\Zn\n    Set the maximum C-state depth allowed by the intel_idle driver.\n")"
      MSG+="$(TEXT " * \Z4pcie_port_pm=off\Zn\n    Turn off the power management of the PCIe port.\n")"
      MSG+="$(TEXT " * \Z4libata.force=noncq\Zn\n    Disable NCQ for all SATA ports.\n")"
      MSG+="$(TEXT " * \Z4SataPortMap=??\Zn\n    Sata Port Map(Not apply to DT models).\n")"
      MSG+="$(TEXT " * \Z4DiskIdxMap=??\Zn\n    Disk Index Map, Modify disk name sequence(Not apply to DT models).\n")"
      MSG+="$(TEXT " * \Z4ahci_remap=4>5:5>8:12>16\Zn\n    Remap data port sequence(Not apply to DT models).\n")"
      MSG+="$(TEXT " * \Z4i915.enable_guc=2\Zn\n    Enable the GuC firmware on Intel graphics hardware.(value: 1,2 or 3)\n")"
      MSG+="$(TEXT " * \Z4i915.max_vfs=7\Zn\n    Set the maximum number of virtual functions (VFs) that can be created for Intel graphics hardware.\n")"
      MSG+="$(TEXT " * \Z4i915.modeset=0\Zn\n    Disable the kernel mode setting (KMS) feature of the i915 driver.\n")"
      MSG+="$(TEXT " * \Z4apparmor.mode=complain\Zn\n    Set the AppArmor security module to complain mode.\n")"
      MSG+="$(TEXT " * \Z4pci=nommconf\Zn\n    Disable the use of Memory-Mapped Configuration for PCI devices(use this parameter cautiously).\n")"
      MSG+="$(TEXT " * \Z4consoleblank=300\Zn\n    Set the console to auto turnoff display 300 seconds after no activity (measured in seconds).\n")"
      MSG+="$(TEXT "Please enter the parameter key and value you need to add.\n")"

      LINENUM=0
      while read -r line; do LINENUM=$((LINENUM + 1 + ${#line} / 96)); done <<<"$(printf "${MSG}")" # When the width is 100, each line displays 96 characters.
      LINENUM=$((${LINENUM:-0} + 9))                                                                # When there are 2 parameters, 9 is the minimum value to include 1 line of MSG.

      DIALOG_MAXX=$(ttysize 2>/dev/null | awk '{print $1}')
      DIALOG_MAXY=$(ttysize 2>/dev/null | awk '{print $2}')
      if [ ${LINENUM:-0} -ge ${DIALOG_MAXY:-0} ]; then
        MSG="$(TEXT "Please enter the parameter key and value you need to add.\n")"
        LINENUM=9
      fi

      while true; do
        DIALOG --title "$(TEXT "Cmdline")" \
          --form "${MSG}" ${LINENUM:-9} 100 2 "Name:" 1 1 "" 1 10 85 0 "Value:" 2 1 "" 2 10 85 0 \
          2>"${TMP_PATH}/resp"
        RET=$?
        case ${RET} in
        0) # ok-button
          NAME="$(cat "${TMP_PATH}/resp" | sed -n '1p')"
          VALUE="$(cat "${TMP_PATH}/resp" | sed -n '2p')"
          if [ -z "${NAME//\"/}" ]; then
            DIALOG --title "$(TEXT "Cmdline")" \
              --yesno "$(TEXT "Invalid parameter name, retry?")" 0 0
            [ $? -eq 0 ] && continue || break
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
      done <<<$(readConfigMap "cmdline" "${USER_CONFIG_FILE}")
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
      RESP=$(cat "${TMP_PATH}/resp")
      [ -z "${RESP}" ] && continue
      for I in ${RESP}; do
        unset CMDLINE[${I}]
        deleteConfigKey "cmdline.\"${I}\"" "${USER_CONFIG_FILE}"
      done
      ;;
    s)
      MSG="$(TEXT "Note: (MAC will not be set to NIC, Only for activation services.)")"
      sn="${SN}"
      mac1="${MAC1}"
      mac2="${MAC2}"
      while true; do
        DIALOG --title "$(TEXT "Cmdline")" \
          --extra-button --extra-label "$(TEXT "Random")" \
          --form "${MSG}" 11 70 3 "sn" 1 1 "${sn}" 1 5 50 0 "mac1" 2 1 "${mac1}" 2 5 60 0 "mac2" 3 1 "${mac2}" 3 5 60 0 \
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
            [ $? -eq 0 ] && continue || break
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
          NETIF_NUM=2
          MACS=($(generateMacAddress "${MODEL}" ${NETIF_NUM}))
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
    # m)
    #   ITEMS=""
    #   while IFS=': ' read KEY VALUE; do
    #     ITEMS+="${KEY}: ${VALUE}\n"
    #   done <<<$(readConfigMap "platforms.${PLATFORM}.cmdline" "${WORK_PATH}/platforms.yml")
    #   DIALOG --title "$(TEXT "Cmdline")" \
    #     --msgbox "${ITEMS}" 0 0
    #   ;;
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
    case "$(cat ${TMP_PATH}/resp)" in
    a)
      MSG=""
      MSG+="$(TEXT "Commonly used synoinfo:\n")"
      MSG+="$(TEXT " * \Z4support_apparmor=no\Zn\n    Disable apparmor.\n")"
      MSG+="$(TEXT " * \Z4maxdisks=??\Zn\n    Maximum number of disks supported.\n")"
      MSG+="$(TEXT " * \Z4internalportcfg=0x????\Zn\n    Internal(sata) disks mask(Not apply to DT models).\n")"
      MSG+="$(TEXT " * \Z4esataportcfg=0x????\Zn\n    Esata disks mask(Not apply to DT models).\n")"
      MSG+="$(TEXT " * \Z4usbportcfg=0x????\Zn\n    USB disks mask(Not apply to DT models).\n")"
      MSG+="$(TEXT " * \Z4max_sys_raid_disks=12\Zn\n    Maximum number of system partition(md0) raid disks.\n")"
      MSG="$(TEXT "Please enter the parameter key and value you need to add.\n")"

      LINENUM=0
      while read -r line; do LINENUM=$((LINENUM + 1 + ${#line} / 96)); done <<<"$(printf "${MSG}")" # When the width is 100, each line displays 96 characters.
      LINENUM=$((${LINENUM:-0} + 9))                                                                # When there are 2 parameters, 9 is the minimum value to include 1 line of MSG.

      DIALOG_MAXX=$(ttysize 2>/dev/null | awk '{print $1}')
      DIALOG_MAXY=$(ttysize 2>/dev/null | awk '{print $2}')
      if [ ${LINENUM:-0} -ge ${DIALOG_MAXY:-0} ]; then
        MSG="$(TEXT "Please enter the parameter key and value you need to add.\n")"
        LINENUM=9
      fi

      while true; do
        DIALOG --title "$(TEXT "Synoinfo")" \
          --form "${MSG}" ${LINENUM:-9} 100 2 "Name:" 1 1 "" 1 10 85 0 "Value:" 2 1 "" 2 10 85 0 \
          2>"${TMP_PATH}/resp"
        RET=$?
        case ${RET} in
        0) # ok-button
          NAME="$(cat "${TMP_PATH}/resp" | sed -n '1p')"
          VALUE="$(cat "${TMP_PATH}/resp" | sed -n '2p')"
          if [ -z "${NAME//\"/}" ]; then
            DIALOG --title "$(TEXT "Synoinfo")" \
              --yesno "$(TEXT "Invalid parameter name, retry?")" 0 0
            [ $? -eq 0 ] && continue || break
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
      done <<<$(readConfigMap "synoinfo" "${USER_CONFIG_FILE}")
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
      RESP=$(cat "${TMP_PATH}/resp")
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
function getSynoExtractor() {
  rm -f "${LOG_FILE}"
  mirrors=("global.synologydownload.com" "global.download.synology.com" "cndl.synology.cn")
  fastest=$(_get_fastest ${mirrors[@]})
  if [ $? -ne 0 ]; then
    MSG="$(TEXT "Network error, please check the network connection and try again.")"
    echo -e "${MSG}" >"${LOG_FILE}"
    return 1
  fi
  OLDPAT_URL="https://${fastest}/download/DSM/release/7.0.1/42218/DSM_DS3622xs%2B_42218.pat"
  OLDPAT_PATH="${TMP_PATH}/DS3622xs+-42218.pat"
  EXTRACTOR_PATH="${PART3_PATH}/extractor"
  EXTRACTOR_BIN="syno_extract_system_patch"

  # Extractor not exists, get it.
  mkdir -p "${EXTRACTOR_PATH}"

  echo "$(TEXT "Downloading old pat to extract synology .pat extractor...")"
  rm -f "${OLDPAT_PATH}"
  STATUS=$(curl -kL --connect-timeout 10 -w "%{http_code}" "${OLDPAT_URL}" -o "${OLDPAT_PATH}")
  RET=$?
  if [ ${RET} -ne 0 -o ${STATUS:-0} -ne 200 ]; then
    rm -f "${OLDPAT_PATH}"
    MSG="$(printf "$(TEXT "Check internet or cache disk space.\nError: %d:%d\n(Please via https://curl.se/libcurl/c/libcurl-errors.html check error description.)")" "${RET}" "${STATUS}")"
    echo -e "${MSG}" >"${LOG_FILE}"
    return 1
  fi

  # Extract DSM ramdisk file from PAT
  rm -rf "${RAMDISK_PATH}"
  mkdir -p "${RAMDISK_PATH}"
  tar -xf "${OLDPAT_PATH}" -C "${RAMDISK_PATH}" rd.gz 2>"${LOG_FILE}"
  if [ $? -ne 0 ]; then
    rm -f "${OLDPAT_PATH}"
    rm -rf "${RAMDISK_PATH}"
    echo -e "$(TEXT "pat Invalid, try again!")" >"${LOG_FILE}"
    return 1
  fi
  rm -f "${OLDPAT_PATH}"
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

  return 0
}

###############################################################################
# Extract linux and ramdisk files from the DSM .pat
function extractPatFiles() {
  rm -f "${LOG_FILE}"
  PAT_PATH="${1}"
  EXT_PATH="${2}"

  header="$(od -bcN2 "${PAT_PATH}" | head -1 | awk '{print $3}')"
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
    echo -e "$(TEXT "Could not determine if pat file is encrypted or not, maybe corrupted, try again!")" >"${LOG_FILE}"
    return 1
    ;;
  esac

  rm -rf "${EXT_PATH}"
  mkdir -p "${EXT_PATH}"
  echo -n "$(printf "$(TEXT "Disassembling %s: ")" "$(basename "${PAT_PATH}")")"

  RET=0
  if [ "${isencrypted}" = "yes" ]; then
    EXTRACTOR_PATH="${PART3_PATH}/extractor"
    EXTRACTOR_BIN="syno_extract_system_patch"
    # Check existance of extractor
    if [ -f "${EXTRACTOR_PATH}/${EXTRACTOR_BIN}" ]; then
      echo "$(TEXT "Extractor cached.")"
    else
      getSynoExtractor
      [ $? -ne 0 ] && return 1
    fi
    # Uses the extractor to untar pat file
    echo "$(TEXT "Extracting ...")"
    LD_LIBRARY_PATH=${EXTRACTOR_PATH} "${EXTRACTOR_PATH}/${EXTRACTOR_BIN}" "${PAT_PATH}" "${EXT_PATH}" >"${LOG_FILE}" 2>&1
    RET=$?
  else
    echo "$(TEXT "Extracting ...")"
    tar -xf "${PAT_PATH}" -C "${EXT_PATH}" >"${LOG_FILE}" 2>&1
    RET=$?
  fi

  if [ ${RET} -ne 0 ] ||
    [ ! -f ${EXT_PATH}/grub_cksum.syno ] ||
    [ ! -f ${EXT_PATH}/GRUB_VER ] ||
    [ ! -f ${EXT_PATH}/zImage ] ||
    [ ! -f ${EXT_PATH}/rd.gz ]; then
    echo -e "$(TEXT "pat Invalid, try again!")\nError: ${RET}" >"${LOG_FILE}"
    return 1
  fi
  rm -f "${LOG_FILE}"
  return 0
}

###############################################################################
# Extract linux and ramdisk files from the DSM .pat
function extractDsmFiles() {
  rm -f "${LOG_FILE}"
  EXTRACTOR_PATH="${PART3_PATH}/extractor"
  EXTRACTOR_BIN="syno_extract_system_patch"

  PATURL="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
  PATSUM="$(readConfigKey "patsum" "${USER_CONFIG_FILE}")"

  PAT_FILE="${MODEL}-${PRODUCTVER}.pat"
  PAT_PATH="${PART3_PATH}/dl/${PAT_FILE}"

  [ -f "${PAT_PATH}" -a -f "${PAT_PATH}.downloading" ] && rm -f "${PAT_PATH}" "${PAT_PATH}.downloading"

  if [ -f "${PAT_PATH}" ]; then
    echo "$(printf "$(TEXT "%s cached.")" "${PAT_FILE}")"
  else
    if [ "${PATURL}" = "#PARSEPAT" ]; then
      echo -e "$(TEXT "The cache has been cleared. Please re 'Parse pat' before build.")" >"${LOG_FILE}"
      return 1
    fi
    if [ "${PATURL}" = "#RECOVERY" ]; then
      echo -e "$(TEXT "The cache has been cleared. Please re 'Try to recovery a installed DSM system' before build.")" >"${LOG_FILE}"
      return 1
    fi
    if [ -z "${PATURL}" -o "${PATURL:0:1}" = "#" ]; then
      echo -e "$(TEXT "The pat url is empty. Please re 'Choose a version' before build.")" >"${LOG_FILE}"
      return 1
    fi
    # If we have little disk space, clean cache folder
    if [ ${CLEARCACHE} -eq 1 ]; then
      echo "$(TEXT "Cleaning cache ...")"
      rm -rf "${PART3_PATH}/dl"
      CLEARCACHE=0
    fi
    mkdir -p "${PART3_PATH}/dl"
    mirrors=("global.synologydownload.com" "global.download.synology.com" "cndl.synology.cn")
    fastest=$(_get_fastest ${mirrors[@]})
    if [ $? -ne 0 ]; then
      MSG="$(TEXT "Network error, please check the network connection and try again.")"
      echo -e "${MSG}" >"${LOG_FILE}"
      return 1
    fi
    mirror="$(echo ${PATURL} | sed 's|^http[s]*://\([^/]*\).*|\1|')"
    if echo "${mirrors[@]}" | grep -wq "${mirror}" && [ "${mirror}" != "${fastest}" ]; then
      echo "$(printf "$(TEXT "Based on the current network situation, switch to %s mirror to downloading.")" "${fastest}")"
      PATURL="$(echo ${PATURL} | sed "s/${mirror}/${fastest}/")"
    fi
    echo "$(printf "$(TEXT "Downloading %s ...")" "${PAT_FILE}")"
    # Check disk space left
    SPACELEFT=$(df --block-size=1 ${PART3_PATH} 2>/dev/null | awk 'NR==2 {print $4}')
    # Discover remote file size
    FILESIZE=$(curl -skLI --connect-timeout 10 "${PATURL}" | grep -i Content-Length | tail -n 1 | tr -d '\r\n' | awk '{print $2}')
    if [ ${FILESIZE:-0} -ge ${SPACELEFT:-0} ]; then
      # No disk space to download, change it to RAMDISK
      PAT_PATH="${TMP_PATH}/${PAT_FILE}"
    fi
    touch "${PAT_PATH}.downloading"
    STATUS=$(curl -kL --connect-timeout 10 -w "%{http_code}" "${PATURL}" -o "${PAT_PATH}")
    RET=$?
    rm -f "${PAT_PATH}.downloading"
    if [ ${RET} -ne 0 -o ${STATUS:-0} -ne 200 ]; then
      rm -f "${PAT_PATH}"
      MSG="$(printf "$(TEXT "Check internet or cache disk space.\nError: %d:%d\n(Please via https://curl.se/libcurl/c/libcurl-errors.html check error description.)")" "${RET}" "${STATUS}")"
      echo -e "${MSG}" >"${LOG_FILE}"
      return 1
    fi
  fi

  echo -n "$(printf "$(TEXT "Checking hash of %s: ")" "${PAT_FILE}")"
  if [ "$(md5sum ${PAT_PATH} | awk '{print $1}')" != "${PATSUM}" ]; then
    rm -f ${PAT_PATH}
    echo -e "$(TEXT "md5 hash of pat not match, Please reget pat data from the version menu and try again!")" >"${LOG_FILE}"
    return 1
  fi
  echo "$(TEXT "OK")"

  rm -rf "${UNTAR_PAT_PATH}"
  mkdir -p "${UNTAR_PAT_PATH}"
  echo -n "$(printf "$(TEXT "Disassembling %s: ")" "${PAT_FILE}")"

  extractPatFiles "${PAT_PATH}" "${UNTAR_PAT_PATH}"
  if [ $? -ne 0 ]; then
    rm -rf "${UNTAR_PAT_PATH}"
    return 1
  fi
  echo -n "$(TEXT "Setting hash: ")"
  ZIMAGE_HASH="$(sha256sum ${UNTAR_PAT_PATH}/zImage | awk '{print $1}')"
  writeConfigKey "zimage-hash" "${ZIMAGE_HASH}" "${USER_CONFIG_FILE}"
  RAMDISK_HASH="$(sha256sum ${UNTAR_PAT_PATH}/rd.gz | awk '{print $1}')"
  writeConfigKey "ramdisk-hash" "${RAMDISK_HASH}" "${USER_CONFIG_FILE}"
  echo "$(TEXT "OK")"

  echo -n "$(TEXT "Copying files: ")"
  copyDSMFiles "${UNTAR_PAT_PATH}"
  rm -rf "${UNTAR_PAT_PATH}"
  echo "$(TEXT "OK")"
}

###############################################################################
# Where the magic happens!
# 1 - silent
function make() {
  function __make() {
    if [ ! -f "${ORI_ZIMAGE_FILE}" -o ! -f "${ORI_RDGZ_FILE}" ]; then
      extractDsmFiles
      [ $? -ne 0 ] && return 1
    fi

    while true; do
      SIZE=256 # initrd-dsm + zImage-dsm ≈ 210M
      SPACELEFT=$(df -m ${PART3_PATH} 2>/dev/null | awk 'NR==2 {print $4}')
      ZIMAGESIZE=$(du -m ${MOD_ZIMAGE_FILE} 2>/dev/null | awk '{print $1}')
      RDGZSIZE=$(du -m ${MOD_RDGZ_FILE} 2>/dev/null | awk '{print $1}')
      SPACEALL=$((${SPACELEFT:-0} + ${ZIMAGESIZE:-0} + ${RDGZSIZE:-0}))
      [ ${SPACEALL:-0} -ge ${SIZE} ] && break
      echo -e "$(TEXT "No disk space left, please clean the cache and try again!")" >"${LOG_FILE}"
      return 1
    done

    ${WORK_PATH}/zimage-patch.sh
    if [ $? -ne 0 ]; then
      echo -e "$(TEXT "zImage not patched,\nPlease upgrade the bootloader version and try again.\nPatch error:\n")$(cat "${LOG_FILE}")" >"${LOG_FILE}"
      return 1
    fi

    ${WORK_PATH}/ramdisk-patch.sh
    if [ $? -ne 0 ]; then
      echo -e "$(TEXT "Ramdisk not patched,\nPlease upgrade the bootloader version and try again.\nPatch error:\n")$(cat "${LOG_FILE}")" >"${LOG_FILE}"
      return 1
    fi
    rm -f ${PART1_PATH}/.build
    echo "$(TEXT "Cleaning ...")"
    rm -rf "${UNTAR_PAT_PATH}"
    rm -f "${LOG_FILE}"
    echo "$(TEXT "Ready!")"
    sleep 3
    return 0
  }
  rm -f "${LOG_FILE}"
  if [ ! "${1}" = "-1" ]; then
    __make 2>&1 | DIALOG --title "$(TEXT "Main menu")" \
      --progressbox "$(TEXT "Making ... ('ctrl + c' to exit)")" 20 100
  else
    __make
  fi
  if [ -f "${LOG_FILE}" ]; then
    if [ ! "${1}" = "-1" ]; then
      DIALOG --title "$(TEXT "Error")" \
        --msgbox "$(cat ${LOG_FILE})" 0 0
    else
      cat "${LOG_FILE}"
    fi
    rm -f "${LOG_FILE}"
    return 1
  else
    PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
    BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
    SMALLNUM="$(readConfigKey "smallnum" "${USER_CONFIG_FILE}")"
    return 0
  fi
}

###############################################################################
# Where the magic happens!
function customDTS() {
  # Loop menu
  while true; do
    [ -f "${USER_UP_PATH}/${MODEL}.dts" ] && CUSTOMDTS="Yes" || CUSTOMDTS="No"
    DIALOG --title "$(TEXT "Custom DTS")" \
      --default-item ${NEXT} --menu "$(TEXT "Choose a option")" 0 0 0 \
      % "$(TEXT "Custom dts: ") ${CUSTOMDTS}" \
      u "$(TEXT "Upload dts file")" \
      d "$(TEXT "Delete dts file")" \
      i "$(TEXT "Edit dts file")" \
      e "$(TEXT "Exit")" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    case "$(cat ${TMP_PATH}/resp)" in
    %) ;;
    u)
      if ! tty 2>/dev/null | grep -q "/dev/pts"; then #if ! tty 2>/dev/null | grep -q "/dev/pts" || [ -z "${SSH_TTY}" ]; then
        MSG=""
        MSG+="$(TEXT "This feature is only available when accessed via ssh (Requires a terminal that supports ZModem protocol).\n")"
        MSG+="$(printf "$(TEXT "Or upload the dts file to %s via DUFS, Will be automatically imported when building.")" "${USER_UP_PATH}/${MODEL}.dts")"
        DIALOG --title "$(TEXT "Custom DTS")" \
          --msgbox "${MSG}" 0 0
        return
      fi
      DIALOG --title "$(TEXT "Custom DTS")" \
        --msgbox "$(TEXT "Currently, only dts format files are supported. Please prepare and click to confirm uploading.\n(saved in /mnt/p3/users/)")" 0 0
      TMP_UP_PATH="${TMP_PATH}/users"
      DTC_ERRLOG="/tmp/dtc.log"
      rm -rf "${TMP_UP_PATH}"
      mkdir -p "${TMP_UP_PATH}"
      pushd "${TMP_UP_PATH}"
      RET=1
      rz -be
      for F in $(ls -A 2>/dev/null); do
        USER_FILE="${TMP_UP_PATH}/${F}"
        dtc -q -I dts -O dtb "${F}" >"test.dtb" 2>"${DTC_ERRLOG}"
        RET=$?
        break
      done
      popd
      if [ ${RET} -ne 0 -o -z "${USER_FILE}" ]; then
        DIALOG --title "$(TEXT "Custom DTS")" \
          --msgbox "$(TEXT "Not a valid dts file, please try again!")\n\n$(cat "${DTC_ERRLOG}")" 0 0
      else
        [ -d "{USER_UP_PATH}" ] || mkdir -p "${USER_UP_PATH}"
        cp -f "${USER_FILE}" "${USER_UP_PATH}/${MODEL}.dts"
        DIALOG --title "$(TEXT "Custom DTS")" \
          --msgbox "$(TEXT "A valid dts file, Automatically import at compile time.")" 0 0
      fi
      rm -rf "${DTC_ERRLOG}"
      touch ${PART1_PATH}/.build
      ;;
    d)
      rm -f "${USER_UP_PATH}/${MODEL}.dts"
      touch ${PART1_PATH}/.build
      ;;
    i)
      rm -rf "${TMP_PATH}/model.dts"
      if [ -f "${USER_UP_PATH}/${MODEL}.dts" ]; then
        cp -f "${USER_UP_PATH}/${MODEL}.dts" "${TMP_PATH}/model.dts"
      else
        ODTB="$(ls ${PART2_PATH}/*.dtb 2>/dev/null | head -1)"
        if [ -f "${ODTB}" ]; then
          dtc -q -I dtb -O dts "${ODTB}" >"${TMP_PATH}/model.dts"
        else
          DIALOG --title "$(TEXT "Custom DTS")" \
            --msgbox "$(TEXT "No dts file to edit. Please upload first!")" 0 0
          continue
        fi
      fi
      DTC_ERRLOG="/tmp/dtc.log"
      while true; do
        DIALOG --title "$(TEXT "Edit with caution")" \
          --editbox "${TMP_PATH}/model.dts" 0 0 2>"${TMP_PATH}/modelEdit.dts"
        [ $? -ne 0 ] && rm -f "${TMP_PATH}/model.dts" "${TMP_PATH}/modelEdit.dts" && return
        dtc -q -I dts -O dtb "${TMP_PATH}/modelEdit.dts" >"test.dtb" 2>"${DTC_ERRLOG}"
        if [ $? -ne 0 ]; then
          DIALOG --title "$(TEXT "Custom DTS")" \
            --msgbox "$(TEXT "Not a valid dts file, please try again!")\n\n$(cat "${DTC_ERRLOG}")" 0 0
        else
          mkdir -p "${USER_UP_PATH}"
          cp -f "${TMP_PATH}/modelEdit.dts" "${USER_UP_PATH}/${MODEL}.dts"
          rm -r "${TMP_PATH}/model.dts" "${TMP_PATH}/modelEdit.dts"
          touch ${PART1_PATH}/.build
          break
        fi
      done
      ;;
    e)
      return
      ;;
    esac
  done
}

###############################################################################
# Permits user edit the user config
function editUserConfig() {
  while true; do
    DIALOG --title "$(TEXT "Edit with caution")" \
      --editbox "${USER_CONFIG_FILE}" 0 0 2>"${TMP_PATH}/userconfig"
    [ $? -ne 0 ] && return
    mv -f "${TMP_PATH}/userconfig" "${USER_CONFIG_FILE}"
    dos2unix "${USER_CONFIG_FILE}"
    ERRORS=$(checkConfigFile "${USER_CONFIG_FILE}")
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
      --editbox "${USER_GRUB_CONFIG}" 0 0 2>"${TMP_PATH}/usergrub.cfg"
    [ $? -ne 0 ] && return
    mv -f "${TMP_PATH}/usergrub.cfg" "${USER_GRUB_CONFIG}"
    dos2unix "${USER_GRUB_CONFIG}"
    break
  done
}

###############################################################################
# Set static IP
function setStaticIP() {
  ETHX=$(ls /sys/class/net/ 2>/dev/null | grep -v lo)
  for ETH in ${ETHX}; do
    MACR="$(cat /sys/class/net/${ETH}/address 2>/dev/null | sed 's/://g')"
    IPR="$(readConfigKey "network.${MACR}" "${USER_CONFIG_FILE}")"
    IFS='/' read -r -a IPRA <<<"$IPR"

    MSG="$(printf "$(TEXT "Set to %s: (Delete if empty)")" "${ETH}(${MACR})")"
    while true; do
      DIALOG --title "$(TEXT "Advanced")" \
        --form "${MSG}" 10 60 4 "address" 1 1 "${IPRA[0]}" 1 9 36 16 "netmask" 2 1 "${IPRA[1]}" 2 9 36 16 "gateway" 3 1 "${IPRA[2]}" 3 9 36 16 "dns" 4 1 "${IPRA[3]}" 4 9 36 16 \
        2>"${TMP_PATH}/resp"
      RET=$?
      case ${RET} in
      0) # ok-button
        DIALOG --title "$(TEXT "Advanced")" \
          --infobox "$(TEXT "Setting IP ...")" 0 0
        address="$(cat "${TMP_PATH}/resp" | sed -n '1p')"
        netmask="$(cat "${TMP_PATH}/resp" | sed -n '2p')"
        gateway="$(cat "${TMP_PATH}/resp" | sed -n '3p')"
        dnsname="$(cat "${TMP_PATH}/resp" | sed -n '4p')"
        if [ -z "${address}" ]; then
          deleteConfigKey "network.${MACR}" "${USER_CONFIG_FILE}"
        else
          ip addr flush dev $ETH
          ip addr add ${address}/${netmask:-"255.255.255.0"} dev $ETH
          if [ -n "${gateway}" ]; then
            ip route add default via ${gateway} dev $ETH
          fi
          if [ -n "${dnsname:-${gateway}}" ]; then
            sed -i "/nameserver ${dnsname:-${gateway}}/d" /etc/resolv.conf
            echo "nameserver ${dnsname:-${gateway}}" >>/etc/resolv.conf
          fi
          writeConfigKey "network.${MACR}" "${address}/${netmask}/${gateway}/${dnsname}" "${USER_CONFIG_FILE}"
          IP="$(getIP)"
          sleep 1
        fi
        touch ${PART1_PATH}/.build
        break
        ;;
      1) # cancel-button
        break
        ;;
      255) # ESC
        break 2
        ;;
      esac
    done
  done
}

###############################################################################
# Set wireless account
function setWirelessAccount() {
  DIALOG --title "$(TEXT "Advanced")" \
    --infobox "$(TEXT "Scanning ...")" 0 0
  ITEM=$(iw wlan0 scan 2>/dev/null | grep SSID: | awk '{print $2}')
  MSG=""
  MSG+="$(TEXT "Scanned SSIDs:\n")"
  for I in $(iw wlan0 scan 2>/dev/null | grep SSID: | awk '{print $2}'); do MSG+="${I}\n"; done
  LINENUM=$(($(echo -e "${MSG}" | wc -l) + 8))
  while true; do
    SSID=$(cat ${PART1_PATH}/wpa_supplicant.conf 2>/dev/null | grep -i SSID | cut -d'=' -f2)
    PSK=$(cat ${PART1_PATH}/wpa_supplicant.conf 2>/dev/null | grep -i PSK | cut -d'=' -f2)
    SSID="${SSID//\"/}"
    PSK="${PSK//\"/}"
    DIALOG --title "$(TEXT "Advanced")" \
      --form "${MSG}" ${LINENUM:-16} 70 2 "SSID" 1 1 "${SSID}" 1 7 58 0 " PSK" 2 1 "${PSK}" 2 7 58 0 \
      2>"${TMP_PATH}/resp"
    RET=$?
    case ${RET} in
    0) # ok-button
      SSID="$(cat "${TMP_PATH}/resp" | sed -n '1p')"
      PSK="$(cat "${TMP_PATH}/resp" | sed -n '2p')"
      if [ -z "${SSID}" -o -z "${PSK}" ]; then
        DIALOG --title "$(TEXT "Advanced")" \
          --yesno "$(TEXT "Invalid SSID/PSK, retry?")" 0 0
        [ $? -eq 0 ] && continue || break
      fi
      (
        rm -f ${PART1_PATH}/wpa_supplicant.conf
        echo "ctrl_interface=/var/run/wpa_supplicant" >>${PART1_PATH}/wpa_supplicant.conf
        echo "update_config=1" >>${PART1_PATH}/wpa_supplicant.conf
        echo "network={" >>${PART1_PATH}/wpa_supplicant.conf
        echo "        ssid=\"${SSID}\"" >>${PART1_PATH}/wpa_supplicant.conf
        echo "        psk=\"${PSK}\"" >>${PART1_PATH}/wpa_supplicant.conf
        echo "}" >>${PART1_PATH}/wpa_supplicant.conf

        for ETH in $(ls /sys/class/net/ 2>/dev/null | grep wlan); do
          connectwlanif "${ETH}" && sleep 1
          MACR="$(cat /sys/class/net/${ETH}/address 2>/dev/null | sed 's/://g')"
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
  return
}

###############################################################################
# Show disks information
function showDisksInfo() {
  MSG=""
  NUMPORTS=0
  [ $(lspci -d ::106 2>/dev/null | wc -l) -gt 0 ] && MSG+="\nSATA:\n"
  for PCI in $(lspci -d ::106 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    MSG+="\Zb${NAME}\Zn\nPorts: "
    PORTS=$(ls -l /sys/class/scsi_host 2>/dev/null | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
    for P in ${PORTS}; do
      if lsscsi -b 2>/dev/null | grep -v - | grep -q "\[${P}:"; then
        DUMMY="$([ "$(cat /sys/class/scsi_host/host${P}/ahci_port_cmd 2>/dev/null)" = "0" ] && echo 1 || echo 2)"
        if [ "$(cat /sys/class/scsi_host/host${P}/ahci_port_cmd 2>/dev/null)" = "0" ]; then
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
  [ $(lspci -d ::104 2>/dev/null | wc -l) -gt 0 ] && MSG+="\nRAID:\n"
  for PCI in $(lspci -d ::104 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORT=$(ls -l /sys/class/scsi_host 2>/dev/null | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
    PORTNUM=$(lsscsi -b 2>/dev/null | grep -v - | grep "\[${PORT}:" | wc -l)
    MSG+="\Zb${NAME}\Zn\nNumber: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  [ $(lspci -d ::107 2>/dev/null | wc -l) -gt 0 ] && MSG+="\nSerial Attached SCSI:\n"
  for PCI in $(lspci -d ::107 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORT=$(ls -l /sys/class/scsi_host 2>/dev/null | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
    PORTNUM=$(lsscsi -b 2>/dev/null | grep -v - | grep "\[${PORT}:" | wc -l)
    MSG+="\Zb${NAME}\Zn\nNumber: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  [ $(lspci -d ::100 2>/dev/null | wc -l) -gt 0 ] && MSG+="\nSCSI:\n"
  for PCI in $(lspci -d ::100 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORTNUM=$(ls -l /sys/block/* 2>/dev/null | grep "${PCI}" | wc -l)
    [ ${PORTNUM} -eq 0 ] && continue
    MSG+="\Zb${NAME}\Zn\nNumber: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  [ $(lspci -d ::101 2>/dev/null | wc -l) -gt 0 ] && MSG+="\nIDE:\n"
  for PCI in $(lspci -d ::101 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORTNUM=$(ls -l /sys/block/* 2>/dev/null | grep "${PCI}" | wc -l)
    [ ${PORTNUM} -eq 0 ] && continue
    MSG+="\Zb${NAME}\Zn\nNumber: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  [ $(ls -l /sys/class/scsi_host 2>/dev/null | grep usb | wc -l) -gt 0 ] && MSG+="\nUSB:\n"
  for PCI in $(lspci -d ::c03 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORT=$(ls -l /sys/class/scsi_host 2>/dev/null | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
    PORTNUM=$(lsscsi -b 2>/dev/null | grep -v - | grep "\[${PORT}:" | wc -l)
    [ ${PORTNUM} -eq 0 ] && continue
    MSG+="\Zb${NAME}\Zn\nNumber: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  [ $(ls -l /sys/class/mmc_host 2>/dev/null | grep mmc_host | wc -l) -gt 0 ] && MSG+="\nMMC:\n"
  for PCI in $(lspci -d ::805 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORTNUM=$(ls -l /sys/block/mmc* 2>/dev/null | grep "${PCI}" | wc -l)
    [ ${PORTNUM} -eq 0 ] && continue
    MSG+="\Zb${NAME}\Zn\nNumber: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  [ $(lspci -d ::108 2>/dev/null | wc -l) -gt 0 ] && MSG+="\nNVME:\n"
  for PCI in $(lspci -d ::108 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORT=$(ls -l /sys/class/nvme 2>/dev/null | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/nvme//' | sort -n)
    PORTNUM=$(lsscsi -b 2>/dev/null | grep -v - | grep "\[N:${PORT}:" | wc -l)
    MSG+="\Zb${NAME}\Zn\nNumber: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  if [ $(lsblk -dpno KNAME,SUBSYSTEMS 2>/dev/null | grep 'vmbus:acpi' | wc -l) -gt 0 ]; then
    MSG+="\nVMBUS:\n"
    NAME="vmbus:acpi"
    PORTNUM=$(lsblk -dpno KNAME,SUBSYSTEMS 2>/dev/null | grep 'vmbus:acpi' | wc -l)
    MSG+="\Zb${NAME}\Zn\nNumber: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  fi
  MSG+="\n"
  MSG+="$(printf "$(TEXT "\nTotal of ports: %s\n")" "${NUMPORTS}")"
  MSG+="$(TEXT "\nPorts with color \Z1red\Zn as DUMMY, color \Z2\Zbgreen\Zn has drive connected.")"
  [ ${NUMPORTS} -eq 0 ] && MSG="\n$(TEXT "No disk found!")"
  DIALOG --title "$(TEXT "Advanced")" \
    --msgbox "${MSG}" 0 0
  return
}

###############################################################################
# Format disk
function formatDisks() {
  rm -f "${TMP_PATH}/opts"
  while read KNAME ID SIZE TYPE PKNAME; do
    [ "${KNAME}" = "N/A" ] && continue
    [[ "${KNAME}" = /dev/md* ]] && continue
    [ "${KNAME}" = "${LOADER_DISK}" -o "${PKNAME}" = "${LOADER_DISK}" ] && continue
    printf "\"%s\" \"%-6s %-4s %s\" \"off\"\n" "${KNAME}" "${SIZE}" "${TYPE}" "${ID}" >>"${TMP_PATH}/opts"
  done <<<$(lsblk -Jpno KNAME,ID,SIZE,TYPE,PKNAME 2>/dev/null | sed 's|null|"N/A"|g' | jq -r '.blockdevices[] | "\(.kname) \(.id) \(.size) \(.type) \(.pkname)"' 2>/dev/null)
  if [ ! -f "${TMP_PATH}/opts" ]; then
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "$(TEXT "No disk found!")" 0 0
    return
  fi
  DIALOG --title "$(TEXT "Advanced")" \
    --checklist "$(TEXT "Advanced")" 0 0 0 --file "${TMP_PATH}/opts" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  RESP=$(cat "${TMP_PATH}/resp")
  [ -z "${RESP}" ] && return
  DIALOG --title "$(TEXT "Advanced")" \
    --yesno "$(TEXT "Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?")" 0 0
  [ $? -ne 0 ] && return
  if [ $(ls /dev/md[0-9]* 2>/dev/null | wc -l) -gt 0 ]; then
    DIALOG --title "$(TEXT "Advanced")" \
      --yesno "$(TEXT "Warning:\nThe current hds is in raid, do you still want to format them?")" 0 0
    [ $? -ne 0 ] && return
    for I in $(ls /dev/md[0-9]* 2>/dev/null); do
      mdadm -S "${I}" >/dev/null 2>&1
    done
  fi
  for I in ${RESP}; do
    if [[ "${I}" = /dev/mmc* ]]; then
      echo y | mkfs.ext4 -T largefile4 -E nodiscard "${I}"
    else
      echo y | mkfs.ext4 -T largefile4 "${I}"
    fi
  done 2>&1 | DIALOG --title "$(TEXT "Advanced")" \
    --progressbox "$(TEXT "Formatting ...")" 20 100
  DIALOG --title "$(TEXT "Advanced")" \
    --msgbox "$(TEXT "Formatting is complete.")" 0 0
  return
}

###############################################################################
# Try to recovery a DSM already installed
function tryRecoveryDSM() {
  DIALOG --title "$(TEXT "Try recovery DSM")" \
    --infobox "$(TEXT "Trying to recovery a installed DSM system ...")" 0 0
  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "$(TEXT "No DSM system partition(md0) found!\nPlease insert all disks before continuing.")" 0 0
    return
  fi

  mkdir -p "${TMP_PATH}/mdX"
  mount -t ext4 "$(echo "${DSMROOTS}" | head -n 1 | cut -d' ' -f1)" "${TMP_PATH}/mdX"
  if [ $? -ne 0 ]; then
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "$(TEXT "mount DSM system partition(md0) failed!\nPlease insert all disks before continuing.")" 0 0
    rm -rf "${TMP_PATH}/mdX"
    return
  fi

  function __umountDSMRootDisk() {
    umount "${TMP_PATH}/mdX"
    rm -rf "${TMP_PATH}/mdX"
  }

  DIALOG --title "$(TEXT "Try recovery DSM")" \
    --infobox "$(TEXT "Checking for backup of user's configuration for bootloader ...")" 0 0
  if [ -f "${TMP_PATH}/mdX/usr/rr/backup/p1/user-config.yml" ]; then
    R_PLATFORM="$(readConfigKey "platform" "${TMP_PATH}/mdX/usr/rr/backup/p1/user-config.yml")"
    R_MODEL="$(readConfigKey "model" "${TMP_PATH}/mdX/usr/rr/backup/p1/user-config.yml")"
    R_MODELID="$(readConfigKey "modelid" "${TMP_PATH}/mdX/usr/rr/backup/p1/user-config.yml")"
    R_PRODUCTVER="$(readConfigKey "productver" "${TMP_PATH}/mdX/usr/rr/backup/p1/user-config.yml")"
    R_BUILDNUM="$(readConfigKey "buildnum" "${TMP_PATH}/mdX/usr/rr/backup/p1/user-config.yml")"
    R_SMALLNUM="$(readConfigKey "smallnum" "${TMP_PATH}/mdX/usr/rr/backup/p1/user-config.yml")"
    R_PATURL="$(readConfigKey "paturl" "${TMP_PATH}/mdX/usr/rr/backup/p1/user-config.yml")"
    R_PATSUM="$(readConfigKey "patsum" "${TMP_PATH}/mdX/usr/rr/backup/p1/user-config.yml")"

    PS="$(readConfigEntriesArray "platforms" "${WORK_PATH}/platforms.yml" | sort)"
    VS="$(readConfigEntriesArray "platforms.${R_PLATFORM}.productvers" "${WORK_PATH}/platforms.yml" | sort -r)"
    if [ -n "${R_PLATFORM}" ] && arrayExistItem "${R_PLATFORM}" ${PS} &&
      [ -n "${R_PRODUCTVER}" ] && arrayExistItem "${R_PRODUCTVER}" ${VS} &&
      [ -n "${R_BUILDNUM}" ] && [ -n "${R_SMALLNUM}" ]; then
      cp -Rf "${TMP_PATH}/mdX/usr/rr/backup/p1/"* "${PART1_PATH}"
      if [ -d "${TMP_PATH}/mdX/usr/rr/backup/p3" ]; then
        cp -Rf "${TMP_PATH}/mdX/usr/rr/backup/p3/"* "${PART3_PATH}"
      fi
      copyDSMFiles "${TMP_PATH}/mdX/.syno/patch"
      __umountDSMRootDisk
      DIALOG --title "$(TEXT "Try recovery DSM")" \
        --msgbox "$(TEXT "Found a backup of the user's configuration, and restored it. Please rebuild and boot.")" 0 0
      exec "$0"
      touch ${PART1_PATH}/.build
      return
    fi
  fi

  DIALOG --title "$(TEXT "Try recovery DSM")" \
    --infobox "$(TEXT "Checking for installed DSM system ...")" 0 0

  setConfigFromDSM "${TMP_PATH}/mdX/.syno/patch"
  if [ $? -ne 0 ]; then
    __umountDSMRootDisk
    DIALOG --title "$(TEXT "Try recovery DSM")" \
      --msgbox "$(TEXT "The installed DSM system was not found, or the system is damaged and cannot be recovered. Please reselect model and build.")" 0 0
    return
  fi

  if [ -f "${TMP_PATH}/mdX/etc/synoinfo.conf" ]; then
    R_SN="$(_get_conf_kv SN "${TMP_PATH}/mdX/etc/synoinfo.conf")"
    [ -n "${R_SN}" ] && SN=${R_SN} && writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
  fi

  writeConfigKey "paturl" "#RECOVERY" "${USER_CONFIG_FILE}"
  writeConfigKey "patsum" "" "${USER_CONFIG_FILE}"

  copyDSMFiles "${TMP_PATH}/mdX/.syno/patch"
  __umountDSMRootDisk
  DIALOG --title "$(TEXT "Try recovery DSM")" \
    --msgbox "$(TEXT "Found a installed DSM system and restored it. Please rebuild and boot.")" 0 0

  return
}

###############################################################################
# Allow downgrade installation
function allowDSMDowngrade() {
  MSG=""
  MSG+="$(TEXT "This feature will allow you to downgrade the installation by removing the VERSION file from the first partition of all disks.\n")"
  MSG+="$(TEXT "Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?")"
  DIALOG --title "$(TEXT "Advanced")" \
    --yesno "${MSG}" 0 0
  [ $? -ne 0 ] && return
  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "$(TEXT "No DSM system partition(md0) found!\nPlease insert all disks before continuing.")" 0 0
    return
  fi
  (
    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      mount -t ext4 "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      [ -f "${TMP_PATH}/mdX/etc/VERSION" ] && rm -f "${TMP_PATH}/mdX/etc/VERSION"
      [ -f "${TMP_PATH}/mdX/etc.defaults/VERSION" ] && rm -f "${TMP_PATH}/mdX/etc.defaults/VERSION"
      sync
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX"
  ) 2>&1 | DIALOG --title "$(TEXT "Advanced")" \
    --progressbox "$(TEXT "Removing ...")" 20 100
  DIALOG --title "$(TEXT "Advanced")" \
    --msgbox "$(TEXT "Remove VERSION file for DSM system partition(md0) completed.")" 0 0
  return
}

###############################################################################
# Reset DSM system password
function resetDSMPassword() {
  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "$(TEXT "No DSM system partition(md0) found!\nPlease insert all disks before continuing.")" 0 0
    return
  fi
  rm -f "${TMP_PATH}/menu"
  mkdir -p "${TMP_PATH}/mdX"
  for I in ${DSMROOTS}; do
    mount -t ext4 "${I}" "${TMP_PATH}/mdX"
    [ $? -ne 0 ] && continue
    if [ -f "${TMP_PATH}/mdX/etc/shadow" ]; then
      while read L; do
        U=$(echo "${L}" | awk -F ':' '{if ($2 != "*" && $2 != "!!") print $1;}')
        [ -z "${U}" ] && continue
        E=$(echo "${L}" | awk -F ':' '{if ($8 == "1") print "disabled"; else print "        ";}')
        grep -q "status=on" "${TMP_PATH}/mdX/usr/syno/etc/packages/SecureSignIn/preference/${U}/method.config" 2>/dev/null
        [ $? -eq 0 ] && S="SecureSignIn" || S="            "
        printf "\"%-36s %-10s %-14s\"\n" "${U}" "${E}" "${S}" >>"${TMP_PATH}/menu"
      done <<<$(cat "${TMP_PATH}/mdX/etc/shadow" 2>/dev/null)
    fi
    umount "${TMP_PATH}/mdX"
    [ -f "${TMP_PATH}/menu" ] && break
  done
  rm -rf "${TMP_PATH}/mdX"
  if [ ! -f "${TMP_PATH}/menu" ]; then
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "$(TEXT "All existing users have been disabled. Please try adding new user.")" 0 0
    return
  fi
  DIALOG --title "$(TEXT "Advanced")" \
    --no-items --menu "$(TEXT "Choose a user name")" 0 0 0 --file "${TMP_PATH}/menu" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  USER="$(cat "${TMP_PATH}/resp" 2>/dev/null | awk '{print $1}')"
  [ -z "${USER}" ] && return
  while true; do
    DIALOG --title "$(TEXT "Advanced")" \
      --inputbox "$(printf "$(TEXT "Type a new password for user '%s'")" "${USER}")" 0 70 "${CMDLINE[${NAME}]}" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && break 2
    VALUE="$(cat "${TMP_PATH}/resp")"
    [ -n "${VALUE}" ] && break
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "$(TEXT "Invalid password")" 0 0
  done
  NEWPASSWD="$(python -c "from passlib.hash import sha512_crypt;pw=\"${VALUE}\";print(sha512_crypt.using(rounds=5000).hash(pw))")"
  (
    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      mount -t ext4 "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      OLDPASSWD="$(cat "${TMP_PATH}/mdX/etc/shadow" 2>/dev/null | grep "^${USER}:" | awk -F ':' '{print $2}')"
      if [ -n "${NEWPASSWD}" -a -n "${OLDPASSWD}" ]; then
        sed -i "s|${OLDPASSWD}|${NEWPASSWD}|g" "${TMP_PATH}/mdX/etc/shadow"
        sed -i "/^${USER}:/ s/\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\)/\1:\2:\3:\4:\5:\6:\7::\9/" "${TMP_PATH}/mdX/etc/shadow"
      fi
      sed -i "s|status=on|status=off|g" "${TMP_PATH}/mdX/usr/syno/etc/packages/SecureSignIn/preference/${USER}/method.config" 2>/dev/null
      sync
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX"
  ) 2>&1 | DIALOG --title "$(TEXT "Advanced")" \
    --progressbox "$(TEXT "Resetting ...")" 20 100
  DIALOG --title "$(TEXT "Advanced")" \
    --msgbox "$(TEXT "Password reset completed.")" 0 0
  return
}

###############################################################################
# Reset DSM system password
function addNewDSMUser() {
  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "$(TEXT "No DSM system partition(md0) found!\nPlease insert all disks before continuing.")" 0 0
    return
  fi
  MSG="$(TEXT "Add to administrators group by default")"
  DIALOG --title "$(TEXT "Advanced")" \
    --form "${MSG}" 8 60 3 "username:" 1 1 "${sn}" 1 10 50 0 "password:" 2 1 "${mac1}" 2 10 50 0 \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return
  username="$(cat "${TMP_PATH}/resp" | sed -n '1p')"
  password="$(cat "${TMP_PATH}/resp" | sed -n '2p')"
  (
    ONBOOTUP=""
    ONBOOTUP="${ONBOOTUP}if synouser --enum local | grep -q ^${username}\$; then synouser --setpw ${username} ${password}; else synouser --add ${username} ${password} rr 0 user@rr.com 1; fi\n"
    ONBOOTUP="${ONBOOTUP}synogroup --memberadd administrators ${username}\n"
    ONBOOTUP="${ONBOOTUP}echo \"DELETE FROM task WHERE task_name LIKE ''RRONBOOTUPRR_ADDUSER'';\" | sqlite3 /usr/syno/etc/esynoscheduler/esynoscheduler.db\n"

    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      mount -t ext4 "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      if [ -f "${TMP_PATH}/mdX/usr/syno/etc/esynoscheduler/esynoscheduler.db" ]; then
        sqlite3 ${TMP_PATH}/mdX/usr/syno/etc/esynoscheduler/esynoscheduler.db <<EOF
DELETE FROM task WHERE task_name LIKE 'RRONBOOTUPRR_ADDUSER';
INSERT INTO task VALUES('RRONBOOTUPRR_ADDUSER', '', 'bootup', '', 1, 0, 0, 0, '', 0, '$(echo -e ${ONBOOTUP})', 'script', '{}', '', '', '{}', '{}');
EOF
        sleep 1
        sync
        echo "true" >${TMP_PATH}/isEnable
      fi
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX"
  ) 2>&1 | DIALOG --title "$(TEXT "Advanced")" \
    --progressbox "$(TEXT "Adding ...")" 20 100
  [ "$(cat ${TMP_PATH}/isEnable 2>/dev/null)" = "true" ] && MSG="$(TEXT "User added successfully.")" || MSG="$(TEXT "User add failed.")"
  DIALOG --title "$(TEXT "Advanced")" \
    --msgbox "${MSG}" 0 0
  return
}

###############################################################################
# Force enable Telnet&SSH of DSM system
function forceEnableDSMTelnetSSH() {
  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "$(TEXT "No DSM system partition(md0) found!\nPlease insert all disks before continuing.")" 0 0
    return
  fi
  (
    ONBOOTUP=""
    ONBOOTUP="${ONBOOTUP}systemctl restart inetd\n"
    ONBOOTUP="${ONBOOTUP}synowebapi --exec api=SYNO.Core.Terminal method=set version=3 enable_telnet=true enable_ssh=true ssh_port=22 forbid_console=false\n"
    ONBOOTUP="${ONBOOTUP}echo \"DELETE FROM task WHERE task_name LIKE ''RRONBOOTUPRR_SSH'';\" | sqlite3 /usr/syno/etc/esynoscheduler/esynoscheduler.db\n"
    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      mount -t ext4 "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      if [ -f "${TMP_PATH}/mdX/usr/syno/etc/esynoscheduler/esynoscheduler.db" ]; then
        sqlite3 ${TMP_PATH}/mdX/usr/syno/etc/esynoscheduler/esynoscheduler.db <<EOF
DELETE FROM task WHERE task_name LIKE 'RRONBOOTUPRR_SSH';
INSERT INTO task VALUES('RRONBOOTUPRR_SSH', '', 'bootup', '', 1, 0, 0, 0, '', 0, '$(echo -e ${ONBOOTUP})', 'script', '{}', '', '', '{}', '{}');
EOF
        sleep 1
        sync
        echo "true" >${TMP_PATH}/isEnable
      fi
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX"
  ) 2>&1 | DIALOG --title "$(TEXT "Advanced")" \
    --progressbox "$(TEXT "Enabling ...")" 20 100
  [ "$(cat ${TMP_PATH}/isEnable 2>/dev/null)" = "true" ] && MSG="$(TEXT "Enabled Telnet&SSH successfully.")" || MSG="$(TEXT "Enabled Telnet&SSH failed.")"
  DIALOG --title "$(TEXT "Advanced")" \
    --msgbox "${MSG}" 0 0
  return
}

###############################################################################
# Removing the blocked ip database
function removeBlockIPDB {
  MSG=""
  MSG+="$(TEXT "This feature will removing the blocked ip database from the first partition of all disks.\n")"
  MSG+="$(TEXT "Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?")"
  DIALOG --title "$(TEXT "Advanced")" \
    --yesno "${MSG}" 0 0
  [ $? -ne 0 ] && return
  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "$(TEXT "No DSM system partition(md0) found!\nPlease insert all disks before continuing.")" 0 0
    return
  fi
  (
    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      mount -t ext4 "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      [ -f "${TMP_PATH}/mdX/etc/synoautoblock.db" ] && rm -f "${TMP_PATH}/mdX/etc/synoautoblock.db"
      sync
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX"
  ) 2>&1 | DIALOG --title "$(TEXT "Advanced")" \
    --progressbox "$(TEXT "Removing ...")" 20 100
  MSG="$(TEXT "The blocked ip database has been deleted.")"
  DIALOG --title "$(TEXT "Advanced")" \
    --msgbox "${MSG}" 0 0
  return
}
###############################################################################
# Initialize DSM network settings
function initDSMNetwork {
  MSG=""
  MSG+="$(TEXT "This option will clear all customized settings of the network card and restore them to the default state.\n")"
  MSG+="$(TEXT "Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?")"
  DIALOG --title "$(TEXT "Advanced")" \
    --yesno "${MSG}" 0 0
  [ $? -ne 0 ] && return
  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "$(TEXT "No DSM system partition(md0) found!\nPlease insert all disks before continuing.")" 0 0
    return
  fi
  (
    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      mount -t ext4 "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      rm -f "${TMP_PATH}/mdX/etc/sysconfig/network-scripts/ifcfg-bond"* "${TMP_PATH}/mdX/etc/sysconfig/network-scripts/ifcfg-eth"*
      rm -f "${TMP_PATH}/mdX/etc.defaults/sysconfig/network-scripts/ifcfg-bond"* "${TMP_PATH}/mdX/etc.defaults/sysconfig/network-scripts/ifcfg-eth"*
      sync
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX"
  ) 2>&1 | DIALOG --title "$(TEXT "Advanced")" \
    --progressbox "$(TEXT "Recovering ...")" 20 100
  MSG="$(TEXT "The network settings have been initialized.")"
  DIALOG --title "$(TEXT "Advanced")" \
    --msgbox "${MSG}" 0 0
  return
}

###############################################################################
# Clone bootloader disk
function cloneBootloaderDisk() {
  rm -f "${TMP_PATH}/opts"
  while read KNAME ID SIZE PKNAME; do
    [ "${KNAME}" = "N/A" ] && continue
    [ "${KNAME}" = "${LOADER_DISK}" -o "${PKNAME}" = "${LOADER_DISK}" ] && continue
    printf "\"%s\" \"%-6s %s\" \"off\"\n" "${KNAME}" "${SIZE}" "${ID}" >>"${TMP_PATH}/opts"
  done <<<$(lsblk -Jpno KNAME,ID,SIZE,PKNAME 2>/dev/null | sed 's|null|"N/A"|g' | jq -r '.blockdevices[] | "\(.kname) \(.id) \(.size) \(.pkname)"' 2>/dev/null)
  if [ ! -f "${TMP_PATH}/opts" ]; then
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "$(TEXT "No disk found!")" 0 0
    return
  fi
  DIALOG --title "$(TEXT "Advanced")" \
    --radiolist "$(TEXT "Choose a disk to clone to")" 0 0 0 --file "${TMP_PATH}/opts" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  RESP=$(cat "${TMP_PATH}/resp")
  if [ -z "${RESP}" ]; then
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "$(TEXT "No disk selected!")" 0 0
    return
  else
    SIZE=$(df -m ${RESP} 2>/dev/null | awk 'NR==2 {print $2}')
    if [ ${SIZE:-0} -lt 1024 ]; then
      DIALOG --title "$(TEXT "Advanced")" \
        --msgbox "$(printf "$(TEXT "Disk %s size is less than 1GB and cannot be cloned!")" "${RESP}")" 0 0
      return
    fi
    MSG=""
    MSG+="$(printf "$(TEXT "Warning:\nDisk %s will be formatted and written to the bootloader. Please confirm that important data has been backed up. \nDo you want to continue?")" "${RESP}")"
    DIALOG --title "$(TEXT "Advanced")" \
      --yesno "${MSG}" 0 0
    [ $? -ne 0 ] && return
  fi
  (
    rm -f "${LOG_FILE}"
    rm -rf "${PART3_PATH}/dl"
    CLEARCACHE=0

    gzip -dc "${WORK_PATH}/grub.img.gz" | dd of="${RESP}" bs=1M conv=fsync status=progress
    hdparm -z "${RESP}" # reset disk cache
    fdisk -l "${RESP}"
    sleep 1

    NEW_BLDISK_P1="$(lsblk "${RESP}" -pno KNAME,LABEL 2>/dev/null | grep 'RR1' | awk '{print $1}')"
    NEW_BLDISK_P2="$(lsblk "${RESP}" -pno KNAME,LABEL 2>/dev/null | grep 'RR2' | awk '{print $1}')"
    NEW_BLDISK_P3="$(lsblk "${RESP}" -pno KNAME,LABEL 2>/dev/null | grep 'RR3' | awk '{print $1}')"
    SIZEOFDISK=$(cat /sys/block/${RESP/\/dev\//}/size)
    ENDSECTOR=$(($(fdisk -l ${RESP} | grep "${NEW_BLDISK_P3}" | awk '{print $3}') + 1))
    if [ ${SIZEOFDISK}0 -ne ${ENDSECTOR}0 ]; then
      echo -e "\033[1;36mResizing ${NEW_BLDISK_P3}\033[0m"
      echo -e "d\n\nn\n\n\n\n\nn\nw" | fdisk "${RESP}" >/dev/null 2>&1
      resize2fs "${NEW_BLDISK_P3}"
      fdisk -l "${RESP}"
      sleep 1
    fi
    function __umountNewBlDisk() {
      umount "${TMP_PATH}/sdX1" 2>/dev/null
      umount "${TMP_PATH}/sdX2" 2>/dev/null
      umount "${TMP_PATH}/sdX3" 2>/dev/null
    }
    mkdir -p "${TMP_PATH}/sdX1"
    mkdir -p "${TMP_PATH}/sdX2"
    mkdir -p "${TMP_PATH}/sdX3"
    mount "${NEW_BLDISK_P1}" "${TMP_PATH}/sdX1" || (
      echo "$(printf "$(TEXT "Can't mount %s.")" "${NEW_BLDISK_P1}")" >"${LOG_FILE}"
      __umountNewBlDisk
      break
    )
    mount "${NEW_BLDISK_P2}" "${TMP_PATH}/sdX2" || (
      echo "$(printf "$(TEXT "Can't mount %s.")" "${NEW_BLDISK_P2}")" >"${LOG_FILE}"
      __umountNewBlDisk
      break
    )
    mount "${NEW_BLDISK_P3}" "${TMP_PATH}/sdX3" || (
      echo "$(printf "$(TEXT "Can't mount %s.")" "${NEW_BLDISK_P3}")" >"${LOG_FILE}"
      __umountNewBlDisk
      break
    )

    SIZEOLD1="$(du -sm "${PART1_PATH}" 2>/dev/null | awk '{print $1}')"
    SIZEOLD2="$(du -sm "${PART2_PATH}" 2>/dev/null | awk '{print $1}')"
    SIZEOLD3="$(du -sm "${PART3_PATH}" 2>/dev/null | awk '{print $1}')"
    SIZENEW1="$(df -m "${NEW_BLDISK_P1}" 2>/dev/null | awk 'NR==2 {print $4}')"
    SIZENEW2="$(df -m "${NEW_BLDISK_P2}" 2>/dev/null | awk 'NR==2 {print $4}')"
    SIZENEW3="$(df -m "${NEW_BLDISK_P3}" 2>/dev/null | awk 'NR==2 {print $4}')"

    if [ ${SIZEOLD1:-0} -ge ${SIZENEW1:-0} ] || [ ${SIZEOLD2:-0} -ge ${SIZENEW2:-0} ] || [ ${SIZEOLD3:-0} -ge ${SIZENEW3:-0} ]; then
      MSG="$(TEXT "Cloning failed due to insufficient remaining disk space on the selected hard drive.")"
      echo "${MSG}" >"${LOG_FILE}"
      __umountNewBlDisk
      break
    fi

    cp -vRf "${PART1_PATH}/". "${TMP_PATH}/sdX1/" || (
      echo "$(printf "$(TEXT "Can't copy to %s.")" "${NEW_BLDISK_P1}")" >"${LOG_FILE}"
      __umountNewBlDisk
      break
    )
    cp -vRf "${PART2_PATH}/". "${TMP_PATH}/sdX2/" || (
      echo "$(printf "$(TEXT "Can't copy to %s.")" "${NEW_BLDISK_P2}")" >"${LOG_FILE}"
      __umountNewBlDisk
      break
    )
    cp -vRf "${PART3_PATH}/". "${TMP_PATH}/sdX3/" || (
      echo "$(printf "$(TEXT "Can't copy to %s.")" "${NEW_BLDISK_P3}")" >"${LOG_FILE}"
      __umountNewBlDisk
      break
    )
    sync
    __umountNewBlDisk
    sleep 3
  ) 2>&1 | DIALOG --title "$(TEXT "Advanced")" \
    --progressbox "$(TEXT "Cloning ...")" 20 100
  if [ -f "${LOG_FILE}" ]; then
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "$(cat ${LOG_FILE})" 0 0
  else
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "$(printf "$(TEXT "Bootloader has been cloned to disk %s, please remove the current bootloader disk!\nReboot?")" "${RESP}")" 0 0
    rebootTo config
  fi
  return
}

function reportBugs() {
  rm -rf "${TMP_PATH}/logs" "${TMP_PATH}/logs.tar.gz"
  MSG=""
  SYSLOG=0
  DSMROOTS="$(findDSMRoot)"
  if [ -n "${DSMROOTS}" ]; then
    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      mount -t ext4 "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      mkdir -p "${TMP_PATH}/logs/md0/log"
      cp -rf ${TMP_PATH}/mdX/.log.junior "${TMP_PATH}/logs/md0"
      cp -rf ${TMP_PATH}/mdX/var/log/messages ${TMP_PATH}/mdX/var/log/*.log "${TMP_PATH}/logs/md0/log"
      SYSLOG=1
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX"
  fi
  if [ ${SYSLOG} -eq 1 ]; then
    MSG+="$(TEXT "Find the system logs!\n")"
  else
    MSG+="$(TEXT "Not Find system logs!\n")"
  fi

  PSTORE=0
  if [ -n "$(ls /sys/fs/pstore 2>/dev/null)" ]; then
    mkdir -p "${TMP_PATH}/logs/pstore"
    cp -rf /sys/fs/pstore/* "${TMP_PATH}/logs/pstore"
    [ -n "$(ls /sys/fs/pstore/*.z 2>/dev/null)" ] && zlib-flate -uncompress </sys/fs/pstore/*.z >"${TMP_PATH}/logs/pstore/ps.log" 2>/dev/null
    PSTORE=1
  fi
  if [ ${PSTORE} -eq 1 ]; then
    MSG+="$(TEXT "Find the pstore logs!\n")"
  else
    MSG+="$(TEXT "Not Find pstore logs!\n")"
  fi

  ADDONS=0
  if [ -d "${PART1_PATH}/logs" ]; then
    mkdir -p "${TMP_PATH}/logs/addons"
    cp -rf "${PART1_PATH}/logs"/* "${TMP_PATH}/logs/addons"
    ADDONS=1
  fi
  if [ ${ADDONS} -eq 1 ]; then
    MSG+="$(TEXT "Find the addons logs!\n")"
  else
    MSG+="$(TEXT "Not Find addons logs!\n")"
    MSG+="$(TEXT "Please do as follows:\n")"
    MSG+="$(TEXT " 1. Add dbgutils in addons and rebuild.\n")"
    MSG+="$(TEXT " 2. Wait 10 minutes after booting.\n")"
    MSG+="$(TEXT " 3. Reboot into RR and go to this option.\n")"
  fi

  if [ -n "$(ls -A ${TMP_PATH}/logs 2>/dev/null)" ]; then
    tar -czf "${TMP_PATH}/logs.tar.gz" -C "${TMP_PATH}" logs
    if [ -z "${SSH_TTY}" ]; then # web
      mv -f "${TMP_PATH}/logs.tar.gz" "/var/www/data/logs.tar.gz"
      URL="http://$(getIP)/logs.tar.gz"
      MSG+="$(printf "$(TEXT "Please via %s to download the logs,\nAnd go to github to create an issue and upload the logs.")" "${URL}")"
    else
      sz -be -B 536870912 "${TMP_PATH}/logs.tar.gz"
      MSG+="$(TEXT "Please go to github to create an issue and upload the logs.")"
    fi
  fi
  DIALOG --title "$(TEXT "Advanced")" \
    --msgbox "${MSG}" 0 0
}

###############################################################################
# Set proxy
# $1 - KEY
function setProxy() {
  RET=1
  PROXY=$(readConfigKey "${1}" "${USER_CONFIG_FILE}")
  while true; do
    [ "${1}" = "global_proxy" ] && EG="http://192.168.1.1:7981/" || EG="https://mirror.ghproxy.com/"
    DIALOG --title "$(TEXT "Advanced")" \
      --inputbox "$(printf "$(TEXT "Please enter a proxy server url.(e.g., %s)")" "${EG}")" 0 70 "${PROXY}" \
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
    deleteConfigKey "${1}" "${USER_CONFIG_FILE}"
    if [ "${1}" = "global_proxy" ]; then
      unset http_proxy
      unset https_proxy
    fi
  else
    writeConfigKey "${1}" "${PROXY}" "${USER_CONFIG_FILE}"
    if [ "${1}" = "global_proxy" ]; then
      export http_proxy="${PROXY}"
      export https_proxy="${PROXY}"
    fi
  fi
  return
}

###############################################################################
# Advanced menu
function advancedMenu() {
  NEXT="q"
  while true; do
    rm -f "${TMP_PATH}/menu"
    echo "9 \"$(TEXT "DSM rd compression:") \Z4${RD_COMPRESSED}\Zn\"" >>"${TMP_PATH}/menu"
    echo "l \"$(TEXT "Switch LKM version:") \Z4${LKM}\Zn\"" >>"${TMP_PATH}/menu"
    echo "j \"$(TEXT "HDD sort(hotplug):") \Z4${HDDSORT}\Zn\"" >>"${TMP_PATH}/menu"
    if [ -n "${PRODUCTVER}" ]; then
      echo "c \"$(TEXT "show/modify the current pat data")\"" >>"${TMP_PATH}/menu"
      echo "8 \"$(TEXT "Switch SATADOM mode:") \Z4${SATADOM}\Zn\"" >>"${TMP_PATH}/menu"
    fi
    if [ -n "${PLATFORM}" ] && [ "true" = "$(readConfigKey "platforms.${PLATFORM}.dt" "${WORK_PATH}/platforms.yml")" ]; then
      echo "d \"$(TEXT "Custom DTS")\"" >>"${TMP_PATH}/menu"
    fi
    echo "q \"$(TEXT "Switch direct boot:") \Z4${DIRECTBOOT}\Zn\"" >>"${TMP_PATH}/menu"
    if [ "${DIRECTBOOT}" = "false" ]; then
      echo "i \"$(TEXT "Timeout of get ip in boot:") \Z4${BOOTIPWAIT}\Zn\"" >>"${TMP_PATH}/menu"
      echo "w \"$(TEXT "Timeout of boot wait:") \Z4${BOOTWAIT}\Zn\"" >>"${TMP_PATH}/menu"
      echo "k \"$(TEXT "kernel switching method:") \Z4${KERNELWAY}\Zn\"" >>"${TMP_PATH}/menu"
    fi
    echo "n \"$(TEXT "Reboot on kernel panic:") \Z4${KERNELPANIC}\Zn\"" >>"${TMP_PATH}/menu"
    if [ -n "$(ls /dev/mmcblk* 2>/dev/null)" ]; then
      echo "b \"$(TEXT "Use EMMC as the system disk:") \Z4${EMMCBOOT}\Zn\"" >>"${TMP_PATH}/menu"
    fi
    echo "0 \"$(TEXT "Custom patch script # Developer")\"" >>"${TMP_PATH}/menu"
    echo "u \"$(TEXT "Edit user config file manually")\"" >>"${TMP_PATH}/menu"
    echo "h \"$(TEXT "Edit grub.cfg file manually")\"" >>"${TMP_PATH}/menu"
    if [ ! "LOCALBUILD" = "${LOADER_DISK}" ]; then
      echo "m \"$(TEXT "Set static IP")\"" >>"${TMP_PATH}/menu"
      echo "3 \"$(TEXT "Set wireless account")\"" >>"${TMP_PATH}/menu"
      echo "s \"$(TEXT "Show disks information")\"" >>"${TMP_PATH}/menu"
      echo "f \"$(TEXT "Format disk(s) # Without loader disk")\"" >>"${TMP_PATH}/menu"
      echo "t \"$(TEXT "Try to recovery a installed DSM system")\"" >>"${TMP_PATH}/menu"
      echo "a \"$(TEXT "Allow downgrade installation")\"" >>"${TMP_PATH}/menu"
      echo "x \"$(TEXT "Reset DSM system password")\"" >>"${TMP_PATH}/menu"
      echo "y \"$(TEXT "Add a new user to DSM system")\"" >>"${TMP_PATH}/menu"
      echo "z \"$(TEXT "Force enable Telnet&SSH of DSM system")\"" >>"${TMP_PATH}/menu"
      echo "4 \"$(TEXT "Remove the blocked ip database of DSM")\"" >>"${TMP_PATH}/menu"
      echo "6 \"$(TEXT "Initialize DSM network settings")\"" >>"${TMP_PATH}/menu"
      echo "r \"$(TEXT "Clone bootloader disk to another disk")\"" >>"${TMP_PATH}/menu"
      echo "v \"$(TEXT "Report bugs to the author")\"" >>"${TMP_PATH}/menu"
      echo "5 \"$(TEXT "Download DSM config backup files")\"" >>"${TMP_PATH}/menu"
      echo "o \"$(TEXT "Install development tools")\"" >>"${TMP_PATH}/menu"
      echo "p \"$(TEXT "Save modifications of '/opt/rr'")\"" >>"${TMP_PATH}/menu"
    fi
    echo "g \"$(TEXT "Show QR logo:") \Z4${DSMLOGO}\Zn\"" >>"${TMP_PATH}/menu"
    echo "1 \"$(TEXT "Set global proxy")\"" >>"${TMP_PATH}/menu"
    echo "2 \"$(TEXT "Set github proxy")\"" >>"${TMP_PATH}/menu"
    echo "! \"$(TEXT "Vigorously miracle")\"" >>"${TMP_PATH}/menu"
    echo "e \"$(TEXT "Exit")\"" >>"${TMP_PATH}/menu"

    DIALOG --title "$(TEXT "Advanced")" \
      --default-item "${NEXT}" --menu "$(TEXT "Advanced option")" 0 0 0 --file "${TMP_PATH}/menu" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && break
    case $(cat "${TMP_PATH}/resp") in
    9)
      [ "${RD_COMPRESSED}" = "true" ] && RD_COMPRESSED='false' || RD_COMPRESSED='true'
      writeConfigKey "rd-compressed" "${RD_COMPRESSED}" "${USER_CONFIG_FILE}"
      touch ${PART1_PATH}/.build
      NEXT="9"
      ;;
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
      NEXT="j"
      ;;
    c)
      PATURL="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
      PATSUM="$(readConfigKey "patsum" "${USER_CONFIG_FILE}")"
      MSG="$(TEXT "pat: (editable)")"
      DIALOG --title "$(TEXT "Advanced")" \
        --form "${MSG}" 10 110 2 "URL" 1 1 "${PATURL}" 1 5 100 0 "MD5" 2 1 "${PATSUM}" 2 5 100 0 \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && continue
      paturl="$(cat "${TMP_PATH}/resp" | sed -n '1p')"
      patsum="$(cat "${TMP_PATH}/resp" | sed -n '2p')"
      if [ ! ${paturl} = ${PATURL} ] || [ ! ${patsum} = ${PATSUM} ]; then
        writeConfigKey "paturl" "${paturl}" "${USER_CONFIG_FILE}"
        writeConfigKey "patsum" "${patsum}" "${USER_CONFIG_FILE}"
        rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
        touch ${PART1_PATH}/.build
      fi
      NEXT="e"
      ;;
    8)
      rm -f "${TMP_PATH}/opts"
      echo "1 \"Native SATA Disk(SYNO)\"" >>"${TMP_PATH}/opts"
      echo "2 \"Fake SATA DOM(Redpill)\"" >>"${TMP_PATH}/opts"
      DIALOG --title "$(TEXT "Advanced")" \
        --default-item "${SATADOM}" --menu "$(TEXT "Choose a mode(Only supported for kernel version 4)")" 0 0 0 --file "${TMP_PATH}/opts" \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && continue
      resp=$(cat ${TMP_PATH}/resp 2>/dev/null)
      [ -z "${resp}" ] && continue
      SATADOM=${resp}
      writeConfigKey "satadom" "${SATADOM}" "${USER_CONFIG_FILE}"
      NEXT="8"
      ;;
    d)
      customDTS
      NEXT="e"
      ;;
    q)
      [ "${DIRECTBOOT}" = "false" ] && DIRECTBOOT='true' || DIRECTBOOT='false'
      writeConfigKey "directboot" "${DIRECTBOOT}" "${USER_CONFIG_FILE}"
      NEXT="q"
      ;;
    i)
      ITEMS="$(echo -e "1 \n5 \n10 \n30 \n60 \n")"
      DIALOG --title "$(TEXT "Advanced")" \
        --default-item "${BOOTIPWAIT}" --no-items --menu "$(TEXT "Choose a time(seconds)")" 0 0 0 ${ITEMS} \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && continue
      resp=$(cat ${TMP_PATH}/resp 2>/dev/null)
      [ -z "${resp}" ] && continue
      BOOTIPWAIT=${resp}
      writeConfigKey "bootipwait" "${BOOTIPWAIT}" "${USER_CONFIG_FILE}"
      NEXT="i"
      ;;
    w)
      ITEMS="$(echo -e "1 \n5 \n10 \n30 \n60 \n")"
      DIALOG --title "$(TEXT "Advanced")" \
        --default-item "${BOOTWAIT}" --no-items --menu "$(TEXT "Choose a time(seconds)")" 0 0 0 ${ITEMS} \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && continue
      resp=$(cat ${TMP_PATH}/resp 2>/dev/null)
      [ -z "${resp}" ] && continue
      BOOTWAIT=${resp}
      writeConfigKey "bootwait" "${BOOTWAIT}" "${USER_CONFIG_FILE}"
      NEXT="w"
      ;;
    k)
      [ "${KERNELWAY}" = "kexec" ] && KERNELWAY='power' || KERNELWAY='kexec'
      writeConfigKey "kernelway" "${KERNELWAY}" "${USER_CONFIG_FILE}"
      NEXT="k"
      ;;
    n)
      rm -f "${TMP_PATH}/opts"
      echo "5 \"Reboot after 5 seconds\"" >>"${TMP_PATH}/opts"
      echo "0 \"No reboot\"" >>"${TMP_PATH}/opts"
      echo "-1 \"Restart immediately\"" >>"${TMP_PATH}/opts"
      DIALOG --title "$(TEXT "Advanced")" \
        --default-item "${KERNELPANIC}" --menu "$(TEXT "Choose a time(seconds)")" 0 0 0 --file "${TMP_PATH}/opts" \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && continue
      resp=$(cat ${TMP_PATH}/resp 2>/dev/null)
      [ -z "${resp}" ] && continue
      KERNELPANIC=${resp}
      writeConfigKey "kernelpanic" "${KERNELPANIC}" "${USER_CONFIG_FILE}"
      NEXT="n"
      ;;
    b)
      if [ "${EMMCBOOT}" = "true" ]; then
        EMMCBOOT='false'
        writeConfigKey "emmcboot" "false" "${USER_CONFIG_FILE}"
        deleteConfigKey "cmdline.root" "${USER_CONFIG_FILE}"
        deleteConfigKey "synoinfo.disk_swap" "${USER_CONFIG_FILE}"
        deleteConfigKey "synoinfo.supportraid" "${USER_CONFIG_FILE}"
        deleteConfigKey "synoinfo.support_emmc_boot" "${USER_CONFIG_FILE}"
        deleteConfigKey "synoinfo.support_install_only_dev" "${USER_CONFIG_FILE}"
      else
        EMMCBOOT='true'
        writeConfigKey "emmcboot" "true" "${USER_CONFIG_FILE}"
        writeConfigKey "cmdline.root" "/dev/mmcblk0p1" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.disk_swap" "no" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.supportraid" "no" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.support_emmc_boot" "yes" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.support_install_only_dev" "yes" "${USER_CONFIG_FILE}"
      fi
      touch ${PART1_PATH}/.build
      NEXT="b"
      ;;
    0)
      MSG=""
      MSG+="$(TEXT "This option is only informative.\n\n")"
      MSG+="$(TEXT "This program reserves an interface for ramdisk custom patch scripts.\n")"
      MSG+="$(TEXT "Call timing: called before ramdisk packaging.\n")"
      MSG+="$(TEXT "Location: /mnt/p3/scripts/*.sh\n")"
      DIALOG --title "$(TEXT "Advanced")" \
        --msgbox "${MSG}" 0 0
      NEXT="e"
      ;;
    u)
      editUserConfig
      NEXT="e"
      ;;
    h)
      editGrubCfg
      NEXT="e"
      ;;
    m)
      setStaticIP
      NEXT="e"
      ;;
    3)
      setWirelessAccount
      NEXT="e"
      ;;
    s)
      showDisksInfo
      NEXT="e"
      ;;
    f)
      formatDisks
      NEXT="e"
      ;;
    t)
      tryRecoveryDSM
      NEXT="e"
      ;;
    a)
      allowDSMDowngrade
      NEXT="e"
      ;;
    x)
      resetDSMPassword
      NEXT="e"
      ;;
    y)
      addNewDSMUser
      NEXT="e"
      ;;
    z)
      forceEnableDSMTelnetSSH
      NEXT="e"
      ;;
    4)
      removeBlockIPDB
      NEXT="e"
      ;;
    6)
      initDSMNetwork
      NEXT="e"
      ;;
    r)
      cloneBootloaderDisk
      NEXT="e"
      ;;
    v)
      reportBugs
      NEXT="e"
      ;;
    5)
      if [ -d "${PART1_PATH}/scbk" ]; then
        rm -f "${TMP_PATH}/scbk.tar.gz"
        tar -czf "${TMP_PATH}/scbk.tar.gz" -C "${PART1_PATH}" scbk
        if [ -z "${SSH_TTY}" ]; then # web
          mv -f "${TMP_PATH}/scbk.tar.gz" "/var/www/data/scbk.tar.gz"
          URL="http://$(getIP)/scbk.tar.gz"
          DIALOG --title "$(TEXT "Advanced")" \
            --msgbox "$(printf "$(TEXT "Please via %s to download the scbk,\nAnd unzip it and back it up in order by file name.")" "${URL}")" 0 0
        else
          sz -be -B 536870912 "${TMP_PATH}/scbk.tar.gz"
          DIALOG --title "$(TEXT "Advanced")" \
            --msgbox "$(TEXT "Please unzip it and back it up in order by file name.")" 0 0
        fi
      else
        MSG=""
        MSG+="$(TEXT "\Z1No scbk found!\Zn\n\n")"
        MSG+="$(TEXT "Please do as follows:\n")"
        MSG+="$(TEXT " 1. Add synoconfbkp in addons and rebuild.\n")"
        MSG+="$(TEXT " 2. Normal use.\n")"
        MSG+="$(TEXT " 3. Reboot into RR and go to this option.\n")"
        DIALOG --title "$(TEXT "Advanced")" \
          --msgbox "${MSG}" 0 0
      fi
      NEXT="e"
      ;;
    o)
      DIALOG --title "$(TEXT "Advanced")" \
        --yesno "$(TEXT "This option only installs opkg package management, allowing you to install more tools for use and debugging. Do you want to continue?")" 0 0
      [ $? -ne 0 ] && continue
      rm -f "${LOG_FILE}"
      while true; do
        wget http://bin.entware.net/x64-k3.2/installer/generic.sh -O "generic.sh" >"${LOG_FILE}"
        [ $? -ne 0 -o ! -f "generic.sh" ] && break
        chmod +x "generic.sh"
        ./generic.sh 2>"${LOG_FILE}"
        [ $? -ne 0 ] && break
        opkg update 2>"${LOG_FILE}"
        [ $? -ne 0 ] && break
        rm -f "generic.sh" "${LOG_FILE}"
        break
      done 2>&1 | DIALOG --title "$(TEXT "Advanced")" \
        --progressbox "$(TEXT "opkg installing ...")" 20 100
      if [ -f "${LOG_FILE}" ]; then
        MSG="$(TEXT "opkg install failed.")\n$(cat "${LOG_FILE}"))"
      else
        MSG="$(TEXT "opkg install complete.")"
      fi
      DIALOG --title "$(TEXT "Advanced")" \
        --msgbox "${MSG}" 0 0
      NEXT="e"
      ;;
    p)
      DIALOG --title "$(TEXT "Advanced")" \
        --yesno "$(TEXT "Warning:\nDo not terminate midway, otherwise it may cause damage to the RR. Do you want to continue?")" 0 0
      [ $? -ne 0 ] && continue
      DIALOG --title "$(TEXT "Advanced")" \
        --infobox "$(TEXT "Saving ...\n(It usually takes 5-10 minutes, please be patient and wait.)")" 0 0
      RDXZ_PATH="${TMP_PATH}/rdxz_tmp"
      rm -rf "${RDXZ_PATH}"
      mkdir -p "${RDXZ_PATH}"
      (
        cd "${RDXZ_PATH}"
        xz -dc <"${RR_RAMDISK_FILE}" | cpio -idm
      ) >/dev/null 2>&1 || true
      rm -rf "${RDXZ_PATH}/opt/rr"
      cp -Rf "$(dirname ${WORK_PATH})" "${RDXZ_PATH}/"
      (
        cd "${RDXZ_PATH}"
        find . 2>/dev/null | cpio -o -H newc -R root:root | pv -n -s $(du -sb ${RDXZ_PATH} | awk '{print $1}') | xz -9 --check=crc32 >"${RR_RAMDISK_FILE}"
      ) 2>&1 | DIALOG --title "$(TEXT "Advanced")" \
        --gauge "$(TEXT "Saving ...\n(It usually takes 5-10 minutes, please be patient and wait.)")" 8 100
      rm -rf "${RDXZ_PATH}"
      DIALOG --title "$(TEXT "Advanced")" \
        --msgbox ""$(TEXT "Save is complete.")"" 0 0
      NEXT="e"
      ;;
    g)
      [ "${DSMLOGO}" = "true" ] && DSMLOGO='false' || DSMLOGO='true'
      writeConfigKey "dsmlogo" "${DSMLOGO}" "${USER_CONFIG_FILE}"
      NEXT="g"
      ;;
    1)
      setProxy "global_proxy"
      NEXT="e"
      ;;
    2)
      setProxy "github_proxy"
      NEXT="e"
      ;;
    !)
      MSG=""
      MSG+="                                            \n"
      MSG+=" ██▀███   ██▀███   ▒█████   ██▀███    ▄████ \n"
      MSG+="▓██ ▒ ██▒▓██ ▒ ██▒▒██▒  ██▒▓██ ▒ ██▒ ██▒ ▀█▒\n"
      MSG+="▓██ ░▄█ ▒▓██ ░▄█ ▒▒██░  ██▒▓██ ░▄█ ▒▒██░▄▄▄░\n"
      MSG+="▒██▀▀█▄  ▒██▀▀█▄  ▒██   ██░▒██▀▀█▄  ░▓█  ██▓\n"
      MSG+="░██▓ ▒██▒░██▓ ▒██▒░ ████▓▒░░██▓ ▒██▒░▒▓███▀▒\n"
      MSG+="░ ▒▓ ░▒▓░░ ▒▓ ░▒▓░░ ▒░▒░▒░ ░ ▒▓ ░▒▓░ ░▒   ▒ \n"
      MSG+="  ░▒ ░ ▒░  ░▒ ░ ▒░  ░ ▒ ▒░   ░▒ ░ ▒░  ░   ░ \n"
      MSG+="  ░░   ░   ░░   ░ ░ ░ ░ ▒    ░░   ░ ░ ░   ░ \n"
      MSG+="   ░        ░         ░ ░     ░           ░ \n"
      MSG+="                                            \n"
      DIALOG --title "$(TEXT "Advanced")" \
        --msgbox "${MSG}" 0 0
      NEXT="e"
      ;;
    e) break ;;
    esac
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
  rm -f "${TMP_PATH}/menu"
  while read L; do
    A="$(echo "$(strings "${WORK_PATH}/lang/${L}/LC_MESSAGES/rr.mo" 2>/dev/null | grep "Last-Translator" | sed "s/Last-Translator://")")"
    echo "${L} \"${A:-"anonymous"}\"" >>"${TMP_PATH}/menu"
  done <<<$(ls ${WORK_PATH}/lang/*/LC_MESSAGES/rr.mo 2>/dev/null | sort | sed -r 's/.*\/lang\/(.*)\/LC_MESSAGES\/rr\.mo$/\1/')

  DIALOG \
    --default-item "${LAYOUT}" --menu "$(TEXT "Choose a language")" 0 0 0 --file "${TMP_PATH}/menu" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  resp=$(cat ${TMP_PATH}/resp 2>/dev/null)
  [ -z "${resp}" ] && return
  LANGUAGE=${resp}
  echo "${LANGUAGE}.UTF-8" >${PART1_PATH}/.locale
  export LC_ALL="${LANGUAGE}.UTF-8"
}

###############################################################################
# Shows available keymaps to user choose one
function keymapMenu() {
  OPTIONS="$(ls /usr/share/keymaps/i386 2>/dev/null | grep -v include)"
  DIALOG \
    --default-item "${LAYOUT}" --no-items --menu "$(TEXT "Choose a layout")" 0 0 0 ${OPTIONS} \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  LAYOUT="$(cat ${TMP_PATH}/resp)"
  OPTIONS=""
  while read KM; do
    OPTIONS+="${KM::-7} "
  done <<<$(
    cd /usr/share/keymaps/i386/${LAYOUT}
    ls *.map.gz 2>/dev/null
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
  MSG="$(TEXT "Checking last version ...")"
  if [ "${5}" = "-1" ]; then
    echo "${T} - ${MSG}"
  else
    DIALOG --title "${T}" \
      --infobox "${MSG}" 0 0
  fi
  TAG=""
  if [ "${PRERELEASE}" = "true" ]; then
    # TAG="$(curl -skL --connect-timeout 10 "${PROXY}${3}/tags" | pup 'a[class="Link--muted"] attr{href}' | grep ".zip" | head -1)"
    TAG="$(curl -skL --connect-timeout 10 "${PROXY}${3}/tags" | grep /refs/tags/.*\.zip | sed -r 's/.*\/refs\/tags\/(.*)\.zip.*$/\1/' | sort -rV | head -1)"
  else
    LATESTURL="$(curl -skL --connect-timeout 10 -w %{url_effective} -o /dev/null "${PROXY}${3}/releases/latest")"
    TAG="${LATESTURL##*/}"
  fi
  [ "${TAG:0:1}" = "v" ] && TAG="${TAG:1}"
  if [ -z "${TAG}" -o "${TAG}" = "latest" ]; then
    MSG="$(printf "$(TEXT "Error checking new version.\nError: TAG is %s")" "${TAG}")"
    if [ "${5}" = "-1" ]; then
      echo "${T} - ${MSG}"
    elif [ "${5}" = "0" ]; then
      DIALOG --title "${T}" \
        --msgbox "${MSG}" 0 0
    else
      DIALOG --title "${T}" \
        --infobox "${MSG}" 0 0
    fi
    return 1
  fi
  if [ "${2}" = "${TAG}" ]; then
    MSG="$(TEXT "No new version.")\n"
    if [ "${5}" = "-1" ]; then
      echo "${T} - ${MSG}"
    elif [ "${5}" = "0" ]; then
      MSG+="$(printf "$(TEXT "Actual version is %s.\nForce update?")" "${2}")"
      DIALOG --title "${T}" \
        --yesno "${MSG}" 0 0
      [ $? -ne 0 ] && return 1
    else
      DIALOG --title "${T}" \
        --infobox "${MSG}" 0 0
      return 1
    fi
  else
    MSG=""
    MSG+="Latest: ${TAG}\n\n"
    MSG+="$(curl -skL --connect-timeout 10 "${PROXY}${3}/releases/tag/${TAG}" | pup 'div[data-test-selector="body-content"]' | html2text --ignore-links --ignore-images)\n\n"
    MSG+="$(TEXT "Do you want to update?")"
    if [ "${5}" = "-1" ]; then
      echo "${T} - ${MSG}"
    elif [ "${5}" = "0" ]; then
      DIALOG --title "${T}" \
        --yesno "$(echo -e "${MSG}")" 0 0
      [ $? -ne 0 ] && return 1
    else
      DIALOG --title "${T}" \
        --infobox "$(echo -e "${MSG}")" 0 0
    fi
  fi
  function __download() {
    rm -f ${TMP_PATH}/${4}*.zip
    touch "${TMP_PATH}/${4}-${TAG}.zip.downloading"
    STATUS=$(curl -kL --connect-timeout 10 -w "%{http_code}" "${PROXY}${3}/releases/download/${TAG}/${4}-${TAG}.zip" -o "${TMP_PATH}/${4}-${TAG}.zip")
    RET=$?
    rm -f "${TMP_PATH}/${4}-${TAG}.zip.downloading"
    if [ ${RET} -ne 0 -o ${STATUS:-0} -ne 200 ]; then
      rm -f "${TMP_PATH}/${4}-${TAG}.zip"
      MSG="$(printf "$(TEXT "Error downloading new version.\nError: %d:%d\n(Please via https://curl.se/libcurl/c/libcurl-errors.html check error description.)")" "${RET}" "${STATUS}")"
      echo -e "${MSG}" >"${LOG_FILE}"
    fi
    return 0
  }
  rm -f "${LOG_FILE}"
  if [ "${5}" = "-1" ]; then
    __download $@ 2>&1
  else
    __download $@ 2>&1 | DIALOG --title "${T}" \
      --progressbox "$(TEXT "Downloading ...")" 20 100
  fi
  if [ -f "${LOG_FILE}" ]; then
    if [ "${5}" = "-1" ]; then
      echo "${T} - $(cat "${LOG_FILE}")"
    elif [ "${5}" = "0" ]; then
      DIALOG --title "${T}" \
        --msgbox "$(cat "${LOG_FILE}")" 0 0
    else
      DIALOG --title "${T}" \
        --infobox "$(cat "${LOG_FILE}")" 0 0
    fi
    return 1
  fi
  return 0
}

# 1 - update file
# 2 - silent
function updateRR() {
  T="$(printf "$(TEXT "Update %s")" "$(TEXT "RR")")"
  MSG="$(TEXT "Extracting update file ...")"
  if [ "${2}" = "-1" ]; then
    echo "${T} - ${MSG}"
  else
    DIALOG --title "${T}" \
      --infobox "${MSG}" 0 0
  fi
  rm -rf "${TMP_PATH}/update"
  mkdir -p "${TMP_PATH}/update"
  unzip -oq "${1}" -d "${TMP_PATH}/update" >"${LOG_FILE}" 2>&1
  if [ $? -ne 0 ]; then
    MSG="$(TEXT "Error extracting update file.")\n$(cat "${LOG_FILE}")"
    if [ "${2}" = "-1" ]; then
      echo "${T} - ${MSG}"
    else
      DIALOG --title "${T}" \
        --msgbox "${MSG}" 0 0
    fi
    return 1
  fi
  # Check checksums
  (cd "${TMP_PATH}/update" && sha256sum --status -c sha256sum)
  if [ $? -ne 0 ]; then
    MSG="$(TEXT "Checksum do not match!")"
    if [ "${2}" = "-1" ]; then
      echo "${T} - ${MSG}"
    else
      DIALOG --title "${T}" \
        --msgbox "${MSG}" 0 0
    fi
    return 1
  fi
  # Check conditions
  if [ -f "${TMP_PATH}/update/update-check.sh" ]; then
    cat "${TMP_PATH}/update/update-check.sh" | bash
    if [ $? -ne 0 ]; then
      MSG="$(TEXT "The current version does not support upgrading to the latest update.zip. Please remake the bootloader disk!")"
      if [ "${2}" = "-1" ]; then
        echo "${T} - ${MSG}"
      else
        DIALOG --title "${T}" \
          --msgbox "${MSG}" 0 0
      fi
      return 1
    fi
  fi

  SIZENEW=0
  SIZEOLD=0
  while IFS=': ' read KEY VALUE; do
    if [ "${KEY: -1}" = "/" ]; then
      rm -Rf "${TMP_PATH}/update/${VALUE}"
      mkdir -p "${TMP_PATH}/update/${VALUE}"
      tar -zxf "${TMP_PATH}/update/$(basename "${KEY}").tgz" -C "${TMP_PATH}/update/${VALUE}" >"${LOG_FILE}" 2>&1
      if [ $? -ne 0 ]; then
        MSG="$(TEXT "Error extracting update file.")\n$(cat "${LOG_FILE}")"
        if [ "${2}" = "-1" ]; then
          echo "${T} - ${MSG}"
        else
          DIALOG --title "${T}" \
            --msgbox "${MSG}" 0 0
        fi
        return 1
      fi
      rm "${TMP_PATH}/update/$(basename "${KEY}").tgz"
    else
      mkdir -p "${TMP_PATH}/update/$(dirname "${VALUE}")"
      mv -f "${TMP_PATH}/update/$(basename "${KEY}")" "${TMP_PATH}/update/${VALUE}"
    fi
    FSNEW=$(du -sm "${TMP_PATH}/update/${VALUE}" 2>/dev/null | awk '{print $1}')
    FSOLD=$(du -sm "${VALUE}" 2>/dev/null | awk '{print $1}')
    SIZENEW=$((${SIZENEW} + ${FSNEW:-0}))
    SIZEOLD=$((${SIZEOLD} + ${FSOLD:-0}))
  done <<<$(readConfigMap "replace" "${TMP_PATH}/update/update-list.yml")

  SIZESPL=$(df -m "${PART3_PATH}" 2>/dev/null | awk 'NR==2 {print $4}')
  if [ ${SIZENEW:-0} -ge $((${SIZEOLD:-0} + ${SIZESPL:-0})) ]; then
    MSG="$(printf "$(TEXT "Failed to install due to insufficient remaning disk space on local hard drive, consider reallocate your disk %s with at least %sM.")" "${PART3_PATH}" "$((${SIZENEW:-0} - ${SIZEOLD:-0} - ${SIZESPL:-0}))")"
    if [ "${2}" = "-1" ]; then
      echo "${T} - ${MSG}"
    else
      DIALOG --title "${T}" \
        --msgbox "${MSG}" 0 0
    fi
    return 1
  fi

  MSG="$(TEXT "Installing new files ...")"
  if [ "${2}" = "-1" ]; then
    echo "${T} - ${MSG}"
  else
    DIALOG --title "${T}" \
      --infobox "${MSG}" 0 0
  fi
  # Process update-list.yml
  while read F; do
    [ -f "${F}" ] && rm -f "${F}"
    [ -d "${F}" ] && rm -Rf "${F}"
  done <<<$(readConfigArray "remove" "${TMP_PATH}/update/update-list.yml")
  while IFS=': ' read KEY VALUE; do
    if [ "${KEY: -1}" = "/" ]; then
      rm -Rf "${VALUE}"/*
      mkdir -p "${VALUE}"
      cp -Rf "${TMP_PATH}/update/${VALUE}"/* "${VALUE}"
      if [ "$(realpath "${VALUE}")" = "$(realpath "${MODULES_PATH}")" ]; then
        if [ -n "${MODEL}" -a -n "${PRODUCTVER}" ]; then
          KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${WORK_PATH}/platforms.yml")"
          KPRE="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kpre" "${WORK_PATH}/platforms.yml")"
          if [ -n "${PLATFORM}" -a -n "${KVER}" ]; then
            writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
            while read ID DESC; do
              writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
            done <<<$(getAllModules "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}")
          fi
        fi
      fi
    else
      mkdir -p "$(dirname "${VALUE}")"
      cp -f "${TMP_PATH}/update/${VALUE}" "${VALUE}"
    fi
  done <<<$(readConfigMap "replace" "${TMP_PATH}/update/update-list.yml")
  rm -rf "${TMP_PATH}/update"
  touch ${PART1_PATH}/.build
  sync
  MSG="$(printf "$(TEXT "%s updated with success!")" "$(TEXT "RR")")\n$(TEXT "Reboot?")"
  if [ "${2}" = "-1" ]; then
    echo "${T} - ${MSG}"
  else
    DIALOG --title "${T}" \
      --msgbox "${MSG}" 0 0
    DIALOG --title "${T}" \
      --infobox "$(TEXT "Reboot to RR")" 0 0
    rebootTo config
    exit 0
  fi
}

# 1 - update file
# 2 - silent
function updateAddons() {
  T="$(printf "$(TEXT "Update %s")" "$(TEXT "Addons")")"
  MSG="$(TEXT "Extracting update file ...")"
  if [ "${2}" = "-1" ]; then
    echo "${T} - ${MSG}"
  else
    DIALOG --title "${T}" \
      --infobox "${MSG}" 0 0
  fi
  rm -rf "${TMP_PATH}/update"
  mkdir -p "${TMP_PATH}/update"
  unzip -oq "${1}" -d "${TMP_PATH}/update" >"${LOG_FILE}" 2>&1
  if [ $? -ne 0 ]; then
    MSG="$(TEXT "Error extracting update file.")\n$(cat "${LOG_FILE}")"
    if [ "${2}" = "-1" ]; then
      echo "${T} - ${MSG}"
    else
      DIALOG --title "${T}" \
        --msgbox "${MSG}" 0 0
    fi
    return 1
  fi

  for PKG in $(ls ${TMP_PATH}/update/*.addon 2>/dev/null); do
    ADDON=$(basename ${PKG} .addon)
    rm -rf "${TMP_PATH}/update/${ADDON}"
    mkdir -p "${TMP_PATH}/update/${ADDON}"
    tar -xaf "${PKG}" -C "${TMP_PATH}/update/${ADDON}" >/dev/null 2>&1
    rm -f "${PKG}"
  done

  SIZENEW="$(du -sm "${TMP_PATH}/update" 2>/dev/null | awk '{print $1}')"
  SIZEOLD="$(du -sm "${ADDONS_PATH}" 2>/dev/null | awk '{print $1}')"
  SIZESPL=$(df -m "${ADDONS_PATH}" 2>/dev/null | awk 'NR==2 {print $4}')
  if [ ${SIZENEW:-0} -ge $((${SIZEOLD:-0} + ${SIZESPL:-0})) ]; then
    MSG="$(printf "$(TEXT "Failed to install due to insufficient remaning disk space on local hard drive, consider reallocate your disk %s with at least %sM.")" "$(dirname "${ADDONS_PATH}")" "$((${SIZENEW:-0} - ${SIZEOLD:-0} - ${SIZESPL:-0}))")"
    if [ "${2}" = "-1" ]; then
      echo "${T} - ${MSG}"
    else
      DIALOG --title "${T}" \
        --msgbox "${MSG}" 0 0
    fi
    return 1
  fi

  rm -Rf "${ADDONS_PATH}/"*
  cp -Rf "${TMP_PATH}/update/"* "${ADDONS_PATH}/"
  rm -rf "${TMP_PATH}/update"
  touch ${PART1_PATH}/.build
  sync
  MSG="$(printf "$(TEXT "%s updated with success!")" "$(TEXT "Addons")")"
  if [ "${2}" = "-1" ]; then
    echo "${T} - ${MSG}"
  elif [ "${2}" = "0" ]; then
    DIALOG --title "${T}" \
      --msgbox "${MSG}" 0 0
  else
    DIALOG --title "${T}" \
      --infobox "${MSG}" 0 0
  fi
}

# 1 - update file
# 2 - silent
function updateModules() {
  T="$(printf "$(TEXT "Update %s")" "$(TEXT "Modules")")"
  MSG="$(TEXT "Extracting update file ...")"
  if [ "${2}" = "-1" ]; then
    echo "${T} - ${MSG}"
  else
    DIALOG --title "${T}" \
      --infobox "${MSG}" 0 0
  fi
  rm -rf "${TMP_PATH}/update"
  mkdir -p "${TMP_PATH}/update"
  unzip -oq "${1}" -d "${TMP_PATH}/update" >"${LOG_FILE}" 2>&1
  if [ $? -ne 0 ]; then
    MSG="$(TEXT "Error extracting update file.")\n$(cat "${LOG_FILE}")"
    if [ "${2}" = "-1" ]; then
      echo "${T} - ${MSG}"
    else
      DIALOG --title "${T}" \
        --msgbox "${MSG}" 0 0
    fi
    return 1
  fi

  SIZENEW="$(du -sm "${TMP_PATH}/update" 2>/dev/null | awk '{print $1}')"
  SIZEOLD="$(du -sm "${MODULES_PATH}" 2>/dev/null | awk '{print $1}')"
  SIZESPL=$(df -m "${MODULES_PATH}" 2>/dev/null | awk 'NR==2 {print $4}')
  if [ ${SIZENEW:-0} -ge $((${SIZEOLD:-0} + ${SIZESPL:-0})) ]; then
    MSG="$(printf "$(TEXT "Failed to install due to insufficient remaning disk space on local hard drive, consider reallocate your disk %s with at least %sM.")" "$(dirname "${MODULES_PATH}")" "$((${SIZENEW:-0} - ${SIZEOLD:-0} - ${SIZESPL:-0}))")"
    if [ "${2}" = "-1" ]; then
      echo "${T} - ${MSG}"
    else
      DIALOG --title "${T}" \
        --msgbox "${MSG}" 0 0
    fi
    return 1
  fi

  rm -rf "${MODULES_PATH}/"*
  cp -rf "${TMP_PATH}/update/"* "${MODULES_PATH}/"
  if [ -n "${MODEL}" -a -n "${PRODUCTVER}" ]; then
    KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${WORK_PATH}/platforms.yml")"
    KPRE="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kpre" "${WORK_PATH}/platforms.yml")"
    if [ -n "${PLATFORM}" -a -n "${KVER}" ]; then
      writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
      while read ID DESC; do
        writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
      done <<<$(getAllModules "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}")
    fi
  fi
  rm -rf "${TMP_PATH}/update"
  touch ${PART1_PATH}/.build
  sync
  MSG="$(printf "$(TEXT "%s updated with success!")" "$(TEXT "Modules")")"
  if [ "${2}" = "-1" ]; then
    echo "${T} - ${MSG}"
  elif [ "${2}" = "0" ]; then
    DIALOG --title "${T}" \
      --msgbox "${MSG}" 0 0
  else
    DIALOG --title "${T}" \
      --infobox "${MSG}" 0 0
  fi
}

# 1 - update file
# 2 - silent
function updateLKMs() {
  T="$(printf "$(TEXT "Update %s")" "$(TEXT "LKMs")")"
  MSG="$(TEXT "Extracting update file ...")"
  if [ "${2}" = "-1" ]; then
    echo "${T} - ${MSG}"
  else
    DIALOG --title "${T}" \
      --infobox "${MSG}" 0 0
  fi
  rm -rf "${TMP_PATH}/update"
  mkdir -p "${TMP_PATH}/update"
  unzip -oq "${1}" -d "${TMP_PATH}/update" >"${LOG_FILE}" 2>&1
  if [ $? -ne 0 ]; then
    MSG="$(TEXT "Error extracting update file.")\n$(cat "${LOG_FILE}")"
    if [ "${2}" = "-1" ]; then
      echo "${T} - ${MSG}"
    else
      DIALOG --title "${T}" \
        --msgbox "${MSG}" 0 0
    fi
    return 1
  fi

  SIZENEW="$(du -sm "${TMP_PATH}/update" 2>/dev/null | awk '{print $1}')"
  SIZEOLD="$(du -sm "${LKMS_PATH}" 2>/dev/null | awk '{print $1}')"
  SIZESPL=$(df -m "${LKMS_PATH}" 2>/dev/null | awk 'NR==2 {print $4}')
  if [ ${SIZENEW:-0} -ge $((${SIZEOLD:-0} + ${SIZESPL:-0})) ]; then
    MSG="$(printf "$(TEXT "Failed to install due to insufficient remaning disk space on local hard drive, consider reallocate your disk %s with at least %sM.")" "$(dirname "${LKMS_PATH}")" "$((${SIZENEW:-0} - ${SIZEOLD:-0} - ${SIZESPL:-0}))")"
    if [ "${2}" = "-1" ]; then
      echo "${T} - ${MSG}"
    else
      DIALOG --title "${T}" \
        --msgbox "${MSG}" 0 0
    fi
    return 1
  fi

  rm -rf "${LKMS_PATH}/"*
  cp -rf "${TMP_PATH}/update/"* "${LKMS_PATH}/"
  rm -rf "${TMP_PATH}/update"
  touch ${PART1_PATH}/.build
  sync
  MSG="$(printf "$(TEXT "%s updated with success!")" "$(TEXT "LKMs")")"
  if [ "${2}" = "-1" ]; then
    echo "${T} - ${MSG}"
  elif [ "${2}" = "0" ]; then
    DIALOG --title "${T}" \
      --msgbox "${MSG}" 0 0
  else
    DIALOG --title "${T}" \
      --infobox "${MSG}" 0 0
  fi
}

# 1 - update file
# 2 - silent
function updateCKs() {
  T="$(printf "$(TEXT "Update %s")" "$(TEXT "CKs")")"
  MSG="$(TEXT "Extracting update file ...")"
  if [ "${2}" = "-1" ]; then
    echo "${T} - ${MSG}"
  else
    DIALOG --title "${T}" \
      --infobox "${MSG}" 0 0
  fi
  rm -rf "${TMP_PATH}/update"
  mkdir -p "${TMP_PATH}/update"
  unzip -oq "${1}" -d "${TMP_PATH}/update" >"${LOG_FILE}" 2>&1
  if [ $? -ne 0 ]; then
    MSG="$(TEXT "Error extracting update file.")\n$(cat "${LOG_FILE}")"
    if [ "${2}" = "-1" ]; then
      echo "${T} - ${MSG}"
    else
      DIALOG --title "${T}" \
        --msgbox "${MSG}" 0 0
    fi
    return 1
  fi

  SIZENEW="$(du -sm "${TMP_PATH}/update" 2>/dev/null | awk '{print $1}')"
  SIZEOLD="$(du -sm "${CKS_PATH}" 2>/dev/null | awk '{print $1}')"
  SIZESPL=$(df -m "${CKS_PATH}" 2>/dev/null | awk 'NR==2 {print $4}')
  if [ ${SIZENEW:-0} -ge $((${SIZEOLD:-0} + ${SIZESPL:-0})) ]; then
    MSG="$(printf "$(TEXT "Failed to install due to insufficient remaning disk space on local hard drive, consider reallocate your disk %s with at least %sM.")" "$(dirname "${CKS_PATH}")" "$((${SIZENEW:-0} - ${SIZEOLD:-0} - ${SIZESPL:-0}))")"
    if [ "${2}" = "-1" ]; then
      echo "${T} - ${MSG}"
    else
      DIALOG --title "${T}" \
        --msgbox "${MSG}" 0 0
    fi
    return 1
  fi

  rm -rf "${CKS_PATH}/"*
  cp -rf "${TMP_PATH}/update/"* "${CKS_PATH}/"
  if [ -n "${MODEL}" -a -n "${PRODUCTVER}" -a "${KERNEL}" = "custom" ]; then
    KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${WORK_PATH}/platforms.yml")"
    KPRE="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kpre" "${WORK_PATH}/platforms.yml")"
    if [ -n "${PLATFORM}" -a -n "${KVER}" ]; then
      writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
      while read ID DESC; do
        writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
      done <<<$(getAllModules "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}")
    fi
  fi
  rm -rf "${TMP_PATH}/update"
  touch ${PART1_PATH}/.build
  sync
  MSG="$(printf "$(TEXT "%s updated with success!")" "$(TEXT "CKs")")"
  if [ "${2}" = "-1" ]; then
    echo "${T} - ${MSG}"
  elif [ "${2}" = "0" ]; then
    DIALOG --title "${T}" \
      --msgbox "${MSG}" 0 0
  else
    DIALOG --title "${T}" \
      --infobox "${MSG}" 0 0
  fi
}

###############################################################################
function updateMenu() {
  while true; do
    CUR_RR_VER="${RR_VERSION:-0}"
    CUR_ADDONS_VER="$(cat "${ADDONS_PATH}/VERSION" 2>/dev/null)"
    CUR_MODULES_VER="$(cat "${MODULES_PATH}/VERSION" 2>/dev/null)"
    CUR_LKMS_VER="$(cat "${LKMS_PATH}/VERSION" 2>/dev/null)"
    CUR_CKS_VER="$(cat "${CKS_PATH}/VERSION" 2>/dev/null)"
    rm -f "${TMP_PATH}/menu"
    echo "a \"$(TEXT "Update") $(TEXT "All")\"" >>"${TMP_PATH}/menu"
    echo "r \"$(TEXT "Update") $(TEXT "RR") (${CUR_RR_VER:-None})\"" >>"${TMP_PATH}/menu"
    echo "d \"$(TEXT "Update") $(TEXT "Addons") (${CUR_ADDONS_VER:-None})\"" >>"${TMP_PATH}/menu"
    echo "m \"$(TEXT "Update") $(TEXT "Modules") (${CUR_MODULES_VER:-None})\"" >>"${TMP_PATH}/menu"
    echo "l \"$(TEXT "Update") $(TEXT "LKMs") (${CUR_LKMS_VER:-None})\"" >>"${TMP_PATH}/menu"
    echo "c \"$(TEXT "Update") $(TEXT "CKs") (${CUR_CKS_VER:-None})\"" >>"${TMP_PATH}/menu"
    echo "u \"$(TEXT "Local upload")\"" >>"${TMP_PATH}/menu"
    echo "b \"$(TEXT "Pre Release:") \Z4${PRERELEASE}\Zn\"" >>"${TMP_PATH}/menu"
    echo "e \"$(TEXT "Exit")\"" >>"${TMP_PATH}/menu"
    if [ -z "${1}" ]; then
      SILENT="0"
      DIALOG --title "$(TEXT "Update")" \
        --menu "$(TEXT "Manually uploading update*.zip,addons*.zip,modules*.zip,rp-lkms*.zip,rr-cks*.zip to /tmp/ will skip the download.")" 0 0 0 --file "${TMP_PATH}/menu" \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && return
    else
      SILENT="-1"
      echo "${1}" >"${TMP_PATH}/resp"
    fi
    case "$(cat ${TMP_PATH}/resp)" in
    a)
      F="$(ls ${PART3_PATH}/updateall*.zip ${TMP_PATH}/updateall*.zip 2>/dev/null | sort -V | tail -n 1)"
      [ -n "${F}" ] && [ -f "${F}.downloading" ] && rm -f "${F}" && rm -f "${F}.downloading" && F=""
      [ -z "${F}" ] && downloadExts "$(TEXT "All")" "${CUR_RR_VER:-None}" "https://github.com/RROrg/rr" "updateall" "${SILENT}"
      F="$(ls ${TMP_PATH}/updateall*.zip 2>/dev/null | sort -V | tail -n 1)"
      [ -n "${F}" ] && updateRR "${F}" "${SILENT}" && rm -f ${TMP_PATH}/updateall*.zip
      ;;
    r)
      F="$(ls ${PART3_PATH}/update*.zip ${TMP_PATH}/update*.zip 2>/dev/null | sort -V | tail -n 1)"
      [ -n "${F}" ] && [ -f "${F}.downloading" ] && rm -f "${F}" && rm -f "${F}.downloading" && F=""
      [ -z "${F}" ] && downloadExts "$(TEXT "RR")" "${CUR_RR_VER:-None}" "https://github.com/RROrg/rr" "update" "${SILENT}"
      F="$(ls ${TMP_PATH}/update*.zip 2>/dev/null | sort -V | tail -n 1)"
      [ -n "${F}" ] && updateRR "${F}" "${SILENT}" && rm -f ${TMP_PATH}/update*.zip
      ;;
    d)
      if [ -z "${DEBUG}" ]; then
        DIALOG --title "$(TEXT "Update")" \
          --msgbox "$(printf "$(TEXT "No longer supports update %s separately. Please choose to update All/RR")" "$(TEXT "Addons")")" 0 0
        continue
      fi
      F="$(ls ${PART3_PATH}/addons*.zip ${TMP_PATH}/addons*.zip 2>/dev/null | sort -V | tail -n 1)"
      [ -n "${F}" ] && [ -f "${F}.downloading" ] && rm -f "${F}" && rm -f "${F}.downloading" && F=""
      [ -z "${F}" ] && downloadExts "$(TEXT "Addons")" "${CUR_ADDONS_VER:-None}" "https://github.com/RROrg/rr-addons" "addons" "${SILENT}"
      F="$(ls ${TMP_PATH}/addons*.zip 2>/dev/null | sort -V | tail -n 1)"
      [ -n "${F}" ] && updateAddons "${F}" "${SILENT}" && rm -f ${TMP_PATH}/addons*.zip
      ;;
    m)
      if [ -z "${DEBUG}" ]; then
        DIALOG --title "$(TEXT "Update")" \
          --msgbox "$(printf "$(TEXT "No longer supports update %s separately. Please choose to update All/RR")" "$(TEXT "Modules")")" 0 0
        continue
      fi
      F="$(ls ${PART3_PATH}/modules*.zip ${TMP_PATH}/modules*.zip 2>/dev/null | sort -V | tail -n 1)"
      [ -n "${F}" ] && [ -f "${F}.downloading" ] && rm -f "${F}" && rm -f "${F}.downloading" && F=""
      [ -z "${F}" ] && downloadExts "$(TEXT "Modules")" "${CUR_MODULES_VER:-None}" "https://github.com/RROrg/rr-modules" "modules" "${SILENT}"
      F="$(ls ${TMP_PATH}/modules*.zip 2>/dev/null | sort -V | tail -n 1)"
      [ -n "${F}" ] && updateModules "${F}" "${SILENT}" && rm -f ${TMP_PATH}/modules*.zip
      ;;
    l)
      if [ -z "${DEBUG}" ]; then
        DIALOG --title "$(TEXT "Update")" \
          --msgbox "$(printf "$(TEXT "No longer supports update %s separately. Please choose to update All/RR")" "$(TEXT "LKMs")")" 0 0
        continue
      fi
      F="$(ls ${PART3_PATH}/rp-lkms*.zip ${TMP_PATH}/rp-lkms*.zip 2>/dev/null | sort -V | tail -n 1)"
      [ -n "${F}" ] && [ -f "${F}.downloading" ] && rm -f "${F}" && rm -f "${F}.downloading" && F=""
      [ -z "${F}" ] && downloadExts "$(TEXT "LKMs")" "${CUR_LKMS_VER:-None}" "https://github.com/RROrg/rr-lkms" "rp-lkms" "${SILENT}"
      F="$(ls ${TMP_PATH}/rp-lkms*.zip 2>/dev/null | sort -V | tail -n 1)"
      [ -n "${F}" ] && updateLKMs "${F}" "${SILENT}" && rm -f ${TMP_PATH}/rp-lkms*.zip
      ;;
    c)
      if [ -z "${DEBUG}" ]; then
        DIALOG --title "$(TEXT "Update")" \
          --msgbox "$(printf "$(TEXT "No longer supports update %s separately. Please choose to update All/RR")" "$(TEXT "CKs")")" 0 0
        continue
      fi
      F="$(ls ${PART3_PATH}/rr-cks*.zip ${TMP_PATH}/rr-cks*.zip 2>/dev/null | sort -V | tail -n 1)"
      [ -n "${F}" ] && [ -f "${F}.downloading" ] && rm -f "${F}" && rm -f "${F}.downloading" && F=""
      [ -z "${F}" ] && downloadExts "$(TEXT "CKs")" "${CUR_CKS_VER:-None}" "https://github.com/RROrg/rr-cks" "rr-cks" "${SILENT}"
      F="$(ls ${TMP_PATH}/rr-cks*.zip 2>/dev/null | sort -V | tail -n 1)"
      [ -n "${F}" ] && updateCKs "${F}" "${SILENT}" && rm -f ${TMP_PATH}/rr-cks*.zip
      ;;
    u)
      if ! tty 2>/dev/null | grep -q "/dev/pts" || [ -z "${SSH_TTY}" ]; then
        MSG=""
        MSG+="$(TEXT "This feature is only available when accessed via ssh (Requires a terminal that supports ZModem protocol).\n")"
        MSG+="$(TEXT "Manually uploading update*.zip,addons*.zip,modules*.zip,rp-lkms*.zip,rr-cks*.zip to /tmp/ will skip the download.")"
        DIALOG --title "$(TEXT "Update")" \
          --msgbox "${MSG}" 0 0
        return
      fi
      MSG=""
      MSG+="$(TEXT "Please keep the attachment name consistent with the attachment name on Github.\n")"
      MSG+="$(TEXT "Upload update*.zip will update RR.\n")"
      MSG+="$(TEXT "Upload addons*.zip will update Addons.\n")"
      MSG+="$(TEXT "Upload modules*.zip will update Modules.\n")"
      MSG+="$(TEXT "Upload rp-lkms*.zip will update LKMs.\n")"
      MSG+="$(TEXT "Upload rr-cks*.zip will update CKs.\n")"
      DIALOG --title "$(TEXT "Update")" \
        --msgbox "${MSG}" 0 0
      EXTS=(update*.zip addons*.zip modules*.zip rp-lkms*.zip rr-cks*.zip)
      TMP_UP_PATH="${TMP_PATH}/users"
      USER_FILE=""
      rm -rf "${TMP_UP_PATH}"
      mkdir -p "${TMP_UP_PATH}"
      pushd "${TMP_UP_PATH}"
      rz -be
      for F in $(ls -A 2>/dev/null); do
        for I in ${EXTS[@]}; do
          [[ "${F}" = ${I} ]] && USER_FILE="${F}"
        done
        break
      done
      popd
      if [ -z "${USER_FILE}" ]; then
        DIALOG --title "$(TEXT "Update")" \
          --msgbox "$(TEXT "Not a valid file, please try again!")" 0 0
      else
        if [[ "${USER_FILE}" = update*.zip ]]; then
          rm -f ${TMP_PATH}/update*.zip
          updateRR "${TMP_UP_PATH}/${USER_FILE}" "${SILENT}"
        elif [[ "${USER_FILE}" = addons*.zip ]]; then
          rm -f ${TMP_PATH}/addons*.zip
          updateAddons "${TMP_UP_PATH}/${USER_FILE}" "${SILENT}"
        elif [[ "${USER_FILE}" = modules*.zip ]]; then
          rm -f ${TMP_PATH}/modules*.zip
          updateModules "${TMP_UP_PATH}/${USER_FILE}" "${SILENT}"
        elif [[ "${USER_FILE}" = rp-lkms*.zip ]]; then
          rm -f ${TMP_PATH}/rp-lkms*.zip
          updateLKMs "${TMP_UP_PATH}/${USER_FILE}" "${SILENT}"
        elif [[ "${USER_FILE}" = rr-cks*.zip ]]; then
          rm -f ${TMP_PATH}/rr-cks*.zip
          updateCKs "${TMP_UP_PATH}/${USER_FILE}" "${SILENT}"
        else
          DIALOG --title "$(TEXT "Update")" \
            --msgbox "$(TEXT "Not a valid file, please try again!")" 0 0
        fi
        rm -f "${TMP_UP_PATH}/${USER_FILE}"
      fi
      ;;
    b)
      [ "${PRERELEASE}" = "false" ] && PRERELEASE='true' || PRERELEASE='false'
      writeConfigKey "prerelease" "${PRERELEASE}" "${USER_CONFIG_FILE}"
      NEXT="e"
      ;;
    e) return ;;
    esac
    [ -z "${1}" ] || return
  done
}

###############################################################################
function cleanCache() {
  if [ ! "${1}" = "-1" ]; then
    rm -rfv "${PART3_PATH}/dl/"* 2>&1 | DIALOG --title "$(TEXT "Main menu")" \
      --progressbox "$(TEXT "Cleaning cache ...")" 20 100
  else
    rm -rfv "${PART3_PATH}/dl/"*
  fi
  return 0
}

###############################################################################
function notepadMenu() {
  [ -d "${USER_UP_PATH}" ] || mkdir -p "${USER_UP_PATH}"
  [ -f "${USER_UP_PATH}/notepad" ] || echo "$(TEXT "This person is very lazy and hasn't written anything.")" >"${USER_UP_PATH}/notepad"
  DIALOG \
    --editbox "${USER_UP_PATH}/notepad" 0 0 2>"${TMP_PATH}/notepad"
  [ $? -ne 0 ] && return
  mv -f "${TMP_PATH}/notepad" "${USER_UP_PATH}/notepad"
  dos2unix "${USER_UP_PATH}/notepad"
}

###############################################################################
###############################################################################
if false && [ $(ps -ef | grep -v grep | grep -c "menu.sh") -gt 1 ]; then
  echo "$(TEXT "Another instance of the menu.sh is running.")"
  exit 1
fi
if [ $# -ge 1 ]; then
  $@
else
  # Main loop
  NEXT="m"
  [ -n "$(ls ${TMP_PATH}/pats/*.pat 2>/dev/null)" ] && NEXT="u"
  [ -f "${PART1_PATH}/.build" ] && NEXT="d"
  [ -n "${MODEL}" ] && NEXT="v"
  while true; do
    echo -n "" >"${TMP_PATH}/menu"
    echo "m \"$(TEXT "Choose a model")\"" >>"${TMP_PATH}/menu"
    if [ -n "${MODEL}" ]; then
      echo "n \"$(TEXT "Choose a version")\"" >>"${TMP_PATH}/menu"
    fi
    echo "u \"$(TEXT "Parse pat")\"" >>"${TMP_PATH}/menu"
    if [ -n "${PRODUCTVER}" ]; then
      KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${WORK_PATH}/platforms.yml")"
      KPRE="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kpre" "${WORK_PATH}/platforms.yml")"
      if [ -f "${CKS_PATH}/bzImage-${PLATFORM}-$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}.gz" ] &&
        [ -f "${CKS_PATH}/modules-${PLATFORM}-$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}.tgz" ]; then
        echo "s \"$(TEXT "Kernel:") \Z4${KERNEL}\Zn\"" >>"${TMP_PATH}/menu"
      fi
      echo "a \"$(TEXT "Addons menu")\"" >>"${TMP_PATH}/menu"
      echo "o \"$(TEXT "Modules menu")\"" >>"${TMP_PATH}/menu"
      echo "x \"$(TEXT "Cmdline menu")\"" >>"${TMP_PATH}/menu"
      echo "i \"$(TEXT "Synoinfo menu")\"" >>"${TMP_PATH}/menu"
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
    if [ 0$(du -sm ${PART3_PATH}/dl 2>/dev/null | awk '{printf $1}') -gt 1 ]; then
      echo "c \"$(TEXT "Clean disk cache")\"" >>"${TMP_PATH}/menu"
    fi
    echo "p \"$(TEXT "Update menu")\"" >>"${TMP_PATH}/menu"
    echo "t \"$(TEXT "Notepad")\"" >>"${TMP_PATH}/menu"
    echo "e \"$(TEXT "Exit")\"" >>"${TMP_PATH}/menu"

    DIALOG --title "$(TEXT "Main menu")" \
      --default-item ${NEXT} --menu "$(TEXT "Choose a option")" 0 0 0 --file "${TMP_PATH}/menu" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && break
    case $(cat "${TMP_PATH}/resp") in
    m)
      modelMenu
      NEXT="n"
      ;;
    n)
      productversMenu
      NEXT="d"
      ;;
    u)
      ParsePat
      NEXT="d"
      ;;
    s)
      DIALOG --title "$(TEXT "Main menu")" \
        --infobox "$(TEXT "Change ...")" 0 0
      [ ! "${KERNEL}" = "custom" ] && KERNEL='custom' || KERNEL='official'
      writeConfigKey "kernel" "${KERNEL}" "${USER_CONFIG_FILE}"
      if [ "${ODP}" = "true" ]; then
        ODP="false"
        writeConfigKey "odp" "${ODP}" "${USER_CONFIG_FILE}"
      fi
      if [ -n "${PLATFORM}" -a -n "${KVER}" ]; then
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        while read ID DESC; do
          writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
        done <<<$(getAllModules "${PLATFORM}" "$([ -n "${KPRE}" ] && echo "${KPRE}-")${KVER}")
      fi
      touch ${PART1_PATH}/.build

      NEXT="o"
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
      cleanCache
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
        echo -n "" >"${TMP_PATH}/menu"
        echo "p \"$(TEXT "Power off")\"" >>"${TMP_PATH}/menu"
        echo "r \"$(TEXT "Reboot")\"" >>"${TMP_PATH}/menu"
        echo "x \"$(TEXT "Reboot to RR")\"" >>"${TMP_PATH}/menu"
        echo "y \"$(TEXT "Reboot to Recovery")\"" >>"${TMP_PATH}/menu"
        echo "z \"$(TEXT "Reboot to Junior")\"" >>"${TMP_PATH}/menu"
        #if efibootmgr | grep -q "^Boot0000"; then
        echo "b \"$(TEXT "Reboot to BIOS")\"" >>"${TMP_PATH}/menu"
        #fi
        echo "s \"$(TEXT "Back to shell")\"" >>"${TMP_PATH}/menu"
        echo "e \"$(TEXT "Exit")\"" >>"${TMP_PATH}/menu"

        DIALOG --title "$(TEXT "Main menu")" \
          --default-item ${NEXT} --menu "$(TEXT "Choose a action")" 0 0 0 --file "${TMP_PATH}/menu" \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && break
        case "$(cat ${TMP_PATH}/resp)" in
        p)
          DIALOG --title "$(TEXT "Main menu")" \
            --infobox "$(TEXT "Power off")" 0 0
          poweroff
          exit 0
          ;;
        r)
          DIALOG --title "$(TEXT "Main menu")" \
            --infobox "$(TEXT "Reboot")" 0 0
          reboot
          exit 0
          ;;
        x)
          DIALOG --title "$(TEXT "Main menu")" \
            --infobox "$(TEXT "Reboot to RR")" 0 0
          rebootTo config
          exit 0
          ;;
        y)
          DIALOG --title "$(TEXT "Main menu")" \
            --infobox "$(TEXT "Reboot to Recovery")" 0 0
          rebootTo recovery
          exit 0
          ;;
        z)
          DIALOG --title "$(TEXT "Main menu")" \
            --infobox "$(TEXT "Reboot to Junior")" 0 0
          rebootTo junior
          exit 0
          ;;
        b)
          DIALOG --title "$(TEXT "Main menu")" \
            --infobox "$(TEXT "Reboot to BIOS")" 0 0
          #efibootmgr -n 0000 >/dev/null 2>&1
          #reboot
          rebootTo bios
          exit 0
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
  ${WORK_PATH}/init.sh
fi
