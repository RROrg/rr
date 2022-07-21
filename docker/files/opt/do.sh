#!/usr/bin/env bash

set -e

function compile-module {
  # Validate
  if [ -z "${1}" ]; then
    echo "Use: compile-module <platform>"
    exit 1
  fi
  VALID=0
  while read PLATFORM KVER; do
    if [ "${PLATFORM}" = "${1}" ]; then
      VALID=1
      break
    fi
  done </opt/platforms
  if [ $VALID -eq 0 ]; then
    echo "Platform ${1} not found."
    exit 1
  fi
  echo "Compiling module for ${PLATFORM}-${KVER}..."
  cp -R /input /tmp
  make -C "/opt/${PLATFORM}" M="/tmp/input" ${PLATFORM^^}-Y=y ${PLATFORM^^}-M=m modules
  while read F; do
    strip -g "${F}"
    echo "Copying `basename ${F}`"
    cp "${F}" "/output"
  done < <(find /tmp/input -name \*.ko)
}

function compile-lkm {
  PLATFORM=${1}
  if [ -z "${PLATFORM}" ]; then
    echo "Use: compile-lkm <platform>"
    exit 1
  fi
  cp -R /input /tmp
  make -C "/tmp/input" LINUX_SRC="/opt/${PLATFORM}" dev-v7
  strip -g "/tmp/input/redpill.ko"
  mv "/tmp/input/redpill.ko" "/output/redpill-dev.ko"
  make -C "/tmp/input" LINUX_SRC="/opt/${PLATFORM}" clean
  make -C "/tmp/input" LINUX_SRC="/opt/${PLATFORM}" prod-v7
  strip -g "/tmp/input/redpill.ko"
  mv "/tmp/input/redpill.ko" "/output/redpill-prod.ko"
}

# function compile-drivers {
#   while read platform kver; do
#     SRC_PATH="/opt/${platform}"
#     echo "Compiling for ${platform}-${kver}"
#     cd /opt/linux-${kver}/drivers
#     while read dir; do
#       if [ -f "${dir}/Makefile" ]; then
#         echo "Driver `basename ${dir}`"
#         grep "CONFIG_.*/.*"   "${dir}/Makefile" | sed 's/.*\(CONFIG_[^)]*\).*/\1=n/g' >  /tmp/env
#         grep "CONFIG_.*\.o.*" "${dir}/Makefile" | sed 's/.*\(CONFIG_[^)]*\).*/\1=m/g' >> /tmp/env
#         make -C "${SRC_PATH}" M=$(readlink -f "${dir}") clean
#         cat /tmp/env | xargs -d '\n' make -C "${SRC_PATH}" M=$(readlink -f "${dir}") modules $@
#       fi
#     done < <(find -type d)
#     DST_PATH="/output/compiled-mods/${platform}-${kver}"
#     mkdir -p "${DST_PATH}"
#     while read f; do
#       strip -g "${f}"
#       mv "${f}" "${DST_PATH}"
#     done < <(find -name \*.ko)
#   done </opt/platforms
# }

if [ $# -lt 1 ]; then
  echo "Use: <command> (<params>)"
  exit 1
fi
case $1 in
  bash) shift; bash -l $@ ;;
  compile-module) compile-module $2 ;;
  compile-lkm) compile-lkm $2 ;;
  # compile-drivers) compile-drivers ;;
  *) echo "Command not recognized: $1" ;;
esac

