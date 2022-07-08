#!/usr/bin/env bash

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
    echo "Platform ${PLATFORM} not found."
    exit 1
  fi
  echo "Compiling module for ${PLATFORM}-${KVER}..."
  cp -R /input /tmp
  make -C "/opt/${PLATFORM}" M="/tmp/input" PLATFORM=${PLATFORM^^} modules
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

if [ $# -lt 1 ]; then
  echo "Use: <command> (<params>)"
  exit 1
fi
case $1 in
  bash) bash -l ;;
  compile-module) compile-module $2 ;;
  compile-lkm) compile-lkm $2 ;;
  *) echo "Command not recognized: $1" ;;
esac
