
ARPL_VERSION="0.3-alpha1"

# Define paths
TMP_PATH="/tmp"
UNTAR_PAT_PATH="${TMP_PATH}/pat"
RAMDISK_PATH="${TMP_PATH}/ramdisk"
LOG_FILE="${TMP_PATH}/log.txt"

USER_CONFIG_FILE="${BOOTLOADER_PATH}/user-config.yml"
MOD_ZIMAGE_FILE="${BOOTLOADER_PATH}/zImage"
MOD_RDGZ_FILE="${BOOTLOADER_PATH}/rd.gz"

ORI_ZIMAGE_FILE="${SLPART_PATH}/zImage"
ORI_RDGZ_FILE="${SLPART_PATH}/rd.gz"

ADDONS_PATH="${CACHE_PATH}/addons"
LKM_PATH="${CACHE_PATH}/lkms"

MODEL_CONFIG_PATH="/opt/arpl/model-configs"
INCLUDE_PATH="/opt/arpl/include"
PATCH_PATH="/opt/arpl/patch"
