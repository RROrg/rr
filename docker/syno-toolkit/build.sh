#!/usr/bin/env bash

set -e

CACHE_DIR="cache"
PLATFORM_FILE="../../PLATFORMS"
TOOLKIT_VER=7.1

###############################################################################
function trap_cancel() {
    echo "Press Control+C once more terminate the process (or wait 2s for it to restart)"
    sleep 2 || exit 1
}
trap trap_cancel SIGINT SIGTERM
cd `dirname $0`

# Read platforms/kerver version
echo "Reading platforms"
declare -A PLATFORMS
while read PLATFORM KVER; do
  PLATFORMS[${PLATFORM}]="${KVER}"
done < ${PLATFORM_FILE}

# Download toolkits
mkdir -p ${CACHE_DIR}

# Check base environment
echo -n "Checking ${CACHE_DIR}/base_env-${TOOLKIT_VER}.txz... "
if [ ! -f "${CACHE_DIR}/base_env-${TOOLKIT_VER}.txz" ]; then
  URL="https://global.download.synology.com/download/ToolChain/toolkit/${TOOLKIT_VER}/${PLATFORM}/base_env-${TOOLKIT_VER}.txz"
  echo "Downloading ${URL}"
  curl -L "${URL}" -o "${CACHE_DIR}/base_env-${TOOLKIT_VER}.txz"
else
  echo "OK"
fi

# Check all platforms
for PLATFORM in ${!PLATFORMS[@]}; do
  echo -n "Checking ${CACHE_DIR}/ds.${PLATFORM}-${TOOLKIT_VER}.dev.txz... "
  if [ ! -f "${CACHE_DIR}/ds.${PLATFORM}-${TOOLKIT_VER}.dev.txz" ]; then
    URL="https://global.download.synology.com/download/ToolChain/toolkit/${TOOLKIT_VER}/${PLATFORM}/ds.${PLATFORM}-${TOOLKIT_VER}.dev.txz"
    echo "Downloading ${URL}"
    curl -L "${URL}" -o "${CACHE_DIR}/ds.${PLATFORM}-${TOOLKIT_VER}.dev.txz"
  else
    echo "OK"
  fi
  echo -n "Checking ${CACHE_DIR}/ds.${PLATFORM}-${TOOLKIT_VER}.env.txz... "
  if [ ! -f "${CACHE_DIR}/ds.${PLATFORM}-${TOOLKIT_VER}.env.txz" ]; then
    URL="https://global.download.synology.com/download/ToolChain/toolkit/${TOOLKIT_VER}/${PLATFORM}/ds.${PLATFORM}-${TOOLKIT_VER}.env.txz"
    echo "Downloading ${URL}"
    curl -L "${URL}" -o "${CACHE_DIR}/ds.${PLATFORM}-${TOOLKIT_VER}.env.txz"
  else
    echo "OK"
  fi
done

# Generate docker images
for PLATFORM in ${!PLATFORMS[@]}; do
  docker buildx build . --build-arg PLATFORM=${PLATFORM} --build-arg TOOLKIT_VER=${TOOLKIT_VER} --build-arg CACHE_DIR="${CACHE_DIR}" \
    --tag fbelavenuto/syno-toolkit:${PLATFORM}-${TOOLKIT_VER} --load
done
