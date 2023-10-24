#!/usr/bin/env sh

#
# WARNING: this file is also embedded in the post-init patcher, so don't go to crazy with the syntax/tools as it must
#          be able to execute in the initramfs/preboot environment (so no bashism etc)
# All comments will be stripped, functions here should NOT start with brp_ as they're not part of the builder

if [ -z "${SED_PATH+x}" ]; then
  echo "Your SED_PATH variable is not set/is empty!"
  exit 1
fi

##$1 from, $2 to, $3 file to path
_replace_in_file() {
  if grep -q "${1}" "${3}"; then
    "${SED_PATH}" -i "${3}" -e "s#${1}#${2}#"
  fi
}

# Replace/remove/add values in .conf K=V file
#
# Args: $1 name, $2 new_val, $3 path
_set_conf_kv() {
  # Delete
  if [ -z "$2" ]; then
    "${SED_PATH}" -i "${3}" -e "s/^${1}=.*$//"
    return 0
  fi

  # Replace
  if grep -q "^${1}=" "${3}"; then
    "${SED_PATH}" -i "${3}" -e "s\"^${1}=.*\"${1}=\\\"${2}\\\"\""
    return 0
  fi

  # Add if doesn't exist
  echo "${1}=\"${2}\"" >>"${3}"
}
