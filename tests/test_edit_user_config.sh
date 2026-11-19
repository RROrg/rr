#!/usr/bin/env bash
# Runs the real dialog transaction against private fixtures, not live RR partitions.
set -euo pipefail
command -v yq >/dev/null || { echo "Mike Farah yq v4 is required" >&2; exit 1; }
rr="$(cd "$(dirname "$0")/../files/initrd/opt/rr" && pwd)"
. "${rr}/include/configFile.sh"
. "${rr}/include/userConfigEditor.sh"
root="$(mktemp -d)"
trap 'rm -rf "${root}"' EXIT
PART1_PATH="${root}/p1"
TMP_PATH="${root}/tmp"
USER_CONFIG_FILE="${PART1_PATH}/user-config.yml"
MOD_ZIMAGE_FILE="${root}/zImage"
MOD_RDGZ_FILE="${root}/ramdisk"
mkdir "${PART1_PATH}" "${TMP_PATH}"
cat >"${root}/base" <<'YAML'
model: Example
productver: "7.4"
buildnum: 12345
sn: 'local test identifier'
modules: {demo: ''}
extension:
  enabled: true
  values: [1, two]
YAML
cp "${root}/base" "${root}/valid"
printf 'note: |\n  keep both\n  lines\n' >>"${root}/valid"
printf 'modules: [\nsecret-canary\n' >"${root}/invalid"

fail() { echo "FAIL: $*" >&2; exit 1; }
TEXT() { printf '%s' "$1"; }

# The real dialog returns the draft on stderr. On retry verify it can be
# corrected without ever observing the rejected contents in the active file.
DIALOG() {
  if [ "$3" = "--msgbox" ]; then
    printf '%s\n' "$4" >>"${root}/messages"
    return 0
  fi
  [ "$3" = "--editbox" ] || fail "unexpected dialog"
  step=$((step + 1))
  case "${scenario}:${step}" in
    cancel:1) return 255 ;;
    headless:1)
      # As in menu.sh's headless DIALOG wrapper, absence of --ret means
      # success with no editbox content; the test must not start a retry loop.
      local ret=0
      while [ "$#" -gt 0 ]; do
        if [ "$1" = "--ret" ]; then ret=$2; shift; fi
        shift
      done
      return "${ret}" ;;
    unchanged:1) cat "$4" >&2 ;;
    reject:1|retry:1) cat "${root}/invalid" >&2 ;;
    reject:2|retry:2)
      cmp -s "$4" "${root}/invalid" || fail "retry lost draft"
      cmp -s "${USER_CONFIG_FILE}" "${root}/base" || fail "rejected config became active"
      if [ "${scenario}" = reject ]; then return 1; fi
      cat "${root}/valid" >&2 ;;
    conflict:1)
      printf 'external: true\n' >>"${USER_CONFIG_FILE}"
      cat "${root}/valid" >&2 ;;
    valid:1) cat "${root}/valid" >&2 ;;
    crlf:1) awk '{printf "%s\r\n", $0}' "${root}/valid" >&2 ;;
    model:1) sed 's/^model: Example/model: New/' "${root}/base" >&2 ;;
    *) fail "unexpected dialog step ${scenario}:${step}" ;;
  esac
}
reset_fixture() {
  cp "${root}/base" "${USER_CONFIG_FILE}"
  chmod 640 "${USER_CONFIG_FILE}"
  printf 'old kernel' >"${MOD_ZIMAGE_FILE}"
  printf 'old ramdisk' >"${MOD_RDGZ_FILE}"
  rm -f "${PART1_PATH}/.build" "${root}/messages"
  MODEL=Example PRODUCTVER=7.4 BUILDNUM=12345 SN=original
  scenario="$1"; step=0
}
check_cleanup() {
  [ -z "$(find "${TMP_PATH}" -mindepth 1 -print)" ] || fail "left draft"
  [ -z "$(find "${PART1_PATH}" -name '*.edit.*' -print)" ] || fail "left publication stage"
}
intact_artifacts() {
  [ "$(cat "${MOD_ZIMAGE_FILE}")" = 'old kernel' ] && [ "$(cat "${MOD_RDGZ_FILE}")" = 'old ramdisk' ] || fail "invalidated artifacts"
}
for input in '' '[foo]' '42' 'null' 'a: x\n---\nb: x' 'not: [' 'addons: null' 'modules: [a]' 'cmdline: x' 'network: false' 'synoinfo: 5' \
    'model: [A]' 'productver: {v: 7}' 'buildnum: [1, 2]' 'sn: {key: x}' 'model: A\nmodel: B' 'custom: x\ncustom: y'; do
  printf '%b\n' "${input}" >"${root}/fixture.yml"
  if checkConfigFile "${root}/fixture.yml" >"${root}/diagnostics" 2>&1; then fail "accepted invalid YAML shape"; fi
  [ ! -s "${root}/diagnostics" ] || fail "validator emitted contents"
done
printf "base: &M {k: x}\naddons: *M\n<<: *M\nk: override\nbuildnum: 3\nsn: null\nunknown: [3, foo]\n" >"${root}/fixture.yml"
checkConfigFile "${root}/fixture.yml" || fail "accepted config with aliases should validate"

for choice in cancel headless unchanged reject; do
  reset_fixture "${choice}"
  editUserConfig
  if [ "${choice}" != reject ]; then [ ! -s "${root}/messages" ] || fail "spurious failure dialog"; fi
  intact_artifacts; cmp "${USER_CONFIG_FILE}" "${root}/base"
  [ ! -e "${PART1_PATH}/.build" ] || fail "marked rebuild after ${choice}"
  check_cleanup
done
grep -q 'Invalid configuration' "${root}/messages" || fail "missing retry diagnostic"
if grep -q secret-canary "${root}/messages"; then fail "exposed draft contents"; fi

for choice in valid retry crlf; do
  reset_fixture "${choice}"
  editUserConfig
  cmp "${USER_CONFIG_FILE}" "${root}/valid"
  [ -e "${PART1_PATH}/.build" ] || fail "not marked after valid edit"
  intact_artifacts; check_cleanup
done
reset_fixture model
editUserConfig
[ "${MODEL}" = New ] && [ -e "${PART1_PATH}/.build" ] || fail "model not refreshed"
[ ! -e "${MOD_ZIMAGE_FILE}" ] && [ ! -e "${MOD_RDGZ_FILE}" ] || fail "old model artifacts left active"
check_cleanup

reset_fixture conflict
if editUserConfig; then fail "accepted stale edit"; fi
[ "$(wc -l <"${root}/messages")" -eq 1 ] && grep -q 'changed while editing' "${root}/messages" || fail "unexpected conflict dialogs"
grep -q '^external: true$' "${USER_CONFIG_FILE}" || fail "lost concurrent update"
[ ! -e "${PART1_PATH}/.build" ] || fail "rebuild after conflict"
intact_artifacts; check_cleanup

reset_fixture valid
# Simulate final rename failure: good draft must not affect live state.
mv() { return 1; }
if editUserConfig; then fail "ignored failed publication"; fi
unset -f mv
[ "$(wc -l <"${root}/messages")" -eq 1 ] && grep -q 'Configuration not saved' "${root}/messages" || fail "missing write failure dialog"
cmp "${USER_CONFIG_FILE}" "${root}/base"; intact_artifacts; check_cleanup
[ ! -e "${PART1_PATH}/.build" ] || fail "rebuild after publication failure"
echo "Config editor checks passed"
