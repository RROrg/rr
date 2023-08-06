################################################################################
#
# libsixel
#
################################################################################
# 6a5be8b72d84037b83a5ea838e17bcf372ab1d5f is v1.8.6 commit ID
LIBSIXEL_VERSION = 6a5be8b72d84037b83a5ea838e17bcf372ab1d5f
LIBSIXEL_SITE = $(call github,saitoha,libsixel,$(LIBSIXEL_VERSION))
LIBSIXEL_LICENSE = MIT
LIBSIXEL_LICENSE_FILES = LICENSE

LIBSIXEL_CPE_ID_VENDOR = libsixel_project
LIBSIXEL_INSTALL_STAGING = YES
LIBSIXEL_AUTORECONF = YES

$(eval $(autotools-package))
$(eval $(host-autotools-package))
