#!/usr/bin/env sh
# =============================================================================
#  fix-magitrickle-ooms.sh - stop the crash loop of the core
# =============================================================================
#  What it does:
#    1. a backup of the state file and of the template;
#    2. the lists that do not fit into the memory of the router are switched
#       off in the STATE FILE and in the TEMPLATE ("RKN Blocked", "RKN IP",
#       "Anti-AD");
#    3. the URL of a switched-off list points to nothing, so that an update
#       in the web interface cannot kill the daemon;
#    4. gen-mtrickle.sh is patched: it reads the state of a list from the
#       template (before the patch it always wrote "true"), so the nightly
#       cron cannot switch the big lists on again;
#    5. the daemon is restarted and the memory is reported.
#
#  Usage on the router:
#      sh fix-magitrickle-ooms.sh
#
#  POSIX sh (busybox ash on the router), no bash.
# =============================================================================
set -u

STATE="${STATE:-/etc/magitrickle/state/config.yaml}"
TEMPLATE="${TEMPLATE:-/etc/mihomo/magitrickle.yaml}"
GEN="${GEN:-/etc/mihomo/scripts/gen-mtrickle.sh}"
MIHOMO_DIR="${MIHOMO_DIR:-/etc/mihomo}"
SAFE_URL="${SAFE_URL:-http://127.0.0.1:1/switched-off.lst}"
BIG="${BIG:-RKN Blocked|RKN IP|Anti-AD}"
STAMP="$(date '+%Y%m%d-%H%M%S')"

log() { printf '%s\n' "$*"; }

# --- 1. the backup ------------------------------------------------------------
for f in "$STATE" "$TEMPLATE" "$GEN"; do
  [ -f "$f" ] || continue
  cp "$f" "$f.bak-$STAMP" && log "backup: $f.bak-$STAMP"
done

# --- 2. the awk that switches the big lists off -------------------------------
# The lists of the "subscriptions" block whose name matches BIG get
# "enable: false" and the safe URL. Everything else stays as it is.
cat >/tmp/flip-lists.awk <<'AWK'
BEGIN { in_subs = 0; buf_n = 0; name = "" }
/^subscriptions:[[:space:]]*$/ { in_subs = 1 }
{
  if (in_subs && /^  - id:/) {
    flush_record()
    name = ""
  }
  if (in_subs && /^    name:/) {
    name = $0
    sub(/^    name:[[:space:]]*/, "", name)
    gsub(/"/, "", name)
  }
  if (in_subs && /^    enable:/) {
    en = $0
    sub(/^    enable:[[:space:]]*/, "", en)
    gsub(/"/, "", en)
    if (name ~ BIG) en = "false"
    buf[buf_n++] = "    enable: " en
    next
  }
  if (in_subs && /^    url:/) {
    u = $0
    sub(/^    url:[[:space:]]*/, "", u)
    if (name ~ BIG) {
      buf[buf_n++] = "    # the list is switched off: it does not fit into the memory of the router"
      buf[buf_n++] = "    # the original url: " u
      buf[buf_n++] = "    url: " SAFE
    } else {
      buf[buf_n++] = "    url: " u
    }
    next
  }
  buf[buf_n++] = $0
}
END { flush_record() }

function flush_record(   i) {
  for (i = 0; i < buf_n; i++) print buf[i]
  buf_n = 0
}
AWK

flip() { # flip <file>
  f="$1"
  [ -f "$f" ] || return 0
  awk -v BIG="$BIG" -v SAFE="$SAFE_URL" -f /tmp/flip-lists.awk "$f" >"$f.new" || return 1
  if [ -s "$f.new" ]; then
    mv "$f.new" "$f"
    log "the big lists are switched off in $f"
  else
    rm -f "$f.new"
    log "WARNING: $f was not changed (the awk produced nothing)"
  fi
}

# --- 3. the state file and the template ---------------------------------------
flip "$STATE"
flip "$TEMPLATE"

# --- 4. the patch of gen-mtrickle.sh ------------------------------------------
# Before the patch the script wrote "state=true" for every list and never read
# the state of the list from the template. After the patch the template is
# the source of truth, so a list that is switched off in the template stays
# switched off - whatever the probe finds.
if [ -f "$GEN" ] && ! grep -q 'the template decides the state of the list' "$GEN"; then
  awk '
    /^  state=true$/ && !done {
      print "  # the template decides the state of the list (patched by fix-magitrickle-ooms.sh)"
      print "  state=$(sed -n '"'"'s/^[[:space:]]*enable:[[:space:]]*//p'"'"' \"$f\" | head -1 | tr -d '"'"'\"'"'"')"
      print "  [ \"$state\" = \"true\" ] || [ \"$state\" = \"false\" ] || state=true"
      done = 1
      next
    }
    { print }
  ' "$GEN" >"$GEN.new" && mv "$GEN.new" "$GEN" && log "gen-mtrickle.sh is patched: the template decides the state of the list"
else
  log "gen-mtrickle.sh does not need the patch (already patched or missing)"
fi

# --- 5. the daemon ------------------------------------------------------------
if [ -x /etc/init.d/magitrickle ]; then
  log "restarting the daemon"
  /etc/init.d/magitrickle restart >/dev/null 2>&1 || log "WARNING: the daemon did not restart cleanly"
  sleep 5
fi

if [ "${RESTART_CORE:-1}" = "1" ] && [ -x /etc/init.d/mihomo ]; then
  log "restarting the core (it was killed by the oom-killer)"
  /etc/init.d/mihomo restart >/dev/null 2>&1 || log "WARNING: the core did not restart cleanly"
  sleep 3
fi

# --- 6. the report ------------------------------------------------------------
log ""
log "the memory now:"
for p in magitrickled mihomo; do
  pid=$(pidof "$p" 2>/dev/null | awk '{print $1}')
  if [ -n "$pid" ]; then
    rss=$(awk '/^VmRSS:/ { print $2 }' "/proc/$pid/status" 2>/dev/null)
    printf '  %-14s pid=%-8s rss=%s kB (%s MB)\n' "$p" "$pid" "${rss:-?}" "$(( ${rss:-0} / 1024 ))"
  else
    printf '  %-14s not running\n' "$p"
  fi
done
awk '/^MemTotal:|^MemAvailable:|^SwapFree:/ { printf "  %-14s %8d kB\n", $1, $2 }' /proc/meminfo 2>/dev/null

log ""
log "the lists of the daemon now:"
if [ -f "$STATE" ]; then
  awk '
    /^subscriptions:/ { s = 1 }
    s && /^  - id:/ { n = "" }
    s && /^    name:/ { n = $0; sub(/^    name: */, "", n) }
    s && /^    enable:/ { e = $2 }
    s && /^    url:/ { printf "  %-22s enable=%-6s %s\n", n, e, $0 }
  ' "$STATE"
fi
log ""
log "done. The nightly cron keeps the lists off now - the template decides."
log ""
log "The original URLs of the switched-off lists are kept in the comments of"
log "the template. To switch a list on later (with a router that has enough"
log "RAM for it), restore its URL and set 'enable: true' in the template:"
log "    $TEMPLATE"
log "and regenerate: sh $GEN"
