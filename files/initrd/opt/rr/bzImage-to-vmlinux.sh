#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

read_u8() {
  dd if="${1}" bs=1 skip="$((${2}))" count=1 2>/dev/null | od -An -tu1 | grep -Eo '[0-9]+'
}
read_u32() {
  dd if="${1}" bs=1 skip="$((${2}))" count=4 2>/dev/null | od -An -tu4 | grep -Eo '[0-9]+'
}

set -x
setup_size=$(read_u8 "${1}" 0x1f1)
payload_offset=$(read_u32 "${1}" 0x248)
payload_length=$(read_u32 "${1}" 0x24c)
inner_pos=$(((setup_size + 1) * 512))

tail -c+$((inner_pos + 1)) "${1}" | tail -c+$((payload_offset + 1)) | head -c "${payload_length}" | head -c $((payload_length - 4)) | unlzma >"${2}"
