#!/usr/bin/env sh
# =============================================================================
#  update-rulesets.sh - update the rule-sets on the router
# =============================================================================
#  Run it on the router (OpenWrt + OpenClash):
#
#      sh /etc/openclash/scripts/update-rulesets.sh
#
#  It rebuilds the rule-sets with the core that is already on the router and
#  installs the result. If anything goes wrong - no network, a list is not
#  reachable - the old files stay in place and the script says so.
#
#  Put it into the cron of the router and the lists are fresh every day
#  (OpenWrt has no /etc/cron.d, use crontab - see docs/INSTALL.md):
#
#      30 5 * * * /etc/openclash/scripts/update-rulesets.sh >/tmp/update-rulesets.log 2>&1
#
#  The layout on the router. build-ruleset.sh takes the folder above its own
#  as the root of the repository and reads lists/custom-domains.list from
#  there, so the two folders have to stay side by side:
#
#      /etc/openclash/scripts/build-ruleset.sh
#      /etc/openclash/scripts/update-rulesets.sh
#      /etc/openclash/lists/custom-domains.list
#      /etc/openclash/ruleset/                      <- the result
#
#  Do not copy the scripts straight into /etc/openclash/ - the root would be
#  /etc and the build would look for /etc/lists/custom-domains.list.
#
#  The last step is the apply: the core reads the rule-sets when it loads the
#  config, so it has to be told to read them again. By default the core is
#  asked to reload its config through its own API - the proxy stays up. With
#  APPLY=restart OpenClash is restarted instead (the proxy is down for a
#  moment). See scripts/apply-rulesets.sh.
#
#  Environment variables:
#      RULES_DIR   where the .mrs files live      (default: /etc/openclash/ruleset)
#      SCRIPTS_DIR where build-ruleset.sh is      (default: the directory of this script)
#      CUSTOM_LIST your own domains               (default: <SCRIPTS_DIR>/../lists/custom-domains.list)
#      MIHOMO      the core to use                (default: the OpenClash core)
#      APPLY       reload | restart | none        (default: reload)
#      RESTART     "0" means APPLY=none           (kept for compatibility)
# =============================================================================

RULES_DIR="${RULES_DIR:-/etc/openclash/ruleset}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$(cd "$(dirname "$0")" && pwd)}"
RESTART="${RESTART:-1}"
APPLY="${APPLY:-reload}"
[ "$RESTART" = "0" ] && APPLY="none"
BUILD="$SCRIPTS_DIR/build-ruleset.sh"
APPLY_SCRIPT="$SCRIPTS_DIR/apply-rulesets.sh"

# The same root that build-ruleset.sh derives: the folder above scripts/.
ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
CUSTOM_LIST="${CUSTOM_LIST:-$ROOT/lists/custom-domains.list}"
export CUSTOM_LIST

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

# --- find the core -----------------------------------------------------------
# The OpenClash core is what does the conversion. Do not download a second one.
CORE=""
for c in "$MIHOMO" \
         /etc/openclash/clash \
         /etc/openclash/core/clash_meta \
         /etc/openclash/core/mihomo \
         /etc/openclash/core/clash_smart; do
  if [ -n "$c" ] && [ -x "$c" ]; then CORE="$c"; break; fi
done
if [ -z "$CORE" ]; then
  if command -v mihomo >/dev/null 2>&1; then
    CORE="$(command -v mihomo)"
  else
    log "ERROR: no mihomo core found. Set MIHOMO=/path/to/mihomo"
    exit 1
  fi
fi
log "core: $CORE"

if [ ! -f "$BUILD" ]; then
  log "ERROR: $BUILD not found - build-ruleset.sh has to lie next to this script"
  exit 1
fi

# --- check the layout before building ----------------------------------------
if [ ! -f "$CUSTOM_LIST" ]; then
  log "ERROR: $CUSTOM_LIST not found"
  log "       the scripts need the layout of the repository: scripts/ and lists/"
  log "       side by side, e.g. /etc/openclash/scripts and /etc/openclash/lists"
  log "       (or point CUSTOM_LIST at your own file)"
  exit 1
fi

# --- build into a temporary directory ----------------------------------------
TMP="$(mktemp -d 2>/dev/null || echo /tmp/rulesets.$$)"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

log "building the rule-sets into $TMP"
if ! MIHOMO="$CORE" sh "$BUILD" "$TMP"; then
  log "ERROR: the build failed - the old rule-sets stay in place"
  exit 1
fi

# --- install ------------------------------------------------------------------
mkdir -p "$RULES_DIR"
count=0
for f in "$TMP"/*.mrs; do
  [ -f "$f" ] || continue
  name="$(basename "$f")"
  if cp "$f" "$RULES_DIR/$name.new" 2>/dev/null && mv "$RULES_DIR/$name.new" "$RULES_DIR/$name" 2>/dev/null; then
    count=$((count + 1))
  else
    log "WARNING: could not install $name"
  fi
done
log "$count rule-sets installed into $RULES_DIR"

# --- apply --------------------------------------------------------------------
# The core has to read the new files. Reload it through the API (the proxy
# stays up), or restart OpenClash.
if [ "$APPLY" = "none" ]; then
  log "APPLY=none - the new rule-sets are used after the next restart of OpenClash"
  exit 0
fi

if [ ! -f "$APPLY_SCRIPT" ]; then
  log "WARNING: $APPLY_SCRIPT not found - restarting OpenClash instead"
  APPLY="restart"
fi

if [ "$APPLY" = "restart" ]; then
  APPLY=restart sh "$APPLY_SCRIPT"
  exit $?
fi

APPLY="$APPLY" sh "$APPLY_SCRIPT"
exit $?
