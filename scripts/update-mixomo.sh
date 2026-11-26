#!/usr/bin/env sh
# =============================================================================
#  update-mixomo.sh - refresh the rule-sets of the mixomo scheme
# =============================================================================
#  Runs on the router, from the crontab (05:30):
#
#      30 5 * * * /etc/mihomo/scripts/update-mixomo.sh >/tmp/update-mixomo.log 2>&1
#
#  Three steps:
#    1. build the rule-sets again (the lists are downloaded fresh and
#       converted to .mrs) - scripts/build-ruleset.sh
#    2. rebuild the state of MagiTrickle: the local groups (your own
#       domains, Netflix, the AI services) are read from the new rule-sets
#       - scripts/gen-mtrickle.sh
#    3. tell the core to read the new files. The reload through the API
#       keeps the connections alive; when it fails the core is restarted.
#
#  Environment variables:
#      MIHOMO_DIR      the layout of mixomo (default: /etc/mihomo)
#      MAGITRICKLE_DIR the state of MagiTrickle
#                      (default: /etc/magitrickle)
#      CORE            path to the core (default: /usr/bin/mihomo)
#      APPLY           reload | restart | none (default: reload)
#
#  POSIX sh (busybox ash on the router), no bash.
# =============================================================================
set -u

MIHOMO_DIR="${MIHOMO_DIR:-/etc/mihomo}"
MAGITRICKLE_DIR="${MAGITRICKLE_DIR:-/etc/magitrickle}"
CORE="${CORE:-/usr/bin/mihomo}"
APPLY="${APPLY:-reload}"
SCRIPTS="$(cd "$(dirname "$0")" && pwd)"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
fail() { log "ERROR: $*"; exit 1; }

[ -x "$CORE" ] || CORE="$(command -v mihomo 2>/dev/null || true)"
[ -n "$CORE" ] || fail "no core found"

# --- 1. the rule-sets ---------------------------------------------------------
log "rebuilding the rule-sets"
[ -f "$SCRIPTS/build-ruleset.sh" ] || fail "$SCRIPTS/build-ruleset.sh is missing"
OUT="$MIHOMO_DIR/rule-files" sh "$SCRIPTS/build-ruleset.sh" "$MIHOMO_DIR/rule-files" \
  || fail "the rule-sets could not be rebuilt"

# --- 2. the state of MagiTrickle ----------------------------------------------
log "rebuilding the state of MagiTrickle"
MIHOMO="$CORE" \
RULE_DIR="$MIHOMO_DIR/rule-files" \
CUSTOM_LIST="$MIHOMO_DIR/lists/custom-domains.list" \
TEMPLATE="$MIHOMO_DIR/magitrickle.yaml" \
OUT="$MAGITRICKLE_DIR/state/config.yaml" \
  sh "$SCRIPTS/gen-mtrickle.sh" || fail "the state of MagiTrickle could not be built"

if [ -x /etc/init.d/magitrickle ]; then
  /etc/init.d/magitrickle restart >/dev/null 2>&1 || log "WARNING: MagiTrickle did not restart cleanly"
fi

# --- 3. the core --------------------------------------------------------------
do_reload() {
  cfg="$MIHOMO_DIR/config.yaml"
  secret=$(grep -E '^[[:space:]]*secret:' "$cfg" 2>/dev/null | head -1 | sed -e 's/^[^:]*:[[:space:]]*//' -e 's/^["'\'']//' -e 's/["'\'']$//')
  port=$(grep -E '^[[:space:]]*external-controller:' "$cfg" 2>/dev/null | head -1 | sed -e 's/^[^:]*:[[:space:]]*//' -e 's/^["'\'']//' -e 's/["'\'']$//' | awk -F: '{print $NF}')
  [ -n "$port" ] || port=9090
  command -v curl >/dev/null 2>&1 || return 1
  if [ -n "$secret" ] && [ "$secret" != "CHANGE_ME" ]; then
    curl -s -o /dev/null -w '%{http_code}' -X PUT \
      -H "Authorization: Bearer $secret" -H 'Content-Type: application/json' \
      -d "{\"path\":\"$cfg\"}" "http://127.0.0.1:$port/configs?force=true" 2>/dev/null
  else
    curl -s -o /dev/null -w '%{http_code}' -X PUT \
      -H 'Content-Type: application/json' \
      -d "{\"path\":\"$cfg\"}" "http://127.0.0.1:$port/configs?force=true" 2>/dev/null
  fi
}

case "$APPLY" in
  none)
    log "APPLY=none - the new rule-sets are used after the next restart"
    ;;
  restart)
    log "restarting the core"
    /etc/init.d/mihomo restart >/dev/null 2>&1 || log "WARNING: the core did not restart cleanly"
    ;;
  reload)
    code=$(do_reload)
    case "$code" in
      204|200)
        log "the core reloaded its config - the new rule-sets are in use"
        ;;
      *)
        log "the reload failed (HTTP ${code:-no answer}) - restarting the core"
        /etc/init.d/mihomo restart >/dev/null 2>&1 || log "WARNING: the core did not restart cleanly"
        ;;
    esac
    ;;
  *)
    fail "APPLY must be reload, restart or none (got: $APPLY)"
    ;;
esac

log "done"
