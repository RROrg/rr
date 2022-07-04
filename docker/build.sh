#!/usr/bin/env bash

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
done <../PLATFORMS

# Download toolkits
mkdir -p cache
TOOLKIT_VER="7.0"
for PLATFORM in ${!PLATFORMS[@]}; do
  echo -n "Checking cache/ds.${PLATFORM}-${TOOLKIT_VER}.dev.txz... "
  if [ ! -f "cache/ds.${PLATFORM}-${TOOLKIT_VER}.dev.txz" ]; then
    URL="https://global.download.synology.com/download/ToolChain/toolkit/${TOOLKIT_VER}/${PLATFORM}/ds.${PLATFORM}-${TOOLKIT_VER}.dev.txz"
    echo "Downloading ${URL}"
    curl -L "${URL}" -o "cache/ds.${PLATFORM}-${TOOLKIT_VER}.dev.txz"
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

# Build
echo "Building... Drink a coffee and wait!"
docker image rm fbelavenuto/syno-compiler >/dev/null 2>&1
docker buildx build . --load --tag fbelavenuto/syno-compiler
