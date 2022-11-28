#!/usr/bin/env bash

CACHE_DIR="cache"
PLATFORM_FILE="../../PLATFORMS"

###############################################################################
function trap_cancel() {
    echo "Press Control+C once more terminate the process (or wait 2s for it to restart)"
    sleep 2 || exit 1
}
trap trap_cancel SIGINT SIGTERM
cd `dirname $0`

###############################################################################
function prepare() {
  declare -A URLS

  URLS["apollolake"]="https://global.download.synology.com/download/ToolChain/toolchain/${TOOLCHAIN_VER}/Intel%20x86%20Linux%204.4.180%20%28Apollolake%29/apollolake-${GCCLIB_VER}_x86_64-GPL.txz"
  URLS["broadwell"]="https://global.download.synology.com/download/ToolChain/toolchain/${TOOLCHAIN_VER}/Intel%20x86%20Linux%204.4.180%20%28Broadwell%29/broadwell-${GCCLIB_VER}_x86_64-GPL.txz"
  URLS["broadwellnk"]="https://global.download.synology.com/download/ToolChain/toolchain/${TOOLCHAIN_VER}/Intel%20x86%20Linux%204.4.180%20%28Broadwellnk%29/broadwellnk-${GCCLIB_VER}_x86_64-GPL.txz"
  URLS["bromolow"]="https://global.download.synology.com/download/ToolChain/toolchain/${TOOLCHAIN_VER}/Intel%20x86%20linux%203.10.108%20%28Bromolow%29/bromolow-${GCCLIB_VER}_x86_64-GPL.txz"
  URLS["denverton"]="https://global.download.synology.com/download/ToolChain/toolchain/${TOOLCHAIN_VER}/Intel%20x86%20Linux%204.4.180%20%28Denverton%29/denverton-${GCCLIB_VER}_x86_64-GPL.txz"
  URLS["geminilake"]="https://global.download.synology.com/download/ToolChain/toolchain/${TOOLCHAIN_VER}/Intel%20x86%20Linux%204.4.180%20%28GeminiLake%29/geminilake-${GCCLIB_VER}_x86_64-GPL.txz"
  URLS["v1000"]="https://global.download.synology.com/download/ToolChain/toolchain/${TOOLCHAIN_VER}/Intel%20x86%20Linux%204.4.180%20%28V1000%29/v1000-${GCCLIB_VER}_x86_64-GPL.txz"
  URLS["r1000"]="https://global.download.synology.com/download/ToolChain/toolchain/${TOOLCHAIN_VER}/AMD%20x86%20Linux%204.4.180%20%28r1000%29/r1000-${GCCLIB_VER}_x86_64-GPL.txz"

  # Read platforms/kerver version
  echo "Reading platforms"
  declare -A PLATFORMS
  while read PLATFORM KVER; do
    PLATFORMS[${PLATFORM}]="${KVER}"
  done < ${PLATFORM_FILE}

  # Download toolkits
  mkdir -p ${CACHE_DIR}

  for PLATFORM in ${!PLATFORMS[@]}; do
    KVER="${PLATFORMS[${PLATFORM}]}"
    echo -n "Checking ${CACHE_DIR}/ds.${PLATFORM}-${TOOLKIT_VER}.dev.txz... "
    if [ ! -f "${CACHE_DIR}/ds.${PLATFORM}-${TOOLKIT_VER}.dev.txz" ]; then
      URL="https://global.download.synology.com/download/ToolChain/toolkit/${TOOLKIT_VER}/${PLATFORM}/ds.${PLATFORM}-${TOOLKIT_VER}.dev.txz"
      echo "Downloading ${URL}"
      curl -L "${URL}" -o "${CACHE_DIR}/ds.${PLATFORM}-${TOOLKIT_VER}.dev.txz"
    else
      echo "OK"
    fi
    echo -n "Checking ${CACHE_DIR}/${PLATFORM}-toolchain.txz... "
    if [ ! -f "${CACHE_DIR}/${PLATFORM}-toolchain.txz" ]; then
      URL=${URLS["${PLATFORM}"]}
      echo "Downloading ${URL}"
      curl -L "${URL}" -o "${CACHE_DIR}/${PLATFORM}-toolchain.txz"
    else
      echo "OK"
    fi
  done

  # Generate Dockerfile
  echo "Generating Dockerfile"
  cp Dockerfile.template Dockerfile
  VALUE=""
  for PLATFORM in ${!PLATFORMS[@]}; do
    VALUE+="${PLATFORM}:${PLATFORMS[${PLATFORM}]} "
  done
  sed -i "s|@@@PLATFORMS@@@|${VALUE::-1}|g" Dockerfile
  sed -i "s|@@@TOOLKIT_VER@@@|${TOOLKIT_VER}|g" Dockerfile
}

# 7.0
#TOOLKIT_VER="7.0"
#TOOLCHAIN_VER="7.0-41890"
#GCCLIB_VER="gcc750_glibc226"
#prepare
#echo "Building ${TOOLKIT_VER}"
#docker image rm fbelavenuto/syno-compiler:${TOOLKIT_VER} >/dev/null 2>&1
#docker buildx build . --load --tag fbelavenuto/syno-compiler:${TOOLKIT_VER}

# 7.1
TOOLKIT_VER="7.1"
TOOLCHAIN_VER="7.1-42661"
GCCLIB_VER="gcc850_glibc226"
prepare
echo "Building ${TOOLKIT_VER}"
docker image rm fbelavenuto/syno-compiler:${TOOLKIT_VER} >/dev/null 2>&1
docker buildx build . --load --tag fbelavenuto/syno-compiler:${TOOLKIT_VER} --tag fbelavenuto/syno-compiler:latest
