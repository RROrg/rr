#!/usr/bin/env bash

set -e

MODEL_CONFIG_PATH="./files/board/arpl/overlayfs/opt/arpl/model-configs"

RELEASE="7.0.1"
BUILDNUMBER="42218"
EXTRA=""

function readConfigKey() {
  RESULT=`yq eval '.'${1}' | explode(.)' "${2}"`
  [ "${RESULT}" == "null" ] && echo "" || echo ${RESULT}
}
function readModelKey() {
  readConfigKey "${2}" "${MODEL_CONFIG_PATH}/${1}.yml"
}

# JSON
cat <<EOF
      {
        "title": "DSM ${RELEASE}-${BUILDNUMBER}",
        "MajorVer": ${RELEASE:0:1},
        "MinorVer": ${RELEASE:2:1},
        "NanoVer": ${RELEASE:4:1},
        "BuildPhase": 0,
        "BuildNum": ${BUILDNUMBER},
        "BuildDate": "2022/08/01",
        "ReqMajorVer": 7,
        "ReqMinorVer": 1,
        "ReqBuildPhase": 0,
        "ReqBuildNum": 41890,
        "ReqBuildDate": "2021/06/25",
        "isSecurityVersion": false,
        "model": [
EOF

while read M; do
  M="`basename ${M}`"
  M="${M::-4}"
  UNIQUE=`readModelKey "${M}" "unique"`
  URL=`readModelKey "${M}" "builds.${BUILDNUMBER}.pat.url"`
  HASH=`readModelKey "${M}" "builds.${BUILDNUMBER}.pat.md5-hash"`
  cat <<EOF
          {
            "mUnique": "${UNIQUE}",
            "mLink": "${URL}",
            "mCheckSum": "${HASH}"
          },
EOF
done < <(find "${MODEL_CONFIG_PATH}" -maxdepth 1 -name \*.yml | sort)

cat <<EOF
        ]
      },
EOF

# XML
cat <<EOF
    <item>
      <title>DSM ${RELEASE}-${BUILDNUMBER}</title>
      <MajorVer>${RELEASE:0:1}</MajorVer>
      <MinorVer>${RELEASE:2:1}</MinorVer>
      <BuildPhase>${RELEASE:4:1}</BuildPhase>
      <BuildNum>${BUILDNUMBER}</BuildNum>
      <BuildDate>2022/08/01</BuildDate>
      <ReqMajorVer>7</ReqMajorVer>
      <ReqMinorVer>0</ReqMinorVer>
      <ReqBuildPhase>0</ReqBuildPhase>
      <ReqBuildNum>41890</ReqBuildNum>
      <ReqBuildDate>2021/06/25</ReqBuildDate>
EOF

while read M; do
  M="`basename ${M}`"
  M="${M::-4}"
  UNIQUE=`readModelKey "${M}" "unique"`
  URL=`readModelKey "${M}" "builds.${BUILDNUMBER}.pat.url"`
  HASH=`readModelKey "${M}" "builds.${BUILDNUMBER}.pat.md5-hash"`
  cat <<EOF
      <model>
        <mUnique>${UNIQUE}</mUnique>
        <mLink>${URL}</mLink>
        <mCheckSum>${HASH}</mCheckSum>
      </model>
EOF
done < <(find "${MODEL_CONFIG_PATH}" -maxdepth 1 -name \*.yml | sort)

cat <<EOF
    </item>
EOF
