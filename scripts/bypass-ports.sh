#!/usr/bin/env sh
# =============================================================================
#  bypass-ports.sh - keep the traffic of the given ports out of the core
# =============================================================================
#  Some traffic must not touch the core at all. A Rust server that sends a
#  lot of UDP is the example from the field: the UDP pipeline of the core is
#  the bottleneck, and the packets of a game server are lost on the way.
#
#  In the mixomo scheme the traffic of the clients reaches the core only
#  when MagiTrickle marked its address. The traffic of a port that is listed
#  here never gets there: the rule below sits in front of the chains of
#  MagiTrickle and accepts the packets of these ports right in PREROUTING,
#  before any mark and before any redirect.
#
#  The rule is ACCEPT and not RETURN on purpose: RETURN from a chain of the
#  mangle table only means "back to PREROUTING and keep looking", so a
#  packet that MagiTrickle marked would still be marked. ACCEPT ends the
#  traversal of the table - the packet keeps its normal route to the
#  provider.
#
#  MagiTrickle restores the position of its own chains after a restart by
#  the rules around them (the "anchors"). A rule of ours that stands in
#  front of them therefore stays in front of them.
#
#  Usage on the router:
#      sh /etc/mihomo/scripts/bypass-ports.sh install
#      sh /etc/mihomo/scripts/bypass-ports.sh status
#      sh /etc/mihomo/scripts/bypass-ports.sh uninstall
#
#  The ports are read from a file, one per line:
#      /etc/mihomo/bypass-ports.txt
#  Empty lines and lines starting with "#" are ignored.
#
#  Environment variables:
#      PORTS_FILE  the file with the ports (default: /etc/mihomo/bypass-ports.txt)
#      CHAIN       the name of the chain (default: MIXOMO_BYPASS)
#      IPT         the iptables binary (default: iptables-nft, then iptables)
#
#  POSIX sh (busybox ash on the router), no bash.
# =============================================================================
set -u

PORTS_FILE="${PORTS_FILE:-/etc/mihomo/bypass-ports.txt}"
CHAIN="${CHAIN:-MIXOMO_BYPASS}"
COMMENT="mixomo-bypass"
IPT="${IPT:-}"

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

find_iptables() {
  if [ -n "$IPT" ]; then return 0; fi
  for c in iptables-nft iptables; do
    if command -v "$c" >/dev/null 2>&1; then
      IPT="$c"
      return 0
    fi
  done
  return 1
}

# The ports of the file, one per line, without the comments.
list_ports() {
  [ -f "$PORTS_FILE" ] || return 0
  sed -e 's/#.*//' -e 's/[[:space:]]//g' "$PORTS_FILE" | grep -E '^[0-9]{1,5}$' || true
}

# The position of the jump into our chain in PREROUTING, empty when it is
# not there.
jump_position() { # jump_position <table>
  "$IPT" -t "$1" -L PREROUTING -n --line-numbers 2>/dev/null \
    | awk -v c="$CHAIN" '$2 == c { print $1; exit }'
}

# One rule per port and protocol. The comment is a convenience for the
# status output; when the kernel has no xt_comment the rule is added
# without it.
add_port_rules() { # add_port_rules <table>
  for p in $(list_ports); do
    for proto in tcp udp; do
      if ! "$IPT" -t "$1" -A "$CHAIN" ! -i lo -p "$proto" --dport "$p" \
           -m comment --comment "$COMMENT" -j ACCEPT 2>/dev/null; then
        "$IPT" -t "$1" -A "$CHAIN" ! -i lo -p "$proto" --dport "$p" -j ACCEPT || return 1
      fi
    done
  done
  return 0
}

do_install() {
  find_iptables || die "no iptables found"
  n=$(list_ports | wc -l | tr -d ' ')
  if [ "$n" = "0" ]; then
    log "no ports in $PORTS_FILE - nothing to bypass"
    do_uninstall
    return 0
  fi
  log "bypassing $n port(s): $(list_ports | tr '\n' ' ')"
  for table in mangle nat; do
    "$IPT" -t "$table" -N "$CHAIN" 2>/dev/null || true
    "$IPT" -t "$table" -F "$CHAIN" 2>/dev/null || true
    add_port_rules "$table" || die "cannot add the rules to the chain in $table"
    pos=$(jump_position "$table")
    if [ -z "$pos" ]; then
      "$IPT" -t "$table" -I PREROUTING 1 -j "$CHAIN" || die "cannot hook the chain into PREROUTING ($table)"
    elif [ "$pos" != "1" ]; then
      # The jump has to be the first rule: in front of the chains of
      # MagiTrickle, otherwise the packets are marked before we see them.
      "$IPT" -t "$table" -D PREROUTING "$pos" 2>/dev/null || true
      "$IPT" -t "$table" -I PREROUTING 1 -j "$CHAIN" || die "cannot move the chain to the front ($table)"
    fi
  done
  log "the ports bypass the core"
}

do_uninstall() {
  find_iptables || return 0
  for table in mangle nat; do
    pos=$(jump_position "$table")
    while [ -n "$pos" ]; do
      "$IPT" -t "$table" -D PREROUTING "$pos" 2>/dev/null || break
      pos=$(jump_position "$table")
    done
    "$IPT" -t "$table" -F "$CHAIN" 2>/dev/null || true
    "$IPT" -t "$table" -X "$CHAIN" 2>/dev/null || true
  done
}

do_status() {
  find_iptables || die "no iptables found"
  n=$(list_ports | wc -l | tr -d ' ')
  log "ports in $PORTS_FILE: $n"
  for table in mangle nat; do
    pos=$(jump_position "$table")
    if [ -n "$pos" ]; then
      log "  $table PREROUTING: the chain $CHAIN is at position $pos"
      "$IPT" -t "$table" -S "$CHAIN" 2>/dev/null | sed -e 's/^/    /' || true
    else
      log "  $table PREROUTING: the chain $CHAIN is not hooked in"
    fi
  done
}

case "${1:-install}" in
  install)   do_install ;;
  uninstall) do_uninstall ;;
  status)    do_status ;;
  *)         die "usage: $0 [install|uninstall|status]" ;;
esac
