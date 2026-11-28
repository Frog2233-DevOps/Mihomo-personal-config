#!/usr/bin/env sh
# =============================================================================
#  diag-core-crash.sh - why does the core of the scheme keep dying?
# =============================================================================
#  Read-only. It changes nothing on the router - it only looks and reports.
#
#  Usage:
#      sh diag-core-crash.sh
#
#  POSIX sh (busybox ash on the router), no bash.
# =============================================================================
set -u

STATE="${STATE:-/etc/magitrickle/state/config.yaml}"
MIHOMO_DIR="${MIHOMO_DIR:-/etc/mihomo}"

hr() { printf '\n=== %s ===\n' "$*"; }

# --- 1. the oom-killer --------------------------------------------------------
hr "the oom-killer"
found=0
if command -v logread >/dev/null 2>&1; then
  out=$(logread 2>/dev/null | grep -iE 'out of memory|killed process|oom-kill|oom_reaper' | tail -25)
  [ -n "$out" ] && { printf '%s\n' "$out"; found=1; }
fi
if [ "$found" = "0" ] && command -v dmesg >/dev/null 2>&1; then
  out=$(dmesg 2>/dev/null | grep -iE 'out of memory|killed process|oom-kill' | tail -25)
  [ -n "$out" ] && { printf '%s\n' "$out"; found=1; }
fi
if [ "$found" = "0" ]; then
  printf 'no oom messages found\n'
  printf '(if the kernel says "permission denied" on dmesg, run: dmesg | tail -40)\n'
fi

# --- 2. the exit of the core --------------------------------------------------
hr "the log of the core (mihomo)"
if command -v logread >/dev/null 2>&1; then
  logread 2>/dev/null | grep -iE 'mihomo' | tail -20
fi

hr "the log of the daemon (magitrickled)"
if command -v logread >/dev/null 2>&1; then
  logread 2>/dev/null | grep -iE 'magitrickle' | tail -20
fi

hr "the services"
for s in mihomo magitrickle hev-socks5-tunnel mixomo-ipv6; do
  if [ -x "/etc/init.d/$s" ]; then
    printf '%-22s %s\n' "$s" "$(/etc/init.d/$s running >/dev/null 2>&1 && echo running || echo 'NOT running')"
  fi
done

# --- 3. the memory ------------------------------------------------------------
hr "the memory of the router"
awk '/^MemTotal:|^MemFree:|^MemAvailable:|^SwapTotal:|^SwapFree:/ { printf "%-14s %8d kB\n", $1, $2 }' /proc/meminfo 2>/dev/null

hr "the rss of the processes"
for p in mihomo magitrickled; do
  pid=$(pidof "$p" 2>/dev/null | awk '{print $1}')
  if [ -n "$pid" ]; then
    rss=$(awk '/^VmRSS:/ { print $2 }' "/proc/$pid/status" 2>/dev/null)
    printf '%-14s pid=%-8s rss=%s kB (%s MB)\n' "$p" "$pid" "${rss:-?}" "$(( ${rss:-0} / 1024 ))"
  else
    printf '%-14s not running\n' "$p"
  fi
done

# --- 4. the state of MagiTrickle ----------------------------------------------
hr "the lists of MagiTrickle (the state file)"
if [ -f "$STATE" ]; then
  printf 'state file: %s\n' "$STATE"
  printf 'size:        %s bytes, changed: %s\n' \
    "$(wc -c <"$STATE" | tr -d ' ')" \
    "$(date -r "$STATE" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '?')"
  printf '\n'
  awk '
    /^subscriptions:/ { s=1 }
    s && /^  - id:/ { n=""; e=""; u=""; i="" }
    s && /^    name:/ { n=$0; sub(/^    name: */,"",n) }
    s && /^    enable:/ { e=$2 }
    s && /^    interface:/ { i=$2 }
    s && /^    url:/ { u=$0; sub(/^    url: */,"",u);
                       printf "  %-22s enable=%-6s interface=%-10s %s\n", n, e, i, u }
  ' "$STATE"
else
  printf 'there is no %s\n' "$STATE"
fi

hr "the address sets of the daemon (the kernel memory)"
if command -v ipset >/dev/null 2>&1; then
  total=0
  for s in $(ipset list -n 2>/dev/null | grep '^mt_'); do
    c=$(ipset list "$s" 2>/dev/null | awk '/^Number of entries:/ {print $4; exit}')
    [ -n "$c" ] || c=0
    total=$((total + c))
  done
  printf '%s sets, %s addresses in them\n' \
    "$(ipset list -n 2>/dev/null | grep -c '^mt_')" "$total"
else
  printf 'no ipset on this router\n'
fi

# --- 5. the cron --------------------------------------------------------------
hr "the cron of the scheme"
crontab -l 2>/dev/null | grep -iE 'mixomo|update' || printf 'no cron job of the scheme\n'

printf '\n--- the end of the report ---\n'
