
###############################################################################
# Delete a key in config file
# 1 - Path of Key
# 2 - Path of yaml config file
function deleteConfigKey() {
  yq eval 'del(.'${1}')' --inplace "${2}"
}

###############################################################################
# Write to yaml config file
# 1 - Path of Key
# 2 - Value
# 3 - Path of yaml config file
function writeConfigKey() {
  [ "${2}" = "{}" ] && yq eval '.'${1}' = {}' --inplace "${3}" || \
    yq eval '.'${1}' = "'${2}'"' --inplace "${3}"
}

###############################################################################
# Read key value from yaml config file
# 1 - Path of key
# 2 - Path of yaml config file
# Return Value
function readConfigKey() {
  RESULT=`yq eval '.'${1}' | explode(.)' "${2}"`
  [ "${RESULT}" == "null" ] && echo "" || echo ${RESULT}
}

###############################################################################
# Read Entries as map(key=value) from yaml config file
# 1 - Path of key
# 2 - Path of yaml config file
# Returns map of values
function readConfigMap() {
  yq eval '.'${1}' | explode(.) | to_entries | map([.key, .value] | join(": ")) | .[]' "${2}"
}

###############################################################################
# Read an array from yaml config file
# 1 - Path of key
# 2 - Path of yaml config file
# Returns array/map of values
function readConfigArray() {
  yq eval '.'${1}'[]' "${2}"
}

###############################################################################
# Read Entries as array from yaml config file
# 1 - Path of key
# 2 - Path of yaml config file
# Returns array of values
function readConfigEntriesArray() {
  yq eval '.'${1}' | explode(.) | to_entries | map([.key])[] | .[]' "${2}"
}
