#!/usr/bin/env bash

set -e

###############################################################################
function compile-module {
  echo -e "Compiling module for \033[7m${PLATFORM}\033[0m..."
  cp -R /input /tmp
  make -C ${KSRC} M=/tmp/input ${PLATFORM^^}-Y=y ${PLATFORM^^}-M=m modules
  while read F; do
    strip -g "${F}"
    echo "Copying `basename ${F}`"
    cp "${F}" "/output"
    chown 1000.1000 "/output/`basename ${F}`"
  done < <(find /tmp/input -name \*.ko)
}

###############################################################################
function compile-lkm {
  cp -R /input /tmp
  make -C "/tmp/input" dev-v7
  strip -g "/tmp/input/redpill.ko"
  mv "/tmp/input/redpill.ko" "/output/redpill-dev.ko"
  chown 1000.1000 /output/redpill-dev.ko
  make -C "/tmp/input" clean
  make -C "/tmp/input" prod-v7
  strip -g "/tmp/input/redpill.ko"
  mv "/tmp/input/redpill.ko" "/output/redpill-prod.ko"
  chown 1000.1000 /output/redpill-prod.ko
}

###############################################################################
###############################################################################

if [ $# -lt 1 ]; then
  echo "Use: <command> (<params>)"
  echo "Commands: shell | compile-module | compile-lkm"
  exit 1
fi
export KSRC="/usr/local/x86_64-pc-linux-gnu/x86_64-pc-linux-gnu/sys-root/usr/lib/modules/DSM-${TOOLKIT_VER}/build"
export LINUX_SRC="/usr/local/x86_64-pc-linux-gnu/x86_64-pc-linux-gnu/sys-root/usr/lib/modules/DSM-${TOOLKIT_VER}/build"
export CROSS_COMPILE="/usr/local/x86_64-pc-linux-gnu/bin/x86_64-pc-linux-gnu-"
export ARCH=x86_64
export CC="x86_64-pc-linux-gnu-gcc"
export LD="x86_64-pc-linux-gnu-ld"

case $1 in
  shell) shift && bash -l $@ ;;
  compile-module) compile-module ;;
  compile-lkm) compile-lkm ;;
  *) echo "Command not recognized: $1" ;;
esac
