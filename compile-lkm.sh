#!/usr/bin/env bash

set -e

TMP_PATH="/tmp"
DEST_PATH="files/board/arpl/p3/lkms"

###############################################################################
function trap_cancel() {
    echo "Press Control+C once more terminate the process (or wait 2s for it to restart)"
    sleep 2 || exit 1
}
trap trap_cancel SIGINT SIGTERM

###############################################################################
function die() {
  echo -e "\033[1;31m$@\033[0m"
  exit 1
}

# Main
while read PLATFORM KVER; do
# Compile using docker
  docker run --rm -t --user `id -u` -v "${TMP_PATH}":/output \
    -v "${PWD}/redpill-lkm":/input fbelavenuto/syno-compiler compile-lkm ${PLATFORM}
  mv "${TMP_PATH}/redpill-dev.ko" "${DEST_PATH}/rp-${PLATFORM}-${KVER}-dev.ko"
  mv "${TMP_PATH}/redpill-prod.ko" "${DEST_PATH}/rp-${PLATFORM}-${KVER}-prod.ko"
done < PLATFORMS
