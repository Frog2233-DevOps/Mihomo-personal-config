#!/usr/bin/env sh
# =============================================================================
#  mixomo-memlimit.sh - the soft memory limit of the two Go programs
# =============================================================================
#  The core (mihomo) and the daemon of MagiTrickle are Go programs. Go has a
#  soft memory limit (GOMEMLIMIT): the garbage collector starts to work
#  harder when the heap comes near the limit, so the process keeps its
#  footprint instead of growing until the oom-killer of the kernel takes it.
#
#  The limit is set in the init script of the service:
#
#      procd_set_param env GOMEMLIMIT=96MiB   # mixomo-gomemlimit
#
#  The rule-sets are NOT part of the heap: the core reads them into the
#  memory of the operating system, and GOMEMLIMIT does not touch them. The
#  limit is therefore a help against a growing heap (the cache of the DNS,
#  the connections), not a replacement for the smaller lists.
#
#  It does not save a list that does not fit: the daemon of MagiTrickle
#  needs about 14 kB of RAM for every domain of a subscription (measured on
#  a Cudy WR3000S: 1000 domains - 27 MB of RSS, 5000 - 78 MB), and a list
#  that is bigger than the RAM of the router kills the daemon whatever the
#  limit is. The size of the lists is the business of scripts/gen-mtrickle.sh.
#
#  The init scripts of mixomo are patched, not replaced. The patch is applied
#  again at every run, so it survives an update of mixomo (the update replaces
#  the init script - the patch follows the new version, run this script again
#  afterwards).
#
#  Usage on the router:
#      sh /etc/mihomo/scripts/mixomo-memlimit.sh
#
#  Environment variables:
#      GOMEMLIMIT_CORE    the limit of the core (default: 96MiB, 0 - none)
#      GOMEMLIMIT_DAEMON  the limit of MagiTrickle (default: 64MiB, 0 - none)
#      MIXOMO_CORE_INIT   the init script of the core
#                         (default: /etc/init.d/mihomo)
#      MIXOMO_DAEMON_INIT the init script of MagiTrickle
#                         (default: /etc/init.d/magitrickle)
#
#  POSIX sh (busybox ash on the router), no bash.
# =============================================================================
set -u

GOMEMLIMIT_CORE="${GOMEMLIMIT_CORE:-96MiB}"
GOMEMLIMIT_DAEMON="${GOMEMLIMIT_DAEMON:-64MiB}"
CORE_INIT="${MIXOMO_CORE_INIT:-/etc/init.d/mihomo}"
DAEMON_INIT="${MIXOMO_DAEMON_INIT:-/etc/init.d/magitrickle}"

MARK="mixomo-gomemlimit"

log() { printf '%s\n' "$*"; }

# The line that is put into the init script.
env_line() { # env_line <value>
  printf '    procd_set_param env GOMEMLIMIT=%s   # %s' "$1" "$MARK"
}

# The patch of one init script.
#
#   1. the line of an earlier patch is removed;
#   2. the new line is put after the first "procd_set_param command".
#
# The file itself is patched, in place. An update of mixomo replaces the init
# script with a new version, and the patch has to follow that version - not
# the one that was there at the first run. The copy "<file>.mixomo-orig" is
# only a backup for the reader; it is refreshed when the file has no patch
# in it (that means the file was replaced by an update).
patch_init() { # patch_init <file> <value>
  f="$1"
  val="$2"

  [ -f "$f" ] || { log "  $f is not there - skipped"; return 0; }
  [ -w "$f" ] || { log "  $f is not writable - skipped"; return 0; }

  if ! grep -q 'procd_set_param command' "$f"; then
    log "  $f has no procd instance - skipped"
    return 0
  fi

  if [ ! -f "$f.mixomo-orig" ] || ! grep -q "$MARK" "$f"; then
    cp "$f" "$f.mixomo-orig" 2>/dev/null || true
  fi

  awk -v ins="$(env_line "$val")" '
    index($0, "mixomo-gomemlimit") > 0 { next }
    { print }
    !done && /procd_set_param command/ { print ins; done = 1 }
  ' "$f" >"$f.new" || { log "  cannot write $f"; return 1; }

  if ! grep -q "$MARK" "$f.new"; then
    log "  the patch did not fit into $f - skipped"
    rm -f "$f.new"
    return 0
  fi

  cat "$f.new" >"$f" || { log "  cannot write $f"; rm -f "$f.new"; return 1; }
  rm -f "$f.new"
  log "  $f: GOMEMLIMIT=$val"
  return 0
}

log "the soft memory limit of the programs of the scheme"

if [ "$GOMEMLIMIT_CORE" = "0" ] || [ -z "$GOMEMLIMIT_CORE" ]; then
  log "  the core: left alone (GOMEMLIMIT_CORE=${GOMEMLIMIT_CORE:-none})"
else
  patch_init "$CORE_INIT" "$GOMEMLIMIT_CORE"
fi

if [ "$GOMEMLIMIT_DAEMON" = "0" ] || [ -z "$GOMEMLIMIT_DAEMON" ]; then
  log "  MagiTrickle: left alone (GOMEMLIMIT_DAEMON=${GOMEMLIMIT_DAEMON:-none})"
else
  patch_init "$DAEMON_INIT" "$GOMEMLIMIT_DAEMON"
fi

log "the services have to be restarted for the limit to take effect"
