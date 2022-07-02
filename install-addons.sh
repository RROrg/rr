#!/usr/bin/env bash

set -e

SRC_PATH="addons"
DEST_PATH="files/board/arpl/p3/addons"

echo "Installing addons to ${DEST_PATH}"
for PKG in `ls ${SRC_PATH}/*.addon`; do
  ADDON=`basename ${PKG} | sed 's|.addon||'`
  mkdir -p "${DEST_PATH}/${ADDON}"
  echo "Extracting ${PKG} to ${DEST_PATH}/${ADDON}"
  tar xaf "${PKG}" -C "${DEST_PATH}/${ADDON}"
done
