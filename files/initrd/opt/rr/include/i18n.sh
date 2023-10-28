[ -z "${WORK_PATH}" -o ! -d "${WORK_PATH}/include" ] && WORK_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../" >/dev/null 2>&1 && pwd)"

if [ -d "/usr/share/locale" ]; then
  if [ $(ls ${WORK_PATH}/lang/*.mo 2>/dev/null | wc -l) -gt 0 ]; then
    for F in $(ls ${WORK_PATH}/lang/*.mo); do
      install "${F}" "/usr/share/locale/$(basename "${F}" .mo)/LC_MESSAGES/rr.mo"
    done
  fi

  if [ -f ${PART1_PATH}/.locale ]; then
    export LANG="$(cat ${PART1_PATH}/.locale)"
  fi

  alias TEXT='gettext "rr"'
  shopt -s expand_aliases
else
  alias TEXT='echo'
  shopt -s expand_aliases
fi