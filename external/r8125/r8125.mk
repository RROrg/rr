################################################################################
#
# r8125
#
################################################################################

R8125_VERSION = 99cd3bc868e4ba82a473d8efaedad04fedb0c0f7
R8125_SITE = $(call github,fbelavenuto,r8125,$(R8125_VERSION))
R8125_LICENSE = GPL-2.0

$(eval $(kernel-module))
$(eval $(generic-package))

