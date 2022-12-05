#!/usr/bin/env bash

set -e

###############################################################################
function export-vars() {
  # Validate
  if [ -z "${1}" ]; then
    echo "Use: export-vars <platform>"
    exit 1
  fi
  export PLATFORM="${1}"
  export KSRC="/opt/${1}/build"
  export CROSS_COMPILE="/opt/${1}/bin/x86_64-pc-linux-gnu-"
  export CFLAGS="-I/opt/${1}/include"
  export LDFLAGS="-I/opt/${1}/lib"
  export LD_LIBRARY_PATH="/opt/${1}/lib"
  export ARCH=x86_64
  export CC="x86_64-pc-linux-gnu-gcc"
  export LD="x86_64-pc-linux-gnu-ld"
  export PATH="/opt/${1}/bin:${PATH}"
}

###############################################################################
function shell() {
  cp /opt/${2}/build/System.map /input
  export-vars $2
  shift 2
  bash -l $@
}

###############################################################################
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
  echo -e "Compiling module for \033[7m${PLATFORM}-${KVER}\033[0m..."
  cp -R /input /tmp
  export-vars ${PLATFORM}
  make -C "/opt/${PLATFORM}/build" M="/tmp/input" \
       ${PLATFORM^^}-Y=y ${PLATFORM^^}-M=m modules
  while read F; do
    strip -g "${F}"
    echo "Copying `basename ${F}`"
    cp "${F}" "/output"
  done < <(find /tmp/input -name \*.ko)
}

###############################################################################
function compile-lkm {
  PLATFORM=${1}
  if [ -z "${PLATFORM}" ]; then
    echo "Use: compile-lkm <platform>"
    exit 1
  fi
  cp -R /input /tmp
  export-vars ${PLATFORM}
  export LINUX_SRC="/opt/${PLATFORM}/build"
  make -C "/tmp/input" dev-v7
  strip -g "/tmp/input/redpill.ko"
  mv "/tmp/input/redpill.ko" "/output/redpill-dev.ko"
  make -C "/tmp/input" clean
  make -C "/tmp/input" prod-v7
  strip -g "/tmp/input/redpill.ko"
  mv "/tmp/input/redpill.ko" "/output/redpill-prod.ko"
}

###############################################################################
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

###############################################################################
###############################################################################

if [ $# -lt 1 ]; then
  echo "Use: <command> (<params>)"
  echo "Commands: bash | shell <platform> | compile-module <platform> | compile-lkm <platform>"
  exit 1
fi
case $1 in
  bash) shift && bash -l $@ ;;
  shell) shell $@ ;;
  compile-module) compile-module $2 ;;
  compile-lkm) compile-lkm $2 ;;
  # compile-drivers) compile-drivers ;;
  *) echo "Command not recognized: $1" ;;
esac
