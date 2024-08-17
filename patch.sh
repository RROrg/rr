#!/bin/sh
set -eo pipefail;
shopt -s nullglob;

#variables
bin_file="synocodectool"
conf_file="activation.conf"
conf_path="/usr/syno/etc/codec"
conf_string='{"success":true,"activated_codec":["hevc_dec","ac3_dec","h264_dec","h264_enc","aac_dec","aac_enc","mpeg4part2_dec","vc1_dec","vc1_enc"],"token":"123456789987654abc"}'
opmode="patchhelp"

#arrays
declare -A binhash_version_list=(
    ["cde88ed8fdb2bfeda8de52ef3adede87a72326ef"]="6.0-7321-0_6.0.3-8754-8"
    ["ec0c3f5bbb857fa84f5d1153545d30d7b408520b"]="6.1-15047-0_6.1.1-15101-4"
    ["1473d6ad6ff6e5b8419c6b0bc41006b72fd777dd"]="6.1.2-15132-0_6.1.3-15152-8"
    ["26e42e43b393811c176dac651efc5d61e4569305"]="6.1.4-15217-0_6.2-23739-2"
    ["1d01ee38211f21c67a4311f90315568b3fa530e6"]="6.2.1-23824-0_6.2.3-25426-3"
    ["c2f07f4cebf0bfb63e3ca38f811fd5b6112a797e"]="7.0.1-42216-0_7.0.1-42218-3"
    ["796ac7fab2dcad7978a0e8ae48abc9150aba916c"]="7.1-42661-0_7.1-42661-0"
    ["22445f5b0d8b6714954b50930c47b8805cf32b98"]="7.1-42661-0_7.1-42661-0"
    ["18461b62813166652fd64a96e06237fde81925f7"]="7.1.1-42962-0_7.1.1-42962-6"
    ["d316d5b2b080346b4bc197ad5ad7994ac043a15d"]="7.2-64570-0_7.2-64570-1"
    ["a205aa337d808213cf6d4d839b035cde0237b424"]="7.2.1-69057-0_7.2.1-69057-5"
)

declare -A patchhash_binhash_list=(
    ["e5c1a65b3967968560476fcda5071fd37db40223"]="cde88ed8fdb2bfeda8de52ef3adede87a72326ef"
    ["d58f5b33ff2b6f2141036837ddf15dd5188384c6"]="ec0c3f5bbb857fa84f5d1153545d30d7b408520b"
    ["56ca9adaf117e8aae9a3a2e29bbcebf0d8903a99"]="1473d6ad6ff6e5b8419c6b0bc41006b72fd777dd"
    ["511dec657daa60b0f11da20295e2c665ba2c749c"]="26e42e43b393811c176dac651efc5d61e4569305"
    ["93067026c251b100e27805a8b4b9d8f0ae8e291c"]="1d01ee38211f21c67a4311f90315568b3fa530e6"
    ["873749b00e1624df4b01335e0b69102acc185eb9"]="c2f07f4cebf0bfb63e3ca38f811fd5b6112a797e"
    ["06d543b2aab5ea73600ca96497febdad96dc7864"]="796ac7fab2dcad7978a0e8ae48abc9150aba916c"
    ["3a5ed18dc41ff243f3481b6e3cf4770651df0b54"]="22445f5b0d8b6714954b50930c47b8805cf32b98"
    ["4bfa2a72da607752435e432545f98f1a0b3815a8"]="18461b62813166652fd64a96e06237fde81925f7"
    ["8ffe49d91dc0fcd3268ff1afcbc9132d1ae634d1"]="d316d5b2b080346b4bc197ad5ad7994ac043a15d"
    ["1f4491bf5f27f0719ddebdcab6ff4eff56c64b2c"]="a205aa337d808213cf6d4d839b035cde0237b424"
)

declare -A binhash_patch_list=(
    ["cde88ed8fdb2bfeda8de52ef3adede87a72326ef"]="00002dc0: 27000084c0eb4cb9b6000000badd6940\n00003660: 24f0000000e8961e000084c00f84b400"
    ["ec0c3f5bbb857fa84f5d1153545d30d7b408520b"]="00002dc0: 27000084c0eb4cb9b7000000bafd6940\n000036f0: 0000e8291e000084c0eb1eb9ec000000"
    ["1473d6ad6ff6e5b8419c6b0bc41006b72fd777dd"]="00002dc0: 27000084c0eb4cb9b7000000baad6a40\n000036f0: 0000e8291e000084c0eb1eb9ec000000"
    ["26e42e43b393811c176dac651efc5d61e4569305"]="00002dc0: 27000084c0eb4cb9ba000000badf6a40\n00003710: f0000000e8271e000084c0eb1eb9ef00"
    ["1d01ee38211f21c67a4311f90315568b3fa530e6"]="00002dc0: 27000084c0eb4cb9bd000000baf76a40\n00003720: 24f0000000e8261e000084c0eb1eb9f2"
    ["c2f07f4cebf0bfb63e3ca38f811fd5b6112a797e"]="00002dc0: 000084c0eb2141b8c1000000b9586c40\n00003780: 1d000084c0e90d0100009041b8f60000"
    ["796ac7fab2dcad7978a0e8ae48abc9150aba916c"]="000035b0: 74cd4889efe8f623000084c0eb004c8d\n000040a0: fdffff4c89efe80519000084c0eb0048"
    ["22445f5b0d8b6714954b50930c47b8805cf32b98"]="00003850: e7e89a27000084c0eb00488dac249000\n00004340: fdffff4c89efe8a51c000084c0eb0048"
    ["18461b62813166652fd64a96e06237fde81925f7"]="000038e0: e7e89a27000084c0eb00488dac249000\n000043d0: fdffff4c89efe8a51c000084c0eb0048"
    ["d316d5b2b080346b4bc197ad5ad7994ac043a15d"]="00004220: 08fdffffe87722000084c090e9000000\n00004390: ffe80a21000084c090e900000000488b"
    ["a205aa337d808213cf6d4d839b035cde0237b424"]="00004220: 08fdffffe87722000084c090e9000000\n00004390: ffe80a21000084c090e900000000488b"
)

declare -a binpath_list=()

declare -a path_list=(
    "/usr/syno/bin"
    "/volume1/@appstore/VideoStation/bin"
    "/volume2/@appstore/VideoStation/bin"
    "/volume3/@appstore/VideoStation/bin"
    "/volume1/@appstore/MediaServer/bin"
    "/volume2/@appstore/MediaServer/bin"
    "/volume3/@appstore/MediaServer/bin"
    "/volume1/@appstore/SurveillanceStation/bin"
    "/volume2/@appstore/SurveillanceStation/bin"
    "/volume3/@appstore/SurveillanceStation/bin"
    "/volume1/@appstore/CodecPack/bin"
    "/volume2/@appstore/CodecPack/bin"
    "/volume3/@appstore/CodecPack/bin"
    "/volume1/@appstore/AudioStation/bin"
    "/volume2/@appstore/AudioStation/bin"
    "/volume3/@appstore/AudioStation/bin"
)

declare -a versions_list=(
    "6.0 7321-0"
    "6.0 7321-1"
    "6.0 7321-2"
    "6.0 7321-3"
    "6.0 7321-4"
    "6.0 7321-5"
    "6.0 7321-6"
    "6.0 7321-7"
    "6.0.1 7393-0"
    "6.0.1 7393-1"
    "6.0.1 7393-2"
    "6.0.2 8451-0"
    "6.0.2 8451-1"
    "6.0.2 8451-2"
    "6.0.2 8451-3"
    "6.0.2 8451-4"
    "6.0.2 8451-5"
    "6.0.2 8451-6"
    "6.0.2 8451-7"
    "6.0.2 8451-8"
    "6.0.2 8451-9"
    "6.0.2 8451-10"
    "6.0.2 8451-11"
    "6.0.3 8754-0"
    "6.0.3 8754-1"
    "6.0.3 8754-2"
    "6.0.3 8754-3"
    "6.0.3 8754-4"
    "6.0.3 8754-5"
    "6.0.3 8754-6"
    "6.0.3 8754-7"
    "6.0.3 8754-8"
    "6.1 15047-0"
    "6.1 15047-1"
    "6.1 15047-2"
    "6.1.1 15101-0"
    "6.1.1 15101-1"
    "6.1.1 15101-2"
    "6.1.1 15101-3"
    "6.1.1 15101-4"
    "6.1.2 15132-0"
    "6.1.2 15132-1"
    "6.1.3 15152-0"
    "6.1.3 15152-1"
    "6.1.3 15152-2"
    "6.1.3 15152-3"
    "6.1.3 15152-4"
    "6.1.3 15152-5"
    "6.1.3 15152-6"
    "6.1.3 15152-7"
    "6.1.3 15152-8"
    "6.1.4 15217-0"
    "6.1.4 15217-1"
    "6.1.4 15217-2"
    "6.1.4 15217-3"
    "6.1.4 15217-4"
    "6.1.4 15217-5"
    "6.1.4 15217-0"
    "6.1.5 15254-0"
    "6.1.5 15254-1"
    "6.1.6 15266-0"
    "6.1.6 15266-1"
    "6.1.7 15284-0"
    "6.1.7 15284-1"
    "6.1.7 15284-2"
    "6.1.7 15284-3"
    "6.2 23739-0"
    "6.2 23739-1"
    "6.2 23739-2"
    "6.2.1 23824-0"
    "6.2.1 23824-1"
    "6.2.1 23824-2"
    "6.2.1 23824-3"
    "6.2.1 23824-4"
    "6.2.1 23824-5"
    "6.2.1 23824-6"
    "6.2.2 24922-0"
    "6.2.2 24922-1"
    "6.2.2 24922-2"
    "6.2.2 24922-3"
    "6.2.2 24922-4"
    "6.2.2 24922-5"
    "6.2.2 24922-6"
    "6.2.3 25423-0"
    "6.2.3 25426-0"
    "6.2.3 25426-2"
    "6.2.3 25426-3"
    "7.0.1 42218-0"
    "7.0.1 42218-1"
    "7.0.1 42218-2"
    "7.0.1 42218-3"
    "7.1 42661-0"
    "7.1 42661-1"
    "7.1 42661-2"
    "7.1 42661-3"
    "7.1 42661-4"
    "7.1.1 42951"
    "7.1.1 42962-0"
    "7.1.1 42962-1"
    "7.1.1 42962-2"
    "7.1.1 42962-3"
    "7.1.1 42962-4"
    "7.1.1 42962-5"
    "7.1.1 42962-6"
    "7.2 64570-0"
    "7.2 64570-1"
    "7.2.1 69057-0"
    "7.2.1 69057-1"
    "7.2.1 69057-2"
    "7.2.1 69057-3"
    "7.2.1 69057-4"
    "7.2.1 69057-5"
)

#functions
print_usage() { 
printf "
SYNOPSIS
    patch.sh [-h] [-p|-r|-l]
DESCRIPTION
    Patch to enable transcoding without a valid serial in DSM 6+
        -h      Print this help message
        -p      Patch synocodectool
        -r      Restore from original from backup
        -l      List supported DSM versions
"
}
check_path () {
    for i in "${path_list[@]}"; do
        if [ -e "$i/$bin_file" ]; then
            binpath_list+=( "$i/$bin_file" )
        fi
    done
}

check_version () {
    local ver="$1"
    for i in "${versions_list[@]}" ; do
        [[ "$i" == "$ver" ]] && return 0
    done ||  return 1
}

list_versions () {
    for i in "${versions_list[@]}"; do
        echo "$i"
    done
    return 0
}

patch_menu() {
    local options=("$@")
    echo "Available binaries to patch/restore:"
    local PS3="Please choose which binary you want to patch/restore:"
    select option in "${options[@]}" "Quit"; do    
    if [[ $REPLY = "$(( ${#options[@]}+1 ))" ]] ; then
        echo "Goodbye"
        exit 0
    fi
    bin_path="$option"
    break
done
}

restore_menu() {
    local options=("$@")
    echo "Available backups to restore:"
    local PS3="Please choose which binary you want to restore to $bin_path:"
    select option in "${options[@]}" "Quit"; do    
    if [[ $REPLY = "$(( ${#options[@]}+1 ))" ]] ; then
        echo "Goodbye"
        exit 0
    fi
    backup_file="$option"
    break
done
}

patch_common () {
    source "/etc/VERSION"
    dsm_version="$productversion $buildnumber-$smallfixnumber"
    if [[ ! "$dsm_version" ]] ; then
        echo "Something went wrong. Could not fetch DSM version"
        exit 1
    fi

    echo "Detected DSM version: $dsm_version"

    if ! check_version "$dsm_version" ; then
        echo "Patch for DSM Version ($dsm_version) not found."
        echo "Patch is available for versions: "
        list_versions
        exit 1
    fi
    
    echo "Patch for DSM Version ($dsm_version) AVAILABLE!"    
    check_path
    
    if  ! (( ${#binpath_list[@]} )) ; then
        echo "Something went wrong. Could not find synocodectool"
        exit 1
    fi
    
    patch_menu "${binpath_list[@]}"
}

patch () {
    patch_common
    local backup_path="${bin_path%??????????????}/backup"
    local synocodectool_hash="$(sha1sum "$bin_path" | cut -f1 -d\ )"
    if [[ "${binhash_version_list[$synocodectool_hash]+isset}" ]] ; then
        local backup_identifier="${synocodectool_hash:0:8}"
        if [[ -f "$backup_path/$bin_file.$backup_identifier" ]]; then
            backup_hash="$(sha1sum "$backup_path/$bin_file.$backup_identifier" | cut -f1 -d\ )"
            if [[ "${binhash_version_list[$backup_hash]+isset}" ]]; then
                echo "Restored synocodectool and valid backup detected (DSM ${binhash_version_list[$backup_hash]}) . Patching..."
                echo -e "${binhash_patch_list[$synocodectool_hash]}" | xxd -r - "$bin_path"                
                echo "Patched successfully"
                echo "Creating spoofed activation.conf.."
                if [ ! -e "$conf_path/$conf_file" ] ; then
                    mkdir -p $conf_path
                    echo "$conf_string" > "$conf_path/$conf_file"
                    chattr +i "$conf_path/$conf_file"
                    echo "Spoofed activation.conf created successfully"
                    exit 0
                    else
                    chattr -i "$conf_path/$conf_file"
                    rm "$conf_path/$conf_file"
                    echo "$conf_string" > "$conf_path/$conf_file"
                    chattr +i "$conf_path/$conf_file"
                    echo "Spoofed activation.conf created successfully"
                    exit 0
                fi
            else
                echo "Corrupted backup and original synocodectool detected. Overwriting backup..."
                mkdir -p "$backup_path"
                cp -p "$bin_path" \
                "$backup_path/$bin_file.$backup_identifier"
                exit 0
            fi
        else    
            echo "Detected valid synocodectool. Creating backup.."
            mkdir -p "$backup_path"
            cp -p "$bin_path" \
            "$backup_path/$bin_file.$backup_identifier"
            echo "Patching..."
            echo -e "${binhash_patch_list[$synocodectool_hash]}" | xxd -r - "$bin_path"            
            echo "Patched"
            echo "Creating spoofed activation.conf.."
            if [ ! -e "$conf_path/$conf_file" ] ; then
                mkdir -p $conf_path
                echo "$conf_string" > "$conf_path/$conf_file"
                chattr +i "$conf_path/$conf_file"
                echo "Spoofed activation.conf created successfully"
                exit 0
            else
                chattr -i "$conf_path/$conf_file"
                rm "$conf_path/$conf_file"
                echo "$conf_string" > "$conf_path/$conf_file"
                chattr +i "$conf_path/$conf_file"
                echo "Spoofed activation.conf created successfully"
                exit 0
            fi
        fi
    elif [[ "${patchhash_binhash_list[$synocodectool_hash]+isset}" ]]; then
        local original_hash="${patchhash_binhash_list[$synocodectool_hash]}"
        local backup_identifier="${original_hash:0:8}"
        if [[ -f "$backup_path/$bin_file.$backup_identifier" ]]; then
            backup_hash="$(sha1sum "$backup_path/$bin_file.$backup_identifier" | cut -f1 -d\ )"
            if [[ "$original_hash"="$backup_hash" ]]; then
                echo "Valid backup and patched synocodectool detected. Skipping patch."
                exit 0
            else
                echo "Patched synocodectool and corrupted backup detected. Skipping patch."
                exit 1
            fi
        else
            echo "Patched synocodectool and no backup detected. Skipping patch."
            exit 1  
        fi
    else
            echo "Corrupted synocodectool detected. Please use the -r option to try restoring it."
            exit 1
    fi 
}

rollback () {
    patch_common
    local backup_path="${bin_path%??????????????}/backup"
    local synocodectool_hash="$(sha1sum "$bin_path" | cut -f1 -d\ )"
    if [[ "${patchhash_binhash_list[$synocodectool_hash]+isset}" ]] ; then
        local original_hash="${patchhash_binhash_list[$synocodectool_hash]}"
        local backup_identifier="${original_hash:0:8}"
        if [[ -e "$backup_path/$bin_file.$backup_identifier" ]] ; then
            local backup_hash="$(sha1sum "$backup_path/$bin_file.$backup_identifier" | cut -f1 -d\ )"
                if [[ "$original_hash" = "$backup_hash" ]]; then
                    cp -p "$backup_path/$bin_file.$backup_identifier" \
                    "$bin_path"
                    echo "Backup restored successfully (DSM ${binhash_version_list[$backup_hash]})"
                    exit 0
                else
                    echo "No valid backup found for patched synocodectool currently in use. You can download the original file for DSM ${binhash_version_list[$original_hash]}  from https://github.com/stl88083365/synocodectool-patch/."
                    exit 1
                fi
        else
            echo "No backups found for patched synocodectool currently in use. You can download the original file for DSM ${binhash_version_list[$original_hash]}  from https://github.com/stl88083365/synocodectool-patch/."
            exit 1
        fi
    elif [[ "${binhash_version_list[$synocodectool_hash]+isset}" ]]; then
        echo "Detected unpatched original synocodectool. Restoring not neccessary!"
        exit 0
    else
        echo "Detected corrupted synocodectool."
        local backup_files=( "$backup_path"/* )
        if (( ${#backup_files[@]} )); then
            restore_menu "${backup_files[@]}"
            echo "Checking Hash.."
            local backup_hash="$(sha1sum "$backup_file" | cut -f1 -d\ )"
            if [[ "${binhash_version_list[$backup_hash]+isset}" ]]; then
                cp -p "$backup_file" \
                "$bin_path"
                echo "Backup restored successfully (DSM ${binhash_version_list[$backup_hash]})"
                exit 0
            else
                echo "Not a valid backup. You can either try restoring another backup or download the original file for DSM $dsm_version from https://github.com/stl88083365/synocodectool-patch/."
                exit 1
            fi
        else
            echo "No backups found. You can download the original file for DSM $dsm_version from https://github.com/stl88083365/synocodectool-patch/."
            exit 1
        fi
    fi        
}

#main()
if (( $EUID != 0 )); then
    echo "Please run as root"
    exit 1
fi

while getopts "prhl" flag; do
    case "${flag}" in
        p) opmode="patch";;
        r) opmode="patchrollback" ;;
        h) opmode="${opmode}" ;;
        l) opmode="listversions" ;;
        *) echo "Incorrect option specified in command line" ; exit 2 ;;
    esac
done

case "${opmode}" in
    patch) patch ;;
    patchrollback) rollback ;;
    patchhelp) print_usage ; exit 2 ;;
    listversions) list_versions ;;
    *) echo "Incorrect combination of flags. Use option -h to get help."
       exit 2 ;;
esac
