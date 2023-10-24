RR_VERSION="23.10.4"
RR_TITLE="rr v${RR_VERSION}"

# Define paths
TMP_PATH="/tmp"
UNTAR_PAT_PATH="${TMP_PATH}/pat"
RAMDISK_PATH="${TMP_PATH}/ramdisk"
LOG_FILE="${TMP_PATH}/log.txt"

USER_CONFIG_FILE="${BOOTLOADER_PATH}/user-config.yml"
GRUB_PATH="${BOOTLOADER_PATH}/boot/grub"

ORI_ZIMAGE_FILE="${SLPART_PATH}/zImage"
ORI_RDGZ_FILE="${SLPART_PATH}/rd.gz"

RR_BZIMAGE_FILE="${CACHE_PATH}/bzImage-rr"
RR_RAMDISK_FILE="${CACHE_PATH}/initrd-rr"
MOD_ZIMAGE_FILE="${CACHE_PATH}/zImage-dsm"
MOD_RDGZ_FILE="${CACHE_PATH}/initrd-dsm"
ADDONS_PATH="${CACHE_PATH}/addons"
LKM_PATH="${CACHE_PATH}/lkms"
MODULES_PATH="${CACHE_PATH}/modules"
USER_UP_PATH="${CACHE_PATH}/users"

MODEL_CONFIG_PATH="/opt/rr/model-configs"
INCLUDE_PATH="/opt/rr/include"
PATCH_PATH="/opt/rr/patch"
