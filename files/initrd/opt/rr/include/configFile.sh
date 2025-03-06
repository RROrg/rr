#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

###############################################################################
# Delete a key in config file
# 1 - Path of Key
# 2 - Path of yaml config file
function deleteConfigKey() {
  yq eval "del(.${1})" --inplace "${2}" 2>/dev/null
}

###############################################################################
# Write to yaml config file
# 1 - Path of Key
# 2 - Value
# 3 - Path of yaml config file
function writeConfigKey() {
  local value="${2}"
  [ "${value}" = "{}" ] && yq eval ".${1} = {}" --inplace "${3}" 2>/dev/null || yq eval ".${1} = \"${value}\"" --inplace "${3}" 2>/dev/null
}

###############################################################################
# Read key value from yaml config file
# 1 - Path of key
# 2 - Path of yaml config file
# Return Value
function readConfigKey() {
  local result
  result=$(yq eval ".${1} | explode(.)" "${2}" 2>/dev/null)
  [ "${result}" = "null" ] && echo "" || echo "${result}"
}

###############################################################################
# Write to yaml config file
# 1 - Modules
# 2 - Path of yaml config file
function mergeConfigModules() {
  # Error: bad file '-': cannot index array with '8139cp' (strconv.ParseInt: parsing "8139cp": invalid syntax)
  # When the first key is a pure number, yq will not process it as a string by default. The current solution is to insert a placeholder key.
  local MS ML XF
  MS="RRORG\n${1// /\\n}"
  ML="$(echo -en "${MS}" | awk '{print "modules."$1":"}')"
  XF=$(mktemp 2>/dev/null)
  XF=${XF:-/tmp/tmp.XXXXXXXXXX}
  echo -en "${ML}" | yq -p p -o y >"${XF}"
  deleteConfigKey "modules.\"RRORG\"" "${XF}"
  yq eval-all --inplace '. as $item ireduce ({}; . * $item)' --inplace "${2}" "${XF}" 2>/dev/null
  rm -f "${XF}"
}

###############################################################################
# Write to yaml config file if key not exists
# 1 - Path of Key
# 2 - Value
# 3 - Path of yaml config file
function initConfigKey() {
  [ -z "$(readConfigKey "${1}" "${3}")" ] && writeConfigKey "${1}" "${2}" "${3}" || true
}

###############################################################################
# Read Entries as map(key=value) from yaml config file
# 1 - Path of key
# 2 - Path of yaml config file
# Returns map of values
function readConfigMap() {
  yq eval ".${1} | explode(.) | to_entries | map([.key, .value] | join(\": \")) | .[]" "${2}" 2>/dev/null
}

###############################################################################
# Read an array from yaml config file
# 1 - Path of key
# 2 - Path of yaml config file
# Returns array/map of values
function readConfigArray() {
  yq eval ".${1}[]" "${2}" 2>/dev/null
}

###############################################################################
# Read Entries as array from yaml config file
# 1 - Path of key
# 2 - Path of yaml config file
# Returns array of values
function readConfigEntriesArray() {
  yq eval ".${1} | explode(.) | to_entries | map([.key])[] | .[]" "${2}" 2>/dev/null
}

###############################################################################
# Check yaml config file
# 1 - Path of yaml config file
# Returns error information
function checkConfigFile() {
  yq eval "${1}" 2>&1
}
