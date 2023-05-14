#!/usr/bin/env bash

set -e

. /opt/arpl/include/functions.sh

# Detect if has new local plugins to install/reinstall
for F in `ls ${CACHE_PATH}/*.addon 2>/dev/null`; do
  ADDON=`basename "${F}" | sed 's|.addon||'`
  rm -rf "${ADDONS_PATH}/${ADDON}"
  mkdir -p "${ADDONS_PATH}/${ADDON}"
  echo "Installing ${F} to ${ADDONS_PATH}/${ADDON}"
  tar -xaf "${F}" -C "${ADDONS_PATH}/${ADDON}"
  rm -f "${F}"
done
