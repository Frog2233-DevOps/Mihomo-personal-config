#!/usr/bin/env sh
# =============================================================================
#  apply-rulesets.sh - make the core use the rule-sets that are on the disk
# =============================================================================
#
#  The rule-set files are read by the core when the config is loaded. After
#  new .mrs files have been installed, the core has to be told to read them
#  again - otherwise it keeps working with the old ones.
#
#  Two ways to do that:
#
#    reload   ask the running core to reload its config through its own API
#             (PUT /configs?force=true). The core process stays alive, the
#             connections are not cut, the new rule-sets are in use after a
#             second. This is the default.
#
#   restart  stop and start the core. Simple, but the proxy is down for
#             half a minute. The fallback when the reload does not work.
#
#    none     do nothing, the new lists are used after the next restart.
#
#    check    only look: how many rule-providers the running core has and
#             how many rules they hold. Nothing is changed.
#
#  Usage on the router:
#      sh /etc/mihomo/scripts/apply-rulesets.sh
#      APPLY=restart sh /etc/mihomo/scripts/apply-rulesets.sh
#
#  How the reload works:
#    1. find the config the core was started with (ps / /proc)
#    2. read the secret and the API address out of it
#    3. PUT /configs?force=true  {"path": "<that config>"}
#       The core reads the same file again, the rule-providers take the new
#       .mrs files from the disk. The proxy is not interrupted.
#
#  Environment variables:
#      APPLY        reload | restart | none      (default: reload)
#      CONFIG_FILE  the config to reload         (default: found via ps)
#      API_ADDR     address of the core API      (default: from the config)
#      SECRET       the API secret                (default: from the config)
# =============================================================================
set -u

APPLY="${APPLY:-reload}"
CONFIG_FILE="${CONFIG_FILE:-}"
API_ADDR="${API_ADDR:-}"
SECRET="${SECRET:-}"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

# A scratch file for the intermediate result of the process search. It has to
# be a file and not a variable: the search runs in a subshell (a pipe), and a
# subshell cannot write back into the parent.
TMP_OUT="/tmp/apply-rulesets.$$.cfg"
trap 'rm -f "$TMP_OUT"' EXIT HUP INT TERM

# --- the config the core runs with -------------------------------------------
# "ps w" on busybox prints the whole command line:
#   /bin/sh -c exec /etc/openclash/core/clash_meta -d /etc/openclash -f /etc/openclash/RU-Mihomo.yaml
find_running_config() {
  if [ -n "$CONFIG_FILE" ]; then printf '%s' "$CONFIG_FILE"; return 0; fi
  cfg=""

  # 1. ps. On busybox "ps w" prints the whole command line:
  #    /bin/sh -c exec /usr/bin/mihomo -d /etc/mihomo -f /etc/mihomo/config.yaml
  # pgrep is not an option: the busybox of the router does not show the
  # arguments of the process.
  # shellcheck disable=SC2009
  ps w 2>/dev/null | grep -E 'clash|mihomo' | grep -v grep | while read -r line; do
    p="$(printf '%s' "$line" | sed -n 's/.*[ ]-f[ ]\([^ ]*\).*/\1/p')"
    if [ -n "$p" ] && [ -f "$p" ]; then printf '%s' "$p"; break; fi
  done > "$TMP_OUT"

  # 2. /proc, for the systems where ps does not show the arguments. The
  #    command line of a process must contain "-f " and the file behind it
  #    must exist - otherwise this script would find ITSELF (on the router
  #    its own path contains "apply-rulesets") and stop with an empty result.
  if [ ! -s "$TMP_OUT" ]; then
    for p in /proc/[0-9]*/cmdline; do
      [ -r "$p" ] || continue
      c="$(tr '\0' ' ' < "$p" 2>/dev/null)"
      case "$c" in
        *"-f "*) ;;
        *) continue ;;
      esac
      q="$(printf '%s' "$c" | sed -n 's/.*[ ]-f[ ]\([^ ]*\).*/\1/p')"
      if [ -n "$q" ] && [ -f "$q" ]; then printf '%s' "$q"; break; fi
    done > "$TMP_OUT"
  fi

  cfg="$(cat "$TMP_OUT" 2>/dev/null)"
  rm -f "$TMP_OUT"

  # a relative path belongs to the working directory of the core
  if [ -n "$cfg" ] && [ "${cfg#/}" = "$cfg" ]; then
    d="$(dirname "$cfg")"; b="$(basename "$cfg")"
    if [ -f "$d/$b" ]; then cfg="$(cd "$d" && pwd)/$b"; fi
  fi
  printf '%s' "$cfg"
}

# --- secret and address out of the config ------------------------------------
# The config of the scheme (/etc/mihomo/config.yaml) holds both: the core is
# started with it and it is the file that is reloaded.
read_from_config() {
  [ -f "$1" ] || return 1
  case "$2" in
    secret)
      sed -n "s/^secret:[ \t]*['\"]\{0,1\}\([^'\"]*\)['\"]\{0,1\}[ \t]*$/\1/p" "$1" | head -1 ;;
    controller)
      sed -n "s/^external-controller:[ \t]*['\"]\{0,1\}\([^'\"]*\)['\"]\{0,1\}[ \t]*$/\1/p" "$1" | head -1 ;;
  esac
}

# --- reload ------------------------------------------------------------------
do_reload() {
  cfg="$1"
  api="$2"
  secret="$3"

  if ! command -v curl >/dev/null 2>&1; then
    log "curl is not on the router - cannot reload, use APPLY=restart"
    return 1
  fi

  port="${api##*:}"
  case "$port" in
    ''|*[!0-9]*) log "cannot read the API port out of '$api'"; return 1 ;;
  esac

  log "reloading $cfg through the API on port $port"
  code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 20 \
          -X PUT -H "Authorization: Bearer $secret" -H 'Content-Type: application/json' \
          -d "{\"path\":\"$cfg\"}" "http://127.0.0.1:$port/configs?force=true" 2>/dev/null)"
  case "$code" in
    204|200)
      log "the core reloaded its config - the new rule-sets are in use"
      return 0 ;;
    *)
      log "the reload failed (HTTP ${code:-no answer})"
      return 1 ;;
  esac
}

# --- restart -----------------------------------------------------------------
do_restart() {
  if [ -x /etc/init.d/mihomo ]; then
    log "restarting the core"
    /etc/init.d/mihomo restart >/dev/null 2>&1
    sleep 3
    log "done"
    return 0
  fi
  log "the core is not installed (no /etc/init.d/mihomo) - nothing to restart"
  return 1
}

# --- check --------------------------------------------------------------------
# What the running core has in its rule-providers right now.
do_check() {
  cfg="$1"; api="$2"; secret="$3"
  if ! command -v curl >/dev/null 2>&1; then
    log "curl is not on the router - cannot check"
    return 1
  fi
  port="${api##*:}"
  case "$port" in
    ''|*[!0-9]*) log "cannot read the API port out of '$api'"; return 1 ;;
  esac

  ver="$(curl -s --connect-timeout 5 --max-time 10 -H "Authorization: Bearer $secret" \
         "http://127.0.0.1:$port/version" 2>/dev/null)"
  log "core: ${ver:-no answer}"

  body="$(curl -s --connect-timeout 5 --max-time 15 -H "Authorization: Bearer $secret" \
          "http://127.0.0.1:$port/providers/rules" 2>/dev/null)"
  if [ -z "$body" ]; then
    log "the API did not answer"
    return 1
  fi
  # one line per provider: "name":{...,"ruleCount":N,...
  # the newline at the end matters: without it "read" drops the last line
  printf '%s\n' "$body" | tr '{' '\n' |
    sed -n 's/.*"name":"\([^"]*\)".*"ruleCount":\([0-9]*\).*/\1 \2/p' |
    while read -r name cnt; do
      log "  $name: $cnt rules"
    done
  printf '%s\n' "$body" | tr '{' '\n' |
    sed -n 's/.*"name":"\([^"]*\)".*"ruleCount":\([0-9]*\).*/\1 \2/p' |
    awk '{n++; s+=$2} END {printf "  %d rule-providers, %d rules in total\n", n, s}'
  return 0
}

# --- go ----------------------------------------------------------------------
case "$APPLY" in
  none)
    log "APPLY=none - the new rule-sets are used after the next restart of the core"
    exit 0 ;;
  check)
    cfg="$(find_running_config)"
    if [ -z "$cfg" ] || [ ! -f "$cfg" ]; then
      log "the running config was not found"
      exit 1
    fi
    [ -n "$API_ADDR" ] || API_ADDR="$(read_from_config "$cfg" controller)"
    [ -n "$SECRET" ]   || SECRET="$(read_from_config "$cfg" secret)"
    do_check "$cfg" "$API_ADDR" "$SECRET"
    exit $? ;;
  restart)
    do_restart
    exit $? ;;
  reload)
    cfg="$(find_running_config)"
    if [ -z "$cfg" ] || [ ! -f "$cfg" ]; then
      log "the running config was not found - restarting instead"
      do_restart
      exit $?
    fi
    [ -n "$API_ADDR" ] || API_ADDR="$(read_from_config "$cfg" controller)"
    [ -n "$SECRET" ]   || SECRET="$(read_from_config "$cfg" secret)"
    if [ -z "$API_ADDR" ]; then
      log "no external-controller in the config - restarting instead"
      do_restart
      exit $?
    fi
    if do_reload "$cfg" "$API_ADDR" "$SECRET"; then
      exit 0
    fi
    log "falling back to a restart"
    do_restart
    exit $? ;;
  *)
    log "ERROR: APPLY must be reload, restart or none (got '$APPLY')"
    exit 1 ;;
esac
