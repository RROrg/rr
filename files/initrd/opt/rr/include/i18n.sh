[ -z "${WORK_PATH}" -o ! -d "${WORK_PATH}/include" ] && WORK_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../" >/dev/null 2>&1 && pwd)"

if type gettext >/dev/null 2>&1; then
  alias TEXT='gettext "rr"'
  shopt -s expand_aliases
else
  alias TEXT='echo'
  shopt -s expand_aliases
fi
if [ -d "${WORK_PATH}/lang" ]; then
  export TEXTDOMAINDIR="${WORK_PATH}/lang"
fi
if [ -f "${PART1_PATH}/.locale" ]; then
  export LC_ALL="$(cat ${PART1_PATH}/.locale)"
fi
if [ -f "${PART1_PATH}/.timezone" ]; then
  TIMEZONE="$(cat ${PART1_PATH}/.timezone)"
  ln -sf "/usr/share/zoneinfo/right/${TIMEZONE}" /etc/localtime
fi
