#!/usr/bin/env bash

# 23.5.0
[ ! -f /mnt/p1/boot/grub/grub.cfg ] && exit 1

# 23.7.0
. /opt/arpl/include/functions.sh
if loaderIsConfigured; then
  if [ -f "${ORI_RDGZ_FILE}" ]; then
    rm -rf "${RAMDISK_PATH}"
    mkdir -p "${RAMDISK_PATH}"
    (
      cd "${RAMDISK_PATH}"
      xz -dc <"${ORI_RDGZ_FILE}" | cpio -idm
    ) >/dev/null 2>&1
    . "${RAMDISK_PATH}/etc/VERSION"
    [ -n "$(readConfigKey "build" "${USER_CONFIG_FILE}")" ] && deleteConfigKey "build" "${USER_CONFIG_FILE}"
    [ -n "$(readConfigKey "smallfixnumber" "${USER_CONFIG_FILE}")" ] && deleteConfigKey "smallfixnumber" "${USER_CONFIG_FILE}"
    [ -z "$(readConfigKey "paturl" "${USER_CONFIG_FILE}")" ] && writeConfigKey "paturl" "" "${USER_CONFIG_FILE}"
    [ -z "$(readConfigKey "patsum" "${USER_CONFIG_FILE}")" ] && writeConfigKey "patsum" "" "${USER_CONFIG_FILE}"
    [ -z "$(readConfigKey "productver" "${USER_CONFIG_FILE}")" ] && writeConfigKey "productver" "${majorversion}.${minorversion}" "${USER_CONFIG_FILE}"
    [ -z "$(readConfigKey "buildnum" "${USER_CONFIG_FILE}")" ] && writeConfigKey "buildnum" "${buildnumber}" "${USER_CONFIG_FILE}"
    [ -z "$(readConfigKey "smallnum" "${USER_CONFIG_FILE}")" ] && writeConfigKey "smallnum" "${smallfixnumber}" "${USER_CONFIG_FILE}"
  fi
fi

# 23.9.7
deleteConfigKey "notsetmacs" "${USER_CONFIG_FILE}"
for N in $(1 8); do
  deleteConfigKey "cmdline.mac${N}" "${USER_CONFIG_FILE}"
  deleteConfigKey "original-mac${N}" "${USER_CONFIG_FILE}"
done
deleteConfigKey "cmdline.netif_num" "${USER_CONFIG_FILE}"
writeConfigKey "mac1" "001132$(printf '%02x%02x%02x' $((${RANDOM} % 256)) $((${RANDOM} % 256)) $((${RANDOM} % 256)))" "${USER_CONFIG_FILE}"

exit 0
