#!/usr/bin/env ash

function use() {
  echo "Use: ${0} junior|config"
  exit 1
}

[ -z "${1}" ] && use
[ "${1}" != "junior" -a "${1}" != "config" ] && use
echo "Rebooting to ${1} mode"
grub-editenv /mnt/p1/grub/grubenv set next_entry="${1}"
reboot
