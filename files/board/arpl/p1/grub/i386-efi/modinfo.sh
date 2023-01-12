#!/bin/bash

# User-controllable options
grub_modinfo_target_cpu=i386
grub_modinfo_platform=efi
grub_disk_cache_stats=0
grub_boot_time_stats=0
grub_have_font_source=1

# Autodetected config
grub_have_asm_uscore=0
grub_bss_start_symbol="__bss_start"
grub_end_symbol="end"

# Build environment
grub_target_cc='gcc'
grub_target_cc_version='gcc (Debian 10.2.1-6) 10.2.1 20210110'
grub_target_cflags='-std=gnu99 -Os -m32 -Wall -W -Wshadow -Wpointer-arith -Wundef -Wchar-subscripts -Wcomment -Wdeprecated-declarations -Wdisabled-optimization -Wdiv-by-zero -Wfloat-equal -Wformat-extra-args -Wformat-security -Wformat-y2k -Wimplicit -Wimplicit-function-declaration -Wimplicit-int -Wmain -Wmissing-braces -Wmissing-format-attribute -Wmultichar -Wparentheses -Wreturn-type -Wsequence-point -Wshadow -Wsign-compare -Wswitch -Wtrigraphs -Wunknown-pragmas -Wunused -Wunused-function -Wunused-label -Wunused-parameter -Wunused-value  -Wunused-variable -Wwrite-strings -Wnested-externs -Wstrict-prototypes -g -Wredundant-decls -Wmissing-prototypes -Wmissing-declarations  -Wextra -Wattributes -Wendif-labels -Winit-self -Wint-to-pointer-cast -Winvalid-pch -Wmissing-field-initializers -Wnonnull -Woverflow -Wvla -Wpointer-to-int-cast -Wstrict-aliasing -Wvariadic-macros -Wvolatile-register-var -Wpointer-sign -Wmissing-include-dirs -Wmissing-prototypes -Wmissing-declarations -Wformat=2 -march=i386 -falign-jumps=1 -falign-loops=1 -falign-functions=1 -freg-struct-return -mno-mmx -mno-sse -mno-sse2 -mno-sse3 -mno-3dnow -msoft-float -fno-dwarf2-cfi-asm -mno-stack-arg-probe -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-ident -fno-PIE -fno-pie -fno-stack-protector -Wtrampolines -Werror'
grub_target_cppflags=' -Wall -W  -DGRUB_MACHINE_EFI=1 -DGRUB_MACHINE=I386_EFI -m32 -nostdinc -isystem /usr/lib/gcc/x86_64-linux-gnu/10/include -I$(top_srcdir)/include -I$(top_builddir)/include'
grub_target_ccasflags=' -m32 -g  -msoft-float -fno-PIE -fno-pie'
grub_target_ldflags=' -m32 -Wl,-melf_i386 -no-pie -Wl,--build-id=none'
grub_cflags=''
grub_cppflags=' -D_FILE_OFFSET_BITS=64'
grub_ccasflags=''
grub_ldflags=''
grub_target_strip='strip'
grub_target_nm='nm'
grub_target_ranlib='ranlib'
grub_target_objconf=''
grub_target_obj2elf=''
grub_target_img_base_ldopt='-Wl,-Ttext'
grub_target_img_ldflags='@TARGET_IMG_BASE_LDFLAGS@'

# Version
grub_version="2.06"
grub_package="grub"
grub_package_string="GRUB 2.06"
grub_package_version="2.06"
grub_package_name="GRUB"
grub_package_bugreport="bug-grub@gnu.org"
