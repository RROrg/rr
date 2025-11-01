#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# shellcheck disable=SC2010,SC2034,SC2115,SC2120

[ -z "${WORK_PATH}" ] || [ ! -d "${WORK_PATH}/include" ] && WORK_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. "${WORK_PATH}/include/functions.sh"
. "${WORK_PATH}/include/addons.sh"
. "${WORK_PATH}/include/modules.sh"

[ -z "${LOADER_DISK}" ] && die "$(TEXT "Loader is not init!")"

# Disable the XON/XOFF flow control in the terminal
# stty -ixon

if [ $# -gt 0 ]; then
  DIALOG() {
    [ ! -t 0 ] && cat
    echo "$@"
    local ret=0
    for ((i = 1; i <= $#; i++)); do
      if [ "${!i}" = "--err" ]; then
        next=$((i + 1))
        printf "%s" "${!next}" >&2
      fi
      if [ "${!i}" = "--ret" ]; then
        next=$((i + 1))
        ret="${!next}"
      fi
    done
    return "${ret}"
  }
else
  DIALOG() {
    args=()
    skip_next=0
    for arg in "$@"; do
      if [ $skip_next -eq 1 ]; then
        skip_next=0
        continue
      fi
      if [ "$arg" = "--err" ]; then
        skip_next=1
        continue
      fi
      if [ "$arg" = "--ret" ]; then
        skip_next=1
        continue
      fi
      args+=("$arg")
    done
    if [ ! -t 0 ]; then
      cat | dialog --backtitle "$(backtitle)" --ignore --colors --aspect 50 "${args[@]}"
    else
      dialog --backtitle "$(backtitle)" --ignore --colors --aspect 50 "${args[@]}"
    fi
  }
fi

# lock
exec 304>"${TMP_PATH}/menu.lock"
flock -n 304 || {
  MSG="$(TEXT "The menu.sh instance is already running in another terminal. To avoid conflicts, please operate in one instance only.")"
  dialog --colors --aspect 50 --title "$(TEXT "Error")" --msgbox "${MSG}" 0 0
  exit 1
}
cleanup_lock() {
  flock -u 304
  rm -f "${TMP_PATH}/menu.lock"
}
trap 'cleanup_lock' EXIT INT TERM HUP

# Check partition 3 space, if < 2GiB is necessary clean cache folder
SPACELEFT=$(df -m "${PART3_PATH}" 2>/dev/null | awk 'NR==2 {print $4}')
CLEARCACHE=0
if [ ${SPACELEFT:-0} -lt 430 ]; then
  CLEARCACHE=1
fi

# Get actual IP
IP="$(getIP)"
echo "${IP}" | grep -q "^169\.254\." && IP=""

# Debug flag
# DEBUG=""

PLATFORM="$(readConfigKey "platform" "${USER_CONFIG_FILE}")"
MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
MODELID="$(readConfigKey "modelid" "${USER_CONFIG_FILE}")"
PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
SMALLNUM="$(readConfigKey "smallnum" "${USER_CONFIG_FILE}")"
DT="$(readConfigKey "dt" "${USER_CONFIG_FILE}")"
KVER="$(readConfigKey "kver" "${USER_CONFIG_FILE}")"
KPRE="$(readConfigKey "kpre" "${USER_CONFIG_FILE}")"
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
USBASINTERNAL="$(readConfigKey "usbasinternal" "${USER_CONFIG_FILE}")"
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
  BACKTITLE+="${RR_TITLE}${RR_RELEASE:+(${RR_RELEASE})}"
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
  DIALOG --title "$(TEXT "Model")" \
    --infobox "$(TEXT "Getting models ...")" 0 0

  rm -f "${TMP_PATH}/modellist"
  PS="$(readConfigEntriesArray "platforms" "${WORK_PATH}/platforms.yml" | sort)"
  MJ="$(python3 ${WORK_PATH}/include/functions.py getmodels -p "${PS[*]}")"

  if [ "${MJ:-"[]"}" = "[]" ]; then
    DIALOG --title "$(TEXT "Model")" \
      --msgbox "$(TEXT "Unable to connect to Synology website, Please check the network and try again, or use 'Parse Pat'!")" 0 0
    return 1
  fi

  echo "${MJ}" | jq -r '.[] | "\(.name) \(.arch)"' >"${TMP_PATH}/modellist"

  RESTRICT=1
  while true; do
    rm -f "${TMP_PATH}/menu"
    FLGNEX=0
    IGPU1L=(apollolake geminilake epyc7002 geminilakenk r1000nk v1000nk)
    IGPU2L=(epyc7002 geminilakenk r1000nk v1000nk)
    KVER5L=(epyc7002 geminilakenk r1000nk v1000nk)
    IGPUID="$(lspci -nd ::300 2>/dev/null | grep "8086" | cut -d' ' -f3 | sed 's/://g')"
    NVMEMS=(DS918+ RS1619xs+ DS419+ DS1019+ DS719+ DS1621xs+)
    NVMEMD=$(find /sys/devices -type d -name nvme | awk -F'/' '{print NF}' | sort -n | tail -n1)
    if [ -n "${IGPUID}" ]; then grep -iq "${IGPUID}" ${WORK_PATH}/i915ids && hasiGPU=1 || hasiGPU=2; else hasiGPU=0; fi
    if [ ${NVMEMD:-0} -lt 6 ]; then hasNVME=0; elif [ ${NVMEMD:-0} -eq 6 ]; then hasNVME=1; else hasNVME=2; fi
    [ "$(lspci -d ::104 2>/dev/null | wc -l)" -gt 0 ] || [ "$(lspci -d ::107 2>/dev/null | wc -l)" -gt 0 ] && hasHBA=1 || hasHBA=0
    while read -r M A; do
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
      unset DT G N H
      [ "$(readConfigKey "platforms.${A}.dt" "${WORK_PATH}/platforms.yml")" = "true" ] && DT="DT" || DT=""
      [ -z "${G}" ] && [ ${hasiGPU} -eq 1 ] && echo "${IGPU1L[@]}" | grep -wq "${A}" && G="G"
      [ -z "${G}" ] && [ ${hasiGPU} -eq 2 ] && echo "${IGPU2L[@]}" | grep -wq "${A}" && G="G"
      [ -z "${N}" ] && [ ${hasNVME} -ne 0 ] && [ "${DT}" = "DT" ] && N="N"
      [ -z "${N}" ] && [ ${hasNVME} -eq 2 ] && echo "${NVMEMS[@]}" | grep -wq "${M}" && N="N"
      [ -z "${H}" ] && [ ${hasHBA} -eq 1 ] && [ ! "${DT}" = "DT" ] && H="H"
      [ -z "${H}" ] && [ ${hasHBA} -eq 1 ] && echo "${KVER5L[@]}" | grep -wq "${A}" && H="H"
      [ ${COMPATIBLE} -eq 1 ] && printf "%s \"\Zb%-14s  %-2s  %-3s\Zn\" " "${M}" "${A}" "${DT}" "${G}${N}${H}" >>"${TMP_PATH}/menu"
    done <"${TMP_PATH}/modellist"
    [ ${FLGNEX} -eq 1 ] && echo "f \"\Z1$(TEXT "Disable flags restriction")\Zn\"" >>"${TMP_PATH}/menu"
    MSG="$(TEXT "Choose the model")"
    MSG+="\n\Z1$(TEXT "DT: Disk identification method is device tree")\Zn"
    MSG+="\n\Z1$(TEXT "G: Support iGPU; N: Support NVMe; H: Support HBA")\Zn"

    VAL=""
    [ -n "${1}" ] && grep -qw "${1}" "${TMP_PATH}/menu" && VAL="${1}"
    DIALOG --err "${VAL}" --title "$(TEXT "Model")" \
      --menu "${MSG}" 0 0 20 --file "${TMP_PATH}/menu" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return 0
    resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
    [ -z "${resp}" ] && return 1
    if [ "${resp}" = "f" ]; then
      RESTRICT=0
      continue
    fi
    respM="${resp}"
    break
  done

  respP="$(grep -w "${respM}" "${TMP_PATH}/modellist" 2>/dev/null | awk '{print $2}' | head -1)"
  rm -f "${TMP_PATH}/modellist"
  [ -z "${respP}" ] && return 1

  reconfiguringM "${respM}" "${respP}"
  return 0
}

###############################################################################
function reconfiguringM() {
  respM="${1}"
  respP="${2}"
  local BASEMODEL="${MODEL}"
  local BASEPLATFORM="${PLATFORM}"

  MODEL="${respM}"
  writeConfigKey "model" "${MODEL}" "${USER_CONFIG_FILE}"
  PLATFORM="${respP}"
  writeConfigKey "platform" "${PLATFORM}" "${USER_CONFIG_FILE}"

  if [ "${MODEL}" != "${BASEMODEL}" ]; then
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
    MACS="$(generateMacAddress "${MODEL}" ${NETIF_NUM})"
    for I in $(seq 1 ${NETIF_NUM}); do
      eval MAC${I}="$(echo ${MACS} | cut -d' ' -f${I})"
      writeConfigKey "mac${I}" "$(echo ${MACS} | cut -d' ' -f${I})" "${USER_CONFIG_FILE}"
    done
    writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
    writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
    # Remove old files
    rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}" >/dev/null 2>&1 || true
    rm -f "${PART1_PATH}/grub_cksum.syno" "${PART1_PATH}/GRUB_VER" "${PART2_PATH}/"* >/dev/null 2>&1 || true
    rm -f "${PART3_PATH}/dl/${MODEL}-${PRODUCTVER}.pat" >/dev/null 2>&1 || true
  else
    if [ -z "${SN}" ]; then
      SN="$(generateSerial "${MODEL}")"
      writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
    fi
    if [ -z "${MAC1}" ]; then
      NETIF_NUM=2
      MACS="$(generateMacAddress "${MODEL}" ${NETIF_NUM})"
      for I in $(seq 1 ${NETIF_NUM}); do
        eval MAC${I}="$(echo ${MACS} | cut -d' ' -f${I})"
        writeConfigKey "mac${I}" "$(echo ${MACS} | cut -d' ' -f${I})" "${USER_CONFIG_FILE}"
      done
    fi
  fi
  touch "${PART1_PATH}/.build"
  return 0
}

###############################################################################
# Shows available buildnumbers from a model to user choose one
function productversMenu() {
  ITEMS="$(readConfigEntriesArray "platforms.${PLATFORM}.productvers" "${WORK_PATH}/platforms.yml" | sort -r)"

  VAL=""
  [ -n "$(echo "${1}" | cut -d'.' -f1,2)" ] && echo "${ITEMS}" | grep -qw "$(echo "${1}" | cut -d'.' -f1,2)" && VAL="$(echo "${1}" | cut -d'.' -f1,2)"
  DIALOG --err "${VAL}" --title "$(TEXT "Product Version")" \
    --no-items --menu "$(TEXT "Choose a product version")" 0 0 0 ${ITEMS} \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 0
  resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
  [ -z "${resp}" ] && return 1

  if [ "${PRODUCTVER}" = "${resp}" ]; then
    MSG="$(printf "$(TEXT "The current version has been set to %s. Do you want to reset the version?")" "${PRODUCTVER}")"
    DIALOG --ret 0 --title "$(TEXT "Product Version")" \
      --yesno "${MSG}" 0 0
    [ $? -ne 0 ] && return 0
  fi

  selver="${resp}"
  urlver=""
  paturl=""
  patsum=""

  while true; do
    # get online pat data
    DIALOG --title "$(TEXT "Product Version")" \
      --infobox "$(TEXT "Get pat data ...")" 0 0

    PJ="$(python3 ${WORK_PATH}/include/functions.py getpats4mv -m "${MODEL}" -v "${selver}")"
    if [ "${PJ:-"{}"}" = "{}" ]; then
      MSG="$(TEXT "Unable to connect to Synology website, Please check the network and try again, or use 'Parse Pat'!")"
      DIALOG --ret 1 --title "$(TEXT "Addons")" \
        --yes-label "$(TEXT "Retry")" --yesno "${MSG}" 0 0
      [ $? -eq 0 ] && continue # yes-button
      return 1
    else
      PVS="$(echo "${PJ}" | jq -r 'keys | sort | reverse | join(" ")')"

      VAL=""
      [ -n "${1}" ] && echo "${PVS}" | tr ' ' '\n' | grep -qw "${1}" && VAL="$(echo "${PVS}" | tr ' ' '\n' | grep -w "${1}" | head -1)"
      DIALOG --err "${VAL}" --title "$(TEXT "Product Version")" \
        --no-items --menu "$(TEXT "Choose a pat version")" 0 0 0 ${PVS} \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && return 1
      resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
      [ -z "${resp}" ] && return 1
      PV="${resp}"
      paturl=$(echo "${PJ}" | jq -r ".\"${PV}\".url")
      patsum=$(echo "${PJ}" | jq -r ".\"${PV}\".sum")
      urlver="$(echo "${PV}" | cut -d'.' -f1,2)"
    fi

    MSG=""
    MSG+="$(TEXT "Please confirm or modify the URL and md5sum to you need (32 '0's will skip the md5 check).")"
    if [ ! "${selver}" = "${urlver}" ]; then
      MSG+="$(printf "$(TEXT "Note: There is no version %s and automatically returns to version %s.")" "${selver}" "${urlver}")"
      selver=${urlver}
    fi
    VAL="${paturl}"$'\n'"${patsum}"
    [ -n "${2}" ] && [ -n "${3}" ] && VAL="${2}"$'\n'"${3}"
    DIALOG --err "${VAL}" --title "$(TEXT "Product Version")" \
      --extra-button --extra-label "$(TEXT "Retry")" \
      --form "${MSG}" 10 110 2 "URL" 1 1 "${paturl}" 1 5 100 0 "MD5" 2 1 "${patsum}" 2 5 100 0 \
      2>"${TMP_PATH}/resp"
    RET=$?
    case ${RET} in
    0)
      # ok-button
      paturl="$(sed -n '1p' "${TMP_PATH}/resp" 2>/dev/null)"
      patsum="$(sed -n '2p' "${TMP_PATH}/resp" 2>/dev/null)"
      break
      ;;
    3)
      # extra-button
      continue
      ;;
    1)
      # cancel-button
      return 0
      ;;
    255)
      # ESC
      return 0
      ;;
    esac
  done

  [ "${paturl:0:1}" = "#" ] && patsum="${paturl}"
  [ -z "${paturl}" ] || [ -z "${patsum}" ] && return 1

  DIALOG --title "$(TEXT "Product Version")" \
    --infobox "$(TEXT "Reconfiguring Synoinfo, Addons and Modules ...")" 0 0
  reconfiguringV "${selver}" "${paturl}" "${patsum}"
  return 0
}

###############################################################################
function reconfiguringV() {
  selver="${1}"
  paturl="${2}"
  patsum="${3}"
  local BASEPATURL BASEPATSUM
  BASEPATURL="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
  BASEPATSUM="$(readConfigKey "patsum" "${USER_CONFIG_FILE}")"

  PRODUCTVER=${selver}
  writeConfigKey "productver" "${PRODUCTVER}" "${USER_CONFIG_FILE}"
  if [ "${BASEPATURL}" != "${paturl}" ] || [ "${BASEPATSUM}" != "${patsum}" ]; then
    BUILDNUM=""
    SMALLNUM=""
    writeConfigKey "buildnum" "${BUILDNUM}" "${USER_CONFIG_FILE}"
    writeConfigKey "smallnum" "${SMALLNUM}" "${USER_CONFIG_FILE}"
  fi
  writeConfigKey "paturl" "${paturl}" "${USER_CONFIG_FILE}"
  writeConfigKey "patsum" "${patsum}" "${USER_CONFIG_FILE}"
  DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${WORK_PATH}/platforms.yml")"
  KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${WORK_PATH}/platforms.yml")"
  KPRE="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kpre" "${WORK_PATH}/platforms.yml")"
  writeConfigKey "dt" "${DT}" "${USER_CONFIG_FILE}"
  writeConfigKey "kver" "${KVER}" "${USER_CONFIG_FILE}"
  writeConfigKey "kpre" "${KPRE}" "${USER_CONFIG_FILE}"
  # Check kernel
  if [ -f "${CKS_PATH}/bzImage-${PLATFORM}-${KPRE:+${KPRE}-}${KVER}.gz" ] &&
    [ -f "${CKS_PATH}/modules-${PLATFORM}-${KPRE:+${KPRE}-}${KVER}.tgz" ]; then
    :
  else
    KERNEL='official'
    writeConfigKey "kernel" "${KERNEL}" "${USER_CONFIG_FILE}"
  fi
  # Check usbasinternal
  if [ "true" = "${DT}" ]; then
    USBASINTERNAL='false'
    writeConfigKey "usbasinternal" "${USBASINTERNAL}" "${USER_CONFIG_FILE}"
  fi

  # Delete synoinfo and reload model/build synoinfo
  writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
  while IFS=': ' read -r KEY VALUE; do
    writeConfigKey "synoinfo.\"${KEY}\"" "${VALUE}" "${USER_CONFIG_FILE}"
  done <<<"$(readConfigMap "platforms.${PLATFORM}.synoinfo" "${WORK_PATH}/platforms.yml")"

  # Check addons
  while IFS=': ' read -r ADDON PARAM; do
    [ -z "${ADDON}" ] && continue
    if ! checkAddonExist "${ADDON}" "${PLATFORM}" "${KPRE:+${KPRE}-}${KVER}"; then
      deleteConfigKey "addons.\"${ADDON}\"" "${USER_CONFIG_FILE}"
    fi
  done <<<"$(readConfigMap "addons" "${USER_CONFIG_FILE}")"

  # Rewrite modules
  writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
  mergeConfigModules "$(getAllModules "${PLATFORM}" "${KPRE:+${KPRE}-}${KVER}" | awk '{print $1}')" "${USER_CONFIG_FILE}"

  if [ "${BASEPATURL}" != "${paturl}" ] || [ "${BASEPATSUM}" != "${patsum}" ]; then
    # Remove old files
    rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}" >/dev/null 2>&1 || true
    rm -f "${PART1_PATH}/grub_cksum.syno" "${PART1_PATH}/GRUB_VER" "${PART2_PATH}/"* >/dev/null 2>&1 || true
    rm -f "${PART3_PATH}/dl/${MODEL}-${PRODUCTVER}.pat" >/dev/null 2>&1 || true
  fi

  touch "${PART1_PATH}/.build"
}

###############################################################################
function setConfigFromDSM() {
  DSM_ROOT="${1}"
  if [ ! -f "${DSM_ROOT}/GRUB_VER" ] || [ ! -f "${DSM_ROOT}/VERSION" ]; then
    echo -e "$(TEXT "DSM Invalid, try again!")" >"${LOG_FILE}"
    return 1
  fi

  PLATFORMTMP="$(_get_conf_kv "${DSM_ROOT}/GRUB_VER" "PLATFORM")"
  MODELTMP="$(_get_conf_kv "${DSM_ROOT}/GRUB_VER" "MODEL")"
  majorversion="$(_get_conf_kv "${DSM_ROOT}/VERSION" "majorversion")"
  minorversion="$(_get_conf_kv "${DSM_ROOT}/VERSION" "minorversion")"
  buildnumber="$(_get_conf_kv "${DSM_ROOT}/VERSION" "buildnumber")"
  smallfixnumber="$(_get_conf_kv "${DSM_ROOT}/VERSION" "smallfixnumber")"
  if [ -z "${PLATFORMTMP}" ] || [ -z "${MODELTMP}" ] || [ -z "${majorversion}" ] || [ -z "${minorversion}" ]; then
    echo -e "$(TEXT "DSM Invalid, try again!")" >"${LOG_FILE}"
    return 1
  fi
  PS="$(readConfigEntriesArray "platforms" "${WORK_PATH}/platforms.yml" | sort)"
  VS="$(readConfigEntriesArray "platforms.${PLATFORMTMP,,}.productvers" "${WORK_PATH}/platforms.yml" | sort -r)"
  if arrayExistItem "${PLATFORMTMP,,}" ${PS} && arrayExistItem "${majorversion}.${minorversion}" ${VS}; then
    PLATFORM="${PLATFORMTMP,,}"
    MODEL="$(echo "${MODELTMP}" | sed 's/d$/D/; s/rp$/RP/; s/rp+/RP+/')"
    MODELID="${MODELTMP}"
    PRODUCTVER="${majorversion}.${minorversion}"
    BUILDNUM="${buildnumber}"
    SMALLNUM="${smallfixnumber}"
  else
    printf "$(TEXT "Currently, %s is not supported.")" "${MODELTMP}-${majorversion}.${minorversion}" >"${LOG_FILE}"
    return 1
  fi

  echo "$(TEXT "Reconfiguring Synoinfo, Addons and Modules ...")"

  writeConfigKey "platform" "${PLATFORM}" "${USER_CONFIG_FILE}"
  writeConfigKey "model" "${MODEL}" "${USER_CONFIG_FILE}"
  writeConfigKey "modelid" "${MODELID}" "${USER_CONFIG_FILE}"
  SN="$(generateSerial "${MODEL}")"
  writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
  NETIF_NUM=2
  MACS="$(generateMacAddress "${MODEL}" ${NETIF_NUM})"
  for I in $(seq 1 ${NETIF_NUM}); do
    eval MAC${I}="$(echo "${MACS}" | cut -d' ' -f${I})"
    writeConfigKey "mac${I}" "$(echo "${MACS}" | cut -d' ' -f${I})" "${USER_CONFIG_FILE}"
  done

  writeConfigKey "productver" "${PRODUCTVER}" "${USER_CONFIG_FILE}"
  writeConfigKey "buildnum" "${BUILDNUM}" "${USER_CONFIG_FILE}"
  writeConfigKey "smallnum" "${SMALLNUM}" "${USER_CONFIG_FILE}"
  writeConfigKey "paturl" "#" "${USER_CONFIG_FILE}"
  writeConfigKey "patsum" "#" "${USER_CONFIG_FILE}"

  DT="$(readConfigKey "platforms.${PLATFORM}.dt" "${WORK_PATH}/platforms.yml")"
  KVER="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kver" "${WORK_PATH}/platforms.yml")"
  KPRE="$(readConfigKey "platforms.${PLATFORM}.productvers.\"${PRODUCTVER}\".kpre" "${WORK_PATH}/platforms.yml")"
  writeConfigKey "dt" "${DT}" "${USER_CONFIG_FILE}"
  writeConfigKey "kver" "${KVER}" "${USER_CONFIG_FILE}"
  writeConfigKey "kpre" "${KPRE}" "${USER_CONFIG_FILE}"
  # Check kernel
  if [ -f "${CKS_PATH}/bzImage-${PLATFORM}-${KPRE:+${KPRE}-}${KVER}.gz" ] &&
    [ -f "${CKS_PATH}/modules-${PLATFORM}-${KPRE:+${KPRE}-}${KVER}.tgz" ]; then
    :
  else
    KERNEL='official'
    writeConfigKey "kernel" "${KERNEL}" "${USER_CONFIG_FILE}"
  fi
  # Check usbasinternal
  if [ "true" = "${DT}" ]; then
    USBASINTERNAL='false'
    writeConfigKey "usbasinternal" "${USBASINTERNAL}" "${USER_CONFIG_FILE}"
  fi
  # Delete synoinfo and reload model/build synoinfo
  writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
  while IFS=': ' read -r KEY VALUE; do
    writeConfigKey "synoinfo.\"${KEY}\"" "${VALUE}" "${USER_CONFIG_FILE}"
  done <<<"$(readConfigMap "platforms.${PLATFORM}.synoinfo" "${WORK_PATH}/platforms.yml")"

  # Check addons
  while IFS=': ' read -r ADDON PARAM; do
    [ -z "${ADDON}" ] && continue
    if ! checkAddonExist "${ADDON}" "${PLATFORM}" "${KPRE:+${KPRE}-}${KVER}"; then
      deleteConfigKey "addons.\"${ADDON}\"" "${USER_CONFIG_FILE}"
    fi
  done <<<"$(readConfigMap "addons" "${USER_CONFIG_FILE}")"

  # Rebuild modules
  writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
  mergeConfigModules "$(getAllModules "${PLATFORM}" "${KPRE:+${KPRE}-}${KVER}" | awk '{print $1}')" "${USER_CONFIG_FILE}"
  touch "${PART1_PATH}/.build"
  return 0
}

###############################################################################
# Parse Pat
function ParsePat() {
  if [ -n "${MODEL}" ] && [ -n "${PRODUCTVER}" ]; then
    MSG="$(printf "$(TEXT "You have selected the %s and %s.\n'Parse Pat' will overwrite the previous selection.\nDo you want to continue?")" "${MODEL}" "${PRODUCTVER}")"
    DIALOG --ret 0 --title "$(TEXT "Parse Pat")" \
      --yesno "${MSG}" 0 0
    [ $? -ne 0 ] && return 1
  fi

  mkdir -p "${TMP_PATH}/pats"
  ITEMS="$(ls ${TMP_PATH}/pats/*.pat 2>/dev/null)"
  if [ -z "${ITEMS}" ]; then
    MSG="$(TEXT "No pat file found in /tmp/pats/ folder!\nPlease upload the pat file to /tmp/pats/ folder via DUFS and re-enter this option.")"
    DIALOG --title "$(TEXT "Update")" \
      --msgbox "${MSG}" 0 0
    return 1
  fi

  DIALOG --title "$(TEXT "Parse Pat")" \
    --no-items --menu "$(TEXT "Choose a pat file")" 0 0 0 ${ITEMS} \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
  [ -z "${resp}" ] && return 1
  PAT_PATH="${resp}"
  if [ ! -f "${PAT_PATH}" ]; then
    DIALOG --title "$(TEXT "Parse Pat")" \
      --msgbox "$(TEXT "pat Invalid, try again!")" 0 0
    return 1
  fi

  while true; do
    rm -f "${LOG_FILE}"
    printf "$(TEXT "Parse %s ...\n")" "$(basename "${PAT_PATH}")"
    extractPatFiles "${PAT_PATH}" "${UNTAR_PAT_PATH}"
    if [ $? -ne 0 ]; then
      rm -rf "${UNTAR_PAT_PATH}"
      break
    fi

    mkdir -p "${PART3_PATH}/dl"
    # Check disk space left
    SPACELEFT=$(df -m "${PART3_PATH}" 2>/dev/null | awk 'NR==2 {print $4}')
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
    writeConfigKey "patsum" "#PARSEPAT" "${USER_CONFIG_FILE}"
    copyDSMFiles "${UNTAR_PAT_PATH}"

    touch "${PART1_PATH}/.build"
    rm -rf "${UNTAR_PAT_PATH}"
    rm -f "${LOG_FILE}"
    echo "$(TEXT "Ready!")"
    sleep 3
    break
  done 2>&1 | DIALOG --title "$(TEXT "Parse Pat")" \
    --progressbox "$(TEXT "Making ...")" 20 100

  if [ -f "${LOG_FILE}" ]; then
    DIALOG --title "$(TEXT "Parse Pat")" \
      --msgbox "$(cat "${LOG_FILE}")" 0 0
    rm -f "${LOG_FILE}"
    return 1
  else
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
    USBASINTERNAL="$(readConfigKey "usbasinternal" "${USER_CONFIG_FILE}")"
    SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"
    MAC1="$(readConfigKey "mac1" "${USER_CONFIG_FILE}")"
    MAC2="$(readConfigKey "mac2" "${USER_CONFIG_FILE}")"
    return 0
  fi
}

###############################################################################
# Manage addons
function addonMenu() {
  NEXT="a"
  while true; do
    unset ADDONS
    declare -A ADDONS
    while IFS=': ' read -r KEY VALUE; do
      [ -n "${KEY}" ] && ADDONS["${KEY}"]="${VALUE}"
    done <<<"$(readConfigMap "addons" "${USER_CONFIG_FILE}")"
    rm -f "${TMP_PATH}/menu"
    {
      echo "a \"$(TEXT "Add an addon")\""
      echo "d \"$(TEXT "Delete addons")\""
      echo "s \"$(TEXT "Show all addons")\""
      echo "u \"$(TEXT "Upload a external addon")\""
      echo "e \"$(TEXT "Exit")\""
    } >"${TMP_PATH}/menu"
    DIALOG --title "$(TEXT "Addons")" \
      --default-item ${NEXT} \
      --menu "$(TEXT "Choose a option")" 0 0 0 --file "${TMP_PATH}/menu" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return 1
    case "$(cat "${TMP_PATH}/resp" 2>/dev/null)" in
    a)
      rm -f "${TMP_PATH}/menu"
      while read -r ADDON DESC; do
        arrayExistItem "${ADDON}" "${!ADDONS[@]}" && continue # Check if addon has already been added
        echo "${ADDON} ${DESC}" >>"${TMP_PATH}/menu"
      done <<<"$(availableAddons "${PLATFORM}" "${KPRE:+${KPRE}-}${KVER}")"
      if [ ! -f "${TMP_PATH}/menu" ]; then
        DIALOG --title "$(TEXT "Addons")" \
          --msgbox "$(TEXT "No available addons to add")" 0 0
        NEXT="e"
        continue
      fi
      DIALOG --title "$(TEXT "Addons")" \
        --menu "$(TEXT "Select an addon")" 0 0 25 --file "${TMP_PATH}/menu" \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && continue
      resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
      [ -z "${resp}" ] && continue
      ADDON="${resp}"
      if [ "$(readAddonKey "${ADDON}" "params")" = "true" ]; then
        DIALOG --title "$(TEXT "Addons")" \
          --inputbox "$(TEXT "Type a optional params to addon")" 0 70 \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
        # [ -z "${resp}" ] && continue  # Addons params can be empty
        VALUE="${resp}"
      else
        VALUE=""
      fi
      ADDONS[${ADDON}]="${VALUE}"
      writeConfigKey "addons.\"${ADDON}\"" "${VALUE}" "${USER_CONFIG_FILE}"
      touch "${PART1_PATH}/.build"
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
      resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
      [ -z "${resp}" ] && continue
      ADDON="${resp}"
      for I in ${ADDON}; do
        unset "ADDONS[${I}]"
        deleteConfigKey "addons.\"${I}\"" "${USER_CONFIG_FILE}"
      done
      touch "${PART1_PATH}/.build"
      ;;
    s)
      MSG="$(TEXT "Name with color \"\Z4blue\Zn\" have been added, with color \"\Z1red\Zn\" are not added.\n")"
      MSG+="\n"
      while read -r ADDON DESC; do
        if arrayExistItem "${ADDON}" "${!ADDONS[@]}"; then
          MSG+="\Z4${ADDON}:\Zn \Z5${DESC}\Zn\n"
        else
          MSG+="\Z1${ADDON}:\Z1 \Z5${DESC}\Zn\n"
        fi
      done <<<"$(availableAddons "${PLATFORM}" "${KPRE:+${KPRE}-}${KVER}")"
      DIALOG --title "$(TEXT "Addons")" \
        --msgbox "${MSG}" 0 0
      ;;
    u)
      if ! tty 2>/dev/null | grep -q "/dev/pts"; then #if ! tty 2>/dev/null | grep -q "/dev/pts" || [ -z "${SSH_TTY}" ]; then
        MSG="$(TEXT "This feature is only available when accessed via ssh (Requires a terminal that supports ZModem protocol).\n")"
        DIALOG --title "$(TEXT "Addons")" \
          --msgbox "${MSG}" 0 0
        continue
      fi
      DIALOG --title "$(TEXT "Addons")" \
        --msgbox "$(TEXT "Please upload the *.addon file.")" 0 0
      TMP_UP_PATH="${TMP_PATH}/users"
      rm -rf "${TMP_UP_PATH}"
      mkdir -p "${TMP_UP_PATH}"
      (cd "${TMP_UP_PATH}" && rz -be) || true
      USER_FILE="$(find "${TMP_UP_PATH}" -type f | head -1)"
      if [ -z "${USER_FILE}" ]; then
        DIALOG --title "$(TEXT "Addons")" \
          --msgbox "$(TEXT "Not a valid file, please try again!")" 0 0
      else
        if [ -d "${ADDONS_PATH}/$(basename "${USER_FILE}" .addon)" ]; then
          DIALOG --title "$(TEXT "Addons")" \
            --yesno "$(TEXT "The addon already exists. Do you want to overwrite it?")" 0 0
          RET=$?
          if [ ${RET} -ne 0 ]; then
            rm -rf "${TMP_UP_PATH}"
            return 1
          fi
        fi
        ADDON="$(untarAddon "${USER_FILE}")"
        rm -rf "${TMP_UP_PATH}"
        if [ -n "${ADDON}" ]; then
          [ -f "${ADDONS_PATH}/VERSION" ] && rm -f "${ADDONS_PATH}/VERSION"
          DIALOG --title "$(TEXT "Addons")" \
            --msgbox "$(printf "$(TEXT "Addon '%s' added to loader, Please enable it in 'Add an addon' menu.")" "${ADDON}")" 0 0
          touch "${PART1_PATH}/.build"
        else
          DIALOG --title "$(TEXT "Addons")" \
            --msgbox "$(TEXT "File format not recognized!")" 0 0
        fi
      fi
      ;;
    e)
      return 0
      ;;
    esac
  done
}

###############################################################################
function moduleMenu() {
  NEXT="c"
  # loop menu
  while true; do
    rm -f "${TMP_PATH}/menu"
    {
      echo "s \"$(TEXT "Show/Select modules")\""
      echo "l \"$(TEXT "Select loaded modules")\""
      echo "u \"$(TEXT "Upload a external module")\""
      echo "i \"$(TEXT "Deselect i915 with dependencies")\""
      echo "p \"$(TEXT "Priority use of official drivers:") \Z4${ODP}\Zn\""
      echo "f \"$(TEXT "Edit modules that need to be copied to DSM")\""
      echo "b \"$(TEXT "modprobe blacklist")\""
      echo "e \"$(TEXT "Exit")\""
    } >"${TMP_PATH}/menu"
    DIALOG --title "$(TEXT "Modules")" \
      --default-item ${NEXT} --menu "$(TEXT "Choose a option")" 0 0 0 --file "${TMP_PATH}/menu" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break
    case "$(cat "${TMP_PATH}/resp" 2>/dev/null)" in
    s)
      while true; do
        DIALOG --title "$(TEXT "Modules")" \
          --infobox "$(TEXT "Reading modules ...")" 0 0
        ALLMODULES=$(getAllModules "${PLATFORM}" "${KPRE:+${KPRE}-}${KVER}")
        unset USERMODULES
        declare -A USERMODULES
        while IFS=': ' read -r KEY VALUE; do
          [ -n "${KEY}" ] && USERMODULES["${KEY}"]="${VALUE}"
        done <<<"$(readConfigMap "modules" "${USER_CONFIG_FILE}")"
        rm -f "${TMP_PATH}/opts"
        while read -r ID DESC; do
          arrayExistItem "${ID}" "${!USERMODULES[@]}" && ACT="on" || ACT="off"
          echo "${ID} ${DESC} ${ACT}" >>"${TMP_PATH}/opts"
        done <<<${ALLMODULES}
        DIALOG --title "$(TEXT "Modules")" \
          --extra-button --extra-label "$(TEXT "Select all")" \
          --help-button --help-label "$(TEXT "Deselect all")" \
          --checklist "$(TEXT "Select modules to include")" 0 0 0 --file "${TMP_PATH}/opts" \
          2>"${TMP_PATH}/resp"
        RET=$?
        case ${RET} in
        0)
          # ok-button
          writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
          mergeConfigModules "$(cat "${TMP_PATH}/resp" 2>/dev/null)" "${USER_CONFIG_FILE}"
          touch "${PART1_PATH}/.build"
          break
          ;;
        3)
          # extra-button
          writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
          mergeConfigModules "$(echo "${ALLMODULES}" | awk '{print $1}')" "${USER_CONFIG_FILE}"
          touch "${PART1_PATH}/.build"
          ;;
        2)
          # help-button
          writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
          touch "${PART1_PATH}/.build"
          ;;
        1)
          # cancel-button
          break
          ;;
        255)
          # ESC
          break
          ;;
        esac
      done
      ;;
    l)
      DIALOG --title "$(TEXT "Modules")" \
        --infobox "$(TEXT "Selecting loaded modules")" 0 0
      writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
      while read -r J; do
        writeConfigKey "modules.\"${J}\"" "" "${USER_CONFIG_FILE}"
      done <<<"$(getLoadedModules "${PLATFORM}" "${KPRE:+${KPRE}-}${KVER}")"
      touch "${PART1_PATH}/.build"
      ;;
    u)
      if ! tty 2>/dev/null | grep -q "/dev/pts"; then #if ! tty 2>/dev/null | grep -q "/dev/pts" || [ -z "${SSH_TTY}" ]; then
        MSG=""
        MSG+="$(TEXT "This feature is only available when accessed via ssh (Requires a terminal that supports ZModem protocol).")"
        DIALOG --title "$(TEXT "Modules")" \
          --msgbox "${MSG}" 0 0
        return 1
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
      TMP_UP_PATH="${TMP_PATH}/users"
      rm -rf "${TMP_UP_PATH}"
      mkdir -p "${TMP_UP_PATH}"
      (cd "${TMP_UP_PATH}" && rz -be) || true
      USER_FILE="$(find "${TMP_UP_PATH}" -type f | head -1)"
      if [ -n "${USER_FILE}" ] && [ "${USER_FILE##*.}" = "ko" ]; then
        addToModules "${PLATFORM}" "${KPRE:+${KPRE}-}${KVER}" "${USER_FILE}"
        [ -f "${MODULES_PATH}/VERSION" ] && rm -f "${MODULES_PATH}/VERSION"
        DIALOG --title "$(TEXT "Modules")" \
          --msgbox "$(printf "$(TEXT "Module '%s' added to %s-%s")" "$(basename "${USER_FILE}" .ko)" "${PLATFORM}" "${KPRE:+${KPRE}-}${KVER}")" 0 0
        rm -rf "${TMP_UP_PATH}"
        touch "${PART1_PATH}/.build"
      else
        DIALOG --title "$(TEXT "Modules")" \
          --msgbox "$(TEXT "Not a valid file, please try again!")" 0 0
        rm -rf "${TMP_UP_PATH}"
      fi
      ;;
    i)
      DEPS="$(getdepends "${PLATFORM}" "${KPRE:+${KPRE}-}${KVER}" i915)"
      DELS=()
      while IFS=': ' read -r KEY VALUE; do
        [ -z "${KEY}" ] && continue
        if echo "${DEPS}" | grep -wq "${KEY}"; then
          DELS+=("${KEY}")
        fi
      done <<<"$(readConfigMap "modules" "${USER_CONFIG_FILE}")"
      if [ ${#DELS[@]} -eq 0 ]; then
        DIALOG --title "$(TEXT "Modules")" \
          --msgbox "$(TEXT "No i915 with dependencies module to deselect.")" 0 0
      else
        for ID in "${DELS[@]}"; do
          deleteConfigKey "modules.\"${ID}\"" "${USER_CONFIG_FILE}"
        done
        DIALOG --title "$(TEXT "Modules")" \
          --msgbox "$(printf "$(TEXT "Module %s deselected.")\n" "${DELS[@]}")" 0 0
      fi
      touch "${PART1_PATH}/.build"
      ;;
    p)
      [ "${ODP}" = "false" ] && ODP='true' || ODP='false'
      writeConfigKey "odp" "${ODP}" "${USER_CONFIG_FILE}"
      touch "${PART1_PATH}/.build"
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
        dos2unix "${USER_UP_PATH}/modulelist" >/dev/null 2>&1 || true
        touch "${PART1_PATH}/.build"
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
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && break
        resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
        [ -z "${resp}" ] && break
        VALUE="${resp}"
        if echo "${VALUE}" | grep -q " "; then
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
    rm -f "${TMP_PATH}/menu"
    {
      echo "a \"$(TEXT "Add/Edit a cmdline item")\""
      echo "d \"$(TEXT "Show/Delete cmdline items")\""
      if [ -n "${MODEL}" ]; then
        echo "s \"$(TEXT "Define SN/MAC")\""
      fi
      # echo "m \"$(TEXT "Show model inherent cmdline")\""
      echo "e \"$(TEXT "Exit")\""
    } >"${TMP_PATH}/menu"
    DIALOG --title "$(TEXT "Cmdline")" \
      --menu "$(TEXT "Choose a option")" 0 0 0 --file "${TMP_PATH}/menu" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return
    case "$(cat "${TMP_PATH}/resp" 2>/dev/null)" in
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
      MSG+="$(TEXT " * \Z4scsi_mod.scan=sync\Zn\n    Synchronize scanning of devices on the SCSI bus during system startup(Resolve the disorderly order of HBA disks).\n")"
      MSG+="$(TEXT " * \Z4i915.enable_guc=2\Zn\n    Enable the GuC firmware on Intel graphics hardware.(value: 1,2 or 3)\n")"
      MSG+="$(TEXT " * \Z4i915.max_vfs=7\Zn\n    Set the maximum number of virtual functions (VFs) that can be created for Intel graphics hardware.\n")"
      MSG+="$(TEXT " * \Z4i915.modeset=0\Zn\n    Disable the kernel mode setting (KMS) feature of the i915 driver.\n")"
      MSG+="$(TEXT " * \Z4apparmor.mode=complain\Zn\n    Set the AppArmor security module to complain mode.\n")"
      MSG+="$(TEXT " * \Z4acpi_enforce_resources=lax\Zn\n    Resolve the issue of some devices (such as fan controllers) not recognizing or using properly.\n")"
      MSG+="$(TEXT " * \Z4pci=nommconf\Zn\n    Disable the use of Memory-Mapped Configuration for PCI devices(use this parameter cautiously).\n")"
      MSG+="$(TEXT " * \Z4consoleblank=300\Zn\n    Set the console to auto turnoff display 300 seconds after no activity (measured in seconds).\n")"
      MSG+="$(TEXT "Please enter the parameter key and value you need to add.\n")"

      LINENUM=0
      while read -r L; do LINENUM=$((LINENUM + 1 + ${#L} / 96)); done <<<"$(printf "${MSG}")" # When the width is 100, each line displays 96 characters.
      LINENUM=$((${LINENUM:-0} + 9))                                                          # When there are 2 parameters, 9 is the minimum value to include 1 line of MSG.

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
        0)
          # ok-button
          NAME="$(sed -n '1p' "${TMP_PATH}/resp" 2>/dev/null)"
          VALUE="$(sed -n '2p' "${TMP_PATH}/resp" 2>/dev/null)"
          [ "${NAME: -1}" = "=" ] && NAME="${NAME:0:-1}"
          [ "${VALUE:0:1}" = "=" ] && VALUE="${VALUE:1}"
          if [ -z "${NAME//\"/}" ]; then
            DIALOG --title "$(TEXT "Cmdline")" \
              --yesno "$(TEXT "Invalid parameter name, retry?")" 0 0
            [ $? -eq 0 ] && continue || break
          fi
          writeConfigKey "cmdline.\"${NAME//\"/}\"" "${VALUE}" "${USER_CONFIG_FILE}"
          break
          ;;
        1)
          # cancel-button
          break
          ;;
        255)
          # ESC
          break
          ;;
        esac
      done
      ;;
    d)
      # Read cmdline from user config
      unset CMDLINE
      declare -A CMDLINE
      while IFS=': ' read -r KEY VALUE; do
        [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
      done <<<"$(readConfigMap "cmdline" "${USER_CONFIG_FILE}")"
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
      resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
      [ -z "${resp}" ] && continue
      for I in ${resp}; do
        unset "CMDLINE[${I}]"
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
          --form "${MSG}" 11 70 3 "sn" 1 1 "${sn}" 1 5 60 0 "mac1" 2 1 "${mac1}" 2 5 60 0 "mac2" 3 1 "${mac2}" 3 5 60 0 \
          2>"${TMP_PATH}/resp"
        RET=$?
        case ${RET} in
        0)
          # ok-button
          sn="$(sed -n '1p' "${TMP_PATH}/resp" 2>/dev/null | sed 's/.*/\U&/')"
          mac1="$(sed -n '2p' "${TMP_PATH}/resp" 2>/dev/null | sed 's/[:-]//g' | sed 's/.*/\U&/')"
          mac2="$(sed -n '3p' "${TMP_PATH}/resp" 2>/dev/null | sed 's/[:-]//g' | sed 's/.*/\U&/')"
          if [ -z "${sn}" ] || [ -z "${mac1}" ]; then
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
        3)
          # extra-button
          sn=$(generateSerial "${MODEL}")
          NETIF_NUM=2
          MACS="$(generateMacAddress "${MODEL}" ${NETIF_NUM})"
          for I in $(seq 1 ${NETIF_NUM}); do
            eval mac${I}="$(echo ${MACS} | cut -d' ' -f${I})"
          done
          ;;
        1)
          # cancel-button
          break
          ;;
        255)
          # ESC
          break
          ;;
        esac
      done
      ;;
    # m)
    #   ITEMS=""
    #   while IFS=': ' read -r KEY VALUE; do
    #     ITEMS+="${KEY}: ${VALUE}\n"
    #   done <<<$(readConfigMap "platforms.${PLATFORM}.cmdline" "${WORK_PATH}/platforms.yml")
    #   DIALOG --title "$(TEXT "Cmdline")" \
    #     --msgbox "${ITEMS}" 0 0
    #   ;;
    e)
      return 0
      ;;
    esac
  done
}

###############################################################################
function synoinfoMenu() {
  # Loop menu
  while true; do
    rm -f "${TMP_PATH}/menu"
    {
      echo "a \"$(TEXT "Add/edit a synoinfo item")\""
      echo "d \"$(TEXT "Show/Delete synoinfo items")\""
      echo "e \"$(TEXT "Exit")\""
    } >"${TMP_PATH}/menu"
    DIALOG --title "$(TEXT "Synoinfo")" \
      --menu "$(TEXT "Choose a option")" 0 0 0 --file "${TMP_PATH}/menu" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return
    case "$(cat "${TMP_PATH}/resp" 2>/dev/null)" in
    a)
      MSG=""
      MSG+="$(TEXT "Commonly used synoinfo:\n")"
      MSG+="$(TEXT " * \Z4support_apparmor=no\Zn\n    Disable apparmor.\n")"
      MSG+="$(TEXT " * \Z4maxdisks=??\Zn\n    Maximum number of disks supported.\n")"
      MSG+="$(TEXT " * \Z4internalportcfg=0x????\Zn\n    Internal(sata) disks mask(Not apply to DT models).\n")"
      MSG+="$(TEXT " * \Z4esataportcfg=0x????\Zn\n    Esata disks mask(Not apply to DT models).\n")"
      MSG+="$(TEXT " * \Z4usbportcfg=0x????\Zn\n    USB disks mask(Not apply to DT models).\n")"
      MSG+="$(TEXT " * \Z4max_sys_raid_disks=12\Zn\n    Maximum number of system partition(md0) raid disks.\n")"
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
        DIALOG --title "$(TEXT "Synoinfo")" \
          --form "${MSG}" ${LINENUM:-9} 100 2 "Name:" 1 1 "" 1 10 85 0 "Value:" 2 1 "" 2 10 85 0 \
          2>"${TMP_PATH}/resp"
        RET=$?
        case ${RET} in
        0)
          # ok-button
          NAME="$(sed -n '1p' "${TMP_PATH}/resp" 2>/dev/null)"
          VALUE="$(sed -n '2p' "${TMP_PATH}/resp" 2>/dev/null)"
          [ "${NAME: -1}" = "=" ] && NAME="${NAME:0:-1}"
          [ "${VALUE:0:1}" = "=" ] && VALUE="${VALUE:1}"
          if [ -z "${NAME//\"/}" ]; then
            DIALOG --title "$(TEXT "Synoinfo")" \
              --yesno "$(TEXT "Invalid parameter name, retry?")" 0 0
            [ $? -eq 0 ] && continue || break
          fi
          writeConfigKey "synoinfo.\"${NAME//\"/}\"" "${VALUE}" "${USER_CONFIG_FILE}"
          touch "${PART1_PATH}/.build"
          break
          ;;
        1)
          # cancel-button
          break
          ;;
        255)
          # ESC
          break
          ;;
        esac
      done
      ;;
    d)
      # Read synoinfo from user config
      unset SYNOINFO
      declare -A SYNOINFO
      while IFS=': ' read -r KEY VALUE; do
        [ -n "${KEY}" ] && SYNOINFO["${KEY}"]="${VALUE}"
      done <<<"$(readConfigMap "synoinfo" "${USER_CONFIG_FILE}")"
      if [ ${#SYNOINFO[@]} -eq 0 ]; then
        DIALOG --title "$(TEXT "Synoinfo")" \
          --msgbox "$(TEXT "No synoinfo entries to remove")" 0 0
        continue
      fi
      rm -f "${TMP_PATH}/opts"
      for I in "${!SYNOINFO[@]}"; do
        echo "\"${I}\" \"${SYNOINFO[${I}]}\" \"off\"" >>"${TMP_PATH}/opts"
      done
      DIALOG --title "$(TEXT "Synoinfo")" \
        --checklist "$(TEXT "Select synoinfo entry to remove")" 0 0 0 --file "${TMP_PATH}/opts" \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && continue
      resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
      [ -z "${resp}" ] && continue
      for I in ${resp}; do
        unset "SYNOINFO[${I}]"
        deleteConfigKey "synoinfo.\"${I}\"" "${USER_CONFIG_FILE}"
      done
      touch "${PART1_PATH}/.build"
      ;;
    e)
      return 0
      ;;
    esac
  done
}

###############################################################################
# Extract linux and ramdisk files from the DSM .pat
function getSynoExtractor() {
  rm -f "${LOG_FILE}"
  mirrors=("global.download.synology.com" "global.synologydownload.com" "cndl.synology.cn")
  fastest=$(_get_fastest "${mirrors[@]}")
  if [ $? -ne 0 ]; then
    echo -e "$(TEXT "The current network status is unknown, using the default mirror.")"
  fi
  OLDPAT_URL="https://${fastest}/download/DSM/release/7.0.1/42218/DSM_DS3622xs%2B_42218.pat"
  OLDPAT_PATH="${TMP_PATH}/DS3622xs+-42218.pat"
  EXTRACTOR_PATH="${PART3_PATH}/extractor"
  EXTRACTOR_BIN="syno_extract_system_patch"

  # Extractor not exists, get it.
  mkdir -p "${EXTRACTOR_PATH}"

  echo "$(TEXT "Downloading old pat to extract synology .pat extractor...")"
  rm -f "${OLDPAT_PATH}"
  STATUS=$(curl -kL --http1.1 --connect-timeout 10 -w "%{http_code}" "${OLDPAT_URL}" -o "${OLDPAT_PATH}")
  RET=$?
  if [ ${RET} -ne 0 ] || [ ${STATUS:-0} -ne 200 ]; then
    rm -f "${OLDPAT_PATH}"
    printf "%s\n%s: %d:%d\n%s\n" "$(TEXT "Check internet.")" "$(TEXT "Error")" "${RET}" "${STATUS}" "$(TEXT "(Please via https://curl.se/libcurl/c/libcurl-errors.html check error description.)")" >"${LOG_FILE}"
    return 1
  fi

  # Extract DSM ramdisk file from PAT
  rm -rf "${RAMDISK_PATH}"
  mkdir -p "${RAMDISK_PATH}"
  tar -xf "${OLDPAT_PATH}" -C "${RAMDISK_PATH}" "rd.gz" 2>"${LOG_FILE}"
  if [ $? -ne 0 ]; then
    rm -f "${OLDPAT_PATH}"
    rm -rf "${RAMDISK_PATH}"
    echo -e "$(TEXT "pat Invalid, try again!")" >"${LOG_FILE}"
    return 1
  fi
  rm -f "${OLDPAT_PATH}"
  # Extract all files from rd.gz
  (cd "${RAMDISK_PATH}" && xz -dc <"rd.gz" | cpio -idm) >/dev/null 2>&1 || true
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
  printf "$(TEXT "Disassembling %s:")" "$(basename "${PAT_PATH}")"

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
    [ ! -f "${EXT_PATH}/grub_cksum.syno" ] ||
    [ ! -f "${EXT_PATH}/GRUB_VER" ] ||
    [ ! -f "${EXT_PATH}/zImage" ] ||
    [ ! -f "${EXT_PATH}/rd.gz" ]; then
    printf "%s\n%s: %d\n" "$(TEXT "pat Invalid, try again!")" "$(TEXT "Error")" "${RET}" >"${LOG_FILE}"
    return 1
  fi
  rm -f "${LOG_FILE}"
  return 0
}

###############################################################################
# Extract linux and ramdisk files from the DSM .pat
function extractDsmFiles() {
  rm -f "${LOG_FILE}"

  PATURL="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
  PATSUM="$(readConfigKey "patsum" "${USER_CONFIG_FILE}")"

  PAT_FILE="${MODEL}-${PRODUCTVER}.pat"
  PAT_PATH="${PART3_PATH}/dl/${PAT_FILE}"

  [ -f "${PAT_PATH}" ] && [ -f "${PAT_PATH}.downloading" ] && rm -f "${PAT_PATH}" "${PAT_PATH}.downloading"

  if [ ! -f "${PAT_PATH}" ]; then
    if [ "${PATURL}" = "#PARSEPAT" ]; then
      echo -e "$(TEXT "The cache has been cleared. Please re 'Parse pat' before build.")" >"${LOG_FILE}"
      return 1
    fi
    if [ "${PATURL}" = "#RECOVERY" ]; then
      echo -e "$(TEXT "The cache has been cleared. Please re 'Try to recovery a installed DSM system' before build.")" >"${LOG_FILE}"
      return 1
    fi
    if [ -z "${PATURL}" ] || [ "${PATURL:0:1}" = "#" ]; then
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
    mirrors=("global.download.synology.com" "global.synologydownload.com" "cndl.synology.cn")
    fastest=$(_get_fastest "${mirrors[@]}")
    if [ $? -ne 0 ]; then
      echo -e "$(TEXT "The current network status is unknown, using the default mirror.")"
    fi
    mirror="$(echo "${PATURL}" | sed 's|^http[s]*://\([^/]*\).*|\1|')"
    if echo "${mirrors[@]}" | grep -wq "${mirror}" && [ "${mirror}" != "${fastest}" ]; then
      printf "$(TEXT "Based on the current network situation, switch to %s mirror to downloading.\n")" "${fastest}"
      PATURL="$(echo "${PATURL}" | sed "s/${mirror}/${fastest}/")"
    fi
    printf "$(TEXT "Downloading %s ...\n")" "${PAT_FILE}"
    # Check disk space left
    SPACELEFT=$(df --block-size=1 "${PART3_PATH}" 2>/dev/null | awk 'NR==2 {print $4}')
    # Discover remote file size
    FILESIZE=$(curl -skLI --http1.1 --connect-timeout 10 "${PATURL}" | grep -i Content-Length | tail -n 1 | tr -d '\r\n' | awk '{print $2}')
    if [ ${FILESIZE:-0} -ge ${SPACELEFT:-0} ]; then
      # No disk space to download, change it to RAMDISK
      PAT_PATH="${TMP_PATH}/${PAT_FILE}"
    fi
    touch "${PAT_PATH}.downloading"
    STATUS=$(curl -kL --http1.1 --connect-timeout 10 -w "%{http_code}" "${PATURL}" -o "${PAT_PATH}")
    RET=$?
    rm -f "${PAT_PATH}.downloading"
    if [ ${RET} -ne 0 ] || [ ${STATUS:-0} -ne 200 ]; then
      rm -f "${PAT_PATH}"
      printf "%s\n%s: %d:%d\n%s\n" "$(TEXT "Check internet.")" "$(TEXT "Error")" "${RET}" "${STATUS}" "$(TEXT "(Please via https://curl.se/libcurl/c/libcurl-errors.html check error description.)")" >"${LOG_FILE}"
      return 1
    fi
  else
    printf "$(TEXT "%s cached.")" "${PAT_FILE}"
  fi

  printf "$(TEXT "Checking hash of %s:")" "${PAT_FILE}"
  if [ "00000000000000000000000000000000" != "${PATSUM}" ] && [ "$(md5sum "${PAT_PATH}" | awk '{print $1}')" != "${PATSUM}" ]; then
    rm -f "${PAT_PATH}"
    echo -e "$(TEXT "md5 hash of pat not match, Please reget pat data from the version menu and try again!")" >"${LOG_FILE}"
    return 1
  fi
  echo "$(TEXT "OK")"

  rm -rf "${UNTAR_PAT_PATH}"
  mkdir -p "${UNTAR_PAT_PATH}"
  printf "$(TEXT "Disassembling %s:")" "${PAT_FILE}"

  extractPatFiles "${PAT_PATH}" "${UNTAR_PAT_PATH}"
  if [ $? -ne 0 ]; then
    rm -rf "${UNTAR_PAT_PATH}"
    return 1
  fi
  echo -n "$(TEXT "Setting hash:")"
  ZIMAGE_HASH="$(sha256sum "${UNTAR_PAT_PATH}/zImage" | awk '{print $1}')"
  writeConfigKey "zimage-hash" "${ZIMAGE_HASH}" "${USER_CONFIG_FILE}"
  RAMDISK_HASH="$(sha256sum "${UNTAR_PAT_PATH}/rd.gz" | awk '{print $1}')"
  writeConfigKey "ramdisk-hash" "${RAMDISK_HASH}" "${USER_CONFIG_FILE}"
  echo "$(TEXT "OK")"

  echo -n "$(TEXT "Copying files:")"
  copyDSMFiles "${UNTAR_PAT_PATH}"
  rm -rf "${UNTAR_PAT_PATH}"
  echo "$(TEXT "OK")"
}

###############################################################################
# Where the magic happens!
# 1 - silent
function make() {
  function __make() {
    if [ ! -f "${ORI_ZIMAGE_FILE}" ] || [ ! -f "${ORI_RDGZ_FILE}" ]; then
      extractDsmFiles || return 1
    fi
    SIZE=256 # initrd-dsm + zImage-dsm ≈ 210M
    SPACELEFT=$(df -m "${PART3_PATH}" 2>/dev/null | awk 'NR==2 {print $4}')
    ZIMAGESIZE=$(du -m "${MOD_ZIMAGE_FILE}" 2>/dev/null | awk '{print $1}')
    RDGZSIZE=$(du -m "${MOD_RDGZ_FILE}" 2>/dev/null | awk '{print $1}')
    SPACEALL=$((${SPACELEFT:-0} + ${ZIMAGESIZE:-0} + ${RDGZSIZE:-0}))
    if [ ${SPACEALL:-0} -lt ${SIZE} ]; then
      echo -e "$(TEXT "No disk space left, please clean the cache and try again!")" >"${LOG_FILE}"
      return 1
    fi
    if [ -f "${PART1_PATH}/.upgraded" ]; then
      echo "$(TEXT "Reconfigure after upgrade ...")"
      PATURL="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
      PATSUM="$(readConfigKey "patsum" "${USER_CONFIG_FILE}")"
      reconfiguringM "${MODEL}" "${PLATFORM}"
      reconfiguringV "${PRODUCTVER}" "${PATURL}" "${PATSUM}"
      if [ $? -ne 0 ]; then
        echo -e "$(TEXT "Reconfiguration failed!")" >"${LOG_FILE}"
        return 1
      fi
      rm -f "${PART1_PATH}/.upgraded"
    fi
    ${WORK_PATH}/zimage-patch.sh || {
      printf "%s\n%s\n%s:\n%s\n" "$(TEXT "DSM zImage not patched")" "$(TEXT "Please upgrade the bootloader version and try again.")" "$(TEXT "Error")" "$(cat "${LOG_FILE}")" >"${LOG_FILE}"
      return 1
    }

    ${WORK_PATH}/ramdisk-patch.sh || {
      printf "%s\n%s\n%s:\n%s\n" "$(TEXT "DSM ramdisk not patched")" "$(TEXT "Please upgrade the bootloader version and try again.")" "$(TEXT "Error")" "$(cat "${LOG_FILE}")" >"${LOG_FILE}"
      return 1
    }

    rm -f "${PART1_PATH}/.build"
    echo "$(TEXT "Cleaning ...")"
    rm -rf "${UNTAR_PAT_PATH}"
    rm -f "${LOG_FILE}"
    echo "$(TEXT "Ready!")"
    sleep 3
    return 0
  }

  rm -f "${LOG_FILE}"
  __make 2>&1 | DIALOG --title "$(TEXT "Main menu")" \
    --progressbox "$(TEXT "Making ... ('ctrl + c' to exit)")" 20 100
  if [ -f "${LOG_FILE}" ]; then
    DIALOG --title "$(TEXT "Error")" \
      --msgbox "$(cat "${LOG_FILE}")" 0 0
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
# Calls boot.sh to boot into DSM kernel/ramdisk
function boot() {
  if [ -f "${PART1_PATH}/.build" ]; then
    DIALOG --ret 0 --title "$(TEXT "Alert")" \
      --yesno "$(TEXT "Config changed, would you like to rebuild the loader?")" 0 0
    if [ $? -eq 0 ]; then
      make || return 1
      "${WORK_PATH}/boot.sh" && exit 0
    fi
  else
    "${WORK_PATH}/boot.sh" && exit 0
  fi
}

###############################################################################
# Where the magic happens!
function customDTS() {
  # Loop menu
  while true; do
    [ -f "${USER_UP_PATH}/${MODEL}.dts" ] && mv -f "${USER_UP_PATH}/${MODEL}.dts" "${USER_UP_PATH}/model.dts"
    [ -f "${USER_UP_PATH}/model.dts" ] && CUSTOMDTS="Yes" || CUSTOMDTS="No"
    rm -f "${TMP_PATH}/menu"
    {
      echo "u \"$(TEXT "Upload dts file")\""
      echo "d \"$(TEXT "Delete dts file")\""
      echo "i \"$(TEXT "Edit dts file")\""
      echo "e \"$(TEXT "Exit")\""
    } >"${TMP_PATH}/menu"
    DIALOG --err "${1}" --title "$(TEXT "Custom DTS")" \
      --menu "$(TEXT "Custom dts:") ${CUSTOMDTS}" 0 0 0 --file "${TMP_PATH}/menu" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return 1
    case "$(cat "${TMP_PATH}/resp" 2>/dev/null)" in
    u)
      if ! tty 2>/dev/null | grep -q "/dev/pts"; then #if ! tty 2>/dev/null | grep -q "/dev/pts" || [ -z "${SSH_TTY}" ]; then
        MSG=""
        MSG+="$(TEXT "This feature is only available when accessed via ssh (Requires a terminal that supports ZModem protocol).\n")"
        MSG+="$(printf "$(TEXT "Or upload the dts file to %s via DUFS, Will be automatically imported when building.\n")" "${USER_UP_PATH}/model.dts")"
        DIALOG --title "$(TEXT "Custom DTS")" \
          --msgbox "${MSG}" 0 0
        return 1
      fi
      DIALOG --title "$(TEXT "Custom DTS")" \
        --msgbox "$(TEXT "Currently, only dts format files are supported. Please prepare and click to confirm uploading.\n(saved in /mnt/p3/users/)\n")" 0 0
      TMP_UP_PATH="${TMP_PATH}/users"
      rm -rf "${TMP_UP_PATH}"
      mkdir -p "${TMP_UP_PATH}"
      (cd "${TMP_UP_PATH}" && rz -be) || true
      USER_FILE="$(find "${TMP_UP_PATH}" -type f | head -1)"
      DTC_ERRLOG="/tmp/dtc.log"
      [ -n "${USER_FILE}" ] && dtc -q -I dts -O dtb "${USER_FILE}" >"test.dtb" 2>"${DTC_ERRLOG}"
      RET=$?
      if [ -z "${USER_FILE}" ] || [ ${RET} -ne 0 ]; then
        MSG="$(printf "%s\n%s:\n%s\n" "$(TEXT "Not a valid dts file, please try again!")" "$(TEXT "Error")" "$(cat "${DTC_ERRLOG}")")"
        DIALOG --title "$(TEXT "Custom DTS")" \
          --msgbox "${MSG}" 0 0
      else
        [ -d "${USER_UP_PATH}" ] || mkdir -p "${USER_UP_PATH}"
        cp -f "${USER_FILE}" "${USER_UP_PATH}/model.dts"
        DIALOG --title "$(TEXT "Custom DTS")" \
          --msgbox "$(TEXT "A valid dts file, Automatically import at compile time.")" 0 0
      fi
      rm -f "${DTC_ERRLOG}"
      rm -rf "${TMP_UP_PATH}"
      touch "${PART1_PATH}/.build"
      ;;
    d)
      rm -f "${USER_UP_PATH}/model.dts"
      touch "${PART1_PATH}/.build"
      ;;
    i)
      rm -rf "${TMP_PATH}/model.dts"
      if [ -f "${USER_UP_PATH}/model.dts" ]; then
        cp -f "${USER_UP_PATH}/model.dts" "${TMP_PATH}/model.dts"
      else
        ODTB="$(find "${PART2_PATH}" -type f -name "*.dtb" | head -1)"
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
        [ $? -ne 0 ] && rm -f "${TMP_PATH}/model.dts" "${TMP_PATH}/modelEdit.dts" && return 1
        dtc -q -I dts -O dtb "${TMP_PATH}/modelEdit.dts" >"test.dtb" 2>"${DTC_ERRLOG}"
        if [ $? -ne 0 ]; then
          MSG="$(printf "%s\n%s:\n%s\n" "$(TEXT "Not a valid dts file, please try again!")" "$(TEXT "Error")" "$(cat "${DTC_ERRLOG}")")"
          DIALOG --title "$(TEXT "Custom DTS")" \
            --msgbox "${MSG}" 0 0
        else
          mkdir -p "${USER_UP_PATH}"
          cp -f "${TMP_PATH}/modelEdit.dts" "${USER_UP_PATH}/model.dts"
          rm -r "${TMP_PATH}/model.dts" "${TMP_PATH}/modelEdit.dts"
          touch "${PART1_PATH}/.build"
          break
        fi
      done
      ;;
    e)
      return 0
      ;;
    esac
  done
}

###############################################################################
# Show disks information
function showDisksInfo() {
  MSG=""
  NUMPORTS=0
  [ "$(lspci -d ::106 2>/dev/null | wc -l)" -gt 0 ] && MSG+="\nSATA:\n"
  for PCI in $(lspci -d ::106 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    MSG+="\Zb${NAME}\Zn\nPorts: "
    PORTS=$(ls -l /sys/class/scsi_host 2>/dev/null | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
    for P in ${PORTS}; do
      if lsscsi -bS 2>/dev/null | awk '$3 != "0"' | grep -v - | grep -q "\[${P}:"; then
        if [ "$(cat "/sys/class/scsi_host/host${P}/ahci_port_cmd" 2>/dev/null)" = "0" ]; then
          MSG+="\Z1$(printf "%02d" "${P}")\Zn "
        else
          MSG+="\Z2$(printf "%02d" "${P}")\Zn "
        fi
      else
        MSG+="$(printf "%02d" "${P}") "
      fi
      NUMPORTS=$((${NUMPORTS} + 1))
    done
    MSG+="\n"
  done
  [ "$(lspci -d ::104 2>/dev/null | wc -l)" -gt 0 ] && MSG+="\nRAID:\n"
  for PCI in $(lspci -d ::104 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORT=$(ls -l /sys/class/scsi_host 2>/dev/null | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
    PORTNUM=$(lsscsi -bS 2>/dev/null | awk '$3 != "0"' | grep -v - | grep "\[${PORT}:" | wc -l)
    [ ${PORTNUM} -eq 0 ] && continue
    MSG+="\Zb${NAME}\Zn\nNumber: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  [ "$(lspci -d ::107 2>/dev/null | wc -l)" -gt 0 ] && MSG+="\nSAS:\n"
  for PCI in $(lspci -d ::107 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORT=$(ls -l /sys/class/scsi_host 2>/dev/null | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
    PORTNUM=$(lsscsi -bS 2>/dev/null | awk '$3 != "0"' | grep -v - | grep "\[${PORT}:" | wc -l)
    [ ${PORTNUM} -eq 0 ] && continue
    MSG+="\Zb${NAME}\Zn\nNumber: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  [ "$(lspci -d ::100 2>/dev/null | wc -l)" -gt 0 ] && MSG+="\nSCSI:\n"
  for PCI in $(lspci -d ::100 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORTNUM=$(ls -l /sys/block/* 2>/dev/null | grep "${PCI}" | wc -l)
    [ ${PORTNUM} -eq 0 ] && continue
    MSG+="\Zb${NAME}\Zn\nNumber: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  [ "$(lspci -d ::101 2>/dev/null | wc -l)" -gt 0 ] && MSG+="\nIDE:\n"
  for PCI in $(lspci -d ::101 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORTNUM=$(ls -l /sys/block/* 2>/dev/null | grep "${PCI}" | wc -l)
    [ ${PORTNUM} -eq 0 ] && continue
    MSG+="\Zb${NAME}\Zn\nNumber: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  [ "$(ls -l /sys/class/scsi_host 2>/dev/null | grep usb | wc -l)" -gt 0 ] && MSG+="\nUSB:\n"
  for PCI in $(lspci -d ::c03 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORT=$(ls -l /sys/class/scsi_host 2>/dev/null | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
    PORTNUM=$(lsscsi -bS 2>/dev/null | awk '$3 != "0"' | grep -v - | grep "\[${PORT}:" | wc -l)
    [ ${PORTNUM} -eq 0 ] && continue
    MSG+="\Zb${NAME}\Zn\nNumber: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  [ "$(ls -l /sys/block/mmc* 2>/dev/null | wc -l)" -gt 0 ] && MSG+="\nMMC:\n"
  for PCI in $(lspci -d ::805 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORTNUM=$(ls -l /sys/block/mmc* 2>/dev/null | grep "${PCI}" | wc -l)
    [ ${PORTNUM} -eq 0 ] && continue
    MSG+="\Zb${NAME}\Zn\nNumber: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  [ "$(lspci -d ::108 2>/dev/null | wc -l)" -gt 0 ] && MSG+="\nNVME:\n"
  for PCI in $(lspci -d ::108 2>/dev/null | awk '{print $1}'); do
    NAME=$(lspci -s "${PCI}" 2>/dev/null | sed "s/\ .*://")
    PORT=$(ls -l /sys/class/nvme 2>/dev/null | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/nvme//' | sort -n)
    PORTNUM=$(lsscsi -bS 2>/dev/null | awk '$3 != "0"' | grep -v - | grep "\[N:${PORT}:" | wc -l)
    [ ${PORTNUM} -eq 0 ] && continue
    MSG+="\Zb${NAME}\Zn\nNumber: ${PORTNUM}\n"
    NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
  done
  if [ "$(lsblk -dpno KNAME,SUBSYSTEMS 2>/dev/null | grep 'vmbus:acpi' | wc -l)" -gt 0 ]; then
    MSG+="\nVMBUS:\n"
    NAME="vmbus:acpi"
    PORTNUM=$(lsblk -dpno KNAME,SUBSYSTEMS 2>/dev/null | grep 'vmbus:acpi' | wc -l)
    [ ${PORTNUM} -eq 0 ] || {
      MSG+="\Zb${NAME}\Zn\nNumber: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    }
  fi
  MSG+="\n"
  MSG+="$(printf "$(TEXT "Total of ports: %s\n")" "${NUMPORTS}")"
  MSG+="\n"
  MSG+="$(TEXT "Ports with color \Z1red\Zn as DUMMY, color \Z2green\Zn has drive connected.")"
  [ ${NUMPORTS} -eq 0 ] && MSG="$(TEXT "No disk found!")"
  DIALOG --title "$(TEXT "Advanced")" \
    --msgbox "${MSG}" 0 0
  return 0
}

###############################################################################
# Mounting DSM storage pool
function MountDSMVolume {
  vgscan >/dev/null 2>&1
  vgchange -ay >/dev/null 2>&1
  VOLS="$(lvdisplay 2>/dev/null | grep 'LV Path' | grep -v 'syno_vg_reserved_area' | awk '{print $3}')"
  if [ -z "${VOLS}" ]; then
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "$(TEXT "No storage pool found!")" 0 0
    return 1
  fi
  for I in ${VOLS}; do
    NAME="$(echo "${I}" | awk -F'/' '{print $3"_"$4}')"
    mkdir -p "/mnt/DSM/${NAME}"
    umount "${I}" 2>/dev/null
    mount "${I}" "/mnt/DSM/${NAME}" -o ro
  done

  MSG=""
  MSG+="$(TEXT "All storage pools are mounted under /mnt/DSM. Please check them yourself via shell/DUFS.")"
  MSG+="$(TEXT "For encrypted volume / encrypted shared folder, please refer to https://kb.synology.com/en-us/DSM/tutorial/How_can_I_recover_data_from_my_DiskStation_using_a_PC")"
  DIALOG --title "$(TEXT "Advanced")" \
    --msgbox "${MSG}" 0 0
  return 0
}

###############################################################################
# Format disk
function formatDisks() {
  rm -f "${TMP_PATH}/opts"
  while read -r KNAME ID SIZE TYPE PKNAME; do
    [ "${KNAME}" = "N/A" ] || [ "${SIZE:0:1}" = "0" ] && continue
    [ "${KNAME:0:7}" = "/dev/md" ] && continue
    [ "${KNAME}" = "${LOADER_DISK}" ] || [ "${PKNAME}" = "${LOADER_DISK}" ] && continue
    printf "\"%s\" \"%-6s %-4s %s\" \"off\"\n" "${KNAME}" "${SIZE}" "${TYPE}" "${ID}" >>"${TMP_PATH}/opts"
  done <<<"$(lsblk -Jpno KNAME,ID,SIZE,TYPE,PKNAME 2>/dev/null | sed 's|null|"N/A"|g' | jq -r '.blockdevices[] | "\(.kname) \(.id) \(.size) \(.type) \(.pkname)"' 2>/dev/null | sort)"
  if [ ! -f "${TMP_PATH}/opts" ]; then
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "$(TEXT "No disk found!")" 0 0
    return 1
  fi
  DIALOG --title "$(TEXT "Advanced")" \
    --checklist "$(TEXT "Advanced")" 0 0 0 --file "${TMP_PATH}/opts" \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
  [ -z "${resp}" ] && return 1
  DIALOG --title "$(TEXT "Advanced")" \
    --yesno "$(TEXT "Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?")" 0 0
  [ $? -ne 0 ] && return 1
  if [ "$(ls /dev/md[0-9]* 2>/dev/null | wc -l)" -gt 0 ]; then
    DIALOG --title "$(TEXT "Advanced")" \
      --yesno "$(TEXT "Warning:\nThe current hds is in raid, do you still want to format them?")" 0 0
    [ $? -ne 0 ] && return 1
    for F in /dev/md[0-9]*; do
      [ ! -e "${F}" ] && continue
      mdadm -S "${F}" >/dev/null 2>&1
    done
  fi
  for I in ${resp}; do
    if [ "${I:0:8}" = "/dev/mmc" ]; then
      echo y | mkfs.ext4 -T largefile4 -E nodiscard "${I}"
    else
      echo y | mkfs.ext4 -T largefile4 "${I}"
    fi
  done 2>&1 | DIALOG --title "$(TEXT "Advanced")" \
    --progressbox "$(TEXT "Formatting ...")" 20 100
  DIALOG --title "$(TEXT "Advanced")" \
    --msgbox "$(TEXT "Formatting is complete.")" 0 0
  return 0
}

###############################################################################
# Download DSM config backup files
function downloadBackupFiles() {
  if [ -d "${PART1_PATH}/scbk" ]; then
    rm -f "${TMP_PATH}/scbk.tar.gz"
    tar -czf "${TMP_PATH}/scbk.tar.gz" -C "${PART1_PATH}" scbk
    if [ -z "${SSH_TTY}" ]; then # web
      mv -f "${TMP_PATH}/scbk.tar.gz" "/var/www/data/scbk.tar.gz"
      HTTP=$(grep -i '^HTTP_PORT=' /etc/rrorg.conf 2>/dev/null | cut -d'=' -f2)
      URL="http://$(getIP):${HTTP:-7080}/scbk.tar.gz"
      DIALOG --title "$(TEXT "Advanced")" \
        --msgbox "$(printf "$(TEXT "Please via %s to download the scbk,\nAnd unzip it and back it up in order by file name.")" "${URL}")" 0 0
    else
      sz -be -B 536870912 "${TMP_PATH}/scbk.tar.gz"
      DIALOG --title "$(TEXT "Advanced")" \
        --msgbox "$(TEXT "Please unzip it and back it up in order by file name.")" 0 0
    fi
  else
    MSG=""
    MSG+="$(TEXT "\Z1No scbk found!\Zn\n")"
    MSG+="\n"
    MSG+="$(TEXT "Please do as follows:\n")"
    MSG+="$(TEXT " 1. Add synoconfbkp in addons and rebuild.\n")"
    MSG+="$(TEXT " 2. Normal use.\n")"
    MSG+="$(TEXT " 3. Reboot into RR and go to this option.\n")"
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "${MSG}" 0 0
  fi
  return 0
}

###############################################################################
# Allow downgrade installation
function allowDSMDowngrade() {
  MSG=""
  MSG+="$(TEXT "This feature will allow you to downgrade the installation by removing the VERSION file from the first partition of all disks.\n")"
  MSG+="$(TEXT "Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?")"
  DIALOG --ret 0 --title "$(TEXT "Advanced")" \
    --yesno "${MSG}" 0 0
  [ $? -ne 0 ] && return 1
  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "$(TEXT "No DSM system partition(md0) found!\nPlease insert all disks before continuing.")" 0 0
    return 1
  fi
  rm -f "${TMP_PATH}/isOk"
  (
    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      fixDSMRootPart "${I}"
      T="$(blkid -o value -s TYPE "${I}" 2>/dev/null | sed 's/linux_raid_member/ext4/')"
      mount -t "${T:-ext4}" "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      rm -f "${TMP_PATH}/mdX/etc/VERSION" "${TMP_PATH}/mdX/etc.defaults/VERSION"
      sync
      echo "true" >"${TMP_PATH}/isOk"
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX"
  ) 2>&1 | DIALOG --title "$(TEXT "Advanced")" \
    --progressbox "$(TEXT "Removing ...")" 20 100
  [ -f "${TMP_PATH}/isOk" ] &&
    MSG="$(TEXT "Remove VERSION file for DSM system partition(md0) completed.")" ||
    MSG="$(TEXT "Remove VERSION file for DSM system partition(md0) failed.")"
  DIALOG --title "$(TEXT "Advanced")" \
    --msgbox "${MSG}" 0 0
  return 0
}

###############################################################################
# Reset DSM system password
function resetDSMPassword() {
  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "$(TEXT "No DSM system partition(md0) found!\nPlease insert all disks before continuing.")" 0 0
    return 1
  fi
  rm -f "${TMP_PATH}/menu"
  mkdir -p "${TMP_PATH}/mdX"
  for I in ${DSMROOTS}; do
    fixDSMRootPart "${I}"
    T="$(blkid -o value -s TYPE "${I}" 2>/dev/null | sed 's/linux_raid_member/ext4/')"
    mount -t "${T:-ext4}" "${I}" "${TMP_PATH}/mdX"
    [ $? -ne 0 ] && continue
    if [ -f "${TMP_PATH}/mdX/etc/shadow" ]; then
      while read -r L; do
        U=$(echo "${L}" | awk -F ':' '{if ($2 != "*" && $2 != "!!") print $1;}')
        [ -z "${U}" ] && continue
        E=$(echo "${L}" | awk -F ':' '{if ($8 == "1") print "disabled"; else print "        ";}')
        grep -q "status=on" "${TMP_PATH}/mdX/usr/syno/etc/packages/SecureSignIn/preference/${U}/method.config" 2>/dev/null
        [ $? -eq 0 ] && S="SecureSignIn" || S="            "
        printf "\"%-36s %-10s %-14s\"\n" "${U}" "${E}" "${S}" >>"${TMP_PATH}/menu"
      done <<<"$(cat "${TMP_PATH}/mdX/etc/shadow" 2>/dev/null)"
    fi
    umount "${TMP_PATH}/mdX"
    [ -f "${TMP_PATH}/menu" ] && break
  done
  rm -rf "${TMP_PATH}/mdX"
  if [ ! -f "${TMP_PATH}/menu" ]; then
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "$(TEXT "All existing users have been disabled. Please try adding new user.")" 0 0
    return 1
  fi
  DIALOG --title "$(TEXT "Advanced")" \
    --no-items --menu "$(TEXT "Choose a user name")" 0 0 20 --file "${TMP_PATH}/menu" \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  USER="$(cat "${TMP_PATH}/resp" 2>/dev/null | awk '{print $1}')"
  [ -z "${USER}" ] && return 1
  local STRPASSWD
  while true; do
    DIALOG --title "$(TEXT "Advanced")" \
      --inputbox "$(printf "$(TEXT "Type a new password for user '%s'")" "${USER}")" 0 70 "" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break 2
    resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
    if [ -z "${resp}" ]; then
      DIALOG --title "$(TEXT "Advanced")" \
        --msgbox "$(TEXT "Invalid password")" 0 0
    else
      STRPASSWD="${resp}"
      break
    fi
  done
  rm -f "${TMP_PATH}/isOk"
  (
    mkdir -p "${TMP_PATH}/mdX"
    local NEWPASSWD
    # NEWPASSWD="$(python3 -c "from passlib.hash import sha512_crypt;pw=\"${STRPASSWD}\";print(sha512_crypt.using(rounds=5000).hash(pw))")"
    # NEWPASSWD="$(echo "${STRPASSWD}" | mkpasswd -m sha512)"
    NEWPASSWD="$(openssl passwd -6 -salt "$(openssl rand -hex 8)" "${STRPASSWD}")"
    for I in ${DSMROOTS}; do
      fixDSMRootPart "${I}"
      T="$(blkid -o value -s TYPE "${I}" 2>/dev/null | sed 's/linux_raid_member/ext4/')"
      mount -t "${T:-ext4}" "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      sed -i "s|^${USER}:[^:]*|${USER}:${NEWPASSWD}|" "${TMP_PATH}/mdX/etc/shadow"
      sed -i "/^${USER}:/ s/^\(${USER}:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:\)[^:]*:/\1:/" "${TMP_PATH}/mdX/etc/shadow"
      sed -i "s|status=on|status=off|g" "${TMP_PATH}/mdX/usr/syno/etc/packages/SecureSignIn/preference/${USER}/method.config" 2>/dev/null
      sed -i "s|list=*$|list=|; s|type=*$|type=none|" "${TMP_PATH}/mdX/usr/syno/etc/packages/SecureSignIn/secure_signin.conf" 2>/dev/null

      mkdir -p "${TMP_PATH}/mdX/usr/rr/once.d"
      {
        echo "#!/usr/bin/env bash"
        echo "synowebapi -s --exec api=SYNO.Core.OTP.EnforcePolicy method=set version=1 enable_otp_enforcement=false otp_enforce_option='\"none\"'"
        echo "synowebapi -s --exec api=SYNO.SecureSignIn.AMFA.Policy method=set version=1 type='\"none\"'"
        echo "synowebapi -s --exec api=SYNO.Core.SmartBlock method=set version=1 enabled=false untrust_try=5 untrust_minute=1 untrust_lock=30 trust_try=10 trust_minute=1 trust_lock=30"
        echo "synowebapi -s --exec api=SYNO.SecureSignIn.Method.Admin method=reset version=1 account='\"${USER}\"' keep_amfa_settings=true"
      } >"${TMP_PATH}/mdX/usr/rr/once.d/addNewDSMUser.sh"

      sync
      echo "true" >"${TMP_PATH}/isOk"
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX"
  ) 2>&1 | DIALOG --title "$(TEXT "Advanced")" \
    --progressbox "$(TEXT "Resetting ...")" 20 100
  [ -f "${TMP_PATH}/isOk" ] &&
    MSG="$(printf "$(TEXT "Reset password for user '%s' completed.")" "${USER}")" ||
    MSG="$(printf "$(TEXT "Reset password for user '%s' failed.")" "${USER}")"
  DIALOG --title "$(TEXT "Advanced")" \
    --msgbox "${MSG}" 0 0
  return 0
}

###############################################################################
# Add new DSM user
function addNewDSMUser() {
  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "$(TEXT "No DSM system partition(md0) found!\nPlease insert all disks before continuing.")" 0 0
    return 1
  fi
  MSG="$(TEXT "Add to administrators group by default")"
  DIALOG --title "$(TEXT "Advanced")" \
    --form "${MSG}" 8 60 3 "username:" 1 1 "" 1 10 50 0 "password:" 2 1 "" 2 10 50 0 \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  username="$(sed -n '1p' "${TMP_PATH}/resp" 2>/dev/null)"
  password="$(sed -n '2p' "${TMP_PATH}/resp" 2>/dev/null)"
  rm -f "${TMP_PATH}/isOk"
  (
    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      fixDSMRootPart "${I}"
      T="$(blkid -o value -s TYPE "${I}" 2>/dev/null | sed 's/linux_raid_member/ext4/')"
      mount -t "${T:-ext4}" "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      mkdir -p "${TMP_PATH}/mdX/usr/rr/once.d"
      {
        echo "#!/usr/bin/env bash"
        echo "if synouser --enum local | grep -q ^${username}\$; then synouser --setpw ${username} ${password}; else synouser --add ${username} ${password} rr 0 user@rr.com 1; fi"
        echo "synogroup --memberadd administrators ${username}"
      } >"${TMP_PATH}/mdX/usr/rr/once.d/addNewDSMUser.sh"
      sync
      echo "true" >"${TMP_PATH}/isOk"
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX"
  ) 2>&1 | DIALOG --title "$(TEXT "Advanced")" \
    --progressbox "$(TEXT "Adding ...")" 20 100
  [ -f "${TMP_PATH}/isOk" ] &&
    MSG="$(printf "$(TEXT "Add new user '%s' completed.")" "${username}")" ||
    MSG="$(printf "$(TEXT "Add new user '%s' failed.")" "${username}")"
  DIALOG --title "$(TEXT "Advanced")" \
    --msgbox "${MSG}" 0 0
  return 0
}

###############################################################################
# Force enable Telnet&SSH of DSM system
function forceEnableDSMTelnetSSH() {
  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "$(TEXT "No DSM system partition(md0) found!\nPlease insert all disks before continuing.")" 0 0
    return 1
  fi
  rm -f "${TMP_PATH}/isOk"
  (
    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      fixDSMRootPart "${I}"
      T="$(blkid -o value -s TYPE "${I}" 2>/dev/null | sed 's/linux_raid_member/ext4/')"
      mount -t "${T:-ext4}" "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      mkdir -p "${TMP_PATH}/mdX/usr/rr/once.d"
      {
        echo "#!/usr/bin/env bash"
        echo "systemctl restart inetd"
        echo "synowebapi -s --exec api=SYNO.Core.Terminal method=set version=3 enable_telnet=true enable_ssh=true ssh_port=22 forbid_console=false"
      } >"${TMP_PATH}/mdX/usr/rr/once.d/enableTelnetSSH.sh"
      sync
      echo "true" >"${TMP_PATH}/isOk"
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX"
  ) 2>&1 | DIALOG --title "$(TEXT "Advanced")" \
    --progressbox "$(TEXT "Enabling ...")" 20 100
  [ -f "${TMP_PATH}/isOk" ] &&
    MSG="$(TEXT "Force enable Telnet&SSH of DSM system completed.")" ||
    MSG="$(TEXT "Force enable Telnet&SSH of DSM system failed.")"
  DIALOG --title "$(TEXT "Advanced")" \
    --msgbox "${MSG}" 0 0
  return 0
}

###############################################################################
# Removing the blocked ip database
function removeBlockIPDB {
  MSG=""
  MSG+="$(TEXT "This feature will removing the blocked ip database from the first partition of all disks.\n")"
  MSG+="$(TEXT "Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?")"
  DIALOG --ret 0 --title "$(TEXT "Advanced")" \
    --yesno "${MSG}" 0 0
  [ $? -ne 0 ] && return 1
  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "$(TEXT "No DSM system partition(md0) found!\nPlease insert all disks before continuing.")" 0 0
    return 1
  fi
  rm -f "${TMP_PATH}/isOk"
  (
    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      fixDSMRootPart "${I}"
      T="$(blkid -o value -s TYPE "${I}" 2>/dev/null | sed 's/linux_raid_member/ext4/')"
      mount -t "${T:-ext4}" "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      rm -f "${TMP_PATH}/mdX/etc/synoautoblock.db"
      sync
      echo "true" >"${TMP_PATH}/isOk"
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX"
  ) 2>&1 | DIALOG --title "$(TEXT "Advanced")" \
    --progressbox "$(TEXT "Removing ...")" 20 100
  [ -f "${TMP_PATH}/isOk" ] &&
    MSG="$(TEXT "Removing the blocked ip database completed.")" ||
    MSG="$(TEXT "Removing the blocked ip database failed.")"
  DIALOG --title "$(TEXT "Advanced")" \
    --msgbox "${MSG}" 0 0
  return 0
}

###############################################################################
# Disable all scheduled tasks of DSM
function disablescheduledTasks {
  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "$(TEXT "No DSM system partition(md0) found!\nPlease insert all disks before continuing.")" 0 0
    return 1
  fi
  rm -f "${TMP_PATH}/isOk"
  (
    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      fixDSMRootPart "${I}"
      T="$(blkid -o value -s TYPE "${I}" 2>/dev/null | sed 's/linux_raid_member/ext4/')"
      mount -t "${T:-ext4}" "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      if [ -f "${TMP_PATH}/mdX/usr/syno/etc/esynoscheduler/esynoscheduler.db" ]; then
        echo "UPDATE task SET enable = 0;" | sqlite3 "${TMP_PATH}/mdX/usr/syno/etc/esynoscheduler/esynoscheduler.db"
        sync
        echo "true" >"${TMP_PATH}/isOk"
      fi
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX"
  ) 2>&1 | DIALOG --title "$(TEXT "Advanced")" \
    --progressbox "$(TEXT "Enabling ...")" 20 100
  [ -f "${TMP_PATH}/isOk" ] &&
    MSG="$(TEXT "Disable all scheduled tasks of DSM completed.")" ||
    MSG="$(TEXT "Disable all scheduled tasks of DSM failed.")"
  DIALOG --title "$(TEXT "Advanced")" \
    --msgbox "${MSG}" 0 0
  return 0
}

###############################################################################
# Initialize DSM network settings
function initDSMNetwork {
  MSG=""
  MSG+="$(TEXT "This option will clear all customized settings of the network card and restore them to the default state.\n")"
  MSG+="$(TEXT "Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?")"
  DIALOG --ret 0 --title "$(TEXT "Advanced")" \
    --yesno "${MSG}" 0 0
  [ $? -ne 0 ] && return 1
  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    DIALOG --title "$(TEXT "Advanced")" \
      --msgbox "$(TEXT "No DSM system partition(md0) found!\nPlease insert all disks before continuing.")" 0 0
    return 1
  fi
  rm -f "${TMP_PATH}/isOk"
  (
    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      fixDSMRootPart "${I}"
      T="$(blkid -o value -s TYPE "${I}" 2>/dev/null | sed 's/linux_raid_member/ext4/')"
      mount -t "${T:-ext4}" "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      for F in ${TMP_PATH}/mdX/etc/sysconfig/network-scripts/ifcfg-* ${TMP_PATH}/mdX/etc.defaults/sysconfig/network-scripts/ifcfg-*; do
        [ ! -e "${F}" ] && continue
        ETHX=$(echo "${F}" | sed -E 's/.*ifcfg-(.*)$/\1/')
        case "${ETHX}" in
        ovs_bond*)
          rm -f "${F}"
          ;;
        ovs_eth*)
          ovs-vsctl del-br ${ETHX}
          sed -i "/${ETHX##ovs_}/"d ${TMP_PATH}/mdX/usr/syno/etc/synoovs/ovs_interface.conf
          rm -f "${F}"
          ;;
        eth*)
          echo -e "DEVICE=${ETHX}\nONBOOT=yes\nBOOTPROTO=dhcp\nIPV6INIT=auto_dhcp\nIPV6_ACCEPT_RA=1" >"${F}"
          ;;
        *) ;;
        esac
      done
      sed -i 's/_mtu=".*"$/_mtu="1500"/g' ${TMP_PATH}/mdX/etc/synoinfo.conf ${TMP_PATH}/mdX/etc.defaults/synoinfo.conf
      # systemctl restart rc-network.service
      sync
      echo "true" >"${TMP_PATH}/isOk"
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX"
  ) 2>&1 | DIALOG --title "$(TEXT "Advanced")" \
    --progressbox "$(TEXT "Recovering ...")" 20 100
  [ -f "${TMP_PATH}/isOk" ] &&
    MSG="$(TEXT "Initialize DSM network settings completed.")" ||
    MSG="$(TEXT "Initialize DSM network settings failed.")"
  DIALOG --title "$(TEXT "Advanced")" \
    --msgbox "${MSG}" 0 0
  return 0
}

###############################################################################
# Choose a language
function languageMenu() {
  rm -f "${TMP_PATH}/menu"
  while read -r L; do
    A="$(echo "$(strings "${WORK_PATH}/lang/${L}/LC_MESSAGES/rr.mo" 2>/dev/null | grep "Last-Translator" | sed "s/Last-Translator://")")"
    echo "${L} \"${A:-"anonymous"}\"" >>"${TMP_PATH}/menu"
  done <<<"$(ls ${WORK_PATH}/lang/*/LC_MESSAGES/rr.mo 2>/dev/null | sort | sed -E 's/.*\/lang\/(.*)\/LC_MESSAGES\/rr\.mo$/\1/')"

  VAL=""
  [ -n "${1%%.*}" ] && grep -qw "${1%%.*}" "${TMP_PATH}/menu" && VAL="${1%%.*}"
  DIALOG --err "${VAL}" --title "$(TEXT "Settings")" \
    --default-item "${LAYOUT}" --menu "$(TEXT "Choose a language")" 0 0 20 --file "${TMP_PATH}/menu" \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
  [ -z "${resp}" ] && return 1
  LANGUAGE="${resp}"
  echo "${LANGUAGE}.UTF-8" >"${PART1_PATH}/.locale"
  export LC_ALL="${LANGUAGE}.UTF-8"
}

###############################################################################
# Choose a timezone
function timezoneMenu() {
  OPTIONS="$(find /usr/share/zoneinfo/right -type f | cut -d'/' -f6- | sort | uniq | xargs)"

  VAL=""
  [ -n "${1}" ] && echo "${OPTIONS}" | grep -qw "${1}" && VAL="${1}"
  DIALOG --err "${VAL}" --title "$(TEXT "Settings")" \
    --default-item "${LAYOUT}" --no-items --menu "$(TEXT "Choose a timezone")" 0 0 20 ${OPTIONS} \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
  [ -z "${resp}" ] && return 1
  TIMEZONE="${resp}"
  echo "${TIMEZONE}" >"${PART1_PATH}/.timezone"
  ln -sf "/usr/share/zoneinfo/right/${TIMEZONE}" /etc/localtime
}

###############################################################################
# Choose a keymap
function keymapMenu() {
  OPTIONS="$(find /usr/share/keymaps/i386/ -maxdepth 2 -type f -name "*.map.gz" | sed 's|/usr/share/keymaps/i386/||; s|\.map\.gz$||' | grep -v "include" | sort)"

  VAL=""
  [ -n "${1}" ] && echo "${OPTIONS}" | grep -qw "${1}" && VAL="${1}"
  DIALOG --err "${VAL}" --title "$(TEXT "Settings")" \
    --default-item "${LAYOUT}/${KEYMAP}" --no-items --menu "$(TEXT "Choose a layout/keymap")" 0 0 20 ${OPTIONS} \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
  [ -z "${resp}" ] && return 1
  LAYOUT="${resp%%/*}"
  KEYMAP="${resp##*/}"
  writeConfigKey "layout" "${LAYOUT}" "${USER_CONFIG_FILE}"
  writeConfigKey "keymap" "${KEYMAP}" "${USER_CONFIG_FILE}"
  loadkeys "/usr/share/keymaps/i386/${LAYOUT}/${KEYMAP}.map.gz"
}

###############################################################################
# Bootloader notifications (Webhook)
function notificationsMenu() {
  MSG=""
  MSG+="$(TEXT "Please enter the webhook url and content text.\n")"
  MSG+="$(TEXT "The webhook url must be a valid URL (Reference https://webhook-test.com/).\n")"
  MSG+="$(TEXT "The notify text is not currently supported, please ignore.\n")"
  WEBHOOKURL="$(readConfigKey "webhookurl" "${USER_CONFIG_FILE}")"
  # NOTIFYTEXT="$(readConfigKey "notifytext" "${USER_CONFIG_FILE}")"
  while true; do
    DIALOG --title "$(TEXT "Settings")" \
      --extra-button --extra-label "$(TEXT "Test")" \
      --form "${MSG}" 10 110 2 "webhookurl" 1 1 "${WEBHOOKURL}" 1 12 93 0 "notifytext" 2 1 "${NOTIFYTEXT}" 2 12 93 0 \
      2>"${TMP_PATH}/resp"
    RET=$?
    case ${RET} in
    0)
      # ok-button
      WEBHOOKURL="$(sed -n '1p' "${TMP_PATH}/resp" 2>/dev/null)"
      # NOTIFYTEXT="$(sed -n '2p' "${TMP_PATH}/resp" 2>/dev/null)"
      writeConfigKey "webhookurl" "${WEBHOOKURL}" "${USER_CONFIG_FILE}"
      # writeConfigKey "notifytext" "${NOTIFYTEXT}" "${USER_CONFIG_FILE}"
      break
      ;;
    3)
      # extra-button
      WEBHOOKURL="$(sed -n '1p' "${TMP_PATH}/resp" 2>/dev/null)"
      # NOTIFYTEXT="$(sed -n '2p' "${TMP_PATH}/resp" 2>/dev/null)"
      sendWebhook "${WEBHOOKURL}"
      ;;
    1)
      # cancel-button
      break
      ;;
    255)
      # ESC
      break
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
    dos2unix "${USER_CONFIG_FILE}" >/dev/null 2>&1 || true
    ERRORS=$(checkConfigFile "${USER_CONFIG_FILE}")
    [ $? -eq 0 ] && break
    DIALOG --title "$(TEXT "Settings")" \
      --msgbox "${ERRORS}" 0 0
  done
  OLDMODEL=${MODEL}
  OLDPRODUCTVER=${PRODUCTVER}
  OLDBUILDNUM=${BUILDNUM}
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
  SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"

  if [ "${MODEL}" != "${OLDMODEL}" ] || [ "${PRODUCTVER}" != "${OLDPRODUCTVER}" ] || [ "${BUILDNUM}" != "${OLDBUILDNUM}" ]; then
    # Remove old files
    rm -f "${MOD_ZIMAGE_FILE}"
    rm -f "${MOD_RDGZ_FILE}"
  fi
  touch "${PART1_PATH}/.build"
}

###############################################################################
# Permits user edit the grub.cfg
function editGrubCfg() {
  while true; do
    DIALOG --title "$(TEXT "Edit with caution")" \
      --editbox "${USER_GRUB_CONFIG}" 0 0 2>"${TMP_PATH}/usergrub.cfg"
    [ $? -ne 0 ] && return 1
    mv -f "${TMP_PATH}/usergrub.cfg" "${USER_GRUB_CONFIG}"
    dos2unix "${USER_GRUB_CONFIG}" >/dev/null 2>&1 || true
    break
  done
}

###############################################################################
# Try to recover a DSM already installed
function tryRecoveryDSM() {
  DIALOG --title "$(TEXT "Settings")" \
    --infobox "$(TEXT "Trying to recover an installed DSM system ...")" 0 0
  DSMROOTS="$(findDSMRoot)"
  DSMROOTPART="$(echo "${DSMROOTS}" | head -n 1 | cut -d' ' -f1)"
  if [ -z "${DSMROOTPART}" ]; then
    DIALOG --title "$(TEXT "Settings")" \
      --msgbox "$(TEXT "No DSM system partition(md0) found!\nPlease insert all disks before continuing.")" 0 0
    return 1
  fi

  mkdir -p "${TMP_PATH}/mdX"
  fixDSMRootPart "${DSMROOTPART}"
  T="$(blkid -o value -s TYPE "${DSMROOTPART}" 2>/dev/null | sed 's/linux_raid_member/ext4/')"
  mount -t "${T:-ext4}" "${DSMROOTPART}" "${TMP_PATH}/mdX"
  if [ $? -ne 0 ]; then
    DIALOG --title "$(TEXT "Settings")" \
      --msgbox "$(TEXT "Mount DSM system partition(md0) failed!\nPlease insert all disks before continuing.")" 0 0
    rm -rf "${TMP_PATH}/mdX"
    return 1
  fi

  function __umountDSMRootDisk() {
    umount "${TMP_PATH}/mdX"
    rm -rf "${TMP_PATH}/mdX"
  }

  DIALOG --title "$(TEXT "Settings")" \
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
      cp -rf "${TMP_PATH}/mdX/usr/rr/backup/p1/"* "${PART1_PATH}"
      if [ -d "${TMP_PATH}/mdX/usr/rr/backup/p3" ]; then
        cp -rf "${TMP_PATH}/mdX/usr/rr/backup/p3/"* "${PART3_PATH}"
      fi
      copyDSMFiles "${TMP_PATH}/mdX/.syno/patch"
      __umountDSMRootDisk
      DIALOG --title "$(TEXT "Settings")" \
        --msgbox "$(TEXT "Found a backup of the user's configuration, and restored it. Please rebuild and boot.")" 0 0
      touch "${PART1_PATH}/.upgraded"
      touch "${PART1_PATH}/.build"
      exec "${0}"
      return 0
    fi
  fi

  DIALOG --title "$(TEXT "Settings")" \
    --infobox "$(TEXT "Checking for installed DSM system ...")" 0 0

  setConfigFromDSM "${TMP_PATH}/mdX/.syno/patch"
  if [ $? -ne 0 ]; then
    __umountDSMRootDisk
    DIALOG --title "$(TEXT "Settings")" \
      --msgbox "$(TEXT "The installed DSM system was not found, or the system is damaged and cannot be recovered. Please reselect model and build.")" 0 0
    return 1
  fi

  if [ -f "${TMP_PATH}/mdX/etc.defaults/synoinfo.conf" ]; then
    R_SN="$(_get_conf_kv "${TMP_PATH}/mdX/etc.defaults/synoinfo.conf" "SN")"
    [ -n "${R_SN}" ] && SN=${R_SN} && writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
  fi

  writeConfigKey "paturl" "#RECOVERY" "${USER_CONFIG_FILE}"
  writeConfigKey "patsum" "#RECOVERY" "${USER_CONFIG_FILE}"

  copyDSMFiles "${TMP_PATH}/mdX/.syno/patch"
  __umountDSMRootDisk
  DIALOG --title "$(TEXT "Settings")" \
    --msgbox "$(TEXT "Found an installed DSM system and restored it. Please rebuild and boot.")" 0 0

  return 0
}

###############################################################################
# Clone bootloader disk
function cloneBootloaderDisk() {
  rm -f "${TMP_PATH}/opts"
  while read -r KNAME ID SIZE PKNAME; do
    [ "${KNAME}" = "N/A" ] || [ "${SIZE:0:1}" = "0" ] && continue
    [ "${KNAME}" = "${LOADER_DISK}" ] || [ "${PKNAME}" = "${LOADER_DISK}" ] && continue
    printf "\"%s\" \"%-6s %s\" \"off\"\n" "${KNAME}" "${SIZE}" "${ID}" >>"${TMP_PATH}/opts"
  done <<<"$(lsblk -Jdpno KNAME,ID,SIZE,PKNAME 2>/dev/null | sed 's|null|"N/A"|g' | jq -r '.blockdevices[] | "\(.kname) \(.id) \(.size) \(.pkname)"' 2>/dev/null | sort)"

  if [ ! -f "${TMP_PATH}/opts" ]; then
    DIALOG --title "$(TEXT "Settings")" \
      --msgbox "$(TEXT "No disk found!")" 0 0
    return 1
  fi

  VAL=""
  [ -n "${1}" ] && grep -qw "${1}" "${TMP_PATH}/opts" && VAL="${1}"
  DIALOG --err "${VAL}" --title "$(TEXT "Settings")" \
    --radiolist "$(TEXT "Choose a disk to clone to")" 0 0 0 --file "${TMP_PATH}/opts" \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"

  if [ -z "${resp}" ]; then
    DIALOG --title "$(TEXT "Settings")" \
      --msgbox "$(TEXT "No disk selected!")" 0 0
    return 1
  fi
  TODESK="${resp}"
  SIZE=$(df -m "${TODESK}" 2>/dev/null | awk 'NR==2 {print $2}')
  if [ ${SIZE:-0} -lt 1536 ]; then
    DIALOG --title "$(TEXT "Settings")" \
      --msgbox "$(printf "$(TEXT "Disk %s size is less than 2GB and cannot be cloned!")" "${TODESK}")" 0 0
    return 1
  fi

  MSG="$(printf "$(TEXT "Warning:\nDisk %s will be formatted and written to the bootloader. Please confirm that important data has been backed up. \nDo you want to continue?")" "${TODESK}")"
  DIALOG --ret 0 --title "$(TEXT "Settings")" \
    --yesno "${MSG}" 0 0
  [ $? -ne 0 ] && return 1

  while true; do
    rm -f "${LOG_FILE}"
    rm -rf "${PART3_PATH}/dl"
    CLEARCACHE=0

    gzip -dc "${WORK_PATH}/grub.img.gz" | dd of="${TODESK}" bs=1M conv=fsync status=progress
    hdparm -z "${TODESK}" # reset disk cache
    fdisk -l "${TODESK}"
    sleep 1

    NEW_BLDISK_P1="$(blkid | grep -v "${LOADER_DISK_PART1}:" | awk -F: '/LABEL="RR1"/ {print $1}')"
    NEW_BLDISK_P2="$(blkid | grep -v "${LOADER_DISK_PART2}:" | awk -F: '/LABEL="RR2"/ {print $1}')"
    NEW_BLDISK_P3="$(blkid | grep -v "${LOADER_DISK_PART3}:" | awk -F: '/LABEL="RR3"/ {print $1}')"
    SIZEOFDISK=$(blockdev --getsz "${TODESK}" 2>/dev/null) # SIZEOFDISK=$(cat /sys/block/${TODESK/\/dev\//}/size)
    ENDSECTOR=$(fdisk -l "${TODESK}" | grep "${NEW_BLDISK_P3}" | awk '{print $(NF-4)}')
    if [ ${SIZEOFDISK:-0} -ne $((${ENDSECTOR:-0} + 1)) ]; then
      if [ -f "/mnt/p1/.noresize" ] || [ ${SIZEOFDISK:-0} -gt $((32 * 1024 * 1024 * 2)) ]; then
        # Create partition 4 with remaining space
        echo -e "\033[1;36mCreating partition 4 with remaining space.\033[0m"
        echo -e "n\n\n\n\n\nw" | fdisk "${TODESK}" >/dev/null 2>&1
        PART4="${TODESK}4"
        mkfs.ext4 -F "${PART4}" # mkfs.ext4 -F -L "RR4" "${PART4}"
      else
        echo -e "\033[1;36mResizing ${NEW_BLDISK_P3}\033[0m"
        echo -e "d\n\nn\n\n\n\n\nn\nw" | fdisk "${TODESK}" >/dev/null 2>&1
        resize2fs "${NEW_BLDISK_P3}"
        fdisk -l "${TODESK}"
      fi
    fi

    function __umountNewBlDisk() {
      umount "${TMP_PATH}/sdX1" 2>/dev/null
      umount "${TMP_PATH}/sdX2" 2>/dev/null
      umount "${TMP_PATH}/sdX3" 2>/dev/null
    }

    for i in {1..3}; do
      rm -rf "${TMP_PATH}/sdX${i}"
      mkdir -p "${TMP_PATH}/sdX${i}"
      PART_NAME="$(eval "echo \${NEW_BLDISK_P${i}}")"
      mount "${PART_NAME}" "${TMP_PATH}/sdX${i}" || {
        printf "$(TEXT "Can't mount %s.")" "${PART_NAME}" >"${LOG_FILE}"
        __umountNewBlDisk
        break 2
      }
    done

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
      break 1
    fi
    for i in {1..3}; do
      PART_NAME="$(eval "echo \${PART${i}_PATH}")"
      cp -vrf "${PART_NAME}/". "${TMP_PATH}/sdX${i}/" || {
        PART_NAME="$(eval "echo \${NEW_BLDISK_P${i}}")"
        printf "$(TEXT "Can't copy to %s.")" "${PART_NAME}" >"${LOG_FILE}"
        __umountNewBlDisk
        break 2
      }
    done
    sync
    __umountNewBlDisk
    sleep 3
    break
  done 2>&1 | DIALOG --title "$(TEXT "Settings")" \
    --progressbox "$(TEXT "Cloning ...")" 20 100

  if [ -f "${LOG_FILE}" ]; then
    DIALOG --title "$(TEXT "Settings")" \
      --msgbox "$(cat "${LOG_FILE}")" 0 0
  else
    DIALOG --title "$(TEXT "Settings")" \
      --msgbox "$(printf "$(TEXT "Bootloader has been cloned to disk %s, please remove the current bootloader disk!\nReboot?")" "${TODESK}")" 0 0
    rebootTo config
  fi
  return 0
}

###############################################################################
# System Environment Report
function systemReport() {
  data="$(inxi -c 0 -F 2>/dev/null)"

  DIALOG --ret 0 --title "$(TEXT "Settings")" \
    --yes-label "$(TEXT "Download")" --no-label "$(TEXT "Cancel")" \
    --yesno "${data}" 0 0
  [ $? -ne 0 ] && return 1

  inxi -c 0 -F >"${TMP_PATH}/system.txt" 2>/dev/null
  if [ -z "${SSH_TTY}" ]; then # web
    mv -f "${TMP_PATH}/system.txt" "/var/www/data/system.txt"
    HTTP=$(grep -i '^HTTP_PORT=' /etc/rrorg.conf 2>/dev/null | cut -d'=' -f2)
    URL="http://$(getIP):${HTTP:-7080}/system.txt"
    MSG="$(printf "$(TEXT "Please via %s to download the system.txt.")" "${URL}")"
    DIALOG --title "$(TEXT "Settings")" \
      --msgbox "${MSG}" 0 0
  else
    sz -be -B 536870912 "${TMP_PATH}/system.txt"
  fi
  return 0
}

###############################################################################
# Report bugs to the author
function reportBugs() {
  rm -rf "${TMP_PATH}/logs" "${TMP_PATH}/logs.tar.gz"
  MSG=""
  FLAG_SYSLOG=0
  DSMROOTS="$(findDSMRoot)"
  if [ -n "${DSMROOTS}" ]; then
    mkdir -p "${TMP_PATH}/mdX"
    for I in ${DSMROOTS}; do
      fixDSMRootPart "${I}"
      T="$(blkid -o value -s TYPE "${I}" 2>/dev/null | sed 's/linux_raid_member/ext4/')"
      mount -t "${T:-ext4}" "${I}" "${TMP_PATH}/mdX"
      [ $? -ne 0 ] && continue
      mkdir -p "${TMP_PATH}/logs/md0/log"
      cp -rf ${TMP_PATH}/mdX/.log.junior "${TMP_PATH}/logs/md0" 2>/dev/null
      cp -rf ${TMP_PATH}/mdX/var/log/messages ${TMP_PATH}/mdX/var/log/*.log "${TMP_PATH}/logs/md0/log" 2>/dev/null
      FLAG_SYSLOG=1
      umount "${TMP_PATH}/mdX"
    done
    rm -rf "${TMP_PATH}/mdX"
  fi
  MSG+=$([ ${FLAG_SYSLOG} -eq 1 ] && echo "$(TEXT "Find the system logs!\n")" || echo "$(TEXT "Not Find system logs!\n")")

  FLAG_PSTORE=0
  if [ -n "$(ls /sys/fs/pstore 2>/dev/null)" ]; then
    mkdir -p "${TMP_PATH}/logs/pstore"
    cp -rf /sys/fs/pstore/* "${TMP_PATH}/logs/pstore" 2>/dev/null
    [ -n "$(ls /sys/fs/pstore/*.z 2>/dev/null)" ] && zlib-flate -uncompress </sys/fs/pstore/*.z >"${TMP_PATH}/logs/pstore/ps.log" 2>/dev/null
    FLAG_PSTORE=1
  fi
  MSG+=$([ ${FLAG_PSTORE} -eq 1 ] && echo "$(TEXT "Find the pstore logs!\n")" || echo "$(TEXT "Not Find pstore logs!\n")")

  FLAG_ADDONS=0
  if [ -d "${PART1_PATH}/logs" ]; then
    mkdir -p "${TMP_PATH}/logs/addons"
    cp -rf "${PART1_PATH}/logs"/* "${TMP_PATH}/logs/addons" 2>/dev/null
    FLAG_ADDONS=1
  fi
  if [ ${FLAG_ADDONS} -eq 1 ]; then
    MSG+="$(TEXT "Find the addons logs!\n")"
  else
    MSG+="$(TEXT "Not Find addons logs!\n")"
    MSG+="$(TEXT "Please do as follows:\n")"
    MSG+="$(TEXT " 1. Add dbgutils in addons and rebuild.\n")"
    MSG+="$(TEXT " 2. Wait 10 minutes after booting.\n")"
    MSG+="$(TEXT " 3. Reboot into RR and go to this option.\n")"
  fi

  if [ -n "$(ls -A ${TMP_PATH}/logs 2>/dev/null)" ]; then
    cp -f "${USER_CONFIG_FILE}" "${TMP_PATH}/logs/user-config.yml" 2>/dev/null
    sed -i "s/^sn:.*/sn: \"\*\*\*\*\*\*\*\*\*\*\*\*\*\"/g" "${TMP_PATH}/logs/user-config.yml"
    sed -i "s/^mac1:.*/mac1: \"\*\*\*\*\*\*\*\*\*\*\*\*\"/g" "${TMP_PATH}/logs/user-config.yml"
    sed -i "s/^mac2:.*/mac2: \"\*\*\*\*\*\*\*\*\*\*\*\*\"/g" "${TMP_PATH}/logs/user-config.yml"
    inxi -c 0 -F >"${TMP_PATH}/logs/system.txt" 2>/dev/null
    tar -czf "${TMP_PATH}/logs.tar.gz" -C "${TMP_PATH}" logs
    if [ -z "${SSH_TTY}" ]; then # web
      mv -f "${TMP_PATH}/logs.tar.gz" "/var/www/data/logs.tar.gz"
      HTTP=$(grep -i '^HTTP_PORT=' /etc/rrorg.conf 2>/dev/null | cut -d'=' -f2)
      URL="http://$(getIP):${HTTP:-7080}/logs.tar.gz"
      MSG+="$(printf "$(TEXT "Please via %s to download the logs,\nAnd go to github to create an issue and upload the logs.\n")" "${URL}")"
    else
      sz -be -B 536870912 "${TMP_PATH}/logs.tar.gz"
      MSG+="$(TEXT "Please go to github to create an issue and upload the logs.\n")"
    fi
  fi
  DIALOG --title "$(TEXT "Settings")" \
    --msgbox "${MSG}" 0 0
}

###############################################################################
# Install development tools
function InstallDevTools() {
  DIALOG --ret 0 --title "$(TEXT "Settings")" \
    --yesno "$(TEXT "This option only installs opkg package management, allowing you to install more tools for use and debugging. Do you want to continue?")" 0 0
  [ $? -ne 0 ] && return 1
  rm -f "${LOG_FILE}"
  while true; do
    wget http://bin.entware.net/x64-k3.2/installer/generic.sh -O "${TMP_PATH}/generic.sh" >"${LOG_FILE}"
    [ $? -ne 0 ] || [ ! -f "${TMP_PATH}/generic.sh" ] && break
    chmod +x "${TMP_PATH}/generic.sh"
    ${TMP_PATH}/generic.sh 2>"${LOG_FILE}"
    [ $? -ne 0 ] && break
    opkg update 2>"${LOG_FILE}"
    [ $? -ne 0 ] && break
    rm -f "${TMP_PATH}/generic.sh" "${LOG_FILE}"
    break
  done 2>&1 | DIALOG --title "$(TEXT "Settings")" \
    --progressbox "$(TEXT "opkg installing ...")" 20 100
  MSG=$([ -f "${LOG_FILE}" ] && printf "%s\n%s:\n%s\n" "$(TEXT "opkg install failed.")" "$(TEXT "Error")" "$(cat "${DTC_ERRLOG}")" || echo "$(TEXT "opkg install complete.")")
  DIALOG --title "$(TEXT "Settings")" \
    --msgbox "${MSG}" 0 0
  return 0
}

###############################################################################
# Save modifications of '/opt/rr'
function savemodrr() {
  DIALOG --ret 0 --title "$(TEXT "Settings")" \
    --yesno "$(TEXT "Warning:\nDo not terminate midway, otherwise it may cause damage to the RR. Do you want to continue?")" 0 0
  [ $? -ne 0 ] && return 1

  DIALOG --title "$(TEXT "Settings")" \
    --infobox "$(TEXT "Saving ...\n(It usually takes 5-10 minutes, please be patient and wait.)")" 0 0
  RDXZ_PATH="${TMP_PATH}/rdxz_tmp"
  rm -rf "${RDXZ_PATH}"
  mkdir -p "${RDXZ_PATH}"
  INITRD_FORMAT=$(file -b --mime-type "${RR_RAMDISK_FILE}")

  case "${INITRD_FORMAT}" in
  *'x-cpio'*) (cd "${RDXZ_PATH}" && cpio -idm <"${RR_RAMDISK_FILE}") >/dev/null 2>&1 ;;
  *'x-xz'*) (cd "${RDXZ_PATH}" && xz -dc "${RR_RAMDISK_FILE}" | cpio -idm) >/dev/null 2>&1 ;;
  *'x-lz4'*) (cd "${RDXZ_PATH}" && lz4 -dc "${RR_RAMDISK_FILE}" | cpio -idm) >/dev/null 2>&1 ;;
  *'x-lzma'*) (cd "${RDXZ_PATH}" && lzma -dc "${RR_RAMDISK_FILE}" | cpio -idm) >/dev/null 2>&1 ;;
  *'x-bzip2'*) (cd "${RDXZ_PATH}" && bzip2 -dc "${RR_RAMDISK_FILE}" | cpio -idm) >/dev/null 2>&1 ;;
  *'gzip'*) (cd "${RDXZ_PATH}" && gzip -dc "${RR_RAMDISK_FILE}" | cpio -idm) >/dev/null 2>&1 ;;
  *'zstd'*) (cd "${RDXZ_PATH}" && zstd -dc "${RR_RAMDISK_FILE}" | cpio -idm) >/dev/null 2>&1 ;;
  *) ;;
  esac

  if [ -z "$(ls -A "$RDXZ_PATH")" ]; then
    DIALOG --title "$(TEXT "Settings")" \
      --msgbox "$(TEXT "initrd-rr file format error!")" 0 0
    return 1
  fi
  rm -rf "${RDXZ_PATH}/opt/rr"
  cp -rpf "$(dirname "${WORK_PATH}")" "${RDXZ_PATH}/" 2>/dev/null
  cp -apf "/root/"{.bashrc,.dialogrc} "${RDXZ_PATH}/root/" 2>/dev/null

  RDSIZE=$(du -sb "${RDXZ_PATH}" 2>/dev/null | awk '{print $1}')
  case "${INITRD_FORMAT}" in
  *'x-cpio'*) (cd "${RDXZ_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root >"${RR_RAMDISK_FILE}") >/dev/null 2>&1 ;;
  *'x-xz'*) (cd "${RDXZ_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root | xz -9 -C crc32 -c - >"${RR_RAMDISK_FILE}") >/dev/null 2>&1 ;;
  *'x-lz4'*) (cd "${RDXZ_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root | lz4 -9 -l -c - >"${RR_RAMDISK_FILE}") >/dev/null 2>&1 ;;
  *'x-lzma'*) (cd "${RDXZ_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root | lzma -9 -c - >"${RR_RAMDISK_FILE}") >/dev/null 2>&1 ;;
  *'x-bzip2'*) (cd "${RDXZ_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root | bzip2 -9 -c - >"${RR_RAMDISK_FILE}") >/dev/null 2>&1 ;;
  *'gzip'*) (cd "${RDXZ_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root | gzip -9 -c - >"${RR_RAMDISK_FILE}") >/dev/null 2>&1 ;;
  *'zstd'*) (cd "${RDXZ_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root | zstd -19 -T0 -f -c - >"${RR_RAMDISK_FILE}") >/dev/null 2>&1 ;;
  *) ;;
  esac

  rm -rf "${RDXZ_PATH}"
  DIALOG --title "$(TEXT "Settings")" \
    --msgbox "$(TEXT "Save is complete.")" 0 0
  return 0
}

###############################################################################
# Set static IP
function setStaticIP() {
  ETHX="$(find /sys/class/net/ -mindepth 1 -maxdepth 1 ! -name lo -exec basename {} \; | sort)"
  for N in ${ETHX}; do
    MACR="$(cat "/sys/class/net/${N}/address" 2>/dev/null | sed 's/://g')"
    IPR="$(readConfigKey "network.${MACR}" "${USER_CONFIG_FILE}")"
    IFS='/' read -r -a IPRA <<<"${IPR}"

    MSG="$(printf "$(TEXT "Set to %s: (Delete if empty)")" "${N}(${MACR})")"
    while true; do
      DIALOG --title "$(TEXT "Settings")" \
        --form "${MSG}" 10 60 4 "address" 1 1 "${IPRA[0]}" 1 9 36 16 "netmask" 2 1 "${IPRA[1]}" 2 9 36 16 "gateway" 3 1 "${IPRA[2]}" 3 9 36 16 "dns" 4 1 "${IPRA[3]}" 4 9 36 16 \
        2>"${TMP_PATH}/resp"
      RET=$?
      case ${RET} in
      0)
        # ok-button
        address="$(sed -n '1p' "${TMP_PATH}/resp" 2>/dev/null)"
        netmask="$(sed -n '2p' "${TMP_PATH}/resp" 2>/dev/null)"
        gateway="$(sed -n '3p' "${TMP_PATH}/resp" 2>/dev/null)"
        dnsname="$(sed -n '4p' "${TMP_PATH}/resp" 2>/dev/null)"
        (
          if [ -z "${address}" ]; then
            if [ -n "$(readConfigKey "network.${MACR}" "${USER_CONFIG_FILE}")" ]; then
              if [ "1" = "$(cat "/sys/class/net/${N}/carrier" 2>/dev/null)" ]; then
                ip addr flush dev ${N}
              fi
              deleteConfigKey "network.${MACR}" "${USER_CONFIG_FILE}"
              IP="$(getIP)"
              sleep 1
            fi
          else
            if [ "1" = "$(cat "/sys/class/net/${N}/carrier" 2>/dev/null)" ]; then
              ip addr flush dev ${N}
              ip addr add ${address}/${netmask:-"255.255.255.0"} dev ${N}
              if [ -n "${gateway}" ]; then
                ip route add default via ${gateway} dev ${N}
              fi
              if [ -n "${dnsname:-${gateway}}" ]; then
                sed -i "/nameserver ${dnsname:-${gateway}}/d" /etc/resolv.conf
                echo "nameserver ${dnsname:-${gateway}}" >>/etc/resolv.conf
              fi
            fi
            writeConfigKey "network.${MACR}" "${address}/${netmask}/${gateway}/${dnsname}" "${USER_CONFIG_FILE}"
            IP="$(getIP)"
            sleep 1
          fi
          touch "${PART1_PATH}/.build"
        ) 2>&1 | DIALOG --title "$(TEXT "Settings")" \
          --progressbox "$(TEXT "Setting ...")" 20 100
        break
        ;;
      1)
        # cancel-button
        break
        ;;
      255)
        # ESC
        break 2
        ;;
      esac
    done
  done
}

###############################################################################
# Set wireless account
function setWirelessAccount() {
  DIALOG --title "$(TEXT "Settings")" \
    --infobox "$(TEXT "Scanning ...")" 0 0
  MSG=""
  MSG+="$(TEXT "Scanned SSIDs:\n")"
  for I in $(iw wlan0 scan 2>/dev/null | grep SSID: | awk '{print $2}'); do MSG+="${I}\n"; done
  LINENUM=$(($(echo -e "${MSG}" | wc -l) + 8))
  while true; do
    SSID="$(cat "${PART1_PATH}/wpa_supplicant.conf" 2>/dev/null | grep 'ssid=' | cut -d'=' -f2 | sed 's/^"//; s/"$//')"
    PSK="$(cat "${PART1_PATH}/wpa_supplicant.conf" 2>/dev/null | grep 'psk=' | cut -d'=' -f2 | sed 's/^"//; s/"$//')"
    DIALOG --title "$(TEXT "Settings")" \
      --form "${MSG}" ${LINENUM:-16} 70 2 "SSID" 1 1 "${SSID}" 1 7 58 0 " PSK" 2 1 "${PSK}" 2 7 58 0 \
      2>"${TMP_PATH}/resp"
    RET=$?
    case ${RET} in
    0)
      # ok-button
      SSID="$(sed -n '1p' "${TMP_PATH}/resp" 2>/dev/null)"
      PSK="$(sed -n '2p' "${TMP_PATH}/resp" 2>/dev/null)"
      (
        ETHX=$(ls /sys/class/net/ 2>/dev/null | grep wlan) || true
        if [ -z "${SSID}" ]; then
          rm -f "${PART1_PATH}/wpa_supplicant.conf"
          for N in ${ETHX}; do
            connectwlanif "${N}" 0 && sleep 1
          done
        else
          echo -e "ctrl_interface=/var/run/wpa_supplicant\nupdate_config=1\nnetwork={\n        ssid=\"${SSID}\"\n        priority=1\n        psk=\"${PSK}\"\n}" >"${PART1_PATH}/wpa_supplicant.conf"
          for N in ${ETHX}; do
            connectwlanif "${N}" 0 && sleep 1
            connectwlanif "${N}" 1 && sleep 1
            MACR="$(cat /sys/class/net/${N}/address 2>/dev/null | sed 's/://g')"
            IPR="$(readConfigKey "network.${MACR}" "${USER_CONFIG_FILE}")"
            if [ -n "${IPR}" ]; then
              ip addr add ${IPC}/24 dev ${N}
              sleep 1
            fi
          done
        fi
      ) 2>&1 | DIALOG --title "$(TEXT "Settings")" \
        --progressbox "$(TEXT "Setting ...")" 20 100
      break
      ;;
    1)
      # cancel-button
      break
      ;;
    255)
      # ESC
      break
      ;;
    esac
  done
  return 0
}

###############################################################################
# Set proxy
# $1 - KEY
function setProxy() {
  local RET=1
  resp="$(readConfigKey "${1}" "${USER_CONFIG_FILE}")"
  while true; do
    [ "${1}" = "global_proxy" ] && EG="http://192.168.1.1:7981/" || EG="https://mirror.ghproxy.com/"
    DIALOG --err "${2}" --title "$(TEXT "Settings")" \
      --inputbox "$(printf "$(TEXT "Please enter a proxy server url.(e.g., %s)")" "${EG}")" 0 70 "${resp}" \
      2>"${TMP_PATH}/resp"
    RET=$?
    [ ${RET} -ne 0 ] && break
    resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
    if [ -z "${resp}" ]; then
      break
    elif echo "${resp}" | grep -Eq "^(https?|socks5)://[^\s/$.?#].[^\s]*$"; then
      break
    else
      DIALOG --ret 0 --title "$(TEXT "Settings")" \
        --yesno "$(TEXT "Invalid proxy server url, continue?")" 0 0
      RET=$?
      [ ${RET} -eq 0 ] && break
    fi
  done
  [ ${RET} -ne 0 ] && return 1

  local PROXY="${resp}"
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
  return 0
}

###############################################################################
# Change root password
function createMicrocode() {
  rm -rf ${TMP_PATH}/kernel
  if [ -d /usr/lib/firmware/amd-ucode ]; then
    mkdir -p ${TMP_PATH}/kernel/x86/microcode
    cat /usr/lib/firmware/amd-ucode/microcode_amd*.bin >${TMP_PATH}/kernel/x86/microcode/AuthenticAMD.bin
  fi
  if [ -d /usr/lib/firmware/intel-ucode ]; then
    mkdir -p ${TMP_PATH}/kernel/x86/microcode
    cat /usr/lib/firmware/intel-ucode/* >${TMP_PATH}/kernel/x86/microcode/GenuineIntel.bin
  fi
  if [ -d ${TMP_PATH}/kernel/x86/microcode ]; then
    (cd ${TMP_PATH} && find kernel 2>/dev/null | cpio -o -H newc -R root:root >"${MC_RAMDISK_FILE}") >/dev/null 2>&1
  fi
}

###############################################################################
# Change root password
function changePassword() {
  DIALOG --title "$(TEXT "Settings")" \
    --inputbox "$(TEXT "New password: (Empty for default value 'rr')")" 0 70 \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  DIALOG --title "$(TEXT "Settings")" \
    --infobox "$(TEXT "Setting ...")" 20 100
  resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
  [ -z "${resp}" ] && return 1
  local STRPASSWD NEWPASSWD
  STRPASSWD="${resp}"
  # local NEWPASSWD="$(python3 -c "from passlib.hash import sha512_crypt;pw=\"${STRPASSWD:-rr}\";print(sha512_crypt.using(rounds=5000).hash(pw))")"
  # local NEWPASSWD="$(echo "${STRPASSWD:-rr}" | mkpasswd -m sha512)"
  NEWPASSWD="$(openssl passwd -6 -salt "$(openssl rand -hex 8)" "${STRPASSWD:-rr}")"
  cp -pf /etc/shadow /etc/shadow-
  sed -i "s|^root:[^:]*|root:${NEWPASSWD}|" /etc/shadow

  local RDXZ_PATH="${TMP_PATH}/rdxz_tmp"
  rm -rf "${RDXZ_PATH}"
  mkdir -p "${RDXZ_PATH}"
  local INITRD_FORMAT
  if [ -f "${RR_RAMUSER_FILE}" ]; then
    INITRD_FORMAT=$(file -b --mime-type "${RR_RAMUSER_FILE}")
    case "${INITRD_FORMAT}" in
    *'x-cpio'*) (cd "${RDXZ_PATH}" && cpio -idm <"${RR_RAMUSER_FILE}") >/dev/null 2>&1 ;;
    *'x-xz'*) (cd "${RDXZ_PATH}" && xz -dc "${RR_RAMUSER_FILE}" | cpio -idm) >/dev/null 2>&1 ;;
    *'x-lz4'*) (cd "${RDXZ_PATH}" && lz4 -dc "${RR_RAMUSER_FILE}" | cpio -idm) >/dev/null 2>&1 ;;
    *'x-lzma'*) (cd "${RDXZ_PATH}" && lzma -dc "${RR_RAMUSER_FILE}" | cpio -idm) >/dev/null 2>&1 ;;
    *'x-bzip2'*) (cd "${RDXZ_PATH}" && bzip2 -dc "${RR_RAMUSER_FILE}" | cpio -idm) >/dev/null 2>&1 ;;
    *'gzip'*) (cd "${RDXZ_PATH}" && gzip -dc "${RR_RAMUSER_FILE}" | cpio -idm) >/dev/null 2>&1 ;;
    *'zstd'*) (cd "${RDXZ_PATH}" && zstd -dc "${RR_RAMUSER_FILE}" | cpio -idm) >/dev/null 2>&1 ;;
    *) ;;
    esac
  else
    INITRD_FORMAT="application/zstd"
  fi

  if [ "${STRPASSWD:-rr}" = "rr" ]; then
    rm -f ${RDXZ_PATH}/etc/shadow* 2>/dev/null
  else
    mkdir -p "${RDXZ_PATH}/etc"
    cp -pf /etc/shadow* ${RDXZ_PATH}/etc && chown root:root ${RDXZ_PATH}/etc/shadow* && chmod 600 ${RDXZ_PATH}/etc/shadow*
  fi

  if [ -n "$(ls -A "${RDXZ_PATH}" 2>/dev/null)" ] && [ -n "$(ls -A "${RDXZ_PATH}/etc" 2>/dev/null)" ]; then
    # local RDSIZE=$(du -sb "${RDXZ_PATH}" 2>/dev/null | awk '{print $1}')
    case "${INITRD_FORMAT}" in
    *'x-cpio'*) (cd "${RDXZ_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root >"${RR_RAMUSER_FILE}") >/dev/null 2>&1 ;;
    *'x-xz'*) (cd "${RDXZ_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root | xz -9 -C crc32 -c - >"${RR_RAMUSER_FILE}") >/dev/null 2>&1 ;;
    *'x-lz4'*) (cd "${RDXZ_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root | lz4 -9 -l -c - >"${RR_RAMUSER_FILE}") >/dev/null 2>&1 ;;
    *'x-lzma'*) (cd "${RDXZ_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root | lzma -9 -c - >"${RR_RAMUSER_FILE}") >/dev/null 2>&1 ;;
    *'x-bzip2'*) (cd "${RDXZ_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root | bzip2 -9 -c - >"${RR_RAMUSER_FILE}") >/dev/null 2>&1 ;;
    *'gzip'*) (cd "${RDXZ_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root | gzip -9 -c - >"${RR_RAMUSER_FILE}") >/dev/null 2>&1 ;;
    *'zstd'*) (cd "${RDXZ_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root | zstd -19 -T0 -f -c - >"${RR_RAMUSER_FILE}") >/dev/null 2>&1 ;;
    *) ;;
    esac
  else
    rm -f "${RR_RAMUSER_FILE}"
  fi
  rm -rf "${RDXZ_PATH}"

  [ "${STRPASSWD:-rr}" = "rr" ] && MSG="$(TEXT "password for root restored.")" || MSG="$(TEXT "password for root changed.")"
  DIALOG --title "$(TEXT "Settings")" \
    --msgbox "${MSG}" 0 0
  return 0
}

###############################################################################
# Change ports of TTYD/DUFS/HTTP
function changePorts() {
  MSG="$(TEXT "Please fill in a number between 0-65535: (Empty for default value.)")"
  unset HTTP_PORT DUFS_PORT TTYD_PORT
  [ -f "/etc/rrorg.conf" ] && source "/etc/rrorg.conf" 2>/dev/null
  local HTTP=${HTTP_PORT:-7080}
  local DUFS=${DUFS_PORT:-7304}
  local TTYD=${TTYD_PORT:-7681}

  while true; do
    DIALOG --title "$(TEXT "Settings")" \
      --form "${MSG}" 11 70 3 "HTTP" 1 1 "${HTTP:-7080}" 1 10 55 0 "DUFS" 2 1 "${DUFS:-7304}" 2 10 55 0 "TTYD" 3 1 "${TTYD:-7681}" 3 10 55 0 \
      2>"${TMP_PATH}/resp"
    RET=$?
    case ${RET} in
    0)
      # ok-button
      function check_port() {
        if [ -z "${1}" ]; then
          return 0
        else
          if echo "${1}" | grep -Eq '^[0-9]+$' && [ "${1}" -ge 0 ] && [ "${1}" -le 65535 ]; then
            return 0
          else
            return 1
          fi
        fi
      }
      HTTP=$(sed -n '1p' "${TMP_PATH}/resp" 2>/dev/null)
      DUFS=$(sed -n '2p' "${TMP_PATH}/resp" 2>/dev/null)
      TTYD=$(sed -n '3p' "${TMP_PATH}/resp" 2>/dev/null)
      local EP=""
      for P in "${HTTP}" "${DUFS}" "${TTYD}"; do check_port "${P}" || EP="${EP} ${P}"; done
      if [ -n "${EP}" ]; then
        DIALOG --title "$(TEXT "Settings")" \
          --yesno "$(printf "$(TEXT "Invalid %s port number, retry?")" "${EP}")" 0 0
        [ $? -eq 0 ] && continue || break
      fi
      DIALOG --title "$(TEXT "Settings")" \
        --infobox "$(TEXT "Setting ...")" 20 100
      # save to rrorg.conf
      rm -f "/etc/rrorg.conf"
      [ ! "${HTTP:-7080}" = "7080" ] && echo "HTTP_PORT=${HTTP}" >>"/etc/rrorg.conf"
      [ ! "${DUFS:-7304}" = "7304" ] && echo "DUFS_PORT=${DUFS}" >>"/etc/rrorg.conf"
      [ ! "${TTYD:-7681}" = "7681" ] && echo "TTYD_PORT=${TTYD}" >>"/etc/rrorg.conf"
      # save to rru
      local RDXZ_PATH="${TMP_PATH}/rdxz_tmp"
      rm -rf "${RDXZ_PATH}"
      mkdir -p "${RDXZ_PATH}"
      local INITRD_FORMAT
      if [ -f "${RR_RAMUSER_FILE}" ]; then
        INITRD_FORMAT=$(file -b --mime-type "${RR_RAMUSER_FILE}")
        case "${INITRD_FORMAT}" in
        *'x-cpio'*) (cd "${RDXZ_PATH}" && cpio -idm <"${RR_RAMUSER_FILE}") >/dev/null 2>&1 ;;
        *'x-xz'*) (cd "${RDXZ_PATH}" && xz -dc "${RR_RAMUSER_FILE}" | cpio -idm) >/dev/null 2>&1 ;;
        *'x-lz4'*) (cd "${RDXZ_PATH}" && lz4 -dc "${RR_RAMUSER_FILE}" | cpio -idm) >/dev/null 2>&1 ;;
        *'x-lzma'*) (cd "${RDXZ_PATH}" && lzma -dc "${RR_RAMUSER_FILE}" | cpio -idm) >/dev/null 2>&1 ;;
        *'x-bzip2'*) (cd "${RDXZ_PATH}" && bzip2 -dc "${RR_RAMUSER_FILE}" | cpio -idm) >/dev/null 2>&1 ;;
        *'gzip'*) (cd "${RDXZ_PATH}" && gzip -dc "${RR_RAMUSER_FILE}" | cpio -idm) >/dev/null 2>&1 ;;
        *'zstd'*) (cd "${RDXZ_PATH}" && zstd -dc "${RR_RAMUSER_FILE}" | cpio -idm) >/dev/null 2>&1 ;;
        *) ;;
        esac
      else
        INITRD_FORMAT="application/zstd"
      fi
      if [ ! -f "/etc/rrorg.conf" ]; then
        rm -f "${RDXZ_PATH}/etc/rrorg.conf" 2>/dev/null
      else
        mkdir -p "${RDXZ_PATH}/etc"
        cp -pf /etc/rrorg.conf ${RDXZ_PATH}/etc
      fi
      if [ -n "$(ls -A "${RDXZ_PATH}" 2>/dev/null)" ] && [ -n "$(ls -A "${RDXZ_PATH}/etc" 2>/dev/null)" ]; then
        # local RDSIZE=$(du -sb "${RDXZ_PATH}" 2>/dev/null | awk '{print $1}')
        case "${INITRD_FORMAT}" in
        *'x-cpio'*) (cd "${RDXZ_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root >"${RR_RAMUSER_FILE}") >/dev/null 2>&1 ;;
        *'x-xz'*) (cd "${RDXZ_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root | xz -9 -C crc32 -c - >"${RR_RAMUSER_FILE}") >/dev/null 2>&1 ;;
        *'x-lz4'*) (cd "${RDXZ_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root | lz4 -9 -l -c - >"${RR_RAMUSER_FILE}") >/dev/null 2>&1 ;;
        *'x-lzma'*) (cd "${RDXZ_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root | lzma -9 -c - >"${RR_RAMUSER_FILE}") >/dev/null 2>&1 ;;
        *'x-bzip2'*) (cd "${RDXZ_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root | bzip2 -9 -c - >"${RR_RAMUSER_FILE}") >/dev/null 2>&1 ;;
        *'gzip'*) (cd "${RDXZ_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root | gzip -9 -c - >"${RR_RAMUSER_FILE}") >/dev/null 2>&1 ;;
        *'zstd'*) (cd "${RDXZ_PATH}" && find . 2>/dev/null | cpio -o -H newc -R root:root | zstd -19 -T0 -f -c - >"${RR_RAMUSER_FILE}") >/dev/null 2>&1 ;;
        *) ;;
        esac
      else
        rm -f "${RR_RAMUSER_FILE}"
      fi
      rm -rf "${RDXZ_PATH}"
      [ ! -f "/etc/rrorg.conf" ] && MSG="$(TEXT "Ports for TTYD/DUFS/HTTP restored.")" || MSG="$(TEXT "Ports for TTYD/DUFS/HTTP changed.")"
      DIALOG --title "$(TEXT "Settings")" \
        --msgbox "${MSG}" 0 0
      rm -f "${TMP_PATH}/restartS.sh"
      {
        [ ! "${HTTP:-7080}" = "${HTTP_PORT:-7080}" ] && echo "/etc/init.d/S90thttpd restart"
        [ ! "${DUFS:-7304}" = "${DUFS_PORT:-7304}" ] && echo "/etc/init.d/S99dufs restart"
        [ ! "${TTYD:-7681}" = "${TTYD_PORT:-7681}" ] && echo "/etc/init.d/S99ttyd restart"
      } >"${TMP_PATH}/restartS.sh"
      chmod +x "${TMP_PATH}/restartS.sh"
      nohup "${TMP_PATH}/restartS.sh" >/dev/null 2>&1
      break
      ;;
    1)
      # cancel-button
      break
      ;;
    255)
      # ESC
      break
      ;;
    esac
  done
  return 0
}

###############################################################################
# Advanced menu
function advancedMenu() {
  NEXT="l"
  while true; do
    rm -f "${TMP_PATH}/menu"
    {
      echo "c \"$(TEXT "DSM rd compression:") \Z4${RD_COMPRESSED}\Zn\""
      echo "l \"$(TEXT "Switch LKM version:") \Z4${LKM}\Zn\""
      echo "h \"$(TEXT "HDD sort(hotplug):") \Z4${HDDSORT}\Zn\""
      if [ -n "${PRODUCTVER}" ]; then
        echo "p \"$(TEXT "Show/modify the current pat data")\""
        echo "m \"$(TEXT "Switch SATADOM mode:") \Z4${SATADOM}\Zn\""
      fi
      if [ -n "${PLATFORM}" ]; then
        echo "d \"$(TEXT "Custom DTS")\""
        echo "u \"$(TEXT "USB disk as internal disk:") \Z4${USBASINTERNAL}\Zn\""
      fi
      AU=$(readConfigMap "addons" "${USER_CONFIG_FILE}" | grep -q "blockupdate" && echo "false" || echo "true")
      echo "j \"$(TEXT "DSM automatic update:") \Z4${AU}\Zn\""
      echo "w \"$(TEXT "Timeout of boot wait:") \Z4${BOOTWAIT}\Zn\""
      if [ "${DIRECTBOOT}" = "false" ]; then
        echo "i \"$(TEXT "Timeout of get IP in boot:") \Z4${BOOTIPWAIT}\Zn\""
        echo "k \"$(TEXT "Kernel switching method:") \Z4${KERNELWAY}\Zn\""
        # Some GPU have compatibility issues, so this function is temporarily disabled. RR_CMDLINE= ... nomodeset
        # checkCmdline "rr_cmdline" "nomodeset" && POWEROFFDISPLAY="false" || POWEROFFDISPLAY="true"
        # echo "v \"$(TEXT "Power off display after boot:") \Z4${POWEROFFDISPLAY}\Zn\""
      fi
      echo "n \"$(TEXT "Reboot on kernel panic:") \Z4${KERNELPANIC}\Zn\""
      if [ -n "$(ls /dev/mmcblk* 2>/dev/null)" ]; then
        echo "b \"$(TEXT "Use EMMC as the system disk:") \Z4${EMMCBOOT}\Zn\""
      fi
      echo "s \"$(TEXT "Show disks information")\""
      echo "t \"$(TEXT "Mounting DSM storage pool")\""
      echo "f \"$(TEXT "Format disk(s) # Without loader disk")\""
      echo "g \"$(TEXT "Download DSM config backup files")\""
      echo "a \"$(TEXT "Allow downgrade installation")\""
      echo "x \"$(TEXT "Reset DSM system password")\""
      echo "y \"$(TEXT "Add a new user to DSM system")\""
      echo "z \"$(TEXT "Force enable Telnet&SSH of DSM system")\""
      echo "o \"$(TEXT "Remove the blocked IP database of DSM")\""
      echo "q \"$(TEXT "Disable all scheduled tasks of DSM")\""
      echo "r \"$(TEXT "Initialize DSM network settings")\""
      echo "e \"$(TEXT "Exit")\""
    } >"${TMP_PATH}/menu"

    DIALOG --err "${1}" --title "$(TEXT "Advanced")" \
      --default-item "${NEXT}" --menu "$(TEXT "Advanced option")" 0 0 0 --file "${TMP_PATH}/menu" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break
    case "$(cat "${TMP_PATH}/resp" 2>/dev/null)" in
    c)
      RD_COMPRESSED=$([ "${RD_COMPRESSED}" = "true" ] && echo 'false' || echo 'true')
      writeConfigKey "rd-compressed" "${RD_COMPRESSED}" "${USER_CONFIG_FILE}"
      touch "${PART1_PATH}/.build"
      NEXT="c"
      ;;
    l)
      LKM=$([ "${LKM}" = "dev" ] && echo 'prod' || ([ "${LKM}" = "test" ] && echo 'dev' || echo 'test'))
      writeConfigKey "lkm" "${LKM}" "${USER_CONFIG_FILE}"
      touch "${PART1_PATH}/.build"
      NEXT="l"
      ;;
    h)
      HDDSORT=$([ "${HDDSORT}" = "true" ] && echo 'false' || echo 'true')
      writeConfigKey "hddsort" "${HDDSORT}" "${USER_CONFIG_FILE}"
      touch "${PART1_PATH}/.build"
      NEXT="h"
      ;;
    p)
      PATURL="$(readConfigKey "paturl" "${USER_CONFIG_FILE}")"
      PATSUM="$(readConfigKey "patsum" "${USER_CONFIG_FILE}")"
      MSG="$(TEXT "pat: (editable)")"
      DIALOG --title "$(TEXT "Advanced")" \
        --form "${MSG}" 10 110 2 "URL" 1 1 "${PATURL}" 1 5 100 0 "MD5" 2 1 "${PATSUM}" 2 5 100 0 \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && continue
      paturl="$(sed -n '1p' "${TMP_PATH}/resp" 2>/dev/null)"
      patsum="$(sed -n '2p' "${TMP_PATH}/resp" 2>/dev/null)"
      if [ ! "${paturl}" = "${PATURL}" ] || [ ! "${patsum}" = "${PATSUM}" ]; then
        writeConfigKey "paturl" "${paturl}" "${USER_CONFIG_FILE}"
        writeConfigKey "patsum" "${patsum}" "${USER_CONFIG_FILE}"
        rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
        touch "${PART1_PATH}/.build"
      fi
      NEXT="e"
      ;;
    m)
      rm -f "${TMP_PATH}/menu"
      {
        echo "1 \"Native SATA Disk(SYNO)\""
        echo "2 \"Fake SATA DOM(Redpill)\""
      } >"${TMP_PATH}/menu"
      DIALOG --title "$(TEXT "Advanced")" \
        --default-item "${SATADOM}" --menu "$(TEXT "Choose a mode(Only supported for kernel version 4)")" 0 0 0 --file "${TMP_PATH}/menu" \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && continue
      resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
      [ -z "${resp}" ] && continue
      SATADOM="${resp}"
      writeConfigKey "satadom" "${SATADOM}" "${USER_CONFIG_FILE}"
      NEXT="m"
      ;;
    d)
      if [ "true" = "${DT}" ]; then
        customDTS
      else
        DIALOG --title "$(TEXT "Advanced")" \
          --msgbox "$(TEXT "Custom DTS is not supported for current model.")" 0 0
      fi
      NEXT="e"
      ;;
    u)
      if [ "true" = "${DT}" ]; then
        DIALOG --title "$(TEXT "Advanced")" \
          --msgbox "$(TEXT "USB disk as internal disk is not supported for current model.")" 0 0
        NEXT="e"
      else
        USBASINTERNAL=$([ "${USBASINTERNAL}" = "true" ] && echo 'false' || echo 'true')
        writeConfigKey "usbasinternal" "${USBASINTERNAL}" "${USER_CONFIG_FILE}"
        NEXT="u"
      fi
      ;;
    j)
      AU=$(readConfigMap "addons" "${USER_CONFIG_FILE}" | grep -q "blockupdate" && echo "false" || echo "true")
      if [ "${AU}" = "true" ]; then
        writeConfigKey "addons.\"blockupdate\"" "" "${USER_CONFIG_FILE}"
      else
        deleteConfigKey "addons.\"blockupdate\"" "${USER_CONFIG_FILE}"
      fi
      touch "${PART1_PATH}/.build"
      NEXT="j"
      ;;
    w)
      ITEMS="$(echo -e "1 \n5 \n10 \n30 \n60 \n")"
      DIALOG --title "$(TEXT "Advanced")" \
        --default-item "${BOOTWAIT}" --no-items --menu "$(TEXT "Choose a time(seconds)")" 0 0 0 ${ITEMS} \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && continue
      resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
      [ -z "${resp}" ] && continue
      BOOTWAIT="${resp}"
      writeConfigKey "bootwait" "${BOOTWAIT}" "${USER_CONFIG_FILE}"
      NEXT="w"
      ;;
    i)
      ITEMS="$(echo -e "1 \n5 \n10 \n30 \n60 \n")"
      DIALOG --title "$(TEXT "Advanced")" \
        --default-item "${BOOTIPWAIT}" --no-items --menu "$(TEXT "Choose a time(seconds)")" 0 0 0 ${ITEMS} \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && continue
      resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
      [ -z "${resp}" ] && continue
      BOOTIPWAIT="${resp}"
      writeConfigKey "bootipwait" "${BOOTIPWAIT}" "${USER_CONFIG_FILE}"
      NEXT="i"
      ;;
    k)
      [ "${KERNELWAY}" = "kexec" ] && KERNELWAY='power' || KERNELWAY='kexec'
      writeConfigKey "kernelway" "${KERNELWAY}" "${USER_CONFIG_FILE}"
      NEXT="k"
      ;;
    # v)
    #   DIALOG --title "$(TEXT "Advanced")" \
    #     --yesno "$(TEXT "Modifying this item requires a reboot, continue?")" 0 0
    #   RET=$?
    #   [ ${RET} -ne 0 ] && continue
    #   checkCmdline "rr_cmdline" "nomodeset" && delCmdline "rr_cmdline" "nomodeset" || addCmdline "rr_cmdline" "nomodeset"
    #   DIALOG --title "$(TEXT "Advanced")" \
    #     --infobox "$(TEXT "Reboot to RR")" 0 0
    #   rebootTo config
    #   exit 0
    #   NEXT="v"
    #   ;;
    n)
      rm -f "${TMP_PATH}/menu"
      {
        echo "5 \"Reboot after 5 seconds\""
        echo "0 \"No reboot\""
        echo "-1 \"Restart immediately\""
      } >"${TMP_PATH}/menu"
      DIALOG --title "$(TEXT "Advanced")" \
        --default-item "${KERNELPANIC}" --menu "$(TEXT "Choose a time(seconds)")" 0 0 0 --file "${TMP_PATH}/menu" \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && continue
      resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
      [ -z "${resp}" ] && continue
      KERNELPANIC="${resp}"
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
      touch "${PART1_PATH}/.build"
      NEXT="b"
      ;;
    s)
      showDisksInfo
      NEXT="e"
      ;;
    t)
      MountDSMVolume
      NEXT="e"
      ;;
    f)
      formatDisks
      NEXT="e"
      ;;
    g)
      downloadBackupFiles
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
    o)
      removeBlockIPDB
      NEXT="e"
      ;;
    q)
      disablescheduledTasks
      NEXT="e"
      ;;
    r)
      initDSMNetwork
      NEXT="e"
      ;;
    e)
      break
      ;;
    esac
  done
}

###############################################################################
# Settings menu
function settingsMenu() {
  NEXT="l"
  while true; do
    rm -f "${TMP_PATH}/menu"
    {
      echo "l \"$(TEXT "Choose a language")\""
      echo "t \"$(TEXT "Choose a timezone")\""
      echo "k \"$(TEXT "Choose a keymap")\""
      echo "o \"$(TEXT "Show QR logo:") \Z4${DSMLOGO}\Zn\""
      echo "n \"$(TEXT "Bootloader notifications (Webhook)")\""
      echo "p \"$(TEXT "Custom patch script # Developer")\""
      echo "u \"$(TEXT "Edit user config file manually")\""
      echo "g \"$(TEXT "Edit grub.cfg file manually")\""
      echo "r \"$(TEXT "Try to recovery a installed DSM system")\""
      echo "c \"$(TEXT "Clone bootloader disk to another disk")\""
      echo "q \"$(TEXT "System Environment Report")\""
      echo "v \"$(TEXT "Report bugs to the author")\""
      echo "d \"$(TEXT "Install development tools")\""
      echo "s \"$(TEXT "Save modifications of '/opt/rr'")\""
      echo "i \"$(TEXT "Set static IP")\""
      echo "w \"$(TEXT "Set wireless account")\""
      echo "1 \"$(TEXT "Set global proxy")\""
      echo "2 \"$(TEXT "Set github proxy")\""
      UPDMC="$([ -f "${MC_RAMDISK_FILE}" ] && echo "true" || echo "false")"
      echo "3 \"$(TEXT "Update microcode:") \Z4${UPDMC}\Zn\""
      echo "4 \"$(TEXT "Change root password # Only RR")\""
      echo "5 \"$(TEXT "Change ports of TTYD/DUFS/HTTP")\""
      echo "! \"$(TEXT "Vigorously miracle")\""
      echo "e \"$(TEXT "Exit")\""
    } >"${TMP_PATH}/menu"

    DIALOG --err "${1}" --title "$(TEXT "Settings")" \
      --default-item "${NEXT}" --menu "$(TEXT "Settings option")" 0 0 0 --file "${TMP_PATH}/menu" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break
    case "$(cat "${TMP_PATH}/resp" 2>/dev/null)" in
    l)
      languageMenu
      NEXT="l"
      ;;
    t)
      timezoneMenu
      NEXT="t"
      ;;
    k)
      keymapMenu
      NEXT="k"
      ;;
    o)
      [ "${DSMLOGO}" = "true" ] && DSMLOGO='false' || DSMLOGO='true'
      writeConfigKey "dsmlogo" "${DSMLOGO}" "${USER_CONFIG_FILE}"
      NEXT="o"
      ;;
    n)
      notificationsMenu
      NEXT="e"
      ;;
    p)
      MSG=""
      MSG+="$(TEXT "This option provides information about custom patch scripts for the ramdisk.\n")"
      MSG+="\n"
      MSG+="$(TEXT "These scripts are executed before the ramdisk is packaged.\n")"
      MSG+="$(TEXT "You can place your custom scripts in the following location:\n")"
      MSG+="$(TEXT "/mnt/p3/scripts/*.sh\n")"
      DIALOG --title "$(TEXT "Settings")" \
        --msgbox "${MSG}" 0 0
      NEXT="e"
      ;;
    u)
      editUserConfig
      NEXT="e"
      ;;
    g)
      editGrubCfg
      NEXT="e"
      ;;
    r)
      tryRecoveryDSM
      NEXT="e"
      ;;
    c)
      cloneBootloaderDisk
      NEXT="e"
      ;;
    q)
      systemReport
      NEXT="e"
      ;;
    v)
      reportBugs
      NEXT="e"
      ;;
    d)
      InstallDevTools
      NEXT="e"
      ;;
    s)
      savemodrr
      NEXT="e"
      ;;
    i)
      setStaticIP
      NEXT="e"
      ;;
    w)
      setWirelessAccount
      NEXT="e"
      ;;
    1)
      setProxy "global_proxy"
      NEXT="e"
      ;;
    2)
      setProxy "github_proxy"
      NEXT="e"
      ;;
    3)
      UPDMC="$([ -f "${MC_RAMDISK_FILE}" ] && echo "true" || echo "false")"
      if [ "${UPDMC}" = "true" ]; then
        rm -f "${MC_RAMDISK_FILE}"
      else
        createMicrocode
      fi
      NEXT="3"
      ;;
    4)
      changePassword
      NEXT="e"
      ;;
    5)
      changePorts
      NEXT="e"
      ;;

    !)
      MSG=""
      MSG+="                                                        \n"
      MSG+="   ██▀███     ██▀███     ▒█████     ██▀███      ▄████   \n"
      MSG+="  ▓██ ▒ ██▒  ▓██ ▒ ██▒  ▒██▒  ██▒  ▓██ ▒ ██▒   ██▒ ▀█▒  \n"
      MSG+="  ▓██ ░▄█ ▒  ▓██ ░▄█ ▒  ▒██░  ██▒  ▓██ ░▄█ ▒▒  ██░▄▄▄░  \n"
      MSG+="  ▒██▀▀█▄    ▒██▀▀█▄    ▒██   ██░  ▒██▀▀█▄  ░  ▓█  ██▓  \n"
      MSG+="  ░██▓ ▒██▒  ░██▓ ▒██▒  ░ ████▓▒░  ░██▓ ▒██▒░  ▒▓███▀▒  \n"
      MSG+="  ░ ▒▓ ░▒▓░  ░ ▒▓ ░▒▓░  ░ ▒░▒░▒░   ░ ▒▓ ░▒▓░   ░▒   ▒   \n"
      MSG+="    ░▒ ░ ▒░    ░▒ ░ ▒░    ░ ▒ ▒░     ░▒ ░ ▒░    ░   ░   \n"
      MSG+="    ░░   ░     ░░   ░   ░ ░ ░ ▒      ░░   ░ ░   ░   ░   \n"
      MSG+="     ░          ░           ░ ░       ░             ░   \n"
      MSG+="                                                        \n"
      DIALOG --title "$(TEXT "Settings")" \
        --ascii-lines --msgbox "${MSG}" 15 60
      NEXT="e"
      ;;
    e)
      break
      ;;
    esac
  done
}

###############################################################################
# 1 - ext name
# 2 - current version
# 3 - repo url
# 4 - attachment name
function downloadExts() {
  PROXY="$(readConfigKey "github_proxy" "${USER_CONFIG_FILE}")"
  [ -n "${PROXY}" ] && [ "${PROXY: -1}" != "/" ] && PROXY="${PROXY}/"
  T="$(printf "$(TEXT "Update %s")" "${1}")"
  MSG="$(TEXT "Checking last version ...")"
  DIALOG --title "${T}" \
    --infobox "${MSG}" 0 0
  TAG=""
  if [ "${PRERELEASE}" = "true" ]; then
    # TAG="$(curl -skL --connect-timeout 10 "${PROXY}${3}/tags" | pup 'a[class="Link--muted"] attr{href}' | grep ".zip" | head -1)"
    TAG="$(curl -skL --connect-timeout 10 "${PROXY}${3}/tags" | grep "/refs/tags/.*\.zip" | sed -E 's/.*\/refs\/tags\/(.*)\.zip.*$/\1/' | sort -rV | head -1)"
  else
    TAG="$(curl -skL --connect-timeout 10 -w "%{url_effective}" -o /dev/null "${PROXY}${3}/releases/latest" | awk -F'/' '{print $NF}')"
  fi
  [ "${TAG:0:1}" = "v" ] && TAG="${TAG:1}"
  if [ "${TAG:-latest}" = "latest" ]; then
    MSG="$(printf "%s\n%s:\n%s\n" "$(TEXT "Error checking new version.")" "$(TEXT "Error")" "Tag is ${TAG}")"
    DIALOG --title "${T}" \
      --msgbox "${MSG}" 0 0
    return 1
  fi
  if [ "${2}" = "${TAG}" ]; then
    MSG="$(TEXT "No new version.\n")"
    MSG+="$(printf "$(TEXT "Actual version is %s.\nForce update?")" "${2}")"
    DIALOG --ret 0 --title "${T}" \
      --yesno "${MSG}" 0 0
    [ $? -ne 0 ] && return 1
  else
    MSG=""
    MSG+="$(printf "$(TEXT "Latest: %s\n")" "${TAG}")"
    MSG+="\n"
    MSG+="$(curl -skL --connect-timeout 10 "${PROXY}${3}/releases/tag/${TAG}" | pup 'div[data-test-selector="body-content"]' | html2text --ignore-links --ignore-images)"
    MSG+="\n"
    MSG+="$(TEXT "Do you want to update?")"
    DIALOG --ret 0 --title "${T}" \
      --yesno "$(echo -e "${MSG}")" 0 0
    [ $? -ne 0 ] && return 1
  fi
  function __download() {
    rm -f ${TMP_PATH}/${4}*.zip
    touch "${TMP_PATH}/${4}-${TAG}.zip.downloading"
    STATUS=$(curl -kL --connect-timeout 10 -w "%{http_code}" "${PROXY}${3}/releases/download/${TAG}/${4}-${TAG}.zip" -o "${TMP_PATH}/${4}-${TAG}.zip")
    RET=$?
    rm -f "${TMP_PATH}/${4}-${TAG}.zip.downloading"
    if [ ${RET} -ne 0 ] || [ ${STATUS:-0} -ne 200 ]; then
      rm -f "${TMP_PATH}/${4}-${TAG}.zip"
      MSG="$(printf "%s\n%s: %d:%d\n%s\n" "$(TEXT "Error downloading new version.")" "$(TEXT "Error")" "${RET}" "${STATUS}" "$(TEXT "(Please via https://curl.se/libcurl/c/libcurl-errors.html check error description.)")")"
      echo -e "${MSG}" >"${LOG_FILE}"
    fi
    return 0
  }
  rm -f "${LOG_FILE}"

  __download "$@" 2>&1 | DIALOG --title "${T}" \
    --progressbox "$(TEXT "Downloading ...")" 20 100

  if [ -f "${LOG_FILE}" ]; then
    DIALOG --title "${T}" \
      --msgbox "$(cat "${LOG_FILE}")" 0 0
    return 1
  fi
  return 0
}

###############################################################################
# 1 - update file
function updateRR() {
  T="$(printf "$(TEXT "Update %s")" "$(TEXT "RR")")"
  MSG="$(TEXT "Extracting update file ...")"
  DIALOG --title "${T}" \
    --infobox "${MSG}" 0 0

  rm -rf "${TMP_PATH}/update"
  mkdir -p "${TMP_PATH}/update"
  unzip -oq "${1}" -d "${TMP_PATH}/update" >"${LOG_FILE}" 2>&1
  if [ $? -ne 0 ]; then
    MSG="$(printf "%s\n%s:\n%s\n" "$(TEXT "Error extracting update file.")" "$(TEXT "Error")" "$(cat "${LOG_FILE}")")"
    DIALOG --title "${T}" \
      --msgbox "${MSG}" 0 0
    return 1
  fi
  # Check checksums
  (cd "${TMP_PATH}/update" && sha256sum --status -c sha256sum)
  if [ $? -ne 0 ]; then
    MSG="$(TEXT "Checksum do not match!")"
    DIALOG --title "${T}" \
      --msgbox "${MSG}" 0 0
    return 1
  fi
  # Check conditions
  if [ -f "${TMP_PATH}/update/update-check.sh" ]; then
    chmod +x "${TMP_PATH}/update/update-check.sh"
    bash "${TMP_PATH}/update/update-check.sh"
    if [ $? -ne 0 ]; then
      MSG="$(TEXT "The current version does not support upgrading to the latest update.zip. Please remake the bootloader disk!")"
      DIALOG --title "${T}" \
        --msgbox "${MSG}" 0 0
      return 1
    fi
  fi

  SIZENEW=0
  SIZEOLD=0
  while IFS=': ' read -r KEY VALUE; do
    VALUE="${VALUE#/}" # Remove leading slash
    VALUE="${VALUE%/}" # Remove trailing slash
    if [ "${KEY: -1}" = "/" ]; then
      rm -rf "${TMP_PATH}/update/${VALUE}"
      mkdir -p "${TMP_PATH}/update/${VALUE}/"
      tar -zxf "${TMP_PATH}/update/$(basename "${KEY}").tgz" -C "${TMP_PATH}/update/${VALUE}" >"${LOG_FILE}" 2>&1
      if [ $? -ne 0 ]; then
        MSG="$(printf "%s\n%s:\n%s\n" "$(TEXT "Error extracting update file.")" "$(TEXT "Error")" "$(cat "${LOG_FILE}")")"
        DIALOG --title "${T}" \
          --msgbox "${MSG}" 0 0
        return 1
      fi
      rm "${TMP_PATH}/update/$(basename "${KEY}").tgz"
    else
      mkdir -p "${TMP_PATH}/update/$(dirname "/${VALUE}")"
      mv -f "${TMP_PATH}/update/$(basename "${KEY}")" "${TMP_PATH}/update/${VALUE}"
    fi
    FSNEW=$(du -sm "${TMP_PATH}/update/${VALUE}" 2>/dev/null | awk '{print $1}')
    FSOLD=$(du -sm "/${VALUE}" 2>/dev/null | awk '{print $1}')
    SIZENEW=$((${SIZENEW} + ${FSNEW:-0}))
    SIZEOLD=$((${SIZEOLD} + ${FSOLD:-0}))
  done <<<"$(readConfigMap "replace" "${TMP_PATH}/update/update-list.yml")"

  SIZESPL=$(df -m "${PART3_PATH}" 2>/dev/null | awk 'NR==2 {print $4}')
  if [ ${SIZENEW:-0} -ge $((${SIZEOLD:-0} + ${SIZESPL:-0})) ]; then
    MSG="$(printf "$(TEXT "Failed to install due to insufficient remaining disk space on local hard drive, consider reallocate your disk %s with at least %sM.")" "${PART3_PATH}" "$((${SIZENEW:-0} - ${SIZEOLD:-0} - ${SIZESPL:-0}))")"
    DIALOG --title "${T}" \
      --msgbox "${MSG}" 0 0
    return 1
  fi

  MSG="$(TEXT "Installing new files ...")"
  DIALOG --title "${T}" \
    --infobox "${MSG}" 0 0
  # Process update-list.yml
  while read -r F; do
    [ -f "${F}" ] && rm -f "${F}"
    [ -d "${F}" ] && rm -rf "${F}"
  done <<<"$(readConfigArray "remove" "${TMP_PATH}/update/update-list.yml")"
  while IFS=': ' read -r KEY VALUE; do
    VALUE="${VALUE#/}" # Remove leading slash
    VALUE="${VALUE%/}" # Remove trailing slash
    [ -z "${VALUE}" ] && continue
    if [ "${KEY: -1}" = "/" ]; then
      rm -rf "/${VALUE}/"*
      mkdir -p "/${VALUE}/"
      cp -rf "${TMP_PATH}/update/${VALUE}/". "/${VALUE}/"
      if [ "$(realpath "/${VALUE}/")" = "$(realpath "${MODULES_PATH}")" ]; then
        if [ -n "${PLATFORM}" ] && [ -n "${PRODUCTVER}" ] && [ -n "${KVER}" ]; then
          writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
          mergeConfigModules "$(getAllModules "${PLATFORM}" "${KPRE:+${KPRE}-}${KVER}" | awk '{print $1}')" "${USER_CONFIG_FILE}"
        fi
      fi
    else
      mkdir -p "$(dirname "/${VALUE}")"
      cp -f "${TMP_PATH}/update/${VALUE}" "/${VALUE}"
    fi
  done <<<"$(readConfigMap "replace" "${TMP_PATH}/update/update-list.yml")"
  rm -rf "${TMP_PATH}/update"
  touch "${PART1_PATH}/.upgraded"
  touch "${PART1_PATH}/.build"
  sync
  MSG="$(printf "$(TEXT "%s updated with success!\n")$(TEXT "Reboot?")" "$(TEXT "RR")")"
  DIALOG --title "${T}" \
    --msgbox "${MSG}" 0 0
  DIALOG --title "${T}" \
    --infobox "$(TEXT "Reboot to RR")" 0 0
  rebootTo config
  exit 0
}

###############################################################################
# 1 - update file
function updateAddons() {
  T="$(printf "$(TEXT "Update %s")" "$(TEXT "Addons")")"
  MSG="$(TEXT "Extracting update file ...")"
  DIALOG --title "${T}" \
    --infobox "${MSG}" 0 0

  rm -rf "${TMP_PATH}/update"
  mkdir -p "${TMP_PATH}/update"
  unzip -oq "${1}" -d "${TMP_PATH}/update" >"${LOG_FILE}" 2>&1
  if [ $? -ne 0 ]; then
    MSG="$(printf "%s\n%s:\n%s\n" "$(TEXT "Error extracting update file.")" "$(TEXT "Error")" "$(cat "${LOG_FILE}")")"
    DIALOG --title "${T}" \
      --msgbox "${MSG}" 0 0
    return 1
  fi

  for F in ${TMP_PATH}/update/*.addon; do
    [ ! -e "${F}" ] && continue
    ADDON=$(basename "${F}" .addon)
    rm -rf "${TMP_PATH}/update/${ADDON}"
    mkdir -p "${TMP_PATH}/update/${ADDON}"
    tar -xaf "${F}" -C "${TMP_PATH}/update/${ADDON}" >/dev/null 2>&1
    rm -f "${F}"
  done

  SIZENEW="$(du -sm "${TMP_PATH}/update" 2>/dev/null | awk '{print $1}')"
  SIZEOLD="$(du -sm "${ADDONS_PATH}" 2>/dev/null | awk '{print $1}')"
  SIZESPL=$(df -m "${ADDONS_PATH}" 2>/dev/null | awk 'NR==2 {print $4}')
  if [ ${SIZENEW:-0} -ge $((${SIZEOLD:-0} + ${SIZESPL:-0})) ]; then
    MSG="$(printf "$(TEXT "Failed to install due to insufficient remaining disk space on local hard drive, consider reallocate your disk %s with at least %sM.")" "$(dirname "${ADDONS_PATH}")" "$((${SIZENEW:-0} - ${SIZEOLD:-0} - ${SIZESPL:-0}))")"
    DIALOG --title "${T}" \
      --msgbox "${MSG}" 0 0
    return 1
  fi

  rm -rf "${ADDONS_PATH}/"*
  cp -rf "${TMP_PATH}/update/"* "${ADDONS_PATH}/"
  rm -rf "${TMP_PATH}/update"
  touch "${PART1_PATH}/.build"
  sync
  MSG="$(printf "$(TEXT "%s updated with success!\n")" "$(TEXT "Addons")")"
  DIALOG --title "${T}" \
    --msgbox "${MSG}" 0 0
  return 0
}

###############################################################################
# 1 - update file
function updateModules() {
  T="$(printf "$(TEXT "Update %s")" "$(TEXT "Modules")")"
  MSG="$(TEXT "Extracting update file ...")"
  DIALOG --title "${T}" \
    --infobox "${MSG}" 0 0

  rm -rf "${TMP_PATH}/update"
  mkdir -p "${TMP_PATH}/update"
  unzip -oq "${1}" -d "${TMP_PATH}/update" >"${LOG_FILE}" 2>&1
  if [ $? -ne 0 ]; then
    MSG="$(printf "%s\n%s:\n%s\n" "$(TEXT "Error extracting update file.")" "$(TEXT "Error")" "$(cat "${LOG_FILE}")")"
    DIALOG --title "${T}" \
      --msgbox "${MSG}" 0 0
    return 1
  fi

  SIZENEW="$(du -sm "${TMP_PATH}/update" 2>/dev/null | awk '{print $1}')"
  SIZEOLD="$(du -sm "${MODULES_PATH}" 2>/dev/null | awk '{print $1}')"
  SIZESPL=$(df -m "${MODULES_PATH}" 2>/dev/null | awk 'NR==2 {print $4}')
  if [ ${SIZENEW:-0} -ge $((${SIZEOLD:-0} + ${SIZESPL:-0})) ]; then
    MSG="$(printf "$(TEXT "Failed to install due to insufficient remaining disk space on local hard drive, consider reallocate your disk %s with at least %sM.")" "$(dirname "${MODULES_PATH}")" "$((${SIZENEW:-0} - ${SIZEOLD:-0} - ${SIZESPL:-0}))")"
    DIALOG --title "${T}" \
      --msgbox "${MSG}" 0 0
    return 1
  fi

  rm -rf "${MODULES_PATH}/"*
  cp -rf "${TMP_PATH}/update/"* "${MODULES_PATH}/"
  if [ -n "${PLATFORM}" ] && [ -n "${PRODUCTVER}" ] && [ -n "${KVER}" ]; then
    writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
    mergeConfigModules "$(getAllModules "${PLATFORM}" "${KPRE:+${KPRE}-}${KVER}" | awk '{print $1}')" "${USER_CONFIG_FILE}"
  fi
  rm -rf "${TMP_PATH}/update"
  touch "${PART1_PATH}/.build"
  sync
  MSG="$(printf "$(TEXT "%s updated with success!\n")" "$(TEXT "Modules")")"
  DIALOG --title "${T}" \
    --msgbox "${MSG}" 0 0
  return 0
}

###############################################################################
# 1 - update file
function updateLKMs() {
  T="$(printf "$(TEXT "Update %s")" "$(TEXT "LKMs")")"
  MSG="$(TEXT "Extracting update file ...")"
  DIALOG --title "${T}" \
    --infobox "${MSG}" 0 0

  rm -rf "${TMP_PATH}/update"
  mkdir -p "${TMP_PATH}/update"
  unzip -oq "${1}" -d "${TMP_PATH}/update" >"${LOG_FILE}" 2>&1
  if [ $? -ne 0 ]; then
    MSG="$(printf "%s\n%s:\n%s\n" "$(TEXT "Error extracting update file.")" "$(TEXT "Error")" "$(cat "${LOG_FILE}")")"
    DIALOG --title "${T}" \
      --msgbox "${MSG}" 0 0
    return 1
  fi

  SIZENEW="$(du -sm "${TMP_PATH}/update" 2>/dev/null | awk '{print $1}')"
  SIZEOLD="$(du -sm "${LKMS_PATH}" 2>/dev/null | awk '{print $1}')"
  SIZESPL=$(df -m "${LKMS_PATH}" 2>/dev/null | awk 'NR==2 {print $4}')
  if [ ${SIZENEW:-0} -ge $((${SIZEOLD:-0} + ${SIZESPL:-0})) ]; then
    MSG="$(printf "$(TEXT "Failed to install due to insufficient remaining disk space on local hard drive, consider reallocate your disk %s with at least %sM.")" "$(dirname "${LKMS_PATH}")" "$((${SIZENEW:-0} - ${SIZEOLD:-0} - ${SIZESPL:-0}))")"
    DIALOG --title "${T}" \
      --msgbox "${MSG}" 0 0
    return 1
  fi

  rm -rf "${LKMS_PATH}/"*
  cp -rf "${TMP_PATH}/update/"* "${LKMS_PATH}/"
  rm -rf "${TMP_PATH}/update"
  touch "${PART1_PATH}/.build"
  sync
  MSG="$(printf "$(TEXT "%s updated with success!\n")" "$(TEXT "LKMs")")"
  DIALOG --title "${T}" \
    --msgbox "${MSG}" 0 0
  return 0
}

###############################################################################
# 1 - update file
function updateCKs() {
  T="$(printf "$(TEXT "Update %s")" "$(TEXT "CKs")")"
  MSG="$(TEXT "Extracting update file ...")"
  DIALOG --title "${T}" \
    --infobox "${MSG}" 0 0

  rm -rf "${TMP_PATH}/update"
  mkdir -p "${TMP_PATH}/update"
  unzip -oq "${1}" -d "${TMP_PATH}/update" >"${LOG_FILE}" 2>&1
  if [ $? -ne 0 ]; then
    MSG="$(printf "%s\n%s:\n%s\n" "$(TEXT "Error extracting update file.")" "$(TEXT "Error")" "$(cat "${LOG_FILE}")")"
    DIALOG --title "${T}" \
      --msgbox "${MSG}" 0 0
    return 1
  fi

  SIZENEW="$(du -sm "${TMP_PATH}/update" 2>/dev/null | awk '{print $1}')"
  SIZEOLD="$(du -sm "${CKS_PATH}" 2>/dev/null | awk '{print $1}')"
  SIZESPL=$(df -m "${CKS_PATH}" 2>/dev/null | awk 'NR==2 {print $4}')
  if [ ${SIZENEW:-0} -ge $((${SIZEOLD:-0} + ${SIZESPL:-0})) ]; then
    MSG="$(printf "$(TEXT "Failed to install due to insufficient remaining disk space on local hard drive, consider reallocate your disk %s with at least %sM.")" "$(dirname "${CKS_PATH}")" "$((${SIZENEW:-0} - ${SIZEOLD:-0} - ${SIZESPL:-0}))")"
    DIALOG --title "${T}" \
      --msgbox "${MSG}" 0 0
    return 1
  fi

  rm -rf "${CKS_PATH}/"*
  cp -rf "${TMP_PATH}/update/"* "${CKS_PATH}/"
  if [ "${KERNEL}" = "custom" ] && [ -n "${PLATFORM}" ] && [ -n "${PRODUCTVER}" ] && [ -n "${KVER}" ]; then
    writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
    mergeConfigModules "$(getAllModules "${PLATFORM}" "${KPRE:+${KPRE}-}${KVER}" | awk '{print $1}')" "${USER_CONFIG_FILE}"
  fi

  rm -rf "${TMP_PATH}/update"
  touch "${PART1_PATH}/.build"
  sync
  MSG="$(printf "$(TEXT "%s updated with success!\n")" "$(TEXT "CKs")")"
  DIALOG --title "${T}" \
    --msgbox "${MSG}" 0 0
  return 0
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
    {
      echo "a \"$(TEXT "Update") $(TEXT "All")\""
      echo "r \"$(TEXT "Update") $(TEXT "RR") (${CUR_RR_VER:-None})\""
      echo "d \"$(TEXT "Update") $(TEXT "Addons") (${CUR_ADDONS_VER:-None})\""
      echo "m \"$(TEXT "Update") $(TEXT "Modules") (${CUR_MODULES_VER:-None})\""
      echo "l \"$(TEXT "Update") $(TEXT "LKMs") (${CUR_LKMS_VER:-None})\""
      echo "c \"$(TEXT "Update") $(TEXT "CKs") (${CUR_CKS_VER:-None})\""
      echo "u \"$(TEXT "Local upload")\""
      echo "b \"$(TEXT "Pre Release:") \Z4${PRERELEASE}\Zn\""
      echo "e \"$(TEXT "Exit")\""
    } >"${TMP_PATH}/menu"
    MSG="$(TEXT "Manually uploading update*.zip,addons*.zip,modules*.zip,rp-lkms*.zip,rr-cks*.zip to /tmp/ will skip the download.\n")"
    DIALOG --err "${1}" --title "$(TEXT "Update")" \
      --menu "${MSG}" 0 0 0 --file "${TMP_PATH}/menu" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return 1

    case "$(cat "${TMP_PATH}/resp" 2>/dev/null)" in
    a)
      F="$(ls ${PART3_PATH}/updateall*.zip ${TMP_PATH}/updateall*.zip 2>/dev/null | sort -V | tail -n 1)"
      [ -n "${F}" ] && [ -f "${F}.downloading" ] && rm -f "${F}" && rm -f "${F}.downloading" && F=""
      [ -z "${F}" ] && downloadExts "$(TEXT "All")" "${CUR_RR_VER:-None}" "https://github.com/RROrg/rr" "updateall"
      F="$(ls ${TMP_PATH}/updateall*.zip 2>/dev/null | sort -V | tail -n 1)"
      [ -n "${F}" ] && updateRR "${F}" && rm -f ${TMP_PATH}/updateall*.zip
      ;;
    r)
      F="$(ls ${PART3_PATH}/update*.zip ${TMP_PATH}/update*.zip 2>/dev/null | sort -V | tail -n 1)"
      [ -n "${F}" ] && [ -f "${F}.downloading" ] && rm -f "${F}" && rm -f "${F}.downloading" && F=""
      [ -z "${F}" ] && downloadExts "$(TEXT "RR")" "${CUR_RR_VER:-None}" "https://github.com/RROrg/rr" "update"
      F="$(ls ${TMP_PATH}/update*.zip 2>/dev/null | sort -V | tail -n 1)"
      [ -n "${F}" ] && updateRR "${F}" && rm -f ${TMP_PATH}/update*.zip
      ;;
    d)
      if [ -z "${DEBUG}" ]; then
        DIALOG --title "$(TEXT "Update")" \
          --msgbox "$(printf "$(TEXT "No longer supports update %s separately. Please choose to update All/RR")" "$(TEXT "Addons")")" 0 0
        continue
      fi
      F="$(ls ${PART3_PATH}/addons*.zip ${TMP_PATH}/addons*.zip 2>/dev/null | sort -V | tail -n 1)"
      [ -n "${F}" ] && [ -f "${F}.downloading" ] && rm -f "${F}" && rm -f "${F}.downloading" && F=""
      [ -z "${F}" ] && downloadExts "$(TEXT "Addons")" "${CUR_ADDONS_VER:-None}" "https://github.com/RROrg/rr-addons" "addons"
      F="$(ls ${TMP_PATH}/addons*.zip 2>/dev/null | sort -V | tail -n 1)"
      [ -n "${F}" ] && updateAddons "${F}" && rm -f ${TMP_PATH}/addons*.zip
      ;;
    m)
      if [ -z "${DEBUG}" ]; then
        DIALOG --title "$(TEXT "Update")" \
          --msgbox "$(printf "$(TEXT "No longer supports update %s separately. Please choose to update All/RR")" "$(TEXT "Modules")")" 0 0
        continue
      fi
      F="$(ls ${PART3_PATH}/modules*.zip ${TMP_PATH}/modules*.zip 2>/dev/null | sort -V | tail -n 1)"
      [ -n "${F}" ] && [ -f "${F}.downloading" ] && rm -f "${F}" && rm -f "${F}.downloading" && F=""
      [ -z "${F}" ] && downloadExts "$(TEXT "Modules")" "${CUR_MODULES_VER:-None}" "https://github.com/RROrg/rr-modules" "modules"
      F="$(ls ${TMP_PATH}/modules*.zip 2>/dev/null | sort -V | tail -n 1)"
      [ -n "${F}" ] && updateModules "${F}" && rm -f ${TMP_PATH}/modules*.zip
      ;;
    l)
      if [ -z "${DEBUG}" ]; then
        DIALOG --title "$(TEXT "Update")" \
          --msgbox "$(printf "$(TEXT "No longer supports update %s separately. Please choose to update All/RR")" "$(TEXT "LKMs")")" 0 0
        continue
      fi
      F="$(ls ${PART3_PATH}/rp-lkms*.zip ${TMP_PATH}/rp-lkms*.zip 2>/dev/null | sort -V | tail -n 1)"
      [ -n "${F}" ] && [ -f "${F}.downloading" ] && rm -f "${F}" && rm -f "${F}.downloading" && F=""
      [ -z "${F}" ] && downloadExts "$(TEXT "LKMs")" "${CUR_LKMS_VER:-None}" "https://github.com/RROrg/rr-lkms" "rp-lkms"
      F="$(ls ${TMP_PATH}/rp-lkms*.zip 2>/dev/null | sort -V | tail -n 1)"
      [ -n "${F}" ] && updateLKMs "${F}" && rm -f ${TMP_PATH}/rp-lkms*.zip
      ;;
    c)
      if [ -z "${DEBUG}" ]; then
        DIALOG --title "$(TEXT "Update")" \
          --msgbox "$(printf "$(TEXT "No longer supports update %s separately. Please choose to update All/RR")" "$(TEXT "CKs")")" 0 0
        continue
      fi
      F="$(ls ${PART3_PATH}/rr-cks*.zip ${TMP_PATH}/rr-cks*.zip 2>/dev/null | sort -V | tail -n 1)"
      [ -n "${F}" ] && [ -f "${F}.downloading" ] && rm -f "${F}" && rm -f "${F}.downloading" && F=""
      [ -z "${F}" ] && downloadExts "$(TEXT "CKs")" "${CUR_CKS_VER:-None}" "https://github.com/RROrg/rr-cks" "rr-cks"
      F="$(ls ${TMP_PATH}/rr-cks*.zip 2>/dev/null | sort -V | tail -n 1)"
      [ -n "${F}" ] && updateCKs "${F}" && rm -f ${TMP_PATH}/rr-cks*.zip
      ;;
    u)
      if ! tty 2>/dev/null | grep -q "/dev/pts" || [ -z "${SSH_TTY}" ]; then
        MSG=""
        MSG+="$(TEXT "This feature is only available when accessed via ssh (Requires a terminal that supports ZModem protocol).\n")"
        MSG+="$(TEXT "Manually uploading update*.zip,addons*.zip,modules*.zip,rp-lkms*.zip,rr-cks*.zip to /tmp/ will skip the download.\n")"
        DIALOG --title "$(TEXT "Update")" \
          --msgbox "${MSG}" 0 0
        return 1
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
      TMP_UP_PATH="${TMP_PATH}/users"
      rm -rf "${TMP_UP_PATH}"
      mkdir -p "${TMP_UP_PATH}"
      (cd "${TMP_UP_PATH}" && rz -be) || true
      USER_FILE="$(find "${TMP_UP_PATH}" -type f | head -1)"
      if [ -z "${USER_FILE}" ]; then
        DIALOG --title "$(TEXT "Update")" \
          --msgbox "$(TEXT "Not a valid file, please try again!")" 0 0
      else
        case "${USER_FILE}" in
        *update*.zip)
          rm -f ${TMP_PATH}/update*.zip
          updateRR "${USER_FILE}"
          ;;
        *addons*.zip)
          rm -f ${TMP_PATH}/addons*.zip
          updateAddons "${USER_FILE}"
          ;;
        *modules*.zip)
          rm -f ${TMP_PATH}/modules*.zip
          updateModules "${USER_FILE}"
          ;;
        *rp-lkms*.zip)
          rm -f ${TMP_PATH}/rp-lkms*.zip
          updateLKMs "${USER_FILE}"
          ;;
        *rr-cks*.zip)
          rm -f ${TMP_PATH}/rr-cks*.zip
          updateCKs "${USER_FILE}"
          ;;
        *)
          DIALOG --title "$(TEXT "Update")" \
            --msgbox "$(TEXT "Not a valid file, please try again!")" 0 0
          ;;
        esac
        rm -rf "${TMP_UP_PATH}"
      fi
      ;;
    b)
      [ "${PRERELEASE}" = "false" ] && PRERELEASE='true' || PRERELEASE='false'
      writeConfigKey "prerelease" "${PRERELEASE}" "${USER_CONFIG_FILE}"
      NEXT="e"
      ;;
    e)
      return 0
      ;;
    esac
    [ -z "${1}" ] || return 0
  done
}

###############################################################################
function cleanCache() {
  rm -rfv "${PART3_PATH}/dl/"* 2>&1 | DIALOG --title "$(TEXT "Main menu")" \
    --progressbox "$(TEXT "Cleaning cache ...")" 20 100
  return 0
}

###############################################################################
function notepadMenu() {
  [ -d "${USER_UP_PATH}" ] || mkdir -p "${USER_UP_PATH}"
  [ -f "${USER_UP_PATH}/notepad" ] || echo "$(TEXT "This person is very lazy and hasn't written anything.")" >"${USER_UP_PATH}/notepad"
  DIALOG --title "$(TEXT "Edit with caution")" \
    --editbox "${USER_UP_PATH}/notepad" 0 0 2>"${TMP_PATH}/notepad"
  [ $? -ne 0 ] && return 1
  mv -f "${TMP_PATH}/notepad" "${USER_UP_PATH}/notepad"
  dos2unix "${USER_UP_PATH}/notepad" >/dev/null 2>&1 || true
  return 0
}

###############################################################################
###############################################################################
if [ ! "$(basename -- "${0}")" = "$(basename -- "${BASH_SOURCE[0]}")" ] || [ $# -gt 0 ]; then
  "$@"
	cleanup_lock
else
  if [ -z "${MODEL}" ] && [ -z "${PRODUCTVER}" ] && [ -n "$(findDSMRoot)" ]; then
    DIALOG --title "$(TEXT "Main menu")" \
      --yesno "$(TEXT "An installed DSM system is detected on the hard disk. Do you want to try to restore it first?")" 0 0
    [ $? -eq 0 ] && tryRecoveryDSM
  fi
  # Main loop
  NEXT="m"
  [ -n "$(ls ${TMP_PATH}/pats/*.pat 2>/dev/null)" ] && NEXT="u"
  [ -f "${PART1_PATH}/.build" ] && NEXT="d"
  [ -n "${MODEL}" ] && NEXT="v"
  while true; do
    rm -f "${TMP_PATH}/menu"
    {
      echo "m \"$(TEXT "Choose a model")\""
      if [ -n "${MODEL}" ]; then
        echo "n \"$(TEXT "Choose a version")\""
      fi
      echo "u \"$(TEXT "Parse pat")\""
      if [ -n "${PRODUCTVER}" ]; then
        if [ -f "${CKS_PATH}/bzImage-${PLATFORM}-${KPRE:+${KPRE}-}${KVER}.gz" ] &&
          [ -f "${CKS_PATH}/modules-${PLATFORM}-${KPRE:+${KPRE}-}${KVER}.tgz" ]; then
          echo "s \"$(TEXT "Kernel:") \Z4${KERNEL}\Zn\""
        fi
        echo "a \"$(TEXT "Addons menu")\""
        echo "o \"$(TEXT "Modules menu")\""
        echo "x \"$(TEXT "Cmdline menu")\""
        echo "i \"$(TEXT "Synoinfo menu")\""
      fi
      echo "v \"$(TEXT "Advanced menu")\""
      if [ -n "${MODEL}" ] && [ -n "${PRODUCTVER}" ]; then
        echo "d \"$(TEXT "Build the loader")\""
      fi
      if loaderIsConfigured; then
        echo "q \"$(TEXT "Direct boot:") \Z4${DIRECTBOOT}\Zn\""
        echo "b \"$(TEXT "Boot the loader")\""
      fi
      echo "h \"$(TEXT "Settings menu")\""
      echo "r \"$(TEXT "Online Assistance")\""
      if [ "0$(du -sm "${PART3_PATH}/dl" 2>/dev/null | awk '{printf $1}')" -gt 1 ]; then
        echo "c \"$(TEXT "Clean disk cache")\""
      fi
      echo "p \"$(TEXT "Update menu")\""
      echo "t \"$(TEXT "Notepad")\""
      echo "e \"$(TEXT "Exit")\""
    } >"${TMP_PATH}/menu"
    DIALOG --title "$(TEXT "Main menu")" \
      --default-item ${NEXT} --menu "$(TEXT "Choose a option")" 0 0 0 --file "${TMP_PATH}/menu" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break
    case "$(cat "${TMP_PATH}/resp" 2>/dev/null)" in
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
      if [ -n "${PLATFORM}" ] && [ -n "${KVER}" ]; then
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        mergeConfigModules "$(getAllModules "${PLATFORM}" "${KPRE:+${KPRE}-}${KVER}" | awk '{print $1}')" "${USER_CONFIG_FILE}"
      fi
      touch "${PART1_PATH}/.build"
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
    q)
      DIRECTBOOT="$([ "${DIRECTBOOT}" = "false" ] && echo "true" || echo "false")"
      writeConfigKey "directboot" "${DIRECTBOOT}" "${USER_CONFIG_FILE}"
      NEXT="q"
      ;;
    b)
      boot && exit 0 || sleep 5
      ;;
    h)
      settingsMenu
      NEXT="m"
      ;;
    r)
      cleanup_lock && exec "${WORK_PATH}/helper.sh"
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
        rm -f "${TMP_PATH}/menu"
        {
          echo "p \"$(TEXT "Power off")\""
          echo "r \"$(TEXT "Reboot")\""
          echo "x \"$(TEXT "Reboot to RR")\""
          echo "y \"$(TEXT "Reboot to Recovery")\""
          echo "z \"$(TEXT "Reboot to Junior")\""
          if [ -d "/sys/firmware/efi" ]; then
            echo "b \"$(TEXT "Reboot to UEFI")\""
          fi
          echo "s \"$(TEXT "Back to shell")\""
          echo "e \"$(TEXT "Exit")\""
        } >"${TMP_PATH}/menu"
        DIALOG --title "$(TEXT "Main menu")" \
          --default-item ${NEXT} --menu "$(TEXT "Choose a action")" 0 0 0 --file "${TMP_PATH}/menu" \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && break
        case "$(cat "${TMP_PATH}/resp" 2>/dev/null)" in
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
            --infobox "$(TEXT "Reboot to UEFI")" 0 0
          rebootTo uefi
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
  "${WORK_PATH}/init.sh"
fi
