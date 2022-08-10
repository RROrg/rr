#!/usr/bin/env bash

# Is necessary test the patches

set -e

declare -A KVERS
KVERS["DS918+"]="4.4.180"
KVERS["DS920+"]="4.4.180"
KVERS["DS1520+"]="4.4.180"
KVERS["DS1621+"]="4.4.180"
KVERS["DS2422+"]="4.4.180"
KVERS["DS3615xs"]="3.10.108"
KVERS["DS3617xs"]="4.4.180"
KVERS["DS3622xs+"]="4.4.180"
KVERS["DVA1622"]="4.4.180"
KVERS["DVA3221"]="4.4.180"
KVERS["FS2500"]="4.4.180"
KVERS["RS4021xs+"]="4.4.180"
RELEASE="7.1.1"
BUILDNUMBER="42951"

for MODEL in DS918+ DS920+ DS1520+ DS1621+ DS2422+ DS3615xs DS3617xs DS3622xs+ DVA1622 DVA3221 FS2500 RS4021xs+; do
  MODEL_CODED=`echo ${MODEL} | sed 's/+/%2B/g'`
  URL="https://global.download.synology.com/download/DSM/release/${RELEASE}/${BUILDNUMBER}/DSM_${MODEL_CODED}_${BUILDNUMBER}.pat"
  FILENAME="${MODEL}-${BUILDNUMBER}.pat"
  FILEPATH="/tmp/${FILENAME}"
  echo -n "Checking ${MODEL}... "
  if [ -f ${FILEPATH} ]; then
    echo "cached"
  else
    STATUS=`curl -s -o /dev/null -w "%{http_code}" -L "${URL}"`
    if [ ${STATUS} -ne 200 ]; then
      echo "error: HTTP status = %{STATUS}"
      continue
    fi
    echo "ok, download it."
    curl --progress-bar -C - -L "${URL}" -o ${FILEPATH}
  fi
  echo "Calculating sha256:"
  sudo rm -rf /tmp/extracted
  docker run --rm -it -v /tmp:/data syno-extractor /data/${FILENAME} /data/extracted
  PAT_CS=`sha256sum ${FILEPATH} | awk '{print$1}'`
  ZIMAGE_CS=`sha256sum /tmp/extracted/zImage | awk '{print$1}'`
  RD_CS=`sha256sum /tmp/extracted/rd.gz | awk '{print$1}'`
  sudo rm -rf /tmp/extracted
  cat <<EOF

  ${BUILDNUMBER}:
    ver: "${RELEASE}"
    kver: "${KVERS[${MODEL}]}"
    rd-compressed: false
    efi-bug: no
    cmdline:
      <<: *cmdline
    synoinfo:
      <<: *synoinfo
    pat:
      url: "${URL}"
      hash: "${PAT_CS}"
      ramdisk-hash: "${RD_CS}"
      zimage-hash: "${ZIMAGE_CS}"
    patch:
      - "ramdisk-common-disable-root-pwd.patch"
      - "ramdisk-common-init-script.patch"
      - "ramdisk-42951-post-init-script.patch"
      - "ramdisk-42661-disable-disabled-ports.patch"

EOF

done
