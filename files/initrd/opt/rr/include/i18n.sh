#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

[ -z "${WORK_PATH}" ] || [ ! -d "${WORK_PATH}/include" ] && WORK_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../" >/dev/null 2>&1 && pwd)"

type gettext >/dev/null 2>&1 && alias TEXT='gettext "rr"' || alias TEXT='echo'
shopt -s expand_aliases

[ -d "${WORK_PATH}/lang" ] && export TEXTDOMAINDIR="${WORK_PATH}/lang"
[ -f "${PART1_PATH}/.locale" ] && LC_ALL="$(cat "${PART1_PATH}/.locale")" && export LC_ALL="${LC_ALL}"

if [ -f "${PART1_PATH}/.timezone" ]; then
  TIMEZONE="$(cat "${PART1_PATH}/.timezone")"
  if [ -f "/usr/share/zoneinfo/right/${TIMEZONE}" ]; then
    ln -sf "/usr/share/zoneinfo/right/${TIMEZONE}" /etc/localtime
  fi
fi
