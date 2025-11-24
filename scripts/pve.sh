#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

REPO="https://github.com/RROrg/rr"

# 参数
ONBOOT=1      # 开机启动，默认1
EFI=1         # 启用 UEFI 引导，默认1
BLTYPE="sata" # 引导盘类型， 支持 sata,usb,nvme 默认 sata
STORAGE=""    # 存储，默认自动获取
V9PPATH=""    # 添加 virtio9p 挂载目录，默认空不添加
VFSDIRID=""   # 添加 virtiofs 挂载文件夹id，默认空不添加
TAG=""        # 镜像tag，默认自动获取
IMG=""        # 本地镜像路径，默认空

usage() {
  echo "Usage: $0 [--onboot <0|1>] [--efi <0|1>] [--bltype <sata|usb|nvme>] [--storage <name>]"
  echo "          [--v9ppath <path>] [--vfsdirid <dirid>] [--tag <tag>] [--img <path>]"
  echo ""
  echo "  --onboot <0|1>             Enable VM on boot, default 1 (enable)"
  echo "  --efi <0|1>                Enable UEFI boot, default 1 (enable)"
  echo "  --bltype <sata|usb|nvme>   Bootloader disk type, default sata"
  echo "  --storage <name>           Storage name for images, as local-lvm, default auto get"
  echo "  --v9ppath <path>           Set to /path/to/9p to mount virtio 9p share"
  echo "  --vfsdirid <dirid>         Set to <dirid> to mount virtio fs share"
  echo "  --tag <tag>                Image tag, download latest release if not set"
  echo "  --img <path>               Local image path, use local image if set"
}

ARGS=$(getopt -o '' --long onboot:,efi:,bltype:,storage:,v9ppath:,vfsdirid:,tag:,img: -n "$0" -- "$@")
if [ $? -ne 0 ]; then
  usage
  exit 1
fi
eval set -- "$ARGS"
while true; do
  case "$1" in
  --onboot)
    ONBOOT="$2"
    echo "$ONBOOT" | grep -qvE '^(0|1)$' && ONBOOT=1
    shift 2
    ;;
  --efi)
    EFI="$2"
    echo "$EFI" | grep -qvE '^(0|1)$' && EFI=1
    shift 2
    ;;
  --bltype)
    BLTYPE="$2"
    echo "$BLTYPE" | grep -qvE '^(sata|usb|nvme)$' && BLTYPE="sata"
    shift 2
    ;;
  --storage)
    STORAGE="$2"
    [ -n "${STORAGE}" ] && pvesm status -content images | grep -qw "^${STORAGE}" || STORAGE=""
    shift 2
    ;;
  --v9ppath)
    V9PPATH="$2"
    [ -d "${V9PPATH}" ] && V9PPATH="$(realpath "${V9PPATH}")" || V9PPATH=""
    shift 2
    ;;
  --vfsdirid)
    VFSDIRID="$2"
    [ -n "${VFSDIRID}" ] && pvesh ls /cluster/mapping/dir | grep -qw "${VFSDIRID}" || VFSDIRID=""
    shift 2
    ;;
  --tag)
    TAG="$2"
    [ "${TAG:0:1}" = "v" ] && TAG="${TAG:1}"
    shift 2
    ;;
  --img)
    IMG="$2"
    [ -f "${IMG}" ] && IMG="$(realpath "${IMG}")" || IMG=""
    shift 2
    ;;
  --)
    shift
    break
    ;;
  *)
    usage
    exit 1
    ;;
  esac
done

if ! command -v qm >/dev/null 2>&1; then
  echo "Not a Proxmox VE environment"
  exit 1
fi

if [ -z "$TAG" ]; then
  TAG="$(curl -skL --connect-timeout 10 -w "%{url_effective}" -o /dev/null "${REPO}/releases/latest" | awk -F'/' '{print $NF}')"
  [ "${TAG:0:1}" = "v" ] && TAG="${TAG:1}"
fi

if [ -n "${IMG}" ] && [ -f "${IMG}" ]; then
  IMG_PATH="${IMG}"
else
  if ! command -v curl >/dev/null 2>&1; then
    apt-get update >/dev/null 2>&1 && apt-get install -y curl >/dev/null 2>&1
  fi
  rm -f "/tmp/rr-${TAG}.img.zip"
  echo "Downloading rr-${TAG}.img.zip ... "
  STATUS=$(curl -skL --connect-timeout 10 -w "%{http_code}" "${REPO}/releases/download/${TAG}/rr-${TAG}.img.zip" -o "/tmp/rr-${TAG}.img.zip")
  if [ $? -ne 0 ] || [ "${STATUS:-0}" -ne 200 ]; then
    rm -f "/tmp/rr-${TAG}.img.zip"
    echo "Download failed rr-${TAG}.img.zip"
    exit 1
  fi
  if ! command -v unzip >/dev/null 2>&1; then
    apt-get update >/dev/null 2>&1 && apt-get install -y unzip >/dev/null 2>&1
  fi
  IMG_FILE=$(unzip -l "/tmp/rr-${TAG}.img.zip" | awk '{print $4}' | grep '\.img$' | head -1)
  if [ -z "${IMG_FILE}" ]; then
    echo "No img file found in rr-${TAG}.img.zip"
    exit 1
  fi
  IMG_PATH="/tmp/${IMG_FILE}"
  rm -f "${IMG_PATH}"
  echo "Unzipping rr-${TAG}.img.zip ... "
  unzip -o "/tmp/rr-${TAG}.img.zip" -d /tmp/ "${IMG_FILE}" >/dev/null 2>&1
  STATUS=$?
  rm -f "/tmp/rr-${TAG}.img.zip"
  if [ "${STATUS:-0}" -ne 0 ]; then
    rm -f "${IMG_PATH}"
    echo "Unzip failed rr-${TAG}.img.zip"
    exit 1
  fi
fi

echo "Creating VM with RR ... "

# 获取可用的 VMID
last_vmid=$(qm list | awk 'NR>1{print$1}' | sort -n | tail -1 2>/dev/null)
if [ -z "$last_vmid" ]; then
  # 如果 last_vmid 是空字符串，说明没有VM，设置一个起始ID
  VMID=100 
else
  # 否则，在最后一个ID的基础上加1
  VMID=$((last_vmid + 1))
fi
ARGS=""
SATAIDX=0

# 创建 VM
qm create ${VMID} --name RR-DSM --machine q35 --ostype l26 --vga virtio --sockets 1 --cores 2 --cpu host --numa 0 --memory 4096 --scsihw virtio-scsi-single
if [ $? -ne 0 ]; then
  echo "Create VM failed"
  exit 1
fi

# 获取 存储
[ -z "${STORAGE}" ] && STORAGE=$(pvesm status -content images | awk 'NR>1 {print $1}' | grep local | tail -1)
if [ -z "${STORAGE}" ]; then
  echo "No storage for images"
  qm destroy ${VMID} --purge
  exit 1
fi

# 启用 UEFI 引导
if [ "${EFI:-1}" -eq 1 ]; then
  if ! qm set ${VMID} --bios ovmf --efidisk0 ${STORAGE}:4,efitype=4m,pre-enrolled-keys=0; then
    echo "Set UEFI failed"
    qm destroy ${VMID} --purge
    exit 1
  fi
fi

# 导入 RR 镜像
BLDISK=$(qm importdisk ${VMID} "${IMG_PATH}" "${STORAGE}" | grep 'successfully imported disk' | sed -n "s/.*'\(.*\)'.*/\1/p")
STATUS=$?
if [ "${STATUS:-0}" -ne 0 ] || [ -z "${BLDISK}" ]; then
  echo "Import disk failed"
  qm destroy ${VMID} --purge
  exit 1
fi
[ -n "${IMG}" ] || rm -f "${IMG_PATH}"
case "${BLTYPE}" in
usb)
  ARGS+="-device nec-usb-xhci,id=usb-bus0,multifunction=on -drive file=$(pvesm path ${BLDISK}),media=disk,format=raw,if=none,id=usb1 -device usb-storage,bus=usb-bus0.0,port=1,drive=usb1,bootindex=999,removable=on "
  ;;
nvme)
  ARGS+="-drive file=$(pvesm path ${BLDISK}),media=disk,format=raw,if=none,id=nvme1 -device nvme,drive=nvme1,serial=nvme001 "
  ;;
sata)
  qm set ${VMID} --sata$((SATAIDX++)) "${BLDISK}"
  ;;
*)
  echo "Setting bootloader disk failed"
  qm destroy ${VMID} --purge
  exit 1
  ;;
esac

X86_VENDOR=$(awk -F: '/vendor_id/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo)
VT_FLAGS=$(grep '^flags' /proc/cpuinfo | head -n 1 | grep -wEo 'vmx|svm')
ARGS+="-cpu host,+kvm_pv_eoi,+kvm_pv_unhalt,${VT_FLAGS:+${VT_FLAGS},}hv_vendor_id=${X86_VENDOR:-unknown} "

if [ -d "${V9PPATH}" ]; then
  [ "virtio9p" = "${VFSDIRID}" ] && V9PTAG="virtio9p0" || V9PTAG="virtio9p"
  ARGS+="-fsdev local,security_model=passthrough,id=fsdev0,path=${V9PPATH} -device virtio-9p-pci,id=fs0,fsdev=fsdev0,mount_tag=${V9PTAG} "
fi

qm set ${VMID} --args "${ARGS}"
if [ $? -ne 0 ]; then
  echo "Set args failed"
  qm destroy ${VMID} --purge
  exit 1
fi

if [ -n "${VFSDIRID}" ]; then
  # pvesh create /cluster/mapping/dir --id "${VFSDIRID}" -map node=node1,path=/path/to/share1 --map node=node2,path=/path/to/share2
  qm set ${VMID} --virtiofs0 dirid=${VFSDIRID},cache=always,direct-io=1
fi

# 添加 32G 数据盘
qm set ${VMID} --sata$((SATAIDX++)) ${STORAGE}:32

BRIDGE=$(awk -F: '/^iface vmbr/ {print $1}' /etc/network/interfaces | awk '{print $2}' | head -1)
if [ -z "${BRIDGE}" ]; then
  echo "Get bridge failed"
  qm destroy ${VMID} --purge
  exit 1
fi
qm set ${VMID} --net0 virtio,bridge=${BRIDGE}

qm set ${VMID} --serial0 socket
qm set ${VMID} --agent enabled=1
qm set ${VMID} --smbios1 "uuid=$(cat /proc/sys/kernel/random/uuid),manufacturer=$(echo -n "RROrg" | base64),product=$(echo -n "RR" | base64),version=$(echo -n "$TAG" | base64),base64=1"
qm set ${VMID} --onboot "${ONBOOT}"

echo "Created success, VMID=${VMID}"
