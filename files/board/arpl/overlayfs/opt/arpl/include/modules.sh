
###############################################################################
# Return list of all modules available
# 1 - Platform
# 2 - Kernel Version
function getAllModules() {
  PLATFORM=${1}
  KVER=${2}
  # Unzip modules for temporary folder
  rm -rf "${TMP_PATH}/modules"
  mkdir -p "${TMP_PATH}/modules"
  tar -zxf "${MODULES_PATH}/${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules"
  # Get list of all modules
  for F in `ls ${TMP_PATH}/modules/*.ko`; do
    X=`basename ${F}`
    M=${X:0:-3}
    DESC=`modinfo ${F} | awk -F':' '/description:/{ print $2}' | awk '{sub(/^[ ]+/,""); print}'`
    [ -z "${DESC}" ] && DESC="${X}"
    echo "${M} \"${DESC}\""
  done
  rm -rf "${TMP_PATH}/modules"
}

###############################################################################
# add a ko of modules.tgz
# 1 - Platform
# 2 - Kernel Version
# 3 - ko file
function addToModules() {
  PLATFORM=${1}
  KVER=${2}
  KOFILE=${3}
  # Unzip modules for temporary folder
  rm -rf "${TMP_PATH}/modules"
  mkdir -p "${TMP_PATH}/modules"
  tar -zxf "${MODULES_PATH}/${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules"
  cp -f ${KOFILE} ${TMP_PATH}/modules
  tar -zcf "${MODULES_PATH}/${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules" .
}

###############################################################################
# del a ko of modules.tgz
# 1 - Platform
# 2 - Kernel Version
# 3 - ko name
function delToModules() {
  PLATFORM=${1}
  KVER=${2}
  KONAME=${3}
  # Unzip modules for temporary folder
  rm -rf "${TMP_PATH}/modules"
  mkdir -p "${TMP_PATH}/modules"
  tar -zxf "${MODULES_PATH}/${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules"
  rm -f ${TMP_PATH}/modules/${KONAME}
  tar -zcf "${MODULES_PATH}/${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules" .
}

###############################################################################
# get depends of ko
# 1 - Platform
# 2 - Kernel Version
# 3 - ko name
function getdepends() {
  function _getdepends() {
    if [ -f "${TMP_PATH}/modules/${1}.ko" ]; then
      depends=(`modinfo "${TMP_PATH}/modules/${1}.ko" | grep depends: | awk -F: '{print $2}' | awk '$1=$1' | sed 's/,/ /g'`)
      if [ ${#depends[*]} > 0 ]; then
          for k in ${depends[@]}
          do 
            echo "${k}"
            _getdepends "${k}"
          done
      fi
    fi
  }
  PLATFORM=${1}
  KVER=${2}
  KONAME=${3}
  # Unzip modules for temporary folder
  rm -rf "${TMP_PATH}/modules"
  mkdir -p "${TMP_PATH}/modules"
  tar -zxf "${MODULES_PATH}/${PLATFORM}-${KVER}.tgz" -C "${TMP_PATH}/modules"
  DPS=(`_getdepends ${KONAME} | tr ' ' '\n' | sort -u`)
  echo ${DPS[@]}
  rm -rf "${TMP_PATH}/modules"
}