[ -z "${WORK_PATH}" -o ! -d "${WORK_PATH}/include" ] && WORK_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../" >/dev/null 2>&1 && pwd)"

if [ -d "/usr/share/locale" ]; then
  for F in $(ls ${WORK_PATH}/lang/*.mo 2>/dev/null); do
    LANG="$(basename "${F}" .mo)"
    LOCALE="${LANG%%_*}"
    if [ -d "/usr/share/locale/${LANG}" ] || [ ! -d "/usr/share/locale/${LOCALE}" ]; then
      mkdir -p "/usr/share/locale/${LANG}/LC_MESSAGES"
      install "${F}" "/usr/share/locale/${LANG}/LC_MESSAGES/rr.mo"
    else
      mkdir -p "/usr/share/locale/${LOCALE}/LC_MESSAGES"
      install "${F}" "/usr/share/locale/${LOCALE}/LC_MESSAGES/rr.mo"
    fi
  done

  if [ -f ${PART1_PATH}/.locale ]; then
    export LC_ALL="$(cat ${PART1_PATH}/.locale)"
  fi

  alias TEXT='gettext "rr"'
  shopt -s expand_aliases
else
  alias TEXT='echo'
  shopt -s expand_aliases
fi
