#!/usr/bin/env sh
# =============================================================================
#  mixomo-ram.sh - how much RAM the scheme uses on this router
# =============================================================================
#  The scheme has two parts that cost memory: the core (mihomo) and the daemon
#  of MagiTrickle. On a router with 256 MB both of them together can push the
#  kernel into the oom-killer, so the numbers are worth watching.
#
#  Usage on the router:
#      sh /etc/mihomo/scripts/mixomo-ram.sh
#      sh /etc/mihomo/scripts/mixomo-ram.sh --log    # with the oom messages
#
#  Environment variables:
#      MIHOMO_DIR  the layout of mixomo (default: /etc/mihomo)
#
#  POSIX sh (busybox ash on the router), no bash.
# =============================================================================
set -u

MIHOMO_DIR="${MIHOMO_DIR:-/etc/mihomo}"
WITH_LOG=0
[ "${1:-}" = "--log" ] && WITH_LOG=1

# The kernel counts the pages, not the kilobytes: the value of MemAvailable
# is the one that matters, the free pages are not usable by the kernel for
# the allocations that need a contiguous block.
meminfo_value() { # meminfo_value <key>
  awk -v k="$1" '$1 == k":" { print $2; exit }' /proc/meminfo 2>/dev/null
}

mb() { # mb <kilobytes>
  awk -v k="${1:-0}" 'BEGIN { printf "%.1f", k / 1024 }'
}

# The RSS of a process, in kilobytes. The name of the process is enough:
# there is one core and one daemon.
rss_of() { # rss_of <name>
  pid=$(pidof "$1" 2>/dev/null | awk '{print $1}')
  [ -n "$pid" ] || return 1
  awk '/^VmRSS:/ { print $2; exit }' "/proc/$pid/status" 2>/dev/null
}

printf '=== the memory of the router ===\n'
total=$(meminfo_value MemTotal)
avail=$(meminfo_value MemAvailable)
free=$(meminfo_value MemFree)
printf 'MemTotal:     %s kB (%s MB)\n' "${total:-?}" "$(mb "${total:-0}")"
printf 'MemAvailable: %s kB (%s MB)\n' "${avail:-?}" "$(mb "${avail:-0}")"
printf 'MemFree:      %s kB (%s MB)\n' "${free:-?}" "$(mb "${free:-0}")"

printf '\n=== the processes of the scheme ===\n'
for p in mihomo magitrickled; do
  r=$(rss_of "$p") || r=""
  if [ -n "$r" ]; then
    printf '%-14s %s kB (%s MB)\n' "$p" "$r" "$(mb "$r")"
  else
    printf '%-14s not running\n' "$p"
  fi
done

printf '\n=== the rule-sets of the core ===\n'
if [ -d "$MIHOMO_DIR/rule-files" ]; then
  n=0
  b=0
  for f in "$MIHOMO_DIR/rule-files"/*.mrs; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    b=$((b + $(wc -c <"$f")))
  done
  printf '%s rule-sets, %s kB on the disk\n' "$n" "$((b / 1024))"
else
  printf 'no directory %s\n' "$MIHOMO_DIR/rule-files"
fi

printf '\n=== the address sets of MagiTrickle ===\n'
if command -v ipset >/dev/null 2>&1; then
  sets=$(ipset list -n 2>/dev/null | grep -c '^mt_' || true)
  printf '%s sets\n' "${sets:-0}"
  total_entries=0
  for s in $(ipset list -n 2>/dev/null | grep '^mt_'); do
    c=$(ipset list "$s" 2>/dev/null | awk '/^Number of entries:/ {print $4; exit}')
    [ -n "$c" ] || c=0
    total_entries=$((total_entries + c))
  done
  printf '%s addresses in them\n' "$total_entries"
else
  printf 'no ipset on this router\n'
fi

if [ "$WITH_LOG" = "1" ]; then
  printf '\n=== the oom-killer ===\n'
  if command -v logread >/dev/null 2>&1; then
    out=$(logread 2>/dev/null | grep -iE 'oom|killed process' | tail -20)
    if [ -n "$out" ]; then
      printf '%s\n' "$out"
    else
      printf 'no oom messages in the log\n'
    fi
  else
    printf 'no logread on this router\n'
  fi
fi

printf '\n=== the swap ===\n'
swap=$(meminfo_value SwapTotal)
swapfree=$(meminfo_value SwapFree)
printf 'SwapTotal: %s kB (%s MB)\n' "${swap:-?}" "$(mb "${swap:-0}")"
printf 'SwapFree:  %s kB (%s MB)\n' "${swapfree:-?}" "$(mb "${swapfree:-0}")"
