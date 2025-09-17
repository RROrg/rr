#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# shellcheck disable=SC2059

[ -z "${WORK_PATH}" ] || [ ! -d "${WORK_PATH}/include" ] && WORK_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. "${WORK_PATH}/include/functions.sh"

# lock
exec 911>"${TMP_PATH}/helper.lock"
flock -n 911 || {
  MSG="$(TEXT "Another instance is already running.")"
  dialog --colors --aspect 50 --title "$(TEXT "Online Assistance")" --msgbox "${MSG}" 0 0
  exit 1
}
trap 'flock -u 911; rm -f "${TMP_PATH}/helper.lock"' EXIT INT TERM HUP

{
  printf "$(TEXT "Closing this window or press 'ctrl + c' to exit the assistance.")\n"
	printf "$(TEXT "Please give the following link to the helper. (Click to open and copy)")\n"
  printf "        👇\n"
  sshx -q --name "RR-Helper" 2>&1
	[ $? -ne 0 ] && while true; do sleep 1; done
} | dialog --colors --aspect 50 --title "$(TEXT "Online Assistance")" --progressbox "$(TEXT "Notice: Please keep this window open.")" 20 100 2>&1

clear
echo -e "$(TEXT "Call \033[1;32mmenu.sh\033[0m to return to menu")"
"${WORK_PATH}/init.sh"
