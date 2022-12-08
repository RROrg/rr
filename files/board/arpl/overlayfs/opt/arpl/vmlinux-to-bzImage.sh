#!/bin/sh
# Based on code and ideas from @jumkey

. /opt/arpl/include/functions.sh

MODEL="`readConfigKey "model" "${USER_CONFIG_FILE}"`"
BUILD="`readConfigKey "build" "${USER_CONFIG_FILE}"`"
KVER="`readModelKey "${MODEL}" "builds.${BUILD}.kver"`"

# Adapted from: scripts/Makefile.lib
# Usage: size_append FILE [FILE2] [FILEn]...
# Output: LE HEX with size of file in bytes (to STDOUT)
file_size_le () {
  printf $(
    dec_size=0;
    for F in "${@}"; do
      fsize=$(stat -c "%s" ${F});
      dec_size=$(expr ${dec_size} + ${fsize});
    done;
    printf "%08x\n" ${dec_size} |
      sed 's/\(..\)/\1 /g' | {
        read ch0 ch1 ch2 ch3;
        for ch in ${ch3} ${ch2} ${ch1} ${ch0}; do
          printf '%s%03o' '\' $((0x${ch}));
        done;
      }
  )
}

size_le () {
  printf $(
    printf "%08x\n" "${@}" |
      sed 's/\(..\)/\1 /g' | {
        read ch0 ch1 ch2 ch3;
        for ch in ${ch3} ${ch2} ${ch1} ${ch0}; do
          printf '%s%03o' '\' $((0x${ch}));
        done;
      }
  )
}
SCRIPT_DIR=`dirname $0`
VMLINUX_MOD=${1}
ZIMAGE_MOD=${2}
if [ ${KVER:0:1} -eq 4 ]; then
  # Kernel version 4.x
  #zImage_head           16494
  #payload(
  #  vmlinux.bin         x
  #  padding             0xf00000-x
  #  vmlinux.bin size    4
  #)                     0xf00004
  #zImage_tail(
  #  unknown             72
  #  run_size            4
  #  unknown             30
  #  vmlinux.bin size    4
  #  unknown             114460
  #)                     114570
  #crc32                 4
  gzip -cd "${SCRIPT_DIR}/bzImage-template-v4.gz" > "${ZIMAGE_MOD}"

  dd if="${VMLINUX_MOD}" of="${ZIMAGE_MOD}" bs=16494 seek=1 conv=notrunc >"${LOG_FILE}" 2>&1 || dieLog
  file_size_le "${VMLINUX_MOD}" | dd of="${ZIMAGE_MOD}" bs=15745134 seek=1 conv=notrunc >"${LOG_FILE}" 2>&1 || dieLog
  file_size_le "${VMLINUX_MOD}" | dd of="${ZIMAGE_MOD}" bs=15745244 seek=1 conv=notrunc >"${LOG_FILE}" 2>&1 || dieLog

  RUN_SIZE=`objdump -h ${VMLINUX_MOD} | sh "${SCRIPT_DIR}/calc_run_size.sh"`
  size_le ${RUN_SIZE} | dd of=${ZIMAGE_MOD} bs=15745210 seek=1 conv=notrunc >"${LOG_FILE}" 2>&1 || dieLog
  size_le $(($((16#`crc32 "${ZIMAGE_MOD}" | awk '{print$1}'`)) ^ 0xFFFFFFFF)) | dd of="${ZIMAGE_MOD}" conv=notrunc oflag=append >"${LOG_FILE}" 2>&1 || dieLog
else
  # Kernel version 5.x
  gzip -cd "${SCRIPT_DIR}/bzImage-template-v5.gz" > "${ZIMAGE_MOD}"

  lzma -9c ${VMLINUX_MOD} > ${TMP_PATH}/vmlinux-mod.lzma
  dd if="${TMP_PATH}/vmlinux-mod.lzma" of="${ZIMAGE_MOD}" bs=15377 seek=1 conv=notrunc >"${LOG_FILE}" 2>&1 || dieLog
  file_size_le "${VMLINUX_MOD}" | dd of="${ZIMAGE_MOD}" bs=8377991 seek=1 conv=notrunc >"${LOG_FILE}" 2>&1 || dieLog
  file_size_le "${VMLINUX_MOD}" | dd of="${ZIMAGE_MOD}" bs=8420412 seek=1 conv=notrunc >"${LOG_FILE}" 2>&1 || dieLog

  RUN_SIZE=`objdump -h ${VMLINUX_MOD} | sh "${SCRIPT_DIR}/calc_run_size.sh"`
  size_le ${RUN_SIZE} | dd of=${ZIMAGE_MOD} bs=8420408 seek=1 conv=notrunc >"${LOG_FILE}" 2>&1 || dieLog
  size_le $(($((16#`crc32 "${ZIMAGE_MOD}" | awk '{print$1}'`)) ^ 0xFFFFFFFF)) | dd of="${ZIMAGE_MOD}" conv=notrunc oflag=append >"${LOG_FILE}" 2>&1 || dieLog
fi
