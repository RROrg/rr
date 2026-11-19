#!/usr/bin/env bash
#
# This is free software, licensed under the MIT License. See /LICENSE.
#

# Return 0 after publication, 2 for cancel/no change, 3 for stale input, 1 on I/O failure.
# A subshell confines the umask/traps so the enclosing menu retains its lock.
function editUserConfigCandidate() (
  umask 077
  local scratch stage="" input
  scratch="$(mktemp -d "${TMP_PATH}/rr-config.XXXXXX")" || exit 1
  trap 'rm -rf "${scratch}"; if [ -n "${stage}" ]; then rm -rf "${stage}"; fi' EXIT
  trap 'exit 1' HUP INT TERM

  cp "${USER_CONFIG_FILE}" "${scratch}/original" || exit 1
  input="${scratch}/original"
  # When menu.sh is run headlessly, its DIALOG wrapper must default to cancel.
  while DIALOG --title "$(TEXT "Edit with caution")" \
    --editbox "${input}" 0 0 --ret 1 2>"${scratch}/response"; do
    cmp -s "${scratch}/response" "${scratch}/original" && exit 2
    # Keep the invalid draft for the next edit. Only validate or normalize copies.
    sed $'s/\r$//' "${scratch}/response" >"${scratch}/draft" || exit 1
    input="${scratch}/draft"
    if ! checkConfigFile "${input}"; then
      DIALOG --title "$(TEXT "Settings")" --msgbox \
        "$(TEXT "Invalid configuration. Use one YAML mapping with unique top-level keys.\nmodel, productver, buildnum and sn must be scalars. cmdline, synoinfo, addons, modules and network must be mappings when present.")" 0 0 || exit 2
      continue
    fi
    cmp -s "${input}" "${scratch}/original" && exit 2

    # The editor uses tmpfs; only the validated file is staged on the target
    # filesystem. Keep the destination's metadata and publish by a single rename.
    stage="$(mktemp -d "${USER_CONFIG_FILE}.edit.XXXXXX")" || exit 1
    cp -p "${USER_CONFIG_FILE}" "${stage}/next" || exit 1
    cat "${input}" >"${stage}/next" || exit 1
    cmp -s "${scratch}/original" "${USER_CONFIG_FILE}" || exit 3
    mv -f "${stage}/next" "${USER_CONFIG_FILE}" || exit 1
    exit 0
  done
  exit 2
)

function editUserConfig() {
  local result=0
  editUserConfigCandidate || result=$?
  case "${result}" in
    0) ;;
    2) return 0 ;;
    3)
      DIALOG --title "$(TEXT "Settings")" --msgbox \
        "$(TEXT "Configuration changed while editing. Reopen the editor to use the latest version.")" 0 0
      return 1
      ;;
    *)
      DIALOG --title "$(TEXT "Settings")" --msgbox \
        "$(TEXT "Configuration not saved. Check the loader filesystem and available space.")" 0 0
      return 1
      ;;
  esac

  local OLDMODEL="${MODEL}" OLDPRODUCTVER="${PRODUCTVER}" OLDBUILDNUM="${BUILDNUM}"
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  BUILDNUM="$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")"
  SN="$(readConfigKey "sn" "${USER_CONFIG_FILE}")"

  if [ ! "${MODEL}" = "${OLDMODEL}" ] || [ ! "${PRODUCTVER}" = "${OLDPRODUCTVER}" ] || [ ! "${BUILDNUM}" = "${OLDBUILDNUM}" ]; then
    rm -f "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
  fi
  touch "${PART1_PATH}/.build"
}
