#!/usr/bin/env sh
# =============================================================================
#  update-rulesets.sh - update the rule-sets on the router
# =============================================================================
#  Run it on the router (OpenWrt + OpenClash):
#
#      sh /etc/openclash/update-rulesets.sh
#
#  It rebuilds the rule-sets with the core that is already on the router and
#  installs the result. If anything goes wrong - no network, a list is not
#  reachable - the old files stay in place and the script says so.
#
#  Put it into the cron of the router and the lists are fresh every day:
#
#      30 5 * * * /etc/openclash/update-rulesets.sh >/tmp/update-rulesets.log 2>&1
#
#  Environment variables:
#      RULES_DIR   where the .mrs files live      (default: /etc/openclash/ruleset)
#      SCRIPTS_DIR where build-ruleset.sh is      (default: the directory of this script)
#      MIHOMO      the core to use                (default: the OpenClash core)
#      RESTART     "1" to restart OpenClash       (default: 1)
# =============================================================================

RULES_DIR="${RULES_DIR:-/etc/openclash/ruleset}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$(cd "$(dirname "$0")" && pwd)}"
RESTART="${RESTART:-1}"
BUILD="$SCRIPTS_DIR/build-ruleset.sh"


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
  log "ERROR: $BUILD not found - copy the scripts/ folder to the router"
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

# --- restart ------------------------------------------------------------------
if [ "$RESTART" = "1" ]; then
  if [ -x /etc/init.d/openclash ]; then
    log "restarting OpenClash"
    /etc/init.d/openclash restart >/dev/null 2>&1
    log "done"
  else
    log "OpenClash not found - restart it by hand"
  fi
else
  log "RESTART=0 - restart OpenClash by hand to apply the new lists"
fi
