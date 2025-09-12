#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

REPO="https://github.com/RROrg/rr"

# 参数
ONBOOT=1 # 开机启动，默认1
# BLTYPE="usb"   # 引导盘类型， 支持 usb,sata,nvme 默认 usb
TAG="" # 镜像tag，默认自动获取
IMG="" # 本地镜像路径，默认空

while [[ $# -gt 0 ]]; do
  case "$1" in
  --onboot)
    ONBOOT="${2}"
    shift 2
    ;;
    #--bltype)
  #  BLTYPE="${2}"
  #  shift 2
  #  ;;
  --tag)
    TAG="${2}"
    shift 2
    ;;
  --img)
    IMG="${2}"
    shift 2
    ;;
  *)
    # echo "Usage: $0 [--onboot <0|1>] [--bltype <usb|sata|nvme>] [--tag <tag>] [--img <path>]"
    echo "Usage: $0 [--onboot <0|1>] [--tag <tag>] [--img <path>]"
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
  rm -f "/tmp/rr-${TAG}.img.zip"
  echo "Downloading rr-${TAG}.img.zip ... "
  STATUS=$(curl -skL --connect-timeout 10 -w "%{http_code}" "${REPO}/releases/download/${TAG}/rr-${TAG}.img.zip" -o "/tmp/rr-${TAG}.img.zip")
  if [ $? -ne 0 ] || [ "${STATUS:-0}" -ne 200 ]; then
    rm -f "/tmp/rr-${TAG}.img.zip"
    echo "Download failed"
    exit 1
  fi
  if ! command -v unzip >/dev/null 2>&1; then
    apt-get update >/dev/null 2>&1 && apt-get install -y unzip >/dev/null 2>&1
  fi
  rm -f "/tmp/rr.img"
  echo "Unzipping rr-${TAG}.img.zip ... "
  unzip -o "/tmp/rr-${TAG}.img.zip" -d /tmp/ >/dev/null 2>&1
  STATUS=$?
  rm -f "/tmp/rr-${TAG}.img.zip"
  if [ "${STATUS:-0}" -ne 0 ]; then
    echo "Unzip failed"
    exit 1
  fi
  IMG_PATH="/tmp/rr.img"
fi

echo "Creating VM with RR ... "

# 获取可用的 VMID
VMID="$(($(qm list | awk 'NR>1{print $1}' | sort -n | tail -1 2>/dev/null || echo 99) + 1))"

# 创建 VM
qm create ${VMID} --name RR-DSM --machine q35 --ostype l26 --vga virtio --sockets 1 --cores 2 --cpu host --numa 0 --memory 4096 --scsihw virtio-scsi-single
if [ $? -ne 0 ]; then
  echo "Create VM failed"
  exit 1
fi

# 导入磁盘
qm importdisk ${VMID} "${IMG_PATH}" local-lvm >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "Import disk failed"
  exit 1
fi
[ -n "${IMG}" ] || rm -f "${IMG_PATH}"

# 设置 VM 配置
qm set ${VMID} --bios ovmf --efidisk0 local-lvm:4,efitype=4m,pre-enrolled-keys=0
qm set ${VMID} --sata0 local-lvm:vm-${VMID}-disk-0
qm set ${VMID} --sata1 local-lvm:32
qm set ${VMID} --net0 virtio,bridge=vmbr0
qm set ${VMID} --serial0 socket
qm set ${VMID} --agent enabled=1
qm set ${VMID} --smbios1 "uuid=$(cat /proc/sys/kernel/random/uuid),manufacturer=$(echo -n "RROrg" | base64),product=$(echo -n "RR" | base64),version=$(echo -n "$TAG" | base64),base64=1"
qm set ${VMID} --onboot "${ONBOOT}"

echo "Created success, VMID=${VMID}"
