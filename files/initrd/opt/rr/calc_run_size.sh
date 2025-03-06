#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# Calculate the amount of space needed to run the kernel, including room for
# the .bss and .brk sections.
#
# Usage:
# objdump -h a.out | sh calc_run_size.sh

NUM='\([0-9a-fA-F]*[ \t]*\)'
OUT=$(sed -n 's/^[ \t0-9]*.b[sr][sk][ \t]*'"${NUM}${NUM}${NUM}${NUM}"'.*/0x\1 0x\4/p')

if [ -z "${OUT}" ]; then
  echo "Never found .bss or .brk file offset" >&2
  exit 1
fi

read -r sizeA offsetA sizeB offsetB <<<"$(echo ${OUT} | awk '{printf "%d %d %d %d", strtonum($1), strtonum($2), strtonum($3), strtonum($4)}')"

runSize=$((offsetA + sizeA + sizeB))

# BFD linker shows the same file offset in ELF.
if [ "${offsetA}" -ne "${offsetB}" ]; then
  # Gold linker shows them as consecutive.
  endSize=$((offsetB + sizeB))
  if [ "${endSize}" -ne "${runSize}" ]; then
    printf "sizeA: 0x%x\n" ${sizeA} >&2
    printf "offsetA: 0x%x\n" ${offsetA} >&2
    printf "sizeB: 0x%x\n" ${sizeB} >&2
    printf "offsetB: 0x%x\n" ${offsetB} >&2
    echo ".bss and .brk are non-contiguous" >&2
    exit 1
  fi
fi

printf "%d\n" ${runSize}
exit 0
