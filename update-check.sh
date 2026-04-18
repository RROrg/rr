#!/usr/bin/env bash

# rr
[ "rr" = "$(hostname)" ] && exit 0  # in RR
[ -f "/usr/rr/VERSION" ] && exit 0  # in DSM

exit 1
