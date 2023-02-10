
ARPL_VERSION="1.1-beta2"

# Define paths
TMP_PATH="/tmp"
UNTAR_PAT_PATH="${TMP_PATH}/pat"
RAMDISK_PATH="${TMP_PATH}/ramdisk"
LOG_FILE="${TMP_PATH}/log.txt"

USER_CONFIG_FILE="${BOOTLOADER_PATH}/user-config.yml"
GRUB_PATH="${BOOTLOADER_PATH}/grub"

ORI_ZIMAGE_FILE="${SLPART_PATH}/zImage"
ORI_RDGZ_FILE="${SLPART_PATH}/rd.gz"

ARPL_BZIMAGE_FILE="${CACHE_PATH}/bzImage-arpl"
ARPL_RAMDISK_FILE="${CACHE_PATH}/initrd-arpl"
MOD_ZIMAGE_FILE="${CACHE_PATH}/zImage-dsm"
MOD_RDGZ_FILE="${CACHE_PATH}/initrd-dsm"
ADDONS_PATH="${CACHE_PATH}/addons"
LKM_PATH="${CACHE_PATH}/lkms"
MODULES_PATH="${CACHE_PATH}/modules"

MODEL_CONFIG_PATH="/opt/arpl/model-configs"
INCLUDE_PATH="/opt/arpl/include"
PATCH_PATH="/opt/arpl/patch"
